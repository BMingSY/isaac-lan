local root = assert(arg[1])
local characters = dofile(root .. "/src/bridge/presentation/menu_characters.lua")()
local Phase = dofile(root .. "/tests/fixtures/net_phases.lua")
local model = dofile(root .. "/src/bridge/presentation/menu_model.lua")(
    Phase,
    dofile(root .. "/tests/fixtures/net_commands.lua"),
    dofile(root .. "/src/bridge/core/endpoint.lua"),
    characters
)
local catalog = {
    ["0"] = { tainted = false, counterpart = 21 },
    ["1"] = { tainted = false, counterpart = 22 },
    ["21"] = { tainted = true, counterpart = 0 },
    ["22"] = { tainted = true, counterpart = 1 },
    ["41"] = { tainted = false, counterpart = 4096 },
    ["4096"] = { tainted = true, counterpart = 41 },
}
for _, slot in ipairs({ 0, 1 }) do
    local ui = { page = "lan", difficulty = 0, seed = "", errorText = "", ip = "", port = "29506" }
    local status = {
        phase = Phase.lobby,
        hosting = slot == 0 and 1 or 0,
        slot = slot,
        players = 2,
    }
    local choiceKey, readyKey = "choice" .. slot, "ready" .. slot
    status[choiceKey], status[readyKey], status["eligible" .. slot] = 0, 0, true
    local choices = { 0, 1, 41, 21, 4096 } -- 22 is locked in this personal save.
    local sent, draws, randomIndex, fail = {}, 0, 1, false
    local deps = {
        character = tostring,
        catalog = catalog,
        random = function(size)
            draws = draws + 1
            assert(randomIndex <= size)
            return randomIndex
        end,
        command = function(action, value)
            if fail then
                error("selection rejected")
            end
            sent[#sent + 1] = { action, value }
            if action == "choose" then
                local id, ready = value:match("^(%d+):([01])$")
                assert(id, "Random placeholder escaped into the network command")
                status[choiceKey], status[readyKey] = tonumber(id), tonumber(ready)
            end
        end,
    }
    local challenges = {
        ["1"] = { id = 1, name = "Fixed", character = 21, difficulty = 0 },
        ["2"] = { id = 2, name = "Free", character = 65535, difficulty = 0 },
    }
    local function rows()
        return model.rows(ui, status, choices, challenges, deps)
    end
    local function change(delta)
        rows()[1].change(delta)
    end
    local function toggle()
        rows()[1].toggle()
    end
    local function prepare()
        rows()[2].action()
    end
    -- Pairing, including sparse Mod IDs, comes from metadata, never ID arithmetic.
    toggle()
    assert(status[choiceKey] == 21)
    change(1)
    assert(status[choiceKey] == 4096)
    toggle()
    assert(status[choiceKey] == 41)
    change(-1)
    assert(status[choiceKey] == 1)
    toggle()
    assert(rows()[1].label == "随机里角色", "Locked counterpart became selectable")
    toggle()
    assert(rows()[1].label == "随机角色")
    change(1)
    assert(status[choiceKey] == 0)
    -- Rendering and switching groups never draw. Ready draws once from that pool.
    for _, tainted in ipairs({ false, true }) do
        local expected = tainted and { 21, 4096 } or { 0, 1, 41 }
        for index, id in ipairs(expected) do
            status[choiceKey], status[readyKey] = tainted and 21 or 0, 0
            change(-1)
            local before = draws
            for _ = 1, 10 do
                rows()
            end
            assert(draws == before and ui.randomCharacter)
            randomIndex = index
            prepare()
            assert(draws == before + 1 and status[choiceKey] == id and status[readyKey] == 1)
            assert(not rows()[1].enabled and not ui.randomCharacter)
            change(1)
            toggle()
            assert(status[choiceKey] == id, "Ready character changed")
            prepare()
            assert(status[readyKey] == 0 and draws == before + 1)
        end
    end
    -- Failed commands preserve random selection; retry uses only valid choices.
    status[choiceKey], status[readyKey], randomIndex = 0, 0, 1
    change(-1)
    fail = true
    prepare()
    assert(ui.randomCharacter and ui.errorText:find("selection rejected"))
    fail = false
    prepare()
    rows()
    assert(not ui.randomCharacter and status[readyKey] == 1 and ui.errorText == "")
    prepare()
    -- A delayed guest acknowledgement does not draw again or ready the old ID.
    status[choiceKey], randomIndex = 0, 2
    choices = { 0, 1, 21 }
    change(-1)
    local immediate, queued = deps.command, {}
    deps.command = function(action, value)
        queued[#queued + 1] = { action, value }
    end
    local before = draws
    prepare()
    prepare()
    assert(draws == before + 1 and queued[1][2] == "1:1" and queued[2][2] == "1:1")
    deps.command = immediate
    immediate(table.unpack(queued[1]))
    assert(not rows()[1].enabled and not ui.randomCharacter)
    prepare()
    status[choiceKey] = 0
    -- Empty alternative, empty catalogue, and a catalogue disappearing while random.
    choices = { 0 }
    toggle()
    assert(not ui.randomCharacter and status[choiceKey] == 0)
    change(-1)
    choices = {}
    local empty = rows()
    assert(not empty[1].enabled and not empty[2].enabled and not ui.randomCharacter)
    choices = { 0, 21 }
    -- Fixed challenges and room/session changes invalidate local pending choices.
    change(-1)
    status.challenge, status[choiceKey] = 1, 21
    assert(not rows()[1].enabled and not ui.randomCharacter)
    toggle()
    assert(status[choiceKey] == 21)
    status.challenge = 2
    assert(rows()[1].enabled)
    change(-1)
    status[choiceKey] = 0
    assert(rows()[1].label == "0" and not ui.randomCharacter)
    change(-1)
    status.phase = Phase.closed
    rows()
    assert(not ui.randomCharacter)
    status.phase = Phase.lobby
    assert(rows()[1].label == "0")
end
print("PASS grouped selection, native pairing, random ready, eligibility and lifecycle")
