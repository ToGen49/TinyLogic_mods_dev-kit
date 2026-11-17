-- 01-window-setting -- a window whose setting survives a restart.
-- Recipe 10.1 in docs/10-recipes.md.

sim.load()
sim.tick(0.05)

-- ---- the window opens as soon as the mod runs --------------------------------
ok(sim.window("My Tool"), "the window opens")
eq(sim.widget("scale") and sim.widget("scale").type, "slider", "it has a scale slider")
eq(sim.widget("progress") and sim.widget("progress").type, "bar", "and a progress bar")
eq(sim.widget("launches") and sim.widget("launches").type, "label", "and a launch counter")

-- ---- a value moved through the UI is written to store.json at once -----------
sim.ui_set("scale", 2.5)
sim.tick(0.05)
eq(sim.store_value("scale"), 2.5, "moving the slider saves the new value")
eq(sim.store_value("launched"), 1, "the launch counter was recorded")

-- ---- the setting is read back on the next load --------------------------------
sim.reload()
sim.tick(0.05)
eq(sim.store_value("launched"), 2, "a second launch increments the counter")
eq(sim.widget("scale").value, 2.5, "the slider comes back at 2.5 after a reload")
eq(sim.eval_value("tl.id"), "01-window-setting", "the test can still talk to the mod")
eq(sim.eval_value("tl.store.get('launched', 0)"), 2, "...including its saved store")

-- ---- a button click is a single frame ----------------------------------------
sim.click_button("reset")
sim.tick(0.05)
eq(sim.store_value("scale"), 1, "reset puts the setting back to 1")

sim.click_button("reset")
sim.tick(0.05)
eq(sim.store_value("launched"), 2, "reset does not touch the launch counter")

-- ---- the window keeps rendering every frame -----------------------------------
local first = #sim.windows()
sim.tick(0.1)
eq(#sim.windows(), first, "the window is redrawn on every frame")

no_faults()
