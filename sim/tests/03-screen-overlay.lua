-- 03-screen-overlay -- a crosshair that follows the mouse, on screen only.
-- Recipe 10.3 in docs/10-recipes.md.

-- Put the mouse where we can predict it before the mod starts, so its first
-- read of tl.input.mouse() already has something to report.
sim.mouse(100, 80)

sim.load()
sim.tick(0.05)

ok(sim.window("Overlay"), "the window opens")
local crosshair = sim.widget("crosshair")
ok(crosshair, "the crosshair toggle is there")
eq(crosshair and crosshair.value, true, "it starts on")

-- 100 / 16 = 6, 80 / 16 = 5 with the camera at the origin
eq(sim.widget("tile 6,5") and sim.widget("tile 6,5").type, "label",
    "the window names the tile under the cursor")

local function find_draw(kind, pred)
    for _, d in ipairs(sim.draws()) do
        if d.kind == kind and not d.board and (not pred or pred(d)) then return d end
    end
    return nil
end

local frame = find_draw(1)
ok(frame, "the crosshair box is drawn")
eq(frame and frame.x, 100 - 4, "4 px above the mouse")
eq(frame and frame.y, 80 - 4, "4 px to its left")
eq(frame and frame.w, 8, "8 px wide")
eq(frame and frame.h, 8, "and 8 px tall")

local label = find_draw(2, function(d) return d.text == "6,5" end)
ok(label, "the tile readout is drawn")
eq(label and label.x, 8, "in the bottom left corner of the screen")
eq(label and label.y, 250)

-- ---- moving the mouse moves everything ----------------------------------------
sim.mouse(32, 16)
sim.tick(0.05)
eq(sim.widget("tile 2,1") and sim.widget("tile 2,1").type, "label",
    "the window follows the cursor")
frame = find_draw(1)
eq(frame and frame.x, 32 - 4, "the crosshair follows it too")
eq(find_draw(2, function(d) return d.text == "2,1" end) ~= nil, true,
    "and so does the readout")

-- ---- nothing is drawn once it is switched off ---------------------------------
sim.ui_set("crosshair", false)
sim.tick(0.05)
eq(#sim.draws(), 0, "a screen overlay draws nothing when it is off")

no_faults()
