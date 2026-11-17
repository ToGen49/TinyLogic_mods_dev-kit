-- my-mod — a Tiny Logic mod.
--
-- Runs once when the mod loads, then reacts to events.
-- Full API: docs/04-api.md  ·  recipes: docs/10-recipes.md
--
-- Order of execution: this file first, then graph.json (both share `vars`).

tl.log("loaded", tl.id, "api", tl.version)

-- A timer: runs again and again, 0.25 s apart.
tl.every(0.25, function()
    -- tl.log("tick", math.floor(tl.time() * 100) / 100)
end)

-- A window: this function runs EVERY FRAME while the window is open.
-- It is a render function, not an "on click" handler: use ui.button's return value.
local count = 0
tl.ui.window("My Mod", function(ui)
    ui.label("parts: " .. tl.board.count())
    ui.bar("progress", count % 10 / 10, "green")

    if ui.button("fit board in view") then
        tl.camera.fit()
    end
    if ui.button("count parts") then
        count = count + 1
        tl.log("counted", tl.board.count())
    end
end, {w = 130})

-- Drawing is cleared every frame: only draw inside a "draw" or "frame" event.
-- tl.draw paints on the board (16 px = 1 tile), tl.hud on the screen (480x270).
tl.on("draw", function()
    -- tl.hud.text("hello", 8, 8, "yellow")
end)

-- React to the player.
tl.on("key", function(key, down)
    if down and key == "f1" then
        tl.ui.toast("hello from " .. tl.id)
    end
end)

-- A console command: type `hello` in this mod's console.
tl.command("hello", function(rest)
    tl.log("hello!", rest)
end)

-- Persist something across sessions (written to store.json immediately).
tl.store.set("launched", (tl.store.get("launched", 0) or 0) + 1)
