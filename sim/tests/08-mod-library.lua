-- 08-mod-library -- publish an API for other mods to use.
-- Recipe 10.8 in docs/10-recipes.md.

sim.load()
sim.tick(0.05)

-- ---- the library announces what it offers ----------------------------------------
logged("exported double, describe, version, lib", "the mod lists its exports")

-- ---- and the API surface is really there ------------------------------------------
eq(sim.eval_value("tl.id"), "08-mod-library", "tl.id is the mod's own id")
eq(sim.eval_value("tl.version"), "0.2-beta", "tl.version is the game's api version")
eq(sim.eval_value("tl.export ~= nil"), true, "tl.export exists")

local window = sim.window("Library")
ok(window, "the library opens a window so you can tell it loaded")

local function window_text()
    local out = {}
    for _, w in ipairs(sim.widgets()) do
        if w.text then out[#out + 1] = w.text end
    end
    return table.concat(out, "\n")
end

contains(window_text(), "exports: double", "and lists them")
contains(window_text(), "double(21) = 42", "the exported function really works")

-- ---- emitting with nobody listening must be harmless ------------------------------
sim.click_button("emit a test event")
sim.tick(0.05)
eq(sim.errors(), 0, "an event with no listener does not fault the mod")

-- ---- the exports are per-mod, so a second load keeps them clean ---------------------
eq(#sim.running(), 1, "only this mod is running")

no_faults()
