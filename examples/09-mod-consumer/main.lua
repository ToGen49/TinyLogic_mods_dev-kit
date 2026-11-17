-- 09-mod-consumer — use another mod's exports, and talk over the event bus.
-- Recipe 10.8 + 10.9 in docs/10-recipes.md.
--
-- Requires 08-mod-library to be running. Load order is the order mods were
-- loaded; tl.mods() lists them. If the library isn't there yet, tl.require
-- returns nil and a reason — handle it, never assume.

local lib = tl.require("08-mod-library")

-- Events: any mod can send, any mod can listen — including the sender.
tl.on("score", function(points)
    tl.log("scored", points)
    if lib and lib.double then
        tl.log("doubled:", lib.double(points))
    end
end)

-- Custom events with arbitrary arguments work the same way.
tl.on("my-mod:pulse", function(a, b, c)
    tl.log("pulse", a, b, c)
end)

local last = "-"

tl.ui.window("Consumer", function(ui)
    if lib then
        ui.label("library: found")
        ui.label("describe: " .. tostring(lib.describe and lib.describe()))
        if ui.button("double(21)") then
            tl.log("= " .. lib.double(21))
        end
    else
        ui.label("library: NOT running")
        ui.label("install 08-mod-library")
        ui.label("and save + run it first")
    end

    ui.space(4)
    if ui.button("emit score") then tl.emit("score", 10) end
    if ui.button("emit pulse") then tl.emit("my-mod:pulse", 1, 2, 3) end

    ui.space(4)
    ui.label("running mods:")
    for _, id in ipairs(tl.mods()) do
        ui.label("  " .. id)
    end
end, {w = 140})
