-- 05-player-input — react to the player.
-- Recipe 10.5 in docs/10-recipes.md.
--
-- tl.input.capture(true) sends key presses to this mod instead of the editor's
-- shortcuts. ESCAPE always gives them back, so the player can never get stuck.

local captured = false
local last_key = "-"

local function set_capture(on)
    captured = on
    tl.input.capture(on)
    tl.log("capture", on and "on" or "off")
end

set_capture(true)

tl.on("key", function(key, down)
    if not down then return end
    last_key = key

    if key == "escape" then
        -- The game hands the keys back on escape; keep our state honest.
        captured = false
        return
    end
    if key == "space" then
        tl.sound.play("click")
    elseif key == "return" then
        tl.sound.note(440, 0.15, 0.3, "square")
    end
end)

tl.on("click", function(x, y)
    tl.log("clicked tile", x, y)
end)

tl.ui.window("Input", function(ui)
    ui.label("last key: " .. last_key)
    local now = ui.toggle("capture keys", captured)
    if now ~= captured then set_capture(now) end
    ui.label("wasd / arrows held?")
    ui.label("up: " .. tostring(tl.input.key("up")))
    ui.label("space: " .. tostring(tl.input.key("space")))
    if ui.button("toast") then tl.ui.toast("hello") end
end, {w = 130})
