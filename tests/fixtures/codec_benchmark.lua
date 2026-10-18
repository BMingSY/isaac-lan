local root, iterations = assert(arg[1]), assert(tonumber(arg[2]))
local native = assert(_IsaacLanCodec)
local reference = dofile(root .. "/src/bridge/sync/codec.lua")
local workloads = dofile(root .. "/tests/fixtures/codec_workloads.lua")(root)
if arg[3] then
    local file = assert(io.open(arg[3], "rb"))
    local bytes = file:read("*a")
    file:close()
    workloads = {
        {
            name = "recorded",
            value = reference.decode(bytes),
            memo = function()
                return {}
            end,
        },
    }
end
local function measure(fn)
    for _ = 1, 3 do
        fn()
    end
    collectgarbage("collect")
    local samples, sum = {}, 0
    for i = 1, iterations do
        local start = os.clock()
        fn()
        local cost = (os.clock() - start) * 1000
        samples[i], sum = cost, sum + cost
    end
    table.sort(samples)
    return sum / #samples, samples[math.ceil(#samples * 0.95)]
end
for _, case in ipairs(workloads) do
    local bytes = reference.encode(case.value)
    assert(native.state_encode(case.value) == bytes)
    assert(reference.encode(native.state_decode(bytes)) == bytes)
    for _, implementation in ipairs({
        { name = "lua", encode = reference.encode, decode = reference.decode },
        { name = "native", encode = native.state_encode, decode = native.state_decode },
    }) do
        for _, operation in ipairs({ "encode", "decode", "encode-three-peers" }) do
            local mean, p95 = measure(function()
                if operation == "decode" then
                    implementation.decode(bytes)
                elseif operation == "encode" then
                    implementation.encode(case.value)
                else
                    local memo = case.memo()
                    for _ = 1, 3 do
                        implementation.encode(case.value, memo)
                    end
                end
            end)
            io.write(
                string.format(
                    '{"case":"%s","implementation":"%s","operation":"%s","bytes":%d,"samples":%d,"mean_ms":%.6f,"p95_ms":%.6f}\n',
                    case.name,
                    implementation.name,
                    operation,
                    #bytes,
                    iterations,
                    mean,
                    p95
                )
            )
        end
    end
end
