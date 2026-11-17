# 5. Node graphs (`graph.json`)

> Back to the [kit index](../readme.md) · Previous: [4. API reference](04-api.md) · Next: [6. Debugging](06-debugging.md)

Format, as used by the shipped samples:

```json
{
 "links": [
  { "from": 1, "to": 2, "out": "next", "in": "exec", "exec": true },
  { "from": 3, "to": 4, "out": "wire", "in": "wire" }
 ],
 "nodes": [
  { "id": 1, "type": "event.every", "values": { "seconds": "0.15" }, "x": 10.0, "y": 10.0 },
  { "id": 4, "type": "board.wire_color", "x": 330.0, "y": 40.0 }
 ]
}
```

- `nodes[].id` is an integer; `nodes[].type` is a node type id.
- `nodes[].values` holds the literal input values (as **strings**).
- `x`/`y` are editor coordinates (floats).
- `links[]`: `from` → node id, `out` → output pin name, `to` → node id,
  `in` → input pin name, `exec: true` for flow links.

Built-in node categories: **Events, Flow, Math, Logic, Text, Variables, Draw,
UI, Sound, Camera, Script**. Highlights:

| Node id | What it does |
|---|---|
| `event.load` | When the mod starts |
| `event.frame` | Every frame (`dt` output) |
| `event.every` | Every N seconds (`seconds` input, const) |
| `event.draw` | When drawing |
| `event.key` | When a key is pressed (`key` input, const) |
| `event.click` | Board left click → `x`, `y` (tiles) |
| `event.placed` / `event.removed` | Part placed / removed |
| `event.wired` | Wire added |
| `event.custom` | Any event by name |
| `event.command` | A console command typed → `text` |
| `event.window` | A window (`title` input, const) |
| `event.function` | A function `main.lua` can call by name |
| `var.set` / `var.get` / `var.add` | The shared `vars` table |
| `var.store_set` / `var.store_get` | Persistent `tl.store` |
| `script.call` | Call a Lua function written in `main.lua` |
| `script.value` | Any name from the script (variable or table field) |
| `script.emit` | `tl.emit` — every mod hears it |
| `script.engine` | `tl.call(op, {})` — raw engine interface |

`main.lua` runs **before** the graph. Both share `vars`.

A runnable graph-only example lives in
[`<kit>/examples/11-graph-only/`](../examples/11-graph-only/).

---

**Next:** [6. Debugging](06-debugging.md)
