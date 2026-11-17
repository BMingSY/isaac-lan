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
    local choiceKey, readyKey, randomKey = "choice" .. slot, "ready" .. slot, "random" .. slot
    status[choiceKey], status[readyKey], status["eligible" .. slot] = 0, 0, true
    local choices = { 0, 1, 41, 21, 4096 } -- 22 is locked in this personal save.
    local sent, fail = {}, false
    local deps = {
        character = tostring,
        catalog = catalog,
        command = function(action, value)
            if fail then
                error("selection rejected")
            end
            sent[#sent + 1] = { action, value }
            if action == "choose" or action == "choose_random" then
                local id, ready = value:match("^(%d+):([01])$")
                assert(id)
                status[randomKey] = action == "choose_random"
                status[choiceKey] = action == "choose_random" and (id == "1" and 21 or 0)
                    or tonumber(id)
                status[readyKey] = tonumber(ready)
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
    assert(status[choiceKey] == 21 and not status[randomKey])
    change(1)
    assert(status[choiceKey] == 4096)
    toggle()
    assert(status[choiceKey] == 41)
    change(-1)
    assert(status[choiceKey] == 1)
    toggle()
    assert(
        rows()[1].label == "?" and status[choiceKey] == 21,
        "Locked counterpart became selectable"
    )
    toggle()
    assert(rows()[1].label == "?" and status[choiceKey] == 0)
    change(1)
    assert(status[choiceKey] == 0 and not status[randomKey])
    -- Random is a synchronized selection, still unknown after ready/unready.
    for _, tainted in ipairs({ false, true }) do
        status[choiceKey], status[readyKey], status[randomKey] = tainted and 21 or 0, 0, false
        change(-1)
        assert(rows()[1].label == "?" and status[randomKey])
        local before = #sent
        for _ = 1, 10 do
            rows()
        end
        assert(#sent == before, "Rendering changed the selection")
        prepare()
        assert(sent[#sent][1] == "choose_random" and sent[#sent][2] == (tainted and "1:1" or "0:1"))
        assert(status[readyKey] == 1 and status[randomKey] and rows()[1].label == "?")
        assert(not rows()[1].enabled and not rows()[1].canToggle)
        before = #sent
        change(1)
        toggle()
        assert(#sent == before, "Ready selection changed")
        prepare()
        assert(status[readyKey] == 0 and status[randomKey] and rows()[1].label == "?")
        change(1)
        assert(not status[randomKey])
    end
    -- Failed commands and delayed acknowledgements never resolve a concrete ID.
    status[choiceKey], status[readyKey], status[randomKey] = 0, 0, false
    change(-1)
    fail = true
    prepare()
    assert(status[randomKey] and status[readyKey] == 0 and ui.errorText:find("selection rejected"))
    fail = false
    local immediate, queued = deps.command, {}
    deps.command = function(action, value)
        queued[#queued + 1] = { action, value }
    end
    prepare()
    prepare()
    assert(queued[1][1] == "choose_random" and queued[1][2] == "0:1")
    assert(queued[2][1] == "choose_random" and queued[2][2] == "0:1")
    deps.command = immediate
    immediate(table.unpack(queued[1]))
    assert(not rows()[1].enabled and rows()[1].label == "?" and ui.errorText == "")
    prepare()
    -- No opposite group and no eligible choices disable the corresponding controls.
    choices = { 0 }
    change(1)
    assert(not rows()[1].canToggle)
    toggle()
    assert(not status[randomKey] and status[choiceKey] == 0)
    change(-1)
    choices = {}
    assert(not rows()[1].enabled and not rows()[2].enabled)
    choices = { 0, 21 }
    -- Authoritative fixed challenges and new sessions replace deferred state.
    status.challenge, status[choiceKey], status[randomKey] = 1, 21, false
    assert(not rows()[1].enabled and not rows()[1].canToggle)
    toggle()
    assert(status[choiceKey] == 21 and not status[randomKey])
    status.challenge = 2
    assert(rows()[1].enabled)
    change(-1)
    assert(rows()[1].label == "?")
    status.phase = Phase.closed
    rows()
    status.phase, status[choiceKey], status[randomKey] = Phase.lobby, 0, false
    assert(rows()[1].label == "0")
end
print("PASS grouped selection, native pairing, deferred readiness and eligibility")
