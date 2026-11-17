-- 04-timer-watch — drive the circuit on a timer, read it with a watch.
-- Recipe 10.4 in docs/10-recipes.md.

local flipping = false

-- Grab the list once. Parts placed later are picked up by the refresh timer.
local switches = tl.board.parts("switch")

tl.every(0.5, function()
    -- Asking the board costs a little: refresh the list four times a second
    -- instead of every tick.
    switches = tl.board.parts("switch")

    if not flipping then return end
    for _, p in ipairs(switches) do
        tl.sim.toggle(p.id)
    end
end)

-- A one-shot timer, and a repeating one, both cancellable.
local function start()
    flipping = true
    tl.log("flipping on")
end
tl.command("flip", function(text)
    if text == "off" then
        flipping = false
        tl.log("flipping off")
    else
        start()
    end
end)

-- A watch fires only when the value changes — no polling needed.
local light = tl.board.parts("light")[1]
if light then
    tl.sim.watch(light.id, nil, function(value, before)
        tl.log("light", tostring(before), "->", tostring(value))
    end)
else
    tl.warn("no light on this board yet — place one and reload")
end

tl.ui.window("Timer", function(ui)
    ui.label(flipping and "flipping: on" or "flipping: off")
    if ui.button("toggle") then flipping = not flipping end
    if ui.button("add switch") then tl.board.place("switch") end
    if ui.button("add light") then tl.board.place("light") end
end, {w = 120})
