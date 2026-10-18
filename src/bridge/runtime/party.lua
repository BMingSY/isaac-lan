-- Bind a complete native party before opening the simulation gate. Physical
-- controller IDs from Continue are not identities; only its saved head order is.
return function(native, player)
    return function(status, continued, restoredOrder)
        if continued then
            local heads = restoredOrder and native.rooms_heads(1) or native.rooms_heads()
            for slot = 0, status.players - 1 do
                local index = assert(heads[tostring(slot)], "联机角色缺失")
                assert(native.input_assign(index, slot + 1), "无法绑定联机角色")
            end
        else
            assert(native.input_assign(0, 1), "无法绑定主机角色")
            for slot = 1, status.players - 1 do
                assert(
                    native.players_spawn(status["character" .. slot], slot + 1),
                    "无法创建客机角色"
                )
            end
        end
        local heads, seen = native.rooms_heads(), {}
        for slot = 0, status.players - 1 do
            local index = assert(heads[tostring(slot)], "联机角色缺失")
            assert(not seen[index], "联机角色重复")
            seen[index] = true
            local p = assert(player(index))
            assert(p.ControllerIndex == slot + 1, "联机角色控制器归属不一致")
        end
    end
end
