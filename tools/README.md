# tools/

Five scripts. The first four are POSIX-ish bash + Python 3, take `--help`, and
never bake in an absolute path — they derive everything from `$HOME`,
`$XDG_DATA_HOME`, or arguments you pass. `tl-sim` is bash + Lua 5.5.

| Script | Purpose |
|---|---|
| `new-mod.sh` | Create a mod from `template/` |
| `validate.py` | Static checks against `api/api.json` |
| `install.sh` | Put a mod where the game looks for it, or zip it for sharing |
| `sync-api.sh` | Refresh `api/api.json` after a game update |
| `tl-sim` | Run a mod without starting the game — smoke run or tests |

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

## tl-sim

```bash
tools/tl-sim <mod-folder>                # smoke run: load, run 2 s, report
tools/tl-sim <mod-folder> --test FILE    # run one test file against the mod
tools/tl-sim --all                       # every test in sim/tests/
```

Runs the mod under the **game's own `prelude.lua`**, so the sandbox, the
instruction budgets, the graph compiler and the event/timer/watch dispatch are
the real thing. Only `host.*` — the board, the clock, the input — is replaced.

```bash
tools/tl-sim examples/06-build-circuit
tools/tl-sim examples/06-build-circuit --test sim/tests/06-build-circuit.lua
```

| Option | Effect |
|---|---|
| `--test FILE` | run a test file instead of a plain smoke run |
| `--seconds N` | how long a smoke run lasts (default `2`) |
| `--fps N` | frame rate (default `60`) |
| `--no-budget` | do not enforce the instruction budgets |
| `--prelude PATH` / `--install PATH` | choose which `prelude.lua` to boot |
| `--no-logs` / `--quiet` | less output |
| `--all` | run every example's test and summarise |

Exit code `0` clean, `1` a check failed or the mod faulted, `2` the simulator
could not start (no Lua, no `prelude.lua`, bad folder).

`prelude.lua` is found via `--prelude`, `--install`, `$TINYLOGIC_INSTALL`, the
usual game locations, and finally the copy bundled in `sim/` — so it works with
or without the game installed, and prefers the installed one so a new release
is picked up automatically.

Test files, the full `sim.*` API and the limits of the circuit model are
documented in [`../sim/README.md`](../sim/README.md).

## Requirements

- bash and Python 3 (standard library only — no pip installs, no `zip` binary)
- **Lua 5.5** for `tl-sim` — the version the game itself runs. `tools/tl-sim`
  finds `lua5.5` or `lua` on `PATH` and warns if what it found is not 5.5;
  set `TINYLOGIC_LUA` to point at a specific interpreter.

Everything else is optional.
