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
	// tile (col,row) of assets/tileset.png (12px tiles, 1px gap) at world x,y
	draw_sprite :: proc(col, row: i32, x, y: f32, alpha: f32, tiles: f32) ---
}

ctx: runtime.Context

Terminal :: struct {
	pos:    [2]int,
	stored: f32, // 0..1 solar charge available to give
}

CAT_COUNT :: 5
CAT_SIT_CHANCE  :: 0.12 // per turn, a wandering cat sits down
CAT_WAKE_CHANCE :: 0.2 // per turn, a sitting cat gets up (sits ~5 turns on average)

Game :: struct {
	pos:      [2]int, // grid tile
	battery:  f32, // 0..1
	dead:     bool,
	turns:    int,
	terminals: [3]Terminal,
	cats:     [CAT_COUNT][2]int, // tiles; cats wander at random and block movement
	sitting:  [CAT_COUNT]bool, // sitting cats stay put until they decide to get up
	flash:    int, // index+1 of the terminal bumped this turn, 0 for none
}

WORLD_SIZE :: 20 // canvas is WORLD_SIZE x WORLD_SIZE tiles
BOARD_W    :: WORLD_SIZE
BOARD_H    :: WORLD_SIZE - 1 // the top row of the canvas is the HUD panel, not board
DRAIN_PER_MOVE :: 0.03 // battery lost each turn
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
	game = {pos = {10, 10}, battery = 1}
	game.terminals = {{pos = {3, 3}, stored = 1}, {pos = {16, 16}, stored = 1}, {pos = {16, 3}, stored = 1}}
	for &cat in game.cats {
		for _ in 0 ..< 1000 {
			cat = {1 + rand.int_max(BOARD_W - 2), 1 + rand.int_max(BOARD_H - 2)}
			if !tile_occupied(cat) { break }
		}
	}
}

tile_occupied :: proc(p: [2]int) -> bool {
	if p == game.pos { return true }
	for t in game.terminals { if t.pos == p { return true } }
	for c in game.cats { if c == p { return true } }
	return false
}

// Walkable area: everything inside the ring of wall tiles.
in_bounds :: proc(p: [2]int) -> bool {
	return p.x >= 1 && p.y >= 1 && p.x <= BOARD_W - 2 && p.y <= BOARD_H - 2
}

move_cats :: proc() {
	dirs := [4][2]int{{-1, 0}, {1, 0}, {0, 1}, {0, -1}}
	for &cat, i in game.cats {
		if game.sitting[i] {
			if rand.float32() < CAT_WAKE_CHANCE { game.sitting[i] = false }
			continue
		}
		if rand.float32() < CAT_SIT_CHANCE {
			game.sitting[i] = true
			continue
		}
		target := cat + dirs[rand.int_max(4)]
		if in_bounds(target) && !tile_occupied(target) { cat = target }
	}
}

// One player move. Nothing in the world changes except as a result of this.
// Every attempted move costs a turn, including walking into a wall, a cat or a terminal.
take_turn :: proc(dir: [2]int) {
	target := game.pos + dir

	game.flash = 0
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
	for c in game.cats {
		if c == target { bumped = true } // cats are solid; bumping one just costs a turn
	}
	if !bumped { game.pos = target }
	move_cats()

	game.turns += 1
	game.battery = min(game.battery - DRAIN_PER_MOVE, 1)
	for &t in game.terminals {
		t.stored = min(t.stored + SOLAR_PER_TURN, 1)
	}
	if game.battery <= 0 {
		game.battery = 0
		game.dead = true
	}
}

// Tileset coordinates (assets/tileset.png, Urizen 1-bit, CC0).
SPR_ROBOT    :: [2]i32{102, 13}
SPR_TERMINAL :: [2]i32{69, 21}
SPR_BATTERY  :: [2]i32{54, 9}
SPR_WALL     :: [2]i32{0, 3}
SPR_FLOOR    :: [2]i32{8, 5}
SPR_CAT      :: [2]i32{1, 14} // (0,14) is a fox

draw_tile :: proc(spr: [2]i32, x, y: f32, alpha: f32 = 1) {
	draw_sprite(spr.x, spr.y, x, y, alpha, WORLD_SIZE)
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
			draw_tile(SPR_WALL if wall else SPR_FLOOR, f32(x), f32(y))
		}
	}
	for t, i in game.terminals {
		if game.flash == i + 1 { draw_rect(f32(t.pos.x), f32(t.pos.y), 1, 1, {0.8, 1, 0.8, 1}) }
		// dim when drained, brighter as the solar store fills
		draw_tile(SPR_TERMINAL, f32(t.pos.x), f32(t.pos.y), 0.3 + 0.7 * t.stored)
	}
	for c in game.cats {
		draw_tile(SPR_CAT, f32(c.x), f32(c.y))
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
	return true
}
