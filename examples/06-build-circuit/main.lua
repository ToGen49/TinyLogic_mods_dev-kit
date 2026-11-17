-- 06-build-circuit — build a small circuit from code.
-- Recipe 10.6 in docs/10-recipes.md.
--
-- Everything a mod does lands in the player's UNDO HISTORY: one undo reverses
-- the whole build, so go wild.

local built = {}

local function build()
    -- Leave x, y out and the game picks the nearest free spot.
    local a = tl.board.place("switch", nil, nil, {label = "A"})
    local b = tl.board.place("switch", nil, nil, {label = "B"})
    local y = tl.board.place("light",  nil, nil, {label = "Y"})

    -- Pins are numbered from 0, or addressed by name ("out", "a", "b").
    tl.board.wire(a, "out", y, 0, "green")
    tl.board.wire(b, "out", y, 1, "blue")

    built = {a, b, y}
    tl.log("built", #built, "parts —", tl.board.count())
    tl.ui.toast("built 2 switches + 1 light")
end

local function clear()
    if #built == 0 then
        tl.warn("nothing built yet")
        return
    end
    tl.board.remove(built)
    built = {}
    tl.log("removed")
end

tl.command("build", build)
tl.command("clear", clear)

tl.ui.window("Builder", function(ui)
    if ui.button("build") then build() end
    if ui.button("remove those") then clear() end
    if ui.button("undo") then tl.board.undo() end
    if ui.button("redo") then tl.board.redo() end
    if ui.button("fit view") then tl.camera.fit() end
    ui.space(4)
    ui.label("parts: " .. tl.board.count())
    ui.label("selected: " .. #tl.board.selection())
end, {w = 130})
