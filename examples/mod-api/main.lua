local mod = RegisterMod("Isaac LAN API example", 1)
local lan = include("isaac_lan").attach(mod, "isaac-lan.example")
-- Local lobby choices can use the same SDK on the host and guest.
if lan.RegisterMenuSetting then
    local mode = 1
    lan:RegisterMenuSetting({
        id = "team-hearts",
        name = "Team hearts",
        choices = { "Default", "Hide", "Numbers" },
        onChange = function(index)
            mode = index
        end,
    })
    lan:OnHUDHearts("teammates", function(panel)
        if mode == 2 then
            return true
        elseif mode == 3 and panel.health then
            Isaac.RenderText(
                string.format("Red %d  Soul %d", panel.health.red, panel.health.soul),
                panel.x,
                panel.y,
                1,
                1,
                1,
                1
            )
            return true
        end
    end)
end
local coin = lan:Action("coin", {
    cooldownTicks = 30,
    execute = function(context)
        context.player:AddCoins(1)
        return {
            status = "applied",
            code = "coin_added",
            data = { coins = context.player:GetNumCoins() },
        }
    end,
})
local resultText = ""
lan:OnLocalRender(function(view)
    for i, player in ipairs(view.players) do
        Isaac.RenderText(
            "Local player " .. i .. ": " .. player:GetNumCoins() .. " coins",
            50,
            55 + i * 12,
            1,
            1,
            1,
            1
        )
    end
    Isaac.RenderText("F6: request coin  " .. resultText, 50, 100, 1, 1, 1, 1)
end)
-- Keyboard indices differ between Repentance and Repentance+. Sample once
-- per render so a short press between simulation updates is still delivered.
local held, pending = false, false
mod:AddCallback(ModCallbacks.MC_POST_RENDER, function()
    local pressed = Input.IsButtonPressed(Keyboard.KEY_F6, 0)
        or Input.IsButtonPressed(Keyboard.KEY_F6, -2)
    pending = pending or (pressed and not held and coin:IsAvailable())
    held = pressed
end)
mod:AddCallback(ModCallbacks.MC_POST_UPDATE, function()
    if pending then
        pending = false
        if not coin:IsAvailable() then
            return
        end
        coin:Request(nil, {
            onResult = function(result)
                resultText = result.status .. ":" .. result.code
            end,
        })
    end
end)
