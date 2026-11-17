# 6. Debugging

> Back to the [kit index](../readme.md) · Previous: [5. Node graphs](05-graphs.md) · Next: [7. Limits and gotchas](07-limits.md)

### 6.1 The mod console

Each mod has a console (tabs in the mods panel: `script`, `graph`, `console`).
Anything typed there is evaluated **in that mod's own environment** — so you can
reach `tl`, `vars`, and anything your `main.lua` defined:

```text
tl.board.count()
vars
tl.time()
```

If the line starts with a name you registered via `tl.command`, that command runs
instead, with the rest of the line as its argument.

### 6.2 Logging

```lua
tl.log("parts:", n)     -- normal line
tl.warn("watch out")    -- yellow line
print("same as tl.log") -- print is routed to the same console
```

### 6.3 Faults

Errors are counted per mod and written to the console as
`<what>: <message>`. At **25** faults the mod is stopped until you *save + run* again.

### 6.4 Game log

```bash
tail -f <profile>/logs/tinylogic.log
```

This is the file to attach when reporting a bug (the game itself says: send the
log from `beta-profile/logs/tinylogic.log`).

### 6.5 Dumping an unknown table

Useful when the API grows and `api.json` lags behind:

```lua
local seen = {}
local function inspect(name, value, depth)
    local t = type(value)
    print(string.rep(" ", depth * 2) .. name .. " [" .. t .. "]")
    if t ~= "table" or depth >= 3 or seen[value] then return end
    seen[value] = true
    local keys = {}
    for k in pairs(value) do keys[#keys + 1] = k end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    for _, k in ipairs(keys) do
        local ok, v = pcall(function() return value[k] end)
        if ok then inspect(tostring(k), v, depth + 1)
        else print("  " .. tostring(k) .. " [unreadable]") end
    end
end

inspect("_G", _G, 0)
inspect("tl", tl, 0)
```

### 6.6 Static checks before you launch

```bash
<kit>/tools/validate.py <kit>/mods/my-mod
```

Checks `mod.json` (required keys, id/folder match, types), warns about `tl.*`
names that are **not** in `api/api.json`, and errors on anything the sandbox
forbids (`io`, `os`, `require`, `load`, `host.*`, sockets).

Rule of thumb, and it applies to this whole kit: **a function is only
documented once its location, parameters and real behaviour are known.** An
`api.json` entry, an in-game tooltip, or observed output all count; a guessed
name does not.

### 6.7 Run it without launching the game

```bash
<kit>/tools/tl-sim <kit>/mods/my-mod              # smoke run: load, run 2 s, report
<kit>/tools/tl-sim <kit>/mods/my-mod --test FILE  # a real test file
<kit>/tools/tl-sim --all                          # every example's test
```

Loads your mod under the **game's own `prelude.lua`** — the real sandbox, the
real instruction budgets, the real graph compiler — with only the board, the
clock and the input replaced by a fake `host.*`. Frames are advanced by hand;
logs, toasts, draws and windows are captured instead of shown. A test file can
press keys, click, place parts, type commands, then assert on what the mod did:

```lua
sim.load()
sim.tick(0.05)
ok(sim.window("My Tool"), "the window opens")
sim.command("build")
eq(#sim.parts(), 3, "the build placed three parts")
no_faults()
```

A failed check prints what it expected and what it got, then exits `1` — so it
drops straight into a pre-commit hook or CI. Full test API, and the limits of
the circuit model, in [`../sim/README.md`](../sim/README.md).

---

**Next:** [7. Limits, gotchas and hard constraints](07-limits.md)
