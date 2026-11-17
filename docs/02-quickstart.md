# 2. Quick start — your first mod

> Back to the [kit index](../readme.md) · Previous: [1. Where things live](01-environment.md) · Next: [3. The sandbox](03-sandbox.md)

### 2.1 Open the mods panel

In a project: **menu → mods** (labelled *scripts + node graphs (beta)*).

Useful buttons you will see there: `+ new mod`, `save + run`, `script`, `graph`,
`console`, `publish`.

### 2.2 Create the mod

With the kit's scaffolder:

```bash
<kit>/tools/new-mod.sh my-mod --name "My Mod"
```

That creates `<kit>/mods/my-mod/` from [`<kit>/template/`](../template/).
Or by hand:

```bash
mkdir -p <profile>/mods/<mod-id>
```

You can also let the game do it: the mods panel has a `+ new mod` button.

### 2.3 `mod.json`

```json
{
 "id": "hello",
 "name": "Hello",
 "author": "you",
 "version": "1.0",
 "description": "A new mod.",
 "enabled": true
}
```

| Key | Required | Notes |
|---|---|---|
| `id` | yes | Folder name too. Used by `tl.id`, `tl.require(id)`, `tl.store` |
| `name` | yes | Shown in the panel |
| `author` | yes | Free text |
| `version` | yes | Free text (`"1.0"`, `"1.1"`…) |
| `description` | yes | One line, shown in the list |
| `enabled` | yes | `true` = the mod loads at start |
| `icon`, `tags` | no | Keys recognised by the game |

Validate any mod against these rules with [`tools/validate.py`](../tools/validate.py).

### 2.4 `main.lua` (optional — a mod can be graph-only)

```lua
-- Runs once when the mod loads.
tl.log("hello from", tl.id, "api", tl.version)

tl.every(1, function()
    tl.log("uptime", math.floor(tl.time()), "s")
end)

tl.ui.window("Hello", function(ui)
    ui.label("parts: " .. tl.board.count())
    if ui.button("fit board") then tl.camera.fit() end
end, {w = 120})
```

### 2.5 `graph.json` (optional)

```json
{ "links": [], "nodes": [] }
```

A mod can be **only** a node graph (see the `rainbow-wires` sample: its
`main.lua` contains only comments). `main.lua` runs first, then the graph —
both in the **same** environment, sharing the `vars` table.

### 2.6 Install it into the profile

```bash
<kit>/tools/install.sh <kit>/mods/my-mod
```

Copy or symlink, your choice (`--link`), into `<profile>/mods/<mod-id>/`.

### 2.7 Run it

Hit **save + run**. To reload after editing files on disk, use *save + run* again
(the mod is dropped and rebuilt from scratch: `__tl.load` → `drop(id)` → `new_mod(id)`).

### 2.8 Files the game writes for you

| File | Written when |
|---|---|
| `store.json` | First `tl.store.set()` — appears next to `mod.json` |
| `mod.json` | When you edit metadata in the panel |
| `main.lua`, `graph.json` | When you edit in the panel's script/graph tabs |

Example `store.json` after `tl.store.set("best", 42)`:

```json
{ "best": 42 }
```

---

**Next:** [3. The sandbox — what Lua you actually get](03-sandbox.md)
