-- 08-mod-library — publish an API for other mods.
-- Recipe 10.8 in docs/10-recipes.md.
--
-- Install this BEFORE 09-mod-consumer: tl.require only sees mods that are
-- already running, in load order (tl.mods()).

local M = {}

-- A function other mods can call.
function M.double(n)
    return (tonumber(n) or 0) * 2
end

function M.describe()
    return string.format("%s v%s", tl.id, tl.version)
end

-- A value, not just a function.
M.version = "1.0"

tl.export("double", M.double)
tl.export("describe", M.describe)
tl.export("version", M.version)
tl.export("lib", M)   -- one entry holding everything, if you prefer

tl.log("exported double, describe, version, lib")

-- A small window so you can tell it loaded.
tl.ui.window("Library", function(ui)
    ui.label("exports: double")
    ui.label("         describe")
    ui.label("         version")
    ui.label("         lib")
    ui.space(4)
    ui.label("double(21) = " .. M.double(21))
    if ui.button("emit a test event") then
        tl.emit("score", 10)
    end
end, {w = 120})
