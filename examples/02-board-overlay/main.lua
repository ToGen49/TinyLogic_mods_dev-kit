-- 02-board-overlay — draw on the board every frame.
-- Recipe 10.2 in docs/10-recipes.md.
--
-- Drawing is CLEARED every frame, so it must happen inside a "draw" event.
-- tl.draw  = board pixels, 1 tile = 16 px, moves with the camera.
-- tl.hud   = screen pixels, fixed 480 x 270.

local show_ids = tl.store.get("show_ids", true)

tl.ui.window("Board Overlay", function(ui)
    local now = ui.toggle("show part numbers", show_ids)
    if now ~= show_ids then
        show_ids = now
        tl.store.set("show_ids", show_ids)
    end
    ui.label("parts: " .. tl.board.count())
end, {w = 120})

tl.on("draw", function()
    if not show_ids then return end

    for _, p in ipairs(tl.board.parts()) do
        -- p.x / p.y are TILES: multiply by 16 to get board pixels.
        -- -8 lifts the label just above the part.
        tl.draw.text("#" .. p.id, p.x * 16, p.y * 16 - 8, "yellow")
    end

    -- The hud is independent of the camera and of the board.
    tl.hud.text("parts: " .. tl.board.count(), 8, 8, "ink")
end)
