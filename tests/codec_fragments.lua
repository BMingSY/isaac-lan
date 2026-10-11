-- Reuse only explicit immutable tuples; preserve the complete original bytes.
local root = assert(arg[1])
local codec = assert(loadfile(root .. "/src/bridge/sync/codec.lua"))()
local actor = { 1, "sprite/path", { 0.125, -2.5 }, { { 1, 2 }, { true, false } } }
local room = { false, 10, { actor }, "opaque\0bytes" }
local memo = { [actor] = false, [room] = false }
for slot = 1, 3 do
    local state = { 13, 10, slot, { actor }, room, { slot * 0.25, "event" .. slot } }
    assert(codec.encode(state, memo) == codec.encode(state))
    assert(codec.encode(codec.decode(codec.encode(state, memo))) == codec.encode(state))
end
assert(type(memo[actor].bytes) == "string" and type(memo[room].bytes) == "string")
local tooDeep = actor
for _ = 1, 10 do
    tooDeep = { tooDeep }
end
assert(not pcall(codec.encode, tooDeep, memo) and not pcall(codec.encode, tooDeep))
-- Tick/floor invalidation replaces the memo before shared data changes.
actor[3][1] = 1.75
room[2] = 11
local nextMemo = { [actor] = false, [room] = false }
assert(codec.encode({ room, actor }, nextMemo) == codec.encode({ room, actor }))
-- Ordinary tables are not cached, so mutable peer-specific events stay current.
local mutable = { 1 }
assert(codec.encode(mutable, nextMemo) == codec.encode(mutable))
mutable[1] = 2
assert(codec.encode(mutable, nextMemo) == codec.encode(mutable) and nextMemo[mutable] == nil)
local invalid = { 0 / 0 }
local badMemo = { [invalid] = false }
assert(not pcall(codec.encode, invalid, badMemo) and badMemo[invalid] == false)
print("PASS immutable tuple fragments preserve bytes and keep mutable values fresh")
