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

---

**Next:** [7. Limits, gotchas and hard constraints](07-limits.md)
