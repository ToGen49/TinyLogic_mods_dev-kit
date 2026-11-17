# Examples

Eleven runnable mods, one per use case. Each folder is a complete mod: copy it
into the profile and hit **save + run**.

```bash
<kit>/tools/install.sh <kit>/examples/01-window-setting
<kit>/tools/validate.py          # checks all of them at once
```

| Folder | Shows | Recipes |
|---|---|---|
| [`01-window-setting`](01-window-setting/) | `tl.ui.window`, sliders/buttons, `tl.store` persistence | 10.1 |
| [`02-board-overlay`](02-board-overlay/) | `tl.draw` on the board, tiles vs board pixels, `tl.on("draw")` | 10.2 |
| [`03-screen-overlay`](03-screen-overlay/) | `tl.hud` on the screen, `tl.input.mouse()` | 10.3 |
| [`04-timer-watch`](04-timer-watch/) | `tl.every`, `tl.command`, `tl.sim.watch` (no polling) | 10.4 |
| [`05-player-input`](05-player-input/) | `tl.input.capture`, `key`/`click` events, `tl.sound` | 10.5 |
| [`06-build-circuit`](06-build-circuit/) | `tl.board.place` / `wire` / `remove`, undo/redo | 10.6 |
| [`07-console-commands`](07-console-commands/) | `tl.command`, argument parsing, `tl.warn` | 10.7 |
| [`08-mod-library`](08-mod-library/) | `tl.export` — publishes an API | 10.8 |
| [`09-mod-consumer`](09-mod-consumer/) | `tl.require`, `tl.emit`/`tl.on` event bus, `tl.mods` | 10.8, 10.9 |
| [`10-custom-node`](10-custom-node/) | `tl.graph.node` — new node types for everyone | 10.10 |
| [`11-graph-only`](11-graph-only/) | `graph.json` with **no** Lua at all | 10.11 |

## How to read them

- Every `main.lua` opens with a comment saying which recipe it implements —
  the prose lives in [`docs/10-recipes.md`](../docs/10-recipes.md).
- They are deliberately small: one idea each, not a framework.
- `08` and `09` are a **pair**. Install and run `08-mod-library` first, otherwise
  `09-mod-consumer` reports the library as missing (that is the point — it shows
  how `tl.require` fails gracefully).

## After a game update

```bash
<kit>/tools/sync-api.sh --auto     # refresh api/api.json
<kit>/tools/validate.py            # re-check every example against it
```
