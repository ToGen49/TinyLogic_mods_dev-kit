-- 10-custom-node — add your own node types to the visual scripting editor.
-- Recipe 10.10 in docs/10-recipes.md.
--
-- The nodes appear in the graph picker for EVERY mod, and disappear when this
-- mod unloads. Namespace the id with your own mod id to avoid collisions.

-- A pure value node: `expr` is an expression, its result goes to the output.
tl.graph.node{
    id = "10-custom-node.double_it",
    cat = "Custom Node",
    title = "Double",
    kind = "value",
    ins  = {{"n", "number", 0}},
    outs = {{"result", "number"}},
    expr = "($n * 2)",
    tip = "Multiplies by two.",
}

-- An action node: `code` is the Lua the node turns into.
-- $name reads an input, @name writes an output.
tl.graph.node{
    id = "10-custom-node.blink",
    cat = "Custom Node",
    title = "Blink a part",
    kind = "action",
    ins  = {{"part", "number", 0}, {"times", "number", 3}},
    code = 'for i = 1, $times do tl.after(i * 0.2, function() tl.sim.toggle($part) end) end',
    tip = "Flips a switch on and off a few times.",
}

-- A node with two inputs and one output, and a tip shown in the picker.
tl.graph.node{
    id = "10-custom-node.percent",
    cat = "Custom Node",
    title = "As percent",
    kind = "value",
    ins  = {{"part", "number", 0}, {"of", "number", 100}},
    outs = {{"result", "number"}},
    expr = "(($part / ($of == 0 and 1 or $of)) * 100)",
    tip = "part as a percentage of `of`.",
}

tl.log("added 3 node types: Double, Blink a part, As percent")

tl.ui.window("Custom Node", function(ui)
    ui.label("Open the graph editor and")
    ui.label("look in the `Custom Node`")
    ui.label("category.")
    ui.space(4)
    ui.label("Nodes are removed when")
    ui.label("this mod unloads.")
end, {w = 130})
