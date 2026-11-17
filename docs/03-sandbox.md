# 3. The sandbox — what Lua you actually get

> Back to the [kit index](../readme.md) · Previous: [2. Quick start](02-quickstart.md) · Next: [4. API reference](04-api.md)

A mod does **not** get a normal Lua state. `prelude.lua` builds a private
environment per mod (`new_mod`), and the game's own text is explicit:

> *"a mod only touches the board through the mod api: it can't read files or reach the internet."*

### 3.1 Available

| Category | Names |
|---|---|
| Base functions | `assert`, `error`, `ipairs`, `next`, `pairs`, `select`, `tonumber`, `tostring`, `type`, `pcall`, `xpcall`, `setmetatable`, `rawget`, `rawset`, `rawequal`, `rawlen`, `_VERSION` |
| `getmetatable` | **Restricted** — returns the metatable of *tables* only; string metatable is unreachable (so no mod can change text behaviour for everyone else) |
| Libraries | `math`, `string`, `table`, `utf8`, `coroutine` — each a **copy**, so one mod cannot poison another |
| Logging | `print(...)` → routed to this mod's console (`host.log(id, 0, ...)`) |
| API | `tl` (see [§4](04-api.md)) |
| Shared state | `vars` — one table shared by this mod's script **and** its node graph |
| Self-reference | `_G` points at the sandbox itself |

### 3.2 Not available

| Missing | Consequence |
|---|---|
| `io` | No file access at all |
| `os` | No time/process/environment access (use `tl.time()`) |
| `package`, `require` | No module system — use `tl.require(id)` for other mods |
| `debug` | No introspection hooks |
| `load`, `loadfile`, `dofile` | **Not in the mod sandbox** (they exist only inside `prelude.lua` itself and in the console evaluator) |
| `dofile`, `loadstring` | No |
| Sockets / `http` | No network of any kind |

[`tools/validate.py`](../tools/validate.py) flags every one of these if it
appears in your `main.lua`.

> Note: the launcher/VM itself *does* have `load`, `loadfile`, `dofile`, `math`,
> `string`, `table`, `coroutine`, `utf8`, `print`, and no `io`/`os`/`package`/`debug`.
> That is the environment `prelude.lua` runs in — **not** the one your mod runs in.
> Don't confuse the two.

### 3.3 Execution budgets

| Budget | Value | Applies to |
|---|---|---|
| `FRAME_BUDGET` | **3 000 000** Lua instructions | One event handler / one timer tick |
| `LOAD_BUDGET` | **30 000 000** Lua instructions | One `main.lua` or graph compile, one console line |

- Exceeding the budget raises an error caught by `host.over()`.
- **25 faults and the mod is stopped**: `"stopped after 25 errors (fix it, then save + run)"`.
- Everything a mod changes lands in the **player's undo history**
  (`tl.board.undo()` / `tl.board.redo()`).

---

**Next:** [4. API reference](04-api.md)
