# 7. Limits, gotchas and hard constraints

> Back to the [kit index](../readme.md) · Previous: [6. Debugging](06-debugging.md) · Next: [8. Sharing](08-sharing.md)

1. **No file I/O, no network, no `require`, no `load`.** If your mod needs
   external data, it must go through `tl.store` or through the game itself.
2. **No real-time external channel.** `tl.store` is cached
   ([§4.10](04-api.md)), so an outside process editing `store.json` is only
   picked up after a reload. There is no socket API, no pipe, no IPC entry point
   anywhere in the sandbox.
3. **Budgets**: 3 M instructions per handler, 30 M per load, 25 faults → stopped.
4. **Undo**: every board change a mod makes is undoable by the player.
5. **Windows redraw every frame** — treat the `fn` you pass to `tl.ui.window` as a
   render function, not as an "on click" handler. Use the return value of
   `ui.button` for actions, and do not allocate heavily there.
6. **Draw calls are cleared each frame** — draw inside `draw`/`frame`.
7. **`tl.require` only sees mods already loaded**, and load order is the order
   they were loaded (`tl.mods()`).
8. **Copies, not the originals**: `math`, `string`, `table`, `utf8`, `coroutine`
   are per-mod copies. Monkey-patching them affects only your mod — and also means
   you cannot patch them for anyone else.
9. **The two Lua worlds are different.** `prelude.lua`'s environment (`load`,
   `dofile`, direct `host.*`) is *not* your mod's environment. Your mod gets `tl.*`.
10. **`host.*` is the launcher-side native table** (`host.budget, call, capture,
    draw, key, log, measure, mouse, note, now, over, sound, store_read,
    store_write, toast, ui_bar, ui_begin, ui_button, ui_end, ui_label,
    ui_slider, ui_space, ui_toggle, viewport`). It is not exposed to mods; the
    `tl` API is a hand-written wrapper over it.

---

**Next:** [8. Sharing](08-sharing.md)
