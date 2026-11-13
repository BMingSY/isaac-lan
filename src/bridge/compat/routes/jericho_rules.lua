-- Portable pair selection, six-day sequence and run persistence.
local rules = {
    version = 1,
    initialChance = 25,
    chanceIncrement = 25,
    repeatChance = 1,
    maximumChance = 100,
    maximumFloors = 128,
    sequenceLength = 6,
    hornFrames = 15,
    hornGraceFrames = 6,
    preferredDistance = { 2, 4 },
    stateFields = { version = 1, chance = 2, generated = 3, depth = 4, floors = 5 },
    fields = {
        key = 1,
        depth = 2,
        first = 3,
        second = 4,
        firstItem = 5,
        secondItem = 6,
        progress = 7,
        complete = 8,
        prepared = 9,
        charged = 10,
        released = 11,
    },
}
local F, S = rules.fields, rules.stateFields
local function integer(value, low, high)
    return math.type(value) == "integer" and value >= low and value <= high
end
function rules.random(key)
    local state = 2166136261
    for i = 1, #key do
        state = ((state ~ key:byte(i)) * 16777619) & 0xffffffff
    end
    return function(maximum)
        assert(integer(maximum, 1, 2147483647))
        state = (state * 1664525 + 1013904223) & 0xffffffff
        return state % maximum + 1
    end
end
function rules.side(floor, index)
    if floor[F.first] == index and index >= 0 then
        return 1
    elseif floor[F.second] == index and index >= 0 then
        return 2
    end
end
function rules.plateSide(plate)
    return plate % 2 == 1 and 1 or 2
end
function rules.selectPair(candidates, connections, random)
    local pairs, preferred = {}, {}
    for first = 1, #candidates - 1 do
        local origin = candidates[first]
        local distance, queue, head = { [origin] = 0 }, { origin }, 1
        while queue[head] do
            local index = queue[head]
            head = head + 1
            for _, target in ipairs(connections[index] or {}) do
                if target >= 0 and connections[target] and not distance[target] then
                    distance[target] = distance[index] + 1
                    queue[#queue + 1] = target
                end
            end
        end
        for second = first + 1, #candidates do
            local target = candidates[second]
            local d = distance[target]
            if d then
                local pair = { origin, target }
                pairs[#pairs + 1] = pair
                if d >= rules.preferredDistance[1] and d <= rules.preferredDistance[2] then
                    preferred[#preferred + 1] = pair
                end
            end
        end
    end
    local choices = #preferred > 0 and preferred or pairs
    if #choices == 0 then
        return
    end
    local choice = choices[random(#choices)]
    if random(2) == 2 then
        return { choice[2], choice[1] }
    end
    return { choice[1], choice[2] }
end
function rules.read(value)
    assert(
        type(value) == "table" and #value == 5 and value[1] == rules.version,
        "Invalid Jericho state"
    )
    assert(integer(value[2], 1, 100) and type(value[3]) == "boolean" and integer(value[4], 0, 32))
    assert((value[3] and value[2] == rules.repeatChance) or (not value[3] and value[2] % 25 == 0))
    assert(type(value[5]) == "table" and #value[5] <= rules.maximumFloors)
    local seen, floors = {}, {}
    for _, floor in ipairs(value[5]) do
        assert(type(floor) == "table" and #floor == F.released, "Invalid Jericho floor")
        assert(type(floor[F.key]) == "string" and #floor[F.key] > 0 and #floor[F.key] <= 96)
        assert(not seen[floor[F.key]], "Duplicate Jericho floor")
        seen[floor[F.key]] = true
        assert(integer(floor[F.depth], 1, 32))
        for _, field in ipairs({ F.first, F.second }) do
            assert(integer(floor[field], -1, 168))
        end
        for _, field in ipairs({ F.firstItem, F.secondItem }) do
            assert(integer(floor[field], 0, 2147483647))
        end
        assert(
            integer(floor[F.progress], 0, rules.sequenceLength)
                and type(floor[F.complete]) == "boolean"
        )
        for _, field in ipairs({ F.prepared, F.charged, F.released }) do
            assert(integer(floor[field], 0, 3))
        end
        if floor[F.first] < 0 then
            assert(floor[F.second] == -1 and floor[F.firstItem] == 0 and floor[F.secondItem] == 0)
            assert(floor[F.progress] == 0 and not floor[F.complete] and floor[F.prepared] == 0)
        else
            assert(value[3] and floor[F.second] >= 0 and floor[F.second] ~= floor[F.first])
            assert(floor[F.firstItem] > 0 and floor[F.secondItem] > 0)
        end
        assert(not floor[F.complete] or floor[F.progress] == rules.sequenceLength)
        assert(floor[F.complete] or (floor[F.charged] == 0 and floor[F.released] == 0))
        floors[#floors + 1] = { table.unpack(floor) }
    end
    return { value[1], value[2], value[3], value[4], floors }
end
function rules.new(saved)
    local state = saved and rules.read(saved)
        or { rules.version, rules.initialChance, false, 0, {} }
    local pads, horn, missed = {}, 0, 0
    local function resetInputs()
        pads, horn, missed = {}, 0, 0
    end
    local function find(key)
        for _, floor in ipairs(state[S.floors]) do
            if floor[F.key] == key then
                return floor
            end
        end
    end
    local function enter(key, depth)
        local floor = find(key)
        if floor then
            return floor, false
        end
        if #state[S.floors] == rules.maximumFloors then
            -- Endless victory laps need bounded history, not a failed session.
            -- Rewind owns its own complete checkpoint of this history.
            table.remove(state[S.floors], 1)
        end
        if not state[S.generated] and state[S.depth] > 0 and depth > state[S.depth] then
            state[S.chance] = math.min(rules.maximumChance, state[S.chance] + rules.chanceIncrement)
        end
        state[S.depth] = math.max(state[S.depth], depth)
        floor = { key, depth, -1, -1, 0, 0, 0, false, 0, 0, 0 }
        state[S.floors][#state[S.floors] + 1] = floor
        resetInputs()
        return floor, true
    end
    local function generate(floor, pair, items)
        assert(floor[F.first] == -1 and pair[1] ~= pair[2])
        floor[F.first], floor[F.second] = pair[1], pair[2]
        floor[F.firstItem], floor[F.secondItem] = items[1], items[2]
        state[S.chance], state[S.generated] = rules.repeatChance, true
    end
    local function step(floor, contacts)
        local present, sounding, pressed, nextPads = {}, {}, {}, {}
        for _, contact in ipairs(contacts) do
            local slot, side, plate = contact.slot, contact.side, contact.plate
            assert(integer(slot, 0, 3) and integer(side, 1, 2))
            assert(not nextPads[slot], "One controller cannot occupy both puzzle rooms")
            nextPads[slot] = { side = side, plate = plate or 0 }
            present[side] = true
            sounding[side] = sounding[side] or contact.horn
            if plate and rules.plateSide(plate) == side then
                assert(integer(plate, 1, rules.sequenceLength))
                local previous = pads[slot]
                if not previous or previous.side ~= side or previous.plate ~= plate then
                    pressed[#pressed + 1] = plate
                end
            end
        end
        pads = nextPads
        if floor[F.complete] or not present[1] or not present[2] then
            horn, missed = 0, 0
            return
        end
        local progress = floor[F.progress]
        if progress < rules.sequenceLength then
            local accepted = false
            for _, plate in ipairs(pressed) do
                if plate > progress + 1 then
                    floor[F.progress] = 0
                    return "wrong"
                elseif plate == progress + 1 then
                    accepted = true
                end
            end
            if accepted then
                floor[F.progress] = progress + 1
                return "step"
            end
        elseif sounding[1] and sounding[2] then
            horn, missed = horn + 1, 0
            if horn >= rules.hornFrames then
                floor[F.complete] = true
                return "complete"
            end
        else
            missed = missed + 1
            if missed > rules.hornGraceFrames then
                horn = 0
            end
        end
    end
    return {
        state = state,
        find = find,
        enter = enter,
        generate = generate,
        step = step,
        resetInputs = resetInputs,
        snapshot = function()
            return rules.read(state)
        end,
    }
end
return rules
