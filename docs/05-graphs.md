# 5. Node graphs (`graph.json`)

> Back to the [kit index](../readme.md) · Previous: [4. API reference](04-api.md) · Next: [6. Debugging](06-debugging.md)

Format, as used by the shipped samples:

```json
{
 "links": [
  { "from": 1, "to": 2, "out": "next", "in": "exec", "exec": true },
  { "from": 2, "to": 3, "out": "next", "in": "exec", "exec": true },
  { "from": 4, "to": 3, "out": "value", "in": "by" }
 ],
 "nodes": [
  { "id": 1, "type": "event.every", "values": { "seconds": "0.15" }, "x": 10.0, "y": 10.0 },
  { "id": 2, "type": "ui.log", "values": { "text": "tick" }, "x": 190.0, "y": 10.0 },
  { "id": 3, "type": "var.add", "values": { "name": "n" }, "x": 360.0, "y": 10.0 },
  { "id": 4, "type": "var.get", "values": { "name": "step" }, "x": 190.0, "y": 110.0 }
 ]
}
```

- `nodes[].id` is an integer; `nodes[].type` is a node type id.
- `nodes[].values` holds the literal input values (as **strings**).
- `x`/`y` are editor coordinates (floats).
- `links[]`: `from` → node id, `out` → output pin name, `to` → node id,
  `in` → input pin name, `exec: true` for flow links.
- Every `from`/`to` must name a node that exists in `nodes[]`.

> **Flow is a chain, not a fan.** A node has exactly **one** `next` slot, and
> the compiler stores it as `exec_out[from].next = to`. Two `next` links leaving
> the same node therefore overwrite each other and only the **last** one runs —
> silently, with no error. To do three things from one event, chain them
> (`1 → 2 → 3 → 4`), never fan out (`1 → 2`, `1 → 3`, `1 → 4`).
> The one place a node *does* branch is a named flow output such as
> `ui.button`'s `clicked`, written `#clicked` in the node's code.

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
