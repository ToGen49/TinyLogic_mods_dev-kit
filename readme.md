# Tiny Logic — Mod Kit

Everything you need to write, test, install and share a Tiny Logic mod: a split
guide, a template, eleven runnable examples, an offline copy of the official API,
and scripts to scaffold, validate and install a mod.

This kit is **machine-independent**. Folders appear as placeholders — substitute
your own:

| Placeholder | Meaning |
|---|---|
| `<kit>` | This folder (the one holding this `readme.md`) |
| `<install>` | The game's installation folder |
| `<profile>` | The game's profile folder — where mods are actually loaded from |
| `<mod-id>` | A single mod's folder, named after its `id` |

Details in [`docs/01-environment.md`](docs/01-environment.md).

- **Game version this kit was written against:** `1.6.0-beta.1`
- **Mod API version:** `0.2-beta` (`tl.version`)
- **Lua runtime:** Lua 5.5 (`_VERSION = "Lua 5.5"`, `jit = nil` — not LuaJIT)
- **Sources:** the game's own `api.json` and `prelude.lua`, read from disk — not guesswork

---

## Sixty-second start

```bash
<kit>/tools/new-mod.sh my-mod --name "My Mod"   # scaffold from template/
<kit>/tools/validate.py mods/my-mod             # check it before launching
<kit>/tools/install.sh mods/my-mod              # copy into <profile>/mods/
```

Then in the game: **menu → mods → save + run**.

To try an existing example instead:

```bash
<kit>/tools/install.sh <kit>/examples/01-window-setting
```

---

## The kit

```text
<kit>/
├── readme.md          ← you are here: the index
├── docs/              the guide, split by topic
│   ├── 01-environment.md    where things live, placeholder conventions
│   ├── 02-quickstart.md     your first mod, end to end
│   ├── 03-sandbox.md        what Lua you get — and what you don't
│   ├── 04-api.md            full API reference (98 entries, 12 groups)
│   ├── 05-graphs.md         graph.json format, built-in node types
│   ├── 06-debugging.md      console, logs, fault limits, table dumping
│   ├── 07-limits.md         gotchas and hard constraints
│   ├── 08-sharing.md        publishing and handing mods to other players
│   ├── 09-samples.md        the samples shipped with the game
│   ├── 10-recipes.md        one snippet per use case
│   └── 11-cheatsheet.md     printable one-pager
├── template/          minimal mod skeleton (mod.json + main.lua + graph.json)
├── examples/          11 runnable mods, one per recipe
├── api/api.json       offline copy of the game's official reference
└── tools/             scripts (see below)
```

### Docs

| Start here if you want to… | Read |
|---|---|
| understand where mods live and what the placeholders mean | [01-environment](docs/01-environment.md) |
| build and run your first mod today | [02-quickstart](docs/02-quickstart.md) |
| know exactly what the sandbox allows | [03-sandbox](docs/03-sandbox.md) |
| look up a function's signature | [04-api](docs/04-api.md) · [`api/api.json`](api/api.json) |
| work with the node graph editor | [05-graphs](docs/05-graphs.md) |
| find out why your mod isn't printing | [06-debugging](docs/06-debugging.md) |
| avoid the ten classic mistakes | [07-limits](docs/07-limits.md) |
| publish or send your mod to someone | [08-sharing](docs/08-sharing.md) |
| copy a working pattern | [10-recipes](docs/10-recipes.md) |
| have everything on one page | [11-cheatsheet](docs/11-cheatsheet.md) |

### Tools

| Script | What it does |
|---|---|
| [`tools/new-mod.sh`](tools/new-mod.sh) | Scaffold a mod from `template/` — `new-mod.sh <mod-id> --name "..."` |
| [`tools/validate.py`](tools/validate.py) | Check `mod.json`, flag `tl.*` names missing from `api/api.json`, error on sandbox violations (`io`, `os`, `require`, `load`, `host.*`) |
| [`tools/install.sh`](tools/install.sh) | Copy (or `--link`) a mod into `<profile>/mods/`, `--zip` to package it, `--where` to print the detected profile |
| [`tools/sync-api.sh`](tools/sync-api.sh) | Refresh `api/api.json` after a game update — `--auto`, `--install <path>`, or `--from <file>` |

All of them take `--help`. `install.sh` auto-detects the profile on Linux
(`$XDG_DATA_HOME` or `~/.local/share`); override with `--profile` or
`TINYLOGIC_PROFILE` on any other platform.

```bash
<kit>/tools/validate.py            # no argument = template/ + every example
```

### Examples

Eleven complete mods in [`examples/`](examples/README.md), one per recipe —
window + persistence, board drawing, screen overlay, timers and watches, player
input, circuit building, console commands, exports/require, event bus, custom
node types, and a graph-only mod with no Lua at all.

---

## Where a mod actually runs

```text
<profile>/mods/<mod-id>/
├── mod.json      # required: id, name, author, version, description, enabled
├── main.lua      # optional: the script (runs first)
├── graph.json    # optional: the node graph (runs second, same environment)
└── store.json    # created by the game on first tl.store.set()
```

Only `<profile>/mods/` is scanned. Keep your sources in this kit, a repo, or
anywhere else — `tools/install.sh` puts them where the game looks.

---

## Constraints worth knowing before you start

1. **No file I/O, no network, no `require`, no `load`.** The sandbox gives you
   `tl.*`, `math`, `string`, `table`, `utf8`, `coroutine` and `print` — nothing else.
2. **No real-time external channel.** `tl.store` is cached in memory; an outside
   process editing `store.json` is only seen after a reload. No sockets, no pipes.
3. **Budgets:** 3 M instructions per handler, 30 M per load, **25 faults → the mod is stopped**.
4. Every change a mod makes lands in the **player's undo history**.

The full list is [docs/07-limits.md](docs/07-limits.md).

---

## Contributing to the kit

- Found an API entry that's wrong? Fix [`docs/04-api.md`](docs/04-api.md) against
  [`api/api.json`](api/api.json) — the JSON is the source of truth.
- Added a pattern worth keeping? Add it to [`docs/10-recipes.md`](docs/10-recipes.md)
  **and** as a runnable folder in [`examples/`](examples/README.md), then run
  `<kit>/tools/validate.py` — unlisted `tl.*` names fail the check.
- Game updated? `<kit>/tools/sync-api.sh --auto`, then re-validate everything.
