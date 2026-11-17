-- 11-graph-only -- a mod with no main.lua at all, only a graph.
-- Recipe 10.11 in docs/10-recipes.md.

ok(sim.eval_value("tl.id") == nil, "before loading, no mod is running")

sim.load()
sim.tick(0.05)

eq(sim.eval_value("tl.id"), "11-graph-only",
   "the graph runs under the mod's own id, without any Lua of ours")

-- ---- the counter starts clean ------------------------------------------------------
local started = sim.eval_value("vars.ticks")
ok(started == nil or started == 0, "the counter has not been touched yet")

-- ---- one tick a second --------------------------------------------------------------
sim.tick(1.2)                    -- crosses t = 1.0

eq(sim.eval_value("vars.ticks"), 1, "the timer fired once")
ok(#sim.toasts() > 0, "the toast node fired")
eq(sim.toasts()[1].text, "tick", "with the right text")
eq(sim.toasts()[1].r ~= nil, true, "and a colour of its own")
logged("tick", "the log node wrote too")

-- ---- and again a second later ---------------------------------------------------------
sim.tick(1.0)                    -- crosses t = 2.0
eq(sim.eval_value("vars.ticks"), 2, "the timer fired a second time")
eq(#sim.toasts(), 2, "one toast per tick")

-- ---- a graph-only mod never needs a window ----------------------------------------------
eq(#sim.windows(), 0, "it draws no window at all")

no_faults()
