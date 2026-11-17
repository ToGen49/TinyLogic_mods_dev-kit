-- 01-window-setting — a window with a setting that survives restarts.
-- Recipe 10.1 in docs/10-recipes.md.

-- Read the saved value once at load; fall back to the default.
local scale = tl.store.get("scale", 1)
local launched = tl.store.get("launched", 0) + 1
tl.store.set("launched", launched)

tl.ui.window("My Tool", function(ui)
    ui.label("launches: " .. launched)

    -- A slider: give it the value, get the new value back.
    local new = ui.slider("scale", scale, 0.5, 4)
    if new ~= scale then
        scale = new
        tl.store.set("scale", scale)   -- written to store.json immediately
    end

    ui.bar("progress", launched % 10 / 10, "green")

    -- ui.button returns true on the frame it was clicked.
    if ui.button("reset") then
        scale = 1
        tl.store.set("scale", 1)
    end
end, {w = 130})
