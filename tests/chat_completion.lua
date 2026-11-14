local root = assert(arg[1])
local factory = dofile(root .. "/src/bridge/presentation/chat_completion.lua")
local rooms = dofile(root .. "/src/bridge/core/room_types.lua")
local model = factory(rooms, 2048)
local function input(text)
    return { open = true, text = text, cursor = #text, anchor = #text }
end
local function has(value)
    for _, row in ipairs(model.rows) do
        if row.value == value then
            return true
        end
    end
    return false
end
local function check(text, expected)
    model.reset()
    model.update(input(text))
    assert(has(expected), "Missing completion for " .. text .. ": " .. expected)
end
check("/", "/tp ")
assert(has("/opacity ") and has("/feedback ") and has("/lanbot "))
local count = #model.rows
local first = model.advance(input("/"))
local current = first
for index = 2, count do
    current = model.advance(input(current))
    assert(model.selected == index, "Tab lost the original completion query")
end
assert(model.advance(input(current)) == first, "Tab did not wrap")
model.update(input("/op"))
assert(#model.rows == 1 and model.advance(input("/op")) == "/opacity ")
model.update(input("/opacity "))
assert(has("/opacity others "), "Single match did not advance to parameter suggestions")
check("  /TP bo", "  /TP boss ")
check("/tp s", "/tp s ")
assert(model.rows[1].value == "/tp s ", "Exact alias was hidden behind partial matches")
check("/tp ", "/tp 2p ")
check("/tp r", "/tp r ")
for _, definition in ipairs(rooms) do
    if definition.aliases then
        check("/tp " .. definition.aliases[1], "/tp " .. definition.aliases[1] .. " ")
    end
end
model.update(input("/tp r -2 "))
assert(#model.rows == 0 and model.usage == "/tp r <x> <y>")
check("/lanbot mo", "/lanbot mode ")
check("/lanbot mode ", "/lanbot mode explore ")
check("/lanbot style ca", "/lanbot style cautious ")
check("/opacity ", "/opacity reset ")
check("/opacity 2p ", "/opacity 2p 50 ")
check("/opacity others 10", "/opacity others 100 ")
check("/con", "/console ")
check("/console g", "/console g ")
assert(model.rows[1].value == "/console g ")
assert(has("/console goto "))
model.update(input("/c giveitem c333"))
assert(#model.rows == 0 and model.usage == "/c giveitem <道具ID>")
assert(model.advance(input("/c giveitem c333")) == nil)
local code = "/c lua print('/tp bo')"
model.update(input(code))
assert(#model.rows == 0 and model.advance(input(code)) == nil, "Completion rewrote Lua arguments")
for _, text in ipairs({
    "普通聊天",
    "聊 /tp bo",
    "",
    "/unknown",
    "/c custom_mod_command argument",
}) do
    model.update(input(text))
    assert(#model.rows == 0 and not model.usage and not model.advance(input(text)))
end
for _, change in ipairs({
    function(value)
        value.open = false
    end,
    function(value)
        value.composing = true
    end,
    function(value)
        value.composition = "中"
    end,
    function(value)
        value.cursor = 1
    end,
    function(value)
        value.anchor = 0
    end,
}) do
    local value = input("/tp bo")
    model.update(value)
    change(value)
    assert(model.advance(value) == nil and #model.rows == 0, "Inactive editor retained suggestions")
end
model.update(input("/tp bo"))
local cached = model.rows
model.update(input("/tp bo"))
assert(model.rows == cached, "Unchanged input rebuilt its suggestions")
model.reset()
assert(#model.rows == 0 and not model.usage and not model.applied)
local nearLimit = "/c " .. string.rep(" ", 2041) .. "go"
model.update(input(nearLimit))
assert(
    #model.rows == 0 and not model.advance(input(nearLimit)),
    "Completion exceeded the byte limit"
)
print("PASS command completion, aliases, arguments, Tab cycling, IME and editor boundaries")
