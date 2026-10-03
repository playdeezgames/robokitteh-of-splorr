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
