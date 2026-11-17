-- 03-screen-overlay — draw on the screen only, no board drawing.
-- Recipe 10.3 in docs/10-recipes.md.

local mouse = tl.input.mouse()
local enabled = true

tl.ui.window("Overlay", function(ui)
    local now = ui.toggle("crosshair", enabled)
    if now ~= enabled then enabled = now end
    ui.label("tile " .. mouse.tile_x .. "," .. mouse.tile_y)
end, {w = 110})

-- Read input in "frame"; draw in "draw". Both run every frame, in that order.
tl.on("frame", function()
    mouse = tl.input.mouse()
end)

tl.on("draw", function()
    if not enabled then return end

    -- x / y are SCREEN pixels (480 x 270); tile_x / tile_y are board tiles.
    tl.hud.frame(mouse.x - 4, mouse.y - 4, 8, 8, "cyan")
    tl.hud.text(mouse.tile_x .. "," .. mouse.tile_y, 8, 250, "muted")
end)
