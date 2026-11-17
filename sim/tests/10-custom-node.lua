-- 10-custom-node -- add node types to the visual scripting editor.
-- Recipe 10.10 in docs/10-recipes.md.

local before = #sim.node_types()
ok(before > 0, "the graph editor already ships with node types")

sim.load()
sim.tick(0.05)

-- ---- three new node types appear -------------------------------------------------
eq(#sim.node_types(), before + 3, "the mod added exactly 3 node types")

local ids = table.concat(sim.node_types(), "\n")
contains(ids, "10-custom-node.double_it", "Double is registered")
contains(ids, "10-custom-node.blink", "Blink a part is registered")
contains(ids, "10-custom-node.percent", "As percent is registered")

-- the id is exact: a substring match would not prove anything
local exact = 0
for _, id in ipairs(sim.node_types()) do
    if id == "10-custom-node.double_it" then exact = exact + 1 end
end
eq(exact, 1, "the id is exact and registered once")

-- ---- the picker gets a title, a category and a tip --------------------------------
local info = sim.node_info("10-custom-node.double_it")
ok(info, "the node is in the catalog")
eq(info and info.title, "Double", "with the right title")
eq(info and info.cat, "Custom Node", "in its own category")
eq(info and info.kind, "value", "as a value node")
eq(info and info.tip, "Multiplies by two.", "carrying its tip")

local blink = sim.node_info("10-custom-node.blink")
eq(blink and blink.kind, "action", "the action node is declared as an action")
eq(#(blink and blink.ins or {}), 2, "with two inputs")

local percent = sim.node_info("10-custom-node.percent")
eq(percent and percent.tip, "part as a percentage of `of`.", "each node keeps its own tip")

-- ---- the built-in nodes were not disturbed -----------------------------------------
ok(sim.node_info("logic.and"), "the built-in logic nodes are still there")
ok(sim.node_info("event.every"), "and so are the event nodes")

logged("added 3 node types", "the mod says what it did")

-- ---- unloading takes them away again -----------------------------------------------
no_faults()

sim.unload()
eq(#sim.node_types(), before, "unloading removes them")
eq(sim.node_info("10-custom-node.double_it"), nil, "leaving no trace")
ok(sim.node_info("logic.and"), "while keeping the built-ins")
