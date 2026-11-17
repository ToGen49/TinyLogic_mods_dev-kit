# 10. Recipes — one example per use case

> Back to the [kit index](../readme.md) · Previous: [9. Samples](09-samples.md) · Next: [11. Cheat sheet](11-cheatsheet.md)

Short, self-contained snippets. Pick the one closest to what you want to build.
Each recipe also exists as a **runnable mod** in [`<kit>/examples/`](../examples/).

| # | Recipe | Runnable example |
|---|---|---|
| 10.1 | A window with a setting that survives restarts | [`01-window-setting`](../examples/01-window-setting/) |
| 10.2 | Something drawn on the board every frame | [`02-board-overlay`](../examples/02-board-overlay/) |
| 10.3 | Something drawn on the screen only | [`03-screen-overlay`](../examples/03-screen-overlay/) |
| 10.4 | Driving the circuit on a timer | [`04-timer-watch`](../examples/04-timer-watch/) |
| 10.5 | Reacting to the player | [`05-player-input`](../examples/05-player-input/) |
| 10.6 | Building a small circuit programmatically | [`06-build-circuit`](../examples/06-build-circuit/) |
| 10.7 | Console commands | [`07-console-commands`](../examples/07-console-commands/) |
| 10.8 | Talking to another mod | [`08-mod-library`](../examples/08-mod-library/) + [`09-mod-consumer`](../examples/09-mod-consumer/) |
| 10.9 | An event bus between mods | [`09-mod-consumer`](../examples/09-mod-consumer/) |
| 10.10 | Adding your own node type | [`10-custom-node`](../examples/10-custom-node/) |
| 10.11 | A graph-only mod (no code) | [`11-graph-only`](../examples/11-graph-only/) |

### 10.1 A window with a setting that survives restarts

```lua
local scale = tl.store.get("scale", 1)

tl.ui.window("My Tool", function(ui)
    local new = ui.slider("scale", scale, 0.5, 4)
    if new ~= scale then
        scale = new
        tl.store.set("scale", scale)   -- written to store.json immediately
    end
    ui.bar("progress", 0.5, "green")
    if ui.button("reset") then tl.store.set("scale", 1) end
end, {w = 130})
```

### 10.2 Something drawn on the board every frame

Drawing is cleared each frame, so it must happen inside a `draw` (or `frame`)
event. Coordinates are **board pixels**: 1 tile = 16.

```lua
tl.on("draw", function()
    for _, p in ipairs(tl.board.parts()) do
        tl.draw.text("#" .. p.id, p.x * 16, p.y * 16 - 8, "yellow")
    end
    tl.hud.text("parts: " .. tl.board.count(), 8, 8, "ink")   -- hud = screen, 480x270
end)
```

### 10.3 Something drawn on the screen only (overlay)

```lua
local mouse = tl.input.mouse()

tl.on("frame", function()
    mouse = tl.input.mouse()
end)

tl.on("draw", function()
    tl.hud.frame(mouse.x - 4, mouse.y - 4, 8, 8, "cyan")
    tl.hud.text(mouse.tile_x .. "," .. mouse.tile_y, 8, 250, "muted")
end)
```

### 10.4 Driving the circuit on a timer

```lua
local switches = tl.board.parts("switch")

tl.every(0.5, function()
    for _, p in ipairs(switches) do
        if p.on then tl.sim.toggle(p.id) end
    end
end)
```

Read without polling — a watch fires only when the value changes:

```lua
local light = tl.board.parts("light")[1]
if light then
    tl.sim.watch(light.id, nil, function(value, before)
        tl.log("light", before, "->", value)
    end)
end
```

### 10.5 Reacting to the player

```lua
tl.input.capture(true)   -- keys go to the mod; Escape always gives them back

tl.on("key", function(key, down)
    if down and key == "space" then tl.sound.play("click") end
end)

tl.on("click", function(x, y)
    tl.log("clicked tile", x, y)
end)
```

### 10.6 Building a small circuit programmatically

```lua
local a = tl.board.place("switch", 2, 2, {label = "A"})
local b = tl.board.place("switch", 2, 4, {label = "B"})
local y = tl.board.place("light",  6, 3, {label = "Y"})

tl.board.wire(a, "out", y, 0, "green")
tl.board.wire(b, "out", y, 1, "blue")
```

`place` returns `id, part`; leave `x, y` out to let the game pick the nearest
free spot. Pins are numbered from **0** or addressed by name (`"out"`, `"a"`).

### 10.7 Console commands

```lua
tl.command("count", function()
    local kinds = {}
    for _, p in ipairs(tl.board.parts()) do
        kinds[p.kind] = (kinds[p.kind] or 0) + 1
    end
    for kind, n in pairs(kinds) do tl.log(kind, n) end
end)
```

Type `count` in the mod's console. The rest of the line arrives as the argument:

```lua
tl.command("say", function(text) tl.log(text or "(nothing)") end)
```

### 10.8 Talking to another mod

Mod A offers something:

```lua
tl.export("double", function(n) return n * 2 end)
tl.export("version", "1.0")
```

Mod B uses it (only if A is already running — see load order in
[§4.2](04-api.md)):

```lua
local other = tl.require("mod-a")
if not other then
    tl.warn("mod-a isn't running")
else
    tl.log(other.double(21), other.version)
end
```

### 10.9 An event bus between mods

```lua
-- sender
tl.emit("score", 10)

-- receiver (any mod, including the sender)
tl.on("score", function(points)
    tl.log("scored", points)
end)
```

### 10.10 Adding your own node type

```lua
tl.graph.node{
    id = "my-mod.double_it",   -- namespace it with your own mod id
    cat = "My Mod",
    title = "Double",
    kind = "value",
    ins  = {{"n", "number", 0}},
    outs = {{"result", "number"}},
    expr = "($n * 2)",
    tip = "Multiplies by two.",
}
```

The node then appears in the graph editor for **every** mod, and disappears when
your mod unloads.

### 10.11 A graph-only mod (no code)

`main.lua` can be empty or comments only. `graph.json` does the work:

```json
{
 "links": [
  { "from": 1, "to": 2, "out": "next", "in": "exec", "exec": true }
 ],
 "nodes": [
  { "id": 1, "type": "event.every", "values": { "seconds": "1" }, "x": 10.0, "y": 10.0 },
  { "id": 2, "type": "ui.toast", "values": { "text": "tick" }, "x": 120.0, "y": 10.0 }
 ]
}
```

---

**Next:** [11. Cheat sheet](11-cheatsheet.md)
