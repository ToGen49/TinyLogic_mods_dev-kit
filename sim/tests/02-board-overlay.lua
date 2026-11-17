-- 02-board-overlay -- labels drawn on the board, and a hud line on the screen.
-- Recipe 10.2 in docs/10-recipes.md.

-- Parts are put on the board BEFORE the mod loads, so the mod can count them
-- on its very first frame.
sim.place("switch", 2, 2, {label = "A"})
sim.place("light", 6, 2, {label = "Y"})

sim.load()
sim.tick(0.05)

-- ---- the window --------------------------------------------------------------
ok(sim.window("Board Overlay"), "the window opens")
local toggle = sim.widget("show part numbers")
ok(toggle, "the toggle is there")
eq(toggle and toggle.type, "toggle", "and it really is a toggle")
eq(toggle and toggle.value, true, "part numbers start on")
eq(sim.widget("parts: 2") and sim.widget("parts: 2").type, "label",
    "the window counts the two parts")

-- ---- board drawing (tiles x 16, moves with the camera) ------------------------
local function board_text()
    local out = {}
    for _, d in ipairs(sim.draws()) do
        if d.kind == 2 and d.board then out[#out + 1] = d.text end
    end
    return out
end

contains(table.concat(board_text(), " "), "#1", "part 1 gets a number")
contains(table.concat(board_text(), " "), "#2", "part 2 gets a number")

local first
for _, d in ipairs(sim.draws()) do
    if d.kind == 2 and d.board and d.text == "#1" then first = d end
end
ok(first, "the label for part 1 was found")
eq(first and first.x, 2 * 16, "drawn at tile x * 16 (board pixels)")
eq(first and first.y, 2 * 16 - 8, "lifted 8 px above the part")

-- ---- the hud is screen pixels, never moves with the camera --------------------
local hud
for _, d in ipairs(sim.draws()) do
    if d.kind == 2 and not d.board and tostring(d.text):find("parts: ", 1, true) then
        hud = d
    end
end
ok(hud, "the hud line is drawn too")
eq(hud and hud.x, 8, "at x = 8 in screen pixels")
eq(hud and hud.y, 8, "at y = 8")

-- ---- turning it off is saved --------------------------------------------------
sim.ui_set("show part numbers", false)
sim.tick(0.05)
eq(sim.store_value("show_ids"), false, "the toggle is written to the store at once")
eq(#board_text(), 0, "and the board numbers disappear in the same frame")

-- ---- it survives a restart ----------------------------------------------------
sim.reload()
sim.tick(0.05)
eq(sim.widget("show part numbers").value, false, "still off after a reload")
eq(#board_text(), 0, "and still not drawn")

no_faults()
