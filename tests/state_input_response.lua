-- Native held bindings and render positions, including unsent input changes.
local native = assert(_IsaacLan)
local f = assert(io.open("./lan-test-role.txt", "r"))
local host = f:read("*l") == "host"
f:close()
f = assert(io.open("./lan-test-menu-port.txt", "r"))
local port = f:read("*l")
f:close()
local function report(text)
    Isaac.DebugString("LAN_NETWORK " .. text)
end
local frame = _IsaacLanFrame
local renders, linked, chosen, finished = 0, false, false, false
local movementRenders, captureCount = 0, 0
local sent, preview, previewSequence = Vector(0, 0), Vector(0, 0), 0
local beforeVelocity, afterVelocity = Vector(0, 0), Vector(0, 0)
local makePrediction = _IsaacLanPrediction.new
_IsaacLanPrediction.new = function(position)
    local model = makePrediction(position)
    local step = model.step
    model.step = function(self, ...)
        beforeVelocity = Vector(self.velocity.X, self.velocity.Y)
        local result = step(self, ...)
        afterVelocity = Vector(self.velocity.X, self.velocity.Y)
        return result
    end
    return model
end
local out = not host and assert(io.open("./lan-test-digest-response.csv", "w"))
if out then
    out:write(
        "time,frame,tick,capture,sequence,sent_x,sent_y,raw_x,raw_y,preview_x,preview_y,x,y,before_vx,before_vy,after_vx,after_vy\n"
    )
end
local function direction(bytes)
    local left, right, up, down = string.unpack(">I2I2I2I2", bytes)
    return Vector((right - left) / 65535, (down - up) / 65535)
end
function _IsaacLanFrame()
    renders = renders + 1
    if not linked and renders >= (host and 300 or 360) then
        linked = true
        _IsaacLanCommand(host and "host" or "join", host and port or "127.0.0.1:" .. port)
        report("MENU_READY")
    end
    local s = frame()
    if s.phase == 2 and not chosen then
        _IsaacLanCommand("choose", "0:1")
        chosen = true
    end
    if host and s.phase == 2 and s.players == 2 and s.ready0 == 1 and s.ready1 == 1 then
        _IsaacLanCommand("start", "YV039KQF:0:0:0:0:0")
    end
    local buttons = 0
    if not host and s.prepared and s.verified >= 60 and s.verified < 500 then
        movementRenders = movementRenders + 1
        -- Odd durations sweep the phase between 60 Hz rendering and 30 Hz sending.
        local phases = { 8, 0, 4, 0, 2, 0, 1, 0, 8, 4, 0 }
        buttons = phases[math.floor(movementRenders / 11) % #phases + 1]
    end
    native.test_gamepad(buttons)
    if s.phase == 4 or s.phase == 9 then
        report("FAILED " .. s.error)
    end
    if s.verified >= 550 and not finished then
        finished = true
        if out then
            out:flush()
        end
        report("PASS immediate native input response")
    end
    return s
end
local gate = native.net_gate
native.net_gate = function(capture, before, collect, restore, present, beginFloor)
    return gate(
        function()
            local bytes = capture()
            captureCount = captureCount + 1
            sent = direction(bytes)
            return bytes
        end,
        function(t, n, b)
            before(t, n, b)
            if t == 0 then
                for i = 0, Game():GetNumPlayers() - 1 do
                    local p = Isaac.GetPlayer(i)
                    p.Position = Vector(320, 220 + i * 60)
                    p:SetMinDamageCooldown(10000)
                end
                for _, e in ipairs(Isaac.GetRoomEntities()) do
                    if e.Type ~= 1 then
                        e:Remove()
                    end
                end
                local room = Game():GetRoom()
                for i = 0, room:GetGridSize() - 1 do
                    if room:GetGridCollision(i) ~= GridCollisionClass.COLLISION_WALL then
                        room:RemoveGridEntity(i, 0, false)
                    end
                end
                room:SetClear(true)
            end
        end,
        collect,
        restore,
        function(input, sequence)
            preview, previewSequence = direction(input), sequence
            present(input, sequence)
        end,
        beginFloor
    )
end
Isaac.AddCallback(
    { Name = "Isolated native input response observer" },
    ModCallbacks.MC_POST_RENDER,
    function()
        if host or not _IsaacLanStatus().prepared or not native.rooms_ready() then
            return
        end
        -- ViewScope reads native bindings without consuming press edges.
        local raw = Vector(
            Input.GetActionValue(ButtonAction.ACTION_RIGHT, 1)
                - Input.GetActionValue(ButtonAction.ACTION_LEFT, 1),
            Input.GetActionValue(ButtonAction.ACTION_DOWN, 1)
                - Input.GetActionValue(ButtonAction.ACTION_UP, 1)
        )
        local p = Isaac.GetPlayer(native.rooms_heads()["1"])
        out:write(
            string.format(
                "%.3f,%d,%d,%d,%d,%.4f,%.4f,%.4f,%.4f,%.4f,%.4f,%.6f,%.6f,%.6f,%.6f,%.6f,%.6f\n",
                Isaac.GetTime() / 1000,
                renders,
                _IsaacLanStatus().verified,
                captureCount,
                previewSequence,
                sent.X,
                sent.Y,
                raw.X,
                raw.Y,
                preview.X,
                preview.Y,
                p.Position.X,
                p.Position.Y,
                beforeVelocity.X,
                beforeVelocity.Y,
                afterVelocity.X,
                afterVelocity.Y
            )
        )
    end
)
