# 4. API reference

> Back to the [kit index](../readme.md) · Previous: [3. The sandbox](03-sandbox.md) · Next: [5. Node graphs](05-graphs.md)

Full, official reference: [`<kit>/api/api.json`](../api/api.json) (copy of
`<install>/assets/mods/api.json`, `version: 0.2-beta`).
Reproduced below, grouped exactly as the game groups it.

### 4.1 core — Events and time

| Signature | Returns | Description |
|---|---|---|
| `tl.on(event, fn)` | handle | Run `fn` when an event happens. Built in: `load`, `unload`, `frame(dt)`, `second`, `draw`, `key(name, down)`, `click(x, y)`, `part_placed(part, kind)`, `part_removed(part)`, `wire_added(wire)`, `wire_removed(wire)`. Any other name is a custom event. |
| `tl.off(handle)` | | Stop a listener that `tl.on` gave back. |
| `tl.emit(event, ...)` | | Send an event to **every** running mod, this one too. |
| `tl.after(seconds, fn)` | timer | Run `fn` once, this many seconds from now. |
| `tl.every(seconds, fn)` | timer | Run `fn` again and again, this many seconds apart. |
| `tl.cancel(timer)` | | Stop a timer from `tl.after` or `tl.every`. |
| `tl.time()` | seconds | Seconds since the mods started. |
| `tl.log(...)` | | Write a line to this mod's console. `print` does the same. |
| `tl.warn(...)` | | Write a yellow line to this mod's console. |
| `tl.command(name, fn)` | | Add a console command: typing `name the rest` calls `fn("the rest")`. |
| `tl.version` | string | The mod API version (`"0.2-beta"`). |
| `tl.id` | string | This mod's id. |
| `vars` | table | A table shared by this mod's script and its node graph. |

Frame order (from `prelude.lua`): timers → watches → `frame` event → `second`
(every ≥1 s) → `draw` event → every open window's function.

### 4.2 mods — Other mods

| Signature | Returns | Description |
|---|---|---|
| `tl.export(name, value)` | | Offer a value or a function to other mods. |
| `tl.require(id)` | exports | Everything another running mod exported, or `nil` and why. |
| `tl.mods()` | ids | The ids of every running mod, **in load order**. |
| `tl.call(op, args)` | result | The raw engine interface every other function is built on. Ops: `state`, `board`, `part`, `probe`, `place`, `wire`, `delete`, `move`, `rotate`, `set`, `press`, `clock`, `camera`, `focus`, `find_space`, `catalog`, `select`, `duplicate`, `truth_table`, `undo`, `redo` and more. Returns the result table, or `nil` and why. |

Load order matters: `tl.require` only sees mods already running.

### 4.3 board — The board

Positions are in **tiles**. Drawing uses **board pixels: 1 tile = 16 px**.

| Signature | Returns | Description |
|---|---|---|
| `tl.board.place(name, x, y, opts)` | id, part | Place a part by its finder name (`"switch"`, `"light"`, `"nand"`…). Leave `x, y` out for the nearest free spot. `opts`: `{label=, on=, number=, bits=, color=}`. |
| `tl.board.chip(name, x, y)` | id, part | Place one of the project's own chips by name. |
| `tl.board.wire(a, pin_a, b, pin_b, color)` | wire | Wire pin `pin_a` of part `a` to pin `pin_b` of part `b`. A pin is its number (counting from **0**) or its name (`"out"`, `"a"`). `color` is 0–8 or a colour name. |
| `tl.board.remove(...)` | count | Remove parts: ids, part tables, or one list of them. |
| `tl.board.remove_wire(...)` | count | Remove wires by id. |
| `tl.board.parts(kind)` | parts | Every part on this level, or only one kind (`"light"`, `"switch"`, `"chip"`…). Each has `id, kind, name, x, y, w, h, rot, on, value, label`. |
| `tl.board.wires(paths)` | wires | Every wire: `id, from, to, color`. `from`/`to` are two-item lists: `w.from[1]` is the part, `w.from[2]` the pin. Pass `true` to get each wire's path and amps too. |
| `tl.board.part(id)` | part | One part with its pins, what it says and its status. Nothing if the part is gone. |
| `tl.board.pins(id)` | pins | A part's pins. |
| `tl.board.set(id, props)` | part | Change a part: `{on=, number=, bits=, value=, label=, color=, rot=, flip=}`. |
| `tl.board.label(id, text)` | part | Give a part a label. |
| `tl.board.move(id, x, y)` | part | Move a part to a tile. Its wires follow. |
| `tl.board.rotate(id, flip)` | | Turn a part a quarter turn, or mirror it when `flip` is true. |
| `tl.board.wire_color(wire, color)` | | Recolour a wire, 0 to 8. |
| `tl.board.clear()` | | Remove everything on this level. |
| `tl.board.find_space(w, h, near_x, near_y)` | x, y | A free spot big enough for `w` by `h` tiles. |
| `tl.board.catalog()` | items | Everything the part finder offers. |
| `tl.board.select(ids)` | | Select these parts. |
| `tl.board.selection()` | ids | What the player has selected. |
| `tl.board.count()` | parts, wires | How many parts and wires are on this level. |
| `tl.board.undo()` | | Undo the last change. Everything a mod does lands in the player's undo history. |
| `tl.board.redo()` | | Redo. |

### 4.4 sim — The simulation

| Signature | Returns | Description |
|---|---|---|
| `tl.sim.read(id, pin)` | value, volts | What a part shows (a light's 1 or 0, a display's number), or what one pin carries. |
| `tl.sim.read_all(ids)` | values | Read many parts in one go. |
| `tl.sim.set(id, on)` | | Close or open a switch. |
| `tl.sim.toggle(id)` | | Flip a switch. |
| `tl.sim.press(id, down)` | | Hold a push button down, or let it go. |
| `tl.sim.tap(id, seconds)` | | Press a push button and let go a moment later. |
| `tl.sim.number(id, n)` | | Set a number input. |
| `tl.sim.clock(action, id)` | | `"play"`, `"pause"`, `"step"` or `"restart"` a clock. |
| `tl.sim.speed(n, id)` | | A clock's speed, 0 to 9. |
| `tl.sim.step(times, id)` | | Step a paused clock. |
| `tl.sim.watch(id, pin, fn)` | watch | Call `fn(value, before)` whenever a reading changes. `pin` is optional. |
| `tl.sim.unwatch(watch)` | | Stop watching. |
| `tl.sim.state()` | state | The editor's state: `project, level, camera, parts, wires, short_circuit, unstable, clock_running…` |
| `tl.sim.truth_table(args)` | table | Work out a circuit's truth table. |

Watches are polled **once per frame** via a single batched `probe` engine call.

### 4.5 elec — Electric parts

Analog parts (supplies, sources, resistors, capacitors, coils, semiconductors).
Values are **SI units**.

| Signature | Returns | Description |
|---|---|---|
| `tl.elec.settings(id)` | settings, names | Every electric setting by name as it is now, and their names in order. A resistor has `ohms`; a function generator `hz, height, center, width`; a bench supply `volts, limit`. |
| `tl.elec.get(id, name)` | value | One setting by name (`nil` when the part has no such setting). |
| `tl.elec.set(id, name, value)` | ok | Change one setting, or several with a table: `tl.elec.set(gen, {hz = 440, height = 2})`. Same as typing it on the part's card, so one undo brings it back. A name the part doesn't have is an error listing the ones it does. |
| `tl.elec.volts(id, pin, other)` | volts | Volts on a pin against ground, or between two pins of the same part when `other` is given. |
| `tl.elec.amps(id)` | amps | Current through a part, in amps. 0 when none flows. |
| `tl.elec.meter(id)` | reading | What a voltmeter or ammeter reads. |
| `tl.elec.watch(id, pin, fn, step)` | watch | Call `fn(volts, before)` whenever a pin's volts moved by `step` from the last value told (**0.1 V** unless given). Checked once a frame. |
| `tl.elec.unwatch(watch)` | | Stop watching. |

### 4.6 draw — Drawing

`tl.draw` paints on the **board** (16 board pixels to a tile, moves with the
camera). `tl.hud` paints on the **screen** (480 × 270).
**Draw inside a `draw` or `frame` event: the picture is wiped every frame.**

| Signature | Returns | Description |
|---|---|---|
| `tl.draw.rect(x, y, w, h, color, alpha)` | | A filled box on the board, in board pixels. |
| `tl.draw.frame(x, y, w, h, color, alpha)` | | An outline on the board. |
| `tl.draw.text(text, x, y, color, scale)` | | Words on the board. |
| `tl.draw.measure(text, scale)` | w, h | How wide and tall some words come out, in pixels, before they're drawn. For centring text or putting a box behind it. |
| `tl.draw.pixel(x, y, color)` | | One board pixel. |
| `tl.draw.line(x0, y0, x1, y1, color)` | | A line on the board. |
| `tl.draw.tile(tx, ty, color, alpha)` | | Fill one whole tile. |
| `tl.draw.cell(tx, ty, color, inset)` | | Fill a tile with a gap round it. |
| `tl.hud.rect(x, y, w, h, color, alpha)` | | A filled box on the screen. |
| `tl.hud.frame(x, y, w, h, color, alpha)` | | An outline on the screen. |
| `tl.hud.text(text, x, y, color, scale)` | | Words on the screen. |
| `tl.hud.measure(text, scale)` | w, h | Text size before drawing. |
| `tl.hud.pixel(x, y, color)` | | One screen pixel. |
| `tl.hud.line(x0, y0, x1, y1, color)` | | A line on the screen. |
| `tl.hud.size()` | w, h | The screen's size: **480, 270**. |
| `tl.color(r, g, b, a)` | colour | 0–255 components, a name (`"red"`, `"green"`, `"yellow"`, `"blue"`, `"cyan"`, `"purple"`, `"pink"`, `"orange"`, `"white"`, `"black"`, `"ink"`, `"muted"`, `"gray"`), or hex (`"#5fe08a"`). |
| `tl.hsv(h, s, v)` | colour | A colour from hue (0 to 1), saturation and value. |

Named colours are exact RGB values from `prelude.lua`, e.g.
`green = {95, 224, 138}`, `yellow = {245, 211, 60}`, `ink = {236, 235, 245}`,
`muted = {150, 147, 176}`, `board = {28, 27, 42}` (`grey` is an alias of `gray`).

### 4.7 ui — Windows

The function you give runs **every frame** and lists what is in the window, top to bottom.

| Signature | Returns | Description |
|---|---|---|
| `tl.ui.toast(text, color)` | | A short message at the bottom of the screen. |
| `tl.ui.window(title, fn, opts)` | window | Open a window. `fn(ui, window)` runs every frame and fills it with labels, buttons and bars. `opts: {x=, y=, w=}` (default `w = 110`). The handle has `close()`. |
| `tl.ui.label(text, color)` | | A line of words. |
| `tl.ui.button(label)` | clicked | A button. **True on the frame it was clicked.** |
| `tl.ui.toggle(label, value)` | value | A switch. Give it the value, get the new value back. |
| `tl.ui.slider(label, value, lo, hi)` | value | A slider. Give it the value, get the new value back. |
| `tl.ui.bar(label, fraction, color)` | | A progress bar, 0 to 1. |
| `tl.ui.space(px)` | | A gap (default 3). |

Idiomatic pattern — persist a toggle:

```lua
local show_ids = tl.store.get("show_ids", false)

tl.ui.window("Board Stats", function(ui)
    local now = ui.toggle("show part numbers", show_ids)
    if now ~= show_ids then
        show_ids = now
        tl.store.set("show_ids", show_ids)
    end
end, {w = 128})
```

### 4.8 input — Keys and the mouse

| Signature | Returns | Description |
|---|---|---|
| `tl.input.key(name)` | down | Is a key held right now? `"a"`, `"space"`, `"left"`, `"return"`… |
| `tl.input.capture(on)` | | While on, key presses go to this mod and not to the editor's shortcuts. **Escape always gives them back.** |
| `tl.input.mouse()` | mouse | `{x, y, tile_x, tile_y, down}` — where the mouse is on the screen and on the board. |

### 4.9 sound

| Signature | Returns | Description |
|---|---|---|
| `tl.sound.play(name, pitch)` | | `hover, click, confirm, tick, pop, boom, whoosh, zap, error, switch, thump, riser, crton, crtoff, glitch, snore, knock, sparkle` |
| `tl.sound.note(hz, seconds, volume, tone)` | | One note. `tone` is `"square"`, `"triangle"`, `"sine"` or `"noise"`. Defaults: `0.15 s`, `0.1` volume, `"square"`. |

### 4.10 store — Saving

What a mod remembers between sessions. Kept in the mod's own folder.

| Signature | Returns | Description |
|---|---|---|
| `tl.store.get(key, default)` | value | Read a saved value. |
| `tl.store.set(key, value)` | | Save a value: numbers, strings, booleans and tables of them. |

**Gotcha — the store is cached in memory.** `prelude.lua` reads `store.json` once,
lazily, then keeps the table:

```lua
local stored
local function store()
    if not stored then stored = host.store_read(mod.id) or {} end
    return stored
end
```

`tl.store.set` writes through to disk immediately, but an **external** change to
`store.json` is invisible until the mod is reloaded. That is why an external
program editing the file will not talk to a running mod in real time.

The underlying natives (launcher side, not available to your mod directly):

```lua
host.store_read(mod.id)      -- -> table or nil
host.store_write(mod.id, t)
```

### 4.11 camera

| Signature | Returns | Description |
|---|---|---|
| `tl.camera.get()` | `{x, y, zoom}` | Where the view is. |
| `tl.camera.go(x, y, zoom)` | | Glide the view to a board position. |
| `tl.camera.fit()` | | Fit the whole board in view. |
| `tl.camera.focus(ids)` | | Bring these parts into view. |

### 4.12 graph — Extending the editor

A mod can add its own node types to the visual scripting editor, for itself and
for every other mod.

```lua
tl.graph.node{
    id = "pack.blink",          -- unique; "your-mod.something" is a good habit
    cat  = "Node Pack",         -- category in the node picker
    title = "Blink part",
    kind = "action",            -- "action" | "value" | "event" | "flow"
    ins  = {{"part", "number", 0}, {"times", "number", 3}},   -- {name, type, default}
    outs = {{"value", "number"}},
    code = 'tl.require("node-pack").blink($part, $times)',    -- action/event/flow
    expr = '(tl.require("node-pack").wave(nil, $speed))',     -- value
    tip  = "Flips a switch on and off a few times.",
}
```

In `code` and `expr`, **`$name` is an input and `@name` an output**.
Types seen in the built-in nodes: `number`, `bool`, `string`, `name`, `color`, `any`.
`const = true` on an input pins it as a literal.

Node types are removed again when the mod unloads.

---

**Next:** [5. Node graphs (`graph.json`)](05-graphs.md)
