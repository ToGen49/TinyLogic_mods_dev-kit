-- 07-console-commands — commands typed in this mod's console.
-- Recipe 10.7 in docs/10-recipes.md.
--
-- Open the mods panel, pick this mod, open the `console` tab, then type a
-- command name. Everything after the name arrives as one string argument.

tl.command("count", function()
    local kinds = {}
    for _, p in ipairs(tl.board.parts()) do
        kinds[p.kind] = (kinds[p.kind] or 0) + 1
    end
    local total = 0
    for kind, n in pairs(kinds) do
        tl.log(string.format("%-12s %d", kind, n))
        total = total + n
    end
    local _, wires = tl.board.count()
    tl.log("total", total, "parts,", wires, "wires")
end)

tl.command("say", function(text)
    if not text or text == "" then
        tl.warn("usage: say <words>")
        return
    end
    tl.log(text)
    tl.ui.toast(text, "yellow")
end)

-- The rest of the line is one string: parse it yourself.
tl.command("go", function(text)
    local x, y = text:match("%s*(-?%d+)%s+(-?%d+)%s*$")
    if not x then
        tl.warn("usage: go <x> <y>")
        return
    end
    tl.camera.go(tonumber(x), tonumber(y))
    tl.log("camera ->", x, y)
end)

tl.command("help", function()
    tl.log("count             list every kind of part on the board")
    tl.log("say <words>       print words and toast them")
    tl.log("go <x> <y>        move the camera")
    tl.log("help              this list")
end)

tl.log("commands ready — type `help` in the console")
