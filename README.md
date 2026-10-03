# Robokitteh of SPLORR!!

An entry for [Jamference: AI Game Jam Hack 1](https://itch.io/jam/jamference-ai-game-jam-hack-1) (October 2–9, 2026). Theme: "Cat and Robot". Mandatory restriction: "Movement Input Only".

You are a robot cat herder, which is an impossible job. Cats wander around the room at random, sometimes sit down for a while, and cannot be herded. Your battery is draining the whole time. The only way to recharge is to bump into a solar-powered terminal.

## How it plays

- Turn based on a grid. Each arrow-key or WASD press moves one tile, and that press is one turn. Nothing happens between presses.
- Every turn costs 3% battery. At 0% the game is over (Space or Enter restarts).
- Walking into a terminal is a bump: you stay put and take up to 15% charge from it. Terminals refill slowly from solar power (1% per turn), so you can drain them by bumping repeatedly.
- Cats are solid and wander randomly. Bumping one costs a turn.
- Walking into a wall also costs a turn (and battery), so you can waste charge by bumbling into things.

## Tech

- [Odin](https://odin-lang.org/) compiled to `js_wasm32`, run in the browser with Odin's own `odin.js` runtime (no emscripten).
- Drawing uses a small 2D canvas shim in `web/index.html` that the Odin code calls through `foreign import`. WebGL was tried first but dropped because some browsers (including software-rendered Linux Chrome) cannot create a context.
- Sprites are from the Urizen 1-bit tileset (CC0), in `assets/tileset.png`.

## Build and run

```bash
./build.sh                                  # writes build/web
python3 -m http.server -d build/web 8000    # then open http://localhost:8000
```

Set `ODIN=/path/to/odin` if `odin` is not on your `PATH`. Zip the contents of `build/web` to upload to itch.io as an HTML5 game.

## Status

Working prototype: grid movement, battery, solar terminals, wandering and sitting cats, walls and floor, and a battery HUD. Still to do: on-screen text (the tileset has a bitmap font), a way to actually interact with the cats, sound, and a game-over screen.

## AI use

This project is built with Claude Code (Claude Sonnet 5.5): the Odin code, the web shim and the build setup were written by the AI in conversation with the human developer, who directed the design (turn-based, battery as the starvation mechanic, bump-to-charge solar terminals, wandering cats) and supplied the art.

## Credits

- Tileset: Urizen 1-bit tileset (CC0).
