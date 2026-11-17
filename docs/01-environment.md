# 1. Where things live

> Back to the [kit index](../readme.md) · Next: [2. Quick start](02-quickstart.md)

Two roots are used throughout the kit:

| Placeholder | Meaning | Typical contents |
|---|---|---|
| `<kit>` | The root folder of this kit (the folder holding this `readme.md`) | `docs/`, `template/`, `examples/`, `api/`, `tools/` |
| `<install>` | The game's installation folder | the executable, `assets/`, `lib/`, `READ ME.txt` |
| `<profile>` | The **beta profile** folder — your data, separate from the stable game | `mods/`, `projects/`, `logs/`, `settings.json`, `library.tlc`, `disks/` |
| `<mod-id>` | A single mod's folder, named after its `id` | `mod.json`, `main.lua`, `graph.json`, `store.json` |

**Where the game looks for mods:**

```text
<profile>/mods/<mod-id>/
```

Only that location is scanned. You can keep sources anywhere else — this kit,
a version control repo, a scratch folder — but a mod runs only once it exists
under `<profile>/mods/<mod-id>/`. The kit's [`tools/install.sh`](../tools/install.sh)
does that copy (or symlink) for you.

**Where the shipped documentation and samples are:**

```text
<install>/assets/mods/
├── api.json      # official API reference (version 0.2-beta)
├── prelude.lua   # the Lua runtime that builds `tl` and the sandbox
└── samples/      # example mods + starter.txt
```

This kit carries its own copy of the official reference at
[`<kit>/api/api.json`](../api/api.json) — see
[`tools/sync-api.sh`](../tools/sync-api.sh) to refresh it after a game update.

**Where the log is:**

```text
<profile>/logs/tinylogic.log        # current session
<profile>/logs/tinylogic.prev.log   # previous session
```

> On Linux, both roots sit under the user's data directory, e.g.
> `~/.local/share/Mazell/TinyLogic/` — with `beta/<version>/` for the install and
> `beta-profile/` for the profile. On other platforms the equivalent is the
> system's application-data folder; the game's own `READ ME.txt` names the exact
> location for your platform. Throughout this kit, only the placeholders are used.

Facts that hold regardless of machine:

- The beta branch keeps its own profile: its own `settings.json`, `library.tlc`,
  `logs/`, `disks/`. **Cloud saves are off** in the beta.
- Art resolution is **480 × 270**; 1 board tile = 16 board pixels.
- The beta is unpacked from the stable game's main menu → *beta*.

## Files of a mod

```text
<profile>/mods/<mod-id>/
├── mod.json      # required: id, name, author, version, description, enabled
├── main.lua      # optional: the script (runs first)
├── graph.json    # optional: the node graph (runs second, same environment)
└── store.json    # created by the game on first tl.store.set()
```

And on the game side:

```text
<install>/assets/mods/
├── api.json      # official API reference (version 0.2-beta)
├── prelude.lua   # the Lua runtime that builds `tl` and the sandbox
└── samples/      # example mods + starter.txt
```
