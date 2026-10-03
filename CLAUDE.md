# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

"Robokitteh of SPLORR!!" — an entry for the itch.io Jamference AI Game Jam Hack 1 (Oct 2–9, 2026). Theme "Cat and Robot" (optional); the mandatory restriction is "Movement Input Only". Judged on Fun, AI Use, Polish. Everything must be built during jam week.

## Stack

Odin compiled to `js_wasm32`, running in the browser via Odin's own `odin.js` runtime (no emscripten). Rendering is a 2D canvas via a JS shim (see below); input through `core:sys/wasm/js` event listeners.

## Commands

```bash
./build.sh                                  # builds into build/web (game.wasm, index.html, odin.js)
python3 -m http.server -d build/web 8000    # serve locally; wasm must be served over http, not file://
```

`ODIN=/path/to/odin ./build.sh` overrides the compiler (odin is at `/home/yermom/ODIN/odin`). Zip the contents of `build/web` for the itch.io HTML5 upload.

## Architecture notes

- `src/main.odin`: `main` runs once for setup; the exported `step(dt, ctx)` is called every animation frame by `odin.js` (return `false` to stop). Event callbacks and `step` must set `context = ctx` themselves.
- `web/index.html` hosts the `#canvas` and the JS shim implementing the `foreign import canvas` procs.
- Art: `assets/tileset.png` is the Urizen 1-bit tileset (CC0, supplied by the user): 12px tiles, 1px gap, so tile (c,r) starts at pixel (13c+1, 13r+1). Tile coordinates used by the game are the `SPR_*` constants in `src/main.odin` (`SPR_CAT` is (1,14); (0,14) is a fox, not a cat).
- Rendering is a 2D canvas, not WebGL: the user's Chrome (Mesa llvmpipe) cannot create a WebGL context. The shim lives in `web/index.html`.
- Text: the tileset has a bitmap font (rows 44-47 from column 78; see `FONT_ROWS` in `src/main.odin`). `draw_text` takes ASCII only, and glyphs are drawn at 0.6 tile (an exact 2x of the 12px source). The game has three states (`Intro`, `Playing`, `Dead`) and a one-line event `message` shown as a banner until the next turn.

## Shipping (itch.io)

`./shippit.sh` runs `butler push build/web thegrumpygamedev/robokitteh-of-splorr:html` (butler is at `~/bin/butler`). **Never run it unless the user explicitly says to**: it publishes the game.

- It does not build first. It uploads whatever is currently in `build/web`, so run `./build.sh` before shipping or the upload can be stale (check that `build/web/game.wasm` is newer than `src/main.odin`).
- It must be run from the project root (the path is relative), and has no `set -e`.
- It needs butler to be logged in (`butler login` or `BUTLER_API_KEY`) and the itch.io project page to already exist. The first push to the `html` channel also needs "This file will be played in the browser" ticked on the page's uploads.
- The itch.io page copy lives in `ITCH_DESCRIPTION.md`.
