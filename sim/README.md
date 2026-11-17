# `sim/` — test a mod without starting the game

> Back to the [kit index](../readme.md)

The simulator loads your mod exactly the way the game does and lets a script
drive it: press keys, click, place parts, run frames, then assert on what the
mod did. No window, no GPU, no profile, no waiting for the game to boot.

```bash
tools/tl-sim <mod-folder>                  # smoke run: load it, run 2 s, report
tools/tl-sim <mod-folder> --test FILE      # run one test file
tools/tl-sim --all                         # run every test in sim/tests/
```

Exit code `0` when everything passed, `1` when a check failed or the mod
faulted, `2` when the simulator itself could not start.

---

## What is real, and what is faked

The whole point is to keep the parts that are easy to get wrong **real**:

| Real (the game's own code) | Faked (this folder) |
|---|---|
| `prelude.lua` — the sandbox, the `tl.*` API | `host.*`, the 24 functions the sandbox calls |
| instruction budgets and the "stopped after 25 errors" rule | the board: parts, wires, camera, selection |
| the graph compiler (`__tl.compile`) | the clock (virtual time, advanced by frames) |
| timers, watches, events, windows, commands | logs, toasts, sounds, draws — captured, not shown |
| the store (`tl.store`) — in memory, not on disk | key/mouse input, which a test injects |

Mod code never runs here. It runs inside `prelude.lua`'s real sandbox; this
folder only answers its questions. That is the entire engine boundary the game
defines, and it is why a test that passes here behaves the same way in game.

### Requirements

* **Lua 5.5** — the same version the game runs. `tools/tl-sim` looks for
  `lua5.5`, then `lua`, and warns if what it found is not 5.5. Set
  `TINYLOGIC_LUA` to point at a specific interpreter.
* bash, for the wrapper.

### Where `prelude.lua` comes from

In this order, and the report always says which one was used:

1. `--prelude <file>`
2. `--install <game folder>` (also `<folder>/prelude.lua`)
3. `$TINYLOGIC_INSTALL`
4. the usual game locations — `$XDG_DATA_HOME/Mazell/TinyLogic/...`,
   `~/Games/...`, `~/...`, one or two version levels deep
5. **`sim/prelude.lua`**, the copy bundled with this kit, so the simulator
   works on a machine that has never installed the game

Because the installed game wins when there is one, a new game release is picked
up automatically. Use `--prelude` to pin a version.

---

## Writing a test

A test file lives in `sim/tests/<mod-id>.lua` and is **plain Lua**, run before
the mod is:

```lua
-- 06-build-circuit.lua
sim.load()                    -- start the mod (call this when you are ready)
sim.tick(0.05)                -- run 3 frames of virtual time

eq(#sim.parts(), 0, "the board starts empty")

sim.command("build")          -- type a command in the mod's console
eq(#sim.parts(), 3, "the build places 3 parts")

sim.undo()
eq(#sim.parts(), 0, "one undo reverses it")
no_faults()
```

Run it with:

```bash
tools/tl-sim examples/06-build-circuit --test sim/tests/06-build-circuit.lua
```

**The test runs first, `sim.load()` is yours to call.** That is what lets you
put parts on the board, move the mouse or pre-seed the store before the mod
starts — several of the shipped examples only make sense that way:

```lua
local sw = sim.place("switch", 2, 2, {label = "A"})
local lt = sim.place("light", 6, 2)
sim.wire(sw, "out", lt, 0, 4)   -- now the mod finds a light on load
sim.load()
```

If a test forgets `sim.load()`, the mod is loaded afterwards and the report
says so — but anything asserted before that point will be checking an empty
world.

To pull in a second mod, pass a path (resolved from the kit root):

```lua
sim.load("examples/08-mod-library")   -- must be running first for tl.require
sim.load()                            -- the mod under test
```

### Assertions

| Assertion | Checks |
|---|---|
| `ok(cond, msg)` | truth |
| `eq(got, want, msg)` | deep equality (tables included) |
| `neq(got, unwanted, msg)` | not equal |
| `near(got, want, tolerance, msg)` | numbers within a tolerance |
| `contains(haystack, needle, msg)` | substring — haystack may be a string or a list |
| `not_contains(haystack, needle, msg)` | substring absent |
| `logged(needle, msg)` | the mod's log mentions it |
| `fails(fn, msg)` | the function raised |
| `no_faults(msg)` | the mod produced no errors (auto-checked anyway) |
| `note(text)` | print a line in the report, assert nothing |

A failed assertion reports what it expected and what it got, and the run exits
`1`. Every test also fails automatically if the mod faulted at any point.

---

## The `sim` object

### Loading and running

| Call | Does |
|---|---|
| `sim.load(folder?)` | start a mod (no folder = the one on the command line) |
| `sim.reload()` | start it again — the store survives |
| `sim.unload(id?)` | stop it; custom node types go away with it |
| `sim.running()` | ids of the mods currently running |
| `sim.tick(seconds)` / `sim.frames(n)` / `sim.seconds(s)` | advance virtual time, one `__tl.frame` per 1/60 s |
| `sim.time()` | virtual seconds elapsed |
| `sim.event(name, ...)` | dispatch a custom event |
| `sim.command(text)` | type into the mod's console |
| `sim.eval(expr)` | run Lua in the mod's environment, return its printed form |
| `sim.eval_value(expr)` | same, but give the value back (see below) |

### Input a mod can see

| Call | Does |
|---|---|
| `sim.key(name, down)` | press or release a key, and dispatch the event |
| `sim.click(x, y)` | click a board tile |
| `sim.mouse(x, y, down?)` | move the cursor (tile coords are derived) |
| `sim.captured(id?)` | whether the mod holds keyboard capture |
| `sim.click_button(label)` | click a button in a window — **next tick only** |
| `sim.ui_set(label, value)` | force a toggle/slider — **next tick only** |

### The board

| Call | Does |
|---|---|
| `sim.place(kind, x?, y?, opts?)` | place a part, returns its id |
| `sim.wire(a, pin_a, b, pin_b, color?)` | wire two pins, returns the wire id |
| `sim.part(id)` / `sim.parts(kind?)` | one part / a list of them |
| `sim.wires(paths?)` | the wires |
| `sim.read(id, pin?)` | `value, volts` — the same number the mod gets |
| `sim.set(id, on)` / `sim.toggle(id)` | throw a switch |
| `sim.count()` | `parts, wires` |
| `sim.clear()` / `sim.undo()` / `sim.redo()` | the editor's own controls |
| `sim.state()` / `sim.camera()` / `sim.select(ids)` | selection, camera |
| `sim.find_space(w, h)` / `sim.catalog()` | the part finder |

### What the mod did

| Call | Does |
|---|---|
| `sim.logs()` / `sim.log_list()` | everything printed, as text / as records |
| `sim.logged(needle)` | search the log, returns a boolean |
| `sim.errors(id?)` / `sim.warns()` / `sim.allow_faults()` / `sim.expect_faults(n)` | fault counting |
| `sim.toasts()` / `sim.sounds()` / `sim.notes()` | popups and audio |
| `sim.draws()` | the draw commands of the last frame |
| `sim.windows()` / `sim.window(title)` / `sim.widget(needle)` / `sim.widgets()` | the mod's UI |
| `sim.store(id?)` / `sim.store_value(key, id?)` | the mod's saved settings |
| `sim.node_types()` / `sim.node_info(id)` / `sim.nodes()` | graph node types |
| `sim.frame_errors()` | errors that escaped `prelude.lua` (budget overruns) |
| `sim.path(rel)` / `sim.mod_id()` / `sim.engine()` | helpers |

### Reading values out of the mod

`sim.eval_value(expr)` runs `expr` inside the mod and hands the value back: a
number, boolean, nil or table comes back as itself, anything else as text.

```lua
eq(sim.eval_value("tl.id"), "06-build-circuit")
eq(sim.eval_value("tl.board.count()"), 3)      -- two values; the first is returned
eq(sim.eval_value("vars.ticks"), 1)            -- the graph's shared vars
eq(sim.eval_value("tl.store.get('launched', 0)"), 2)
```

It is a text bridge, not a reference: you get the value at the moment you ask,
not a handle onto it, and locals in `main.lua` are invisible (only globals such
as `tl` and `vars` are).

---

## The circuit model — and its limits

Wires are joined into nets (union-find), then values are propagated:

* **power / ground / switch / button / number / clock** drive their output net
* **and / or / not / nand / nor / xor / xnor / buffer** are evaluated until
  nothing changes any more
* **resistor / capacitor / coil / diode** pass their input net through
* **light / display / led / buzzer** read their input net
* a high digital net reads **5 V**; anything else reads itself

**Not modelled: transistors and analogue.** A transistor reads 0, so a gate
built the way the shipped `auto-builder` sample builds one will not conduct.
Unknown part kinds are still placeable — they get default pins and behave as
passive blocks reading 0, so an unusual mod is never blocked, it just gets no
circuit behaviour from that kind.

This is enough to test *mods*: what a mod places, wires, reads, draws and
says. It is not a SPICE. If you need the real thing, run the game.

**Undo** is snapshot based and grouped by action — one command, one timer tick,
one load = one undo step — which is what makes `tl.board.undo()` reverse a
whole build in a single go.

**Budgets** are enforced with a Lua count hook, so a mod that spins forever
stops the same way it does in game. `--no-budget` turns this off if it gets in
the way.

---

## Files

| File | What it is |
|---|---|
| `run.lua` | entry point: parse options, find `prelude.lua`, boot, report |
| `engine.lua` | the fake `host.*` and the in-memory board |
| `harness.lua` | the `sim` object, assertions, the report |
| `catalog.lua` | part kinds, pins, and how the circuit model treats each |
| `json.lua` | a small JSON decoder, for `mod.json` and `graph.json` |
| `prelude.lua` | **the game's**, bundled as the fallback when no game is installed |
| `tests/` | one test per example in `<kit>/examples/` |

---

**Next:** [11. Cheat sheet](../docs/11-cheatsheet.md)
