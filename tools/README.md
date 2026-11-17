# tools/

Four scripts. All are POSIX-ish bash + Python 3, take `--help`, and never bake
in an absolute path — they derive everything from `$HOME`, `$XDG_DATA_HOME`, or
arguments you pass.

| Script | Purpose |
|---|---|
| `new-mod.sh` | Create a mod from `template/` |
| `validate.py` | Static checks against `api/api.json` |
| `install.sh` | Put a mod where the game looks for it, or zip it for sharing |
| `sync-api.sh` | Refresh `api/api.json` after a game update |

## new-mod.sh

```bash
tools/new-mod.sh <mod-id> [--name "Human Name"] [--author "you"] [--dir <parent>]
```

Creates `<dir>/<mod-id>/` (default `<kit>/mods/`) with `mod.json`, `main.lua`,
`graph.json` from `template/`. Refuses to overwrite an existing folder, and
rejects ids that aren't `lowercase-with-dashes`.

```bash
tools/new-mod.sh led-matrix --name "LED Matrix"
```

## validate.py

```bash
tools/validate.py [<mod-folder> ...]        # no args: template/ + examples/*
```

| Check | Severity |
|---|---|
| `mod.json` missing / not JSON / missing a required key / wrong value type | error |
| `id` != folder name (skipped for `template/`, whose id is a placeholder) | error |
| unknown keys in `mod.json` | warning |
| id not lowercase `a-z0-9_-` | warning |
| neither `main.lua` nor `graph.json` | error |
| `io`, `os`, `require`, `package`, `debug`, `load`, `loadfile`, `dofile`, `host`, `collectgarbage` used in `main.lua` | error |
| `tl.something` not present in `api/api.json` | error |
| unbalanced `()` `{}` `[]` in `main.lua` | warning |
| `graph.json` invalid, node without `id`/`type`, link pointing at a missing node | error |

Exit code `0` when clean, `1` on any error. Warnings don't fail the run.

It reads `api/api.json`, so after a game update run `sync-api.sh` first — the
checker stays correct even when the prose in `docs/` lags behind.

## install.sh

```bash
tools/install.sh <mod-folder> [--profile <path>] [--link] [--dry-run]
tools/install.sh --zip <mod-folder>       # build dist/<id>.zip for sharing
tools/install.sh --where                  # print the profile it would use
```

Profile detection order:

1. `--profile <path>`
2. `$TINYLOGIC_PROFILE`
3. `$XDG_DATA_HOME`/`~/.local/share` → `Mazell/TinyLogic/beta-profile`
4. any sibling folder of that base holding `mods/` or `projects/`
5. give up and tell you to pass `--profile`

Installs to `<profile>/mods/<id>/`. Copies exclude `store.json` (runtime state,
not yours to ship) and `.git`. `--link` symlinks instead, so edits show up on the
next **save + run** without re-copying. Warns when `mod.json`'s `id` disagrees
with the folder name — the game keys mods on the folder name.

## sync-api.sh

```bash
tools/sync-api.sh --auto                       # search common locations
tools/sync-api.sh --install <game-install>     # accepts the root or assets/mods/
tools/sync-api.sh --from <file>
```

Copies the game's `api.json` over `api/api.json` and prints what changed
(version, group count, entry count). Safe to re-run: if source and destination
are the same file it says so instead of erroring.

## Requirements

- bash and Python 3 (standard library only — no pip installs, no `zip` binary)

Everything else is optional.
