# Template

The minimal skeleton of a mod. Three files, two of them optional.

| File | Required | Notes |
|---|---|---|
| `mod.json` | **yes** | `id` must match the folder name |
| `main.lua` | no* | The script. Runs **first** |
| `graph.json` | no* | The node graph. Runs **second**, same environment |

\* A mod needs at least one of the two — a mod can be graph-only (empty
`main.lua`) or script-only (empty `nodes`/`links`).

## Use it

```bash
<kit>/tools/new-mod.sh <mod-id> --name "Human Name"
<kit>/tools/validate.py mods/<mod-id>
<kit>/tools/install.sh mods/<mod-id>
```

Then in the game: **menu → mods → save + run**.

## Notes

- `main.lua` and `graph.json` share the `vars` table.
- Anything you set up in `main.lua` runs again from scratch on every *save + run*.
- The window callback in `main.lua` runs every frame — keep it light.
