-- sim/json.lua
--
-- A small JSON decoder, just enough for mod.json and graph.json.
-- Returns Lua values: objects -> tables, arrays -> tables, true/false -> booleans,
-- null -> nil (absent keys, exactly how the game's own reader treats it).

local M = {}

local ESCAPES = {
    ['"'] = '"', ['\\'] = '\\', ['/'] = '/', b = '\b', f = '\f',
    n = '\n', r = '\r', t = '\t',
}

local function fail(s, pos, msg)
    local line, col = 1, 1
    for i = 1, math.min(pos, #s) do
        if s:sub(i, i) == "\n" then line, col = line + 1, 1 else col = col + 1 end
    end
    error(string.format("json: line %d, col %d: %s", line, col, msg), 0)
end

local Parser = {}
Parser.__index = Parser

local function skip_ws(p)
    local s, i = p.s, p.i
    while true do
        local c = s:sub(i, i)
        if c == " " or c == "\t" or c == "\n" or c == "\r" then
            i = i + 1
        else
            break
        end
    end
    p.i = i
end

local decode_value

local function decode_string(p)
    local s, i = p.s, p.i
    if s:sub(i, i) ~= '"' then fail(s, i, "expected a string") end
    i = i + 1
    local out = {}
    while true do
        local c = s:sub(i, i)
        if c == "" then fail(s, i, "unterminated string") end
        if c == '"' then p.i = i + 1; return table.concat(out) end
        if c == "\\" then
            local e = s:sub(i + 1, i + 1)
            if ESCAPES[e] then
                out[#out + 1] = ESCAPES[e]
                i = i + 2
            elseif e == "u" then
                local hex = s:sub(i + 2, i + 5)
                if not hex:match("^%x%x%x%x$") then fail(s, i, "bad \\u escape") end
                local cp = tonumber(hex, 16)
                -- UTF-8 encode the code point (surrogate pairs are not needed
                -- for mod.json / graph.json, but plain astral chars are cheap).
                if cp < 0x80 then
                    out[#out + 1] = string.char(cp)
                elseif cp < 0x800 then
                    out[#out + 1] = string.char(0xC0 | (cp >> 6), 0x80 | (cp & 0x3F))
                elseif cp < 0x10000 then
                    out[#out + 1] = string.char(0xE0 | (cp >> 12), 0x80 | ((cp >> 6) & 0x3F), 0x80 | (cp & 0x3F))
                else
                    out[#out + 1] = string.char(0xF0 | (cp >> 18), 0x80 | ((cp >> 12) & 0x3F),
                                                 0x80 | ((cp >> 6) & 0x3F), 0x80 | (cp & 0x3F))
                end
                i = i + 6
            else
                fail(s, i, "bad escape \\" .. e)
            end
        else
            out[#out + 1] = c
            i = i + 1
        end
    end
end

local function decode_number(p)
    local s, i = p.s, p.i
    local j = s:find("[^%d%+%-%.eE]", i) or (#s + 1)
    local text = s:sub(i, j - 1)
    if text == "" then fail(s, i, "expected a number") end
    local v = tonumber(text)
    if not v then fail(s, i, "bad number '" .. text .. "'") end
    p.i = j
    return v
end

decode_value = function(p)
    skip_ws(p)
    local s, i = p.s, p.i
    local c = s:sub(i, i)
    if c == "" then fail(s, i, "unexpected end of input") end

    if c == '"' then return decode_string(p) end
    if c == "{" then
        p.i = i + 1
        local out = {}
        skip_ws(p)
        if s:sub(p.i, p.i) == "}" then p.i = p.i + 1; return out end
        while true do
            skip_ws(p)
            local key = decode_string(p)
            skip_ws(p)
            if s:sub(p.i, p.i) ~= ":" then fail(s, p.i, "expected ':' after '" .. key .. "'") end
            p.i = p.i + 1
            out[key] = decode_value(p)
            skip_ws(p)
            local d = s:sub(p.i, p.i)
            if d == "," then p.i = p.i + 1
            elseif d == "}" then p.i = p.i + 1; return out
            else fail(s, p.i, "expected ',' or '}'") end
        end
    end
    if c == "[" then
        p.i = i + 1
        local out = {}
        skip_ws(p)
        if s:sub(p.i, p.i) == "]" then p.i = p.i + 1; return out end
        while true do
            out[#out + 1] = decode_value(p)
            skip_ws(p)
            local d = s:sub(p.i, p.i)
            if d == "," then p.i = p.i + 1
            elseif d == "]" then p.i = p.i + 1; return out
            else fail(s, p.i, "expected ',' or ']'") end
        end
    end
    if c == "t" and s:sub(i, i + 3) == "true" then p.i = i + 4; return true end
    if c == "f" and s:sub(i, i + 4) == "false" then p.i = i + 5; return false end
    if c == "n" and s:sub(i, i + 3) == "null" then p.i = i + 4; return nil end
    if c == "-" or c:match("%d") then return decode_number(p) end

    fail(s, i, "unexpected character '" .. c .. "'")
end

-- M.decode(text) -> value, err
function M.decode(text)
    if type(text) ~= "string" then return nil, "json: expected a string" end
    local p = setmetatable({s = text, i = 1}, Parser)
    local ok, value = pcall(decode_value, p)
    if not ok then return nil, tostring(value) end
    skip_ws(p)
    if p.i <= #text then return nil, "json: trailing data at byte " .. p.i end
    return value
end

-- M.read(path) -> value, err   (err also covers "can't open the file")
function M.read(path)
    local f, err = io.open(path, "rb")
    if not f then return nil, "can't open " .. path .. ": " .. tostring(err) end
    local text = f:read("*a")
    f:close()
    return M.decode(text)
end

return M
