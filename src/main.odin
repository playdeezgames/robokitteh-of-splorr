package main

import "base:runtime"
import "core:math/rand"
import "core:sys/wasm/js"
import "core:time"

// Implemented in web/index.html (2D canvas); world coordinates, y up.
foreign import canvas "canvas"
@(default_calling_convention = "contextless")
foreign canvas {
	clear_canvas :: proc(r, g, b: f32) ---
	fill_rect :: proc(x, y, w, h: f32, r, g, b: f32, tiles: f32) ---
	// tile (col,row) of assets/tileset.png (12px tiles, 1px gap) at world x,y; blue swaps red and blue channels
	draw_sprite :: proc(col, row: i32, x, y: f32, alpha: f32, tiles: f32, blue: bool) ---
}

ctx: runtime.Context

Terminal :: struct {
	pos:    [2]int,
	stored: f32, // 0..1 solar charge available to give
}

MAX_CATS    :: 8
BLOCK_COUNT :: 6
START_CATS  :: 3 // cats on level 1; each level adds one, up to MAX_CATS
CAT_SIT_CHANCE  :: 0.12 // per turn, a wandering cat sits down
CAT_WAKE_CHANCE :: 0.2 // per turn, a sitting cat gets up (sits ~5 turns on average)

Cat :: struct {
	pos:     [2]int,
	sitting: bool, // sitting cats stay put until they decide to get up
	gone:    bool, // left through the door, or not part of this level
}

Game :: struct {
	pos:      [2]int, // grid tile
	battery:  f32, // 0..1
	dead:     bool,
	turns:    int,
	terminals: [3]Terminal,
	cats:     [MAX_CATS]Cat, // cats wander at random and block movement
	cat_count: int, // cats in this level
	herded:   int, // cats that have left through the door this level
	level:    int,
	door:     [2]int, // a wall tile (never a corner) that cats can walk into to leave
	blocks:   [BLOCK_COUNT][2]int, // sokoban-style: the robot pushes them, cats can't enter them
	flash:    int, // index+1 of the terminal bumped this turn, 0 for none
}

WORLD_SIZE :: 20 // canvas is WORLD_SIZE x WORLD_SIZE tiles
BOARD_W    :: WORLD_SIZE
BOARD_H    :: WORLD_SIZE - 1 // the top row of the canvas is the HUD panel, not board
DRAIN_PER_MOVE :: 0.03 // battery lost each turn
PUSH_DRAIN     :: 0.06 // battery lost on a turn that successfully pushes a barrel
BUMP_CHARGE    :: 0.15 // most battery a single bump can transfer
SOLAR_PER_TURN :: 0.01 // terminal store refilled each turn

game: Game

main :: proc() {
	ctx = context
	rand.reset(u64(time.now()._nsec))
	js.add_window_event_listener(.Key_Down, nil, on_key)
	reset_game()
}

on_key :: proc(e: js.Event) {
	if e.kind != .Key_Down || e.key.repeat { return }
	dir: [2]int
	switch e.key.code {
	case "ArrowLeft", "KeyA":  dir = {-1, 0}
	case "ArrowRight", "KeyD": dir = {1, 0}
	case "ArrowUp", "KeyW":    dir = {0, 1}
	case "ArrowDown", "KeyS":  dir = {0, -1}
	case "Space", "Enter":
		if game.dead { reset_game() }
	case: return
	}
	js.event_prevent_default()
	if dir != {} && !game.dead { take_turn(dir) }
}

reset_game :: proc() {
	game = {battery = 1, level = 1}
	setup_level()
}

// Re-rolls the whole layout. Battery, turn count and level carry over.
setup_level :: proc() {
	game.pos = {10, 10}
	game.flash = 0
	game.herded = 0
	game.cat_count = min(START_CATS + game.level - 1, MAX_CATS)
	game.terminals = {}
	game.blocks = {}
	game.cats = {}
	place_door()
	for &t in game.terminals {
		t.stored = 1
		for _ in 0 ..< 1000 {
			t.pos = {1 + rand.int_max(BOARD_W - 2), 1 + rand.int_max(BOARD_H - 2)}
			if !tile_occupied(t.pos) { break }
		}
	}
	for &block in game.blocks {
		for _ in 0 ..< 1000 {
			// keep off the edges so no block starts stuck against a wall
			block = {2 + rand.int_max(BOARD_W - 4), 2 + rand.int_max(BOARD_H - 4)}
			if !tile_occupied(block) { break }
		}
	}
	for &cat, i in game.cats {
		if i >= game.cat_count {
			cat.gone = true
			continue
		}
		for _ in 0 ..< 1000 {
			cat.pos = {1 + rand.int_max(BOARD_W - 2), 1 + rand.int_max(BOARD_H - 2)}
			if !tile_occupied(cat.pos) { break }
		}
	}
}

// Puts the door on a random wall tile, never a corner, and never where it already is.
place_door :: proc() {
	old := game.door
	for _ in 0 ..< 1000 {
		switch rand.int_max(4) {
		case 0: game.door = {1 + rand.int_max(BOARD_W - 2), 0}
		case 1: game.door = {1 + rand.int_max(BOARD_W - 2), BOARD_H - 1}
		case 2: game.door = {0, 1 + rand.int_max(BOARD_H - 2)}
		case 3: game.door = {BOARD_W - 1, 1 + rand.int_max(BOARD_H - 2)}
		}
		if game.door != old { break }
	}
}

tile_occupied :: proc(p: [2]int) -> bool {
	if p == game.pos { return true }
	for t in game.terminals { if t.pos == p { return true } }
	for c in game.cats { if !c.gone && c.pos == p { return true } }
	for b in game.blocks { if b == p { return true } }
	return false
}

// Walkable area: everything inside the ring of wall tiles.
in_bounds :: proc(p: [2]int) -> bool {
	return p.x >= 1 && p.y >= 1 && p.x <= BOARD_W - 2 && p.y <= BOARD_H - 2
}

move_cats :: proc() {
	dirs := [4][2]int{{-1, 0}, {1, 0}, {0, 1}, {0, -1}}
	for &cat in game.cats {
		if cat.gone { continue }
		if cat.sitting {
			if rand.float32() < CAT_WAKE_CHANCE { cat.sitting = false }
			continue
		}
		if rand.float32() < CAT_SIT_CHANCE {
			cat.sitting = true
			continue
		}
		target := cat.pos + dirs[rand.int_max(4)]
		if target == game.door {
			cat.gone = true
			game.herded += 1
			place_door() // each use moves the door
		} else if in_bounds(target) && !tile_occupied(target) {
			cat.pos = target
		}
	}
}

// One player move. Nothing in the world changes except as a result of this.
// Every attempted move costs a turn, including walking into a wall, a cat or a terminal.
take_turn :: proc(dir: [2]int) {
	target := game.pos + dir

	game.flash = 0
	pushed := false
	bumped := !in_bounds(target) // walls are solid; bumping one just wastes a turn
	for &t, i in game.terminals {
		if t.pos == target {
			bumped = true
			given := min(BUMP_CHARGE, t.stored)
			game.battery += given
			t.stored -= given
			if given > 0 { game.flash = i + 1 }
		}
	}
	for &b in game.blocks {
		if b == target {
			// push if the tile behind is free, otherwise it's just a bump
			dest := b + dir
			if in_bounds(dest) && !tile_occupied(dest) {
				b = dest
				pushed = true
			} else {
				bumped = true
			}
		}
	}
	for c in game.cats {
		if !c.gone && c.pos == target { bumped = true } // cats are solid; bumping one just costs a turn
	}
	if !bumped { game.pos = target }
	move_cats()

	game.turns += 1
	game.battery = min(game.battery - (PUSH_DRAIN if pushed else DRAIN_PER_MOVE), 1)
	for &t in game.terminals {
		t.stored = min(t.stored + SOLAR_PER_TURN, 1)
	}

	if game.herded >= game.cat_count {
		game.level += 1
		setup_level()
	} else if game.battery <= 0 {
		game.battery = 0
		game.dead = true
	}
}

// Tileset coordinates (assets/tileset.png, Urizen 1-bit, CC0).
SPR_ROBOT    :: [2]i32{102, 13}
SPR_TERMINAL :: [2]i32{69, 21}
SPR_BATTERY  :: [2]i32{54, 9}
SPR_BLOCK    :: [2]i32{11, 36}
SPR_WALL     :: [2]i32{0, 3}
SPR_DOOR     :: [2]i32{4, 1}
SPR_FLOOR    :: [2]i32{8, 5}
SPR_CAT      :: [2]i32{1, 14} // (0,14) is a fox

draw_tile :: proc(spr: [2]i32, x, y: f32, alpha: f32 = 1, blue := false) {
	draw_sprite(spr.x, spr.y, x, y, alpha, WORLD_SIZE, blue)
}

draw_rect :: proc(x, y, w, h: f32, color: [4]f32) {
	fill_rect(x, y, w, h, color.r, color.g, color.b, WORLD_SIZE)
}

// Only draws; all state changes happen in take_turn.
@(export)
step :: proc(dt: f64, c: runtime.Context) -> bool {
	context = ctx

	clear_canvas(0.08, 0.08, 0.12)
	for y in 0 ..< BOARD_H {
		for x in 0 ..< BOARD_W {
			wall := !in_bounds({x, y})
			if wall {
				draw_tile(SPR_WALL, f32(x), f32(y), blue = true) // it's a blue room
			} else {
				draw_tile(SPR_FLOOR, f32(x), f32(y))
			}
		}
	}
	draw_tile(SPR_DOOR, f32(game.door.x), f32(game.door.y))
	for b in game.blocks {
		draw_tile(SPR_BLOCK, f32(b.x), f32(b.y))
	}
	for t, i in game.terminals {
		if game.flash == i + 1 { draw_rect(f32(t.pos.x), f32(t.pos.y), 1, 1, {0.8, 1, 0.8, 1}) }
		// dim when drained, brighter as the solar store fills
		draw_tile(SPR_TERMINAL, f32(t.pos.x), f32(t.pos.y), 0.3 + 0.7 * t.stored)
	}
	for c in game.cats {
		if !c.gone { draw_tile(SPR_CAT, f32(c.pos.x), f32(c.pos.y)) }
	}
	draw_tile(SPR_ROBOT, f32(game.pos.x), f32(game.pos.y), 0.4 if game.dead else 1)

	// HUD panel: the canvas row above the board, visibly not part of the playfield
	top := f32(BOARD_H)
	draw_rect(0, top, WORLD_SIZE, 1, {0.16, 0.17, 0.22, 1})
	draw_rect(0, top, WORLD_SIZE, 0.08, {0.45, 0.47, 0.55, 1}) // edge where the board's top wall meets the panel
	draw_tile(SPR_BATTERY, 0.5, top)
	draw_rect(1.7, top + 0.2, 6, 0.6, {0.2, 0.2, 0.25, 1})
	bar := [4]f32{0.3, 0.9, 0.4, 1}
	if game.battery < 0.25 { bar = {0.95, 0.25, 0.2, 1} }
	draw_rect(1.7, top + 0.2, 6 * game.battery, 0.6, bar)

	// herding progress: one cat icon per cat in the level, bright once it has left through the door
	for i in 0 ..< game.cat_count {
		draw_tile(SPR_CAT, 19.0 - f32(game.cat_count - i), top, 1 if i < game.herded else 0.25)
	}
	return true
}
