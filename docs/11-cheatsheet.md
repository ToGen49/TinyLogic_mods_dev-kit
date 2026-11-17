# 11. Cheat sheet

> Back to the [kit index](../readme.md) · Previous: [10. Recipes](10-recipes.md)

Print it, keep it next to the editor. Full signatures:
[4. API reference](04-api.md) · machine-checkable source of truth:
[`<kit>/api/api.json`](../api/api.json).

```lua
-- lifecycle
tl.on("load", fn)            tl.on("unload", fn)      tl.off(handle)
tl.on("frame", function(dt) end)                      tl.on("second", fn)
tl.after(1.5, fn)            tl.every(0.25, fn)       tl.cancel(timer)
tl.time()                    tl.id                    tl.version

-- board (tiles; 1 tile = 16 board px)
tl.board.parts(kind?)        tl.board.part(id)        tl.board.pins(id)
tl.board.place(name, x, y)   tl.board.chip(name, x, y)
tl.board.wire(a, pa, b, pb)  tl.board.set(id, props)  tl.board.label(id, text)
tl.board.move(id, x, y)      tl.board.rotate(id, flip)
tl.board.remove(...)         tl.board.remove_wire(...) tl.board.clear()
tl.board.find_space(w, h)    tl.board.catalog()       tl.board.count()
tl.board.select(ids)         tl.board.selection()     tl.board.undo/redo()

-- simulation
tl.sim.read(id, pin?)        tl.sim.read_all(ids)     tl.sim.toggle(id)
tl.sim.set(id, on)           tl.sim.press(id, down)   tl.sim.tap(id, s)
tl.sim.number(id, n)         tl.sim.clock(action, id) tl.sim.speed(n, id)
tl.sim.watch(id, pin, fn)    tl.sim.unwatch(w)        tl.sim.state()
tl.sim.truth_table(args)

-- electric parts (SI units)
tl.elec.settings(id)         tl.elec.get(id, name)    tl.elec.set(id, name, v)
tl.elec.volts(id, pin, o)    tl.elec.amps(id)         tl.elec.meter(id)
tl.elec.watch(id, pin, fn, step)                      tl.elec.unwatch(w)

-- drawing: tl.draw = board (16 px/tile), tl.hud = screen (480x270)
tl.draw.rect/frame/text/measure/pixel/line/tile/cell
tl.hud.rect/frame/text/measure/pixel/line/size()
tl.color(r, g, b, a)         tl.hsv(h, s, v)

-- ui (runs every frame)
tl.ui.window(title, fn, opts) tl.ui.toast(text, color)
tl.ui.label/toggle/slider/bar/space

-- input / sound / camera
tl.input.key(name)           tl.input.capture(on)     tl.input.mouse()
tl.sound.play(name, pitch)   tl.sound.note(hz, s, vol, tone)
tl.camera.get/go/fit/focus

-- persistence and other mods
tl.store.get(key, default)   tl.store.set(key, value)
tl.export(name, value)       tl.require(id)           tl.mods()
tl.emit(event, ...)          tl.call(op, args)        tl.command(name, fn)
tl.graph.node(def)           vars                     tl.log / tl.warn / print
```

**Events you can listen for:** `load`, `unload`, `frame(dt)`, `second`, `draw`,
`key(name, down)`, `click(x, y)`, `part_placed(part, kind)`, `part_removed(part)`,
`wire_added(wire)`, `wire_removed(wire)` — plus any custom name you `tl.emit`.

**Sound names:** `hover, click, confirm, tick, pop, boom, whoosh, zap, error,
switch, thump, riser, crton, crtoff, glitch, snore, knock, sparkle`.

**Colour names:** `red, green, yellow, blue, cyan, purple, pink, orange, white,
black, ink, muted, gray` (alias `grey`), or hex `"#5fe08a"`.
