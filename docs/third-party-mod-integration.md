# 第三方 Mod 接入

Isaac LAN API 2 提供本机视图、逐帧本机 UI、主机动作和生命周期通知。使用同一个 SDK，可以同时支持单机与 LAN；无需直接访问 `_IsaacLan` 或判断主客机分支。API 由 DLL 在第三方 Mod 初始化前发布。

## 快速开始

将 [`src/bridge/api/sdk.lua`](https://github.com/BMingSY/isaac-lan/blob/main/src/bridge/api/sdk.lua) 复制到 Mod 目录，命名为 `isaac_lan.lua`。该文件自带 LuaLS 类型注解，也是 DLL 内使用的实现。加载时绑定一次：

```lua
local mod = RegisterMod("My Mod", 1)
local lan = include("isaac_lan").attach(mod, "author.my-mod")
```

没有安装 LAN 时，SDK 使用游戏单机接口；LAN 会话准备中则等待本机视图就绪，不绕过主机执行玩法。依赖 LAN 的集成也可直接调用 `IsaacLAN:Attach(mod, "author.my-mod")`。

| 要做的事 | 接口 |
| --- | --- |
| 属性面板、地图、说明等本机 UI | `lan:OnLocalRender(fn)`，回调中读取 `view.players` |
| 判断回调角色是否属于本机 | `lan:IsLocalPlayer(player)` |
| 从 UI 发起修改世界的操作 | `lan:Action(name, definition)`，再 `action:Request(...)` |
| 清理跨房／换层缓存 | `lan:On(event, fn)`；完整事件见[接口参考](https://github.com/BMingSY/isaac-lan/blob/main/docs/mod-api-reference.md) |
| 适配没有主动接入的第三方 Mod | [自动适配器](https://github.com/BMingSY/isaac-lan/blob/main/docs/mod-adapter-development.md) |

## 本机 UI

```lua
local cancel = lan:OnLocalRender(function(view)
    for i, player in ipairs(view.players) do
        Isaac.RenderText(string.format("P%d damage %.2f", i, player.Damage),
            50, 55 + i * 12, 1, 1, 1, 1)
    end
end)
```

回调跟随游戏渲染帧执行，不等待新的网络快照。SDK 自动进入本机房间和角色作用域；旧 UI 中的 `Game():GetRoom()`、`Game():GetNumPlayers()`、`Isaac.GetPlayer(i)` 也能读取本机视图。准备阶段跳过绘制；错误只停用出错的回调并恢复作用域。`cancel()` 可重复调用，`lan:Close()` 会统一清理。

这里用于读取世界和绘制 UI。造成伤害、给予道具、传送等操作通过主机动作执行。全局脚本缓存仍由 Mod 自己管理，原生角色对象应从当前视图重新取得。

## 请求玩法动作

以下教学动作每次给所选角色增加一枚硬币；正式 Mod 可换成自己的业务条件与效果：

```lua
local coin = lan:Action("coin", {
    cooldownTicks = 30,
    execute = function(context)
        context.player:AddCoins(1)
        return {status = "applied", code = "coin_added",
            data = {coins = context.player:GetNumCoins()}}
    end,
})

-- 从自己的按钮或输入回调触发；也可以不指定 player，默认本机第一个角色。
local request = coin:Request(nil, {
    player = lan:GetLocalPlayers()[1],
    onResult = function(result)
        Isaac.DebugString(result.status .. ":" .. result.code)
    end,
})
```

单机直接调用 `execute`；LAN 中只由主机在该参与者的房间内执行，并按请求 ID 去重。`context.player` 是本次选中的身体，主机重新核对所属参与者，不相信载荷中的玩家编号。界面用 `coin:IsAvailable()` 判断主机能力；结果回调在成功或拒绝时都只执行一次，可能在 `Request` 返回前同步发生。

带参数时提供 `validate(payload)`；默认仅接受 `nil`。主机必须在 `execute` 中检查当前玩法条件，载荷只表达意图。异步 LAN 操作使用 `context:Wait(...)` 或 `context:MoveTo(...)`，并提供 `solo(context, payload)` 调用自己的单机逻辑，详见[动作参考](https://github.com/BMingSY/isaac-lan/blob/main/docs/mod-api-reference.md#动作与完成结果)。

## 可运行示例

[`examples/mod-api/main.lua`](https://github.com/BMingSY/isaac-lan/blob/main/examples/mod-api/main.lua) 是完整 Mod：显示本机角色硬币数，按 F6 请求一枚硬币。用下列命令生成含 SDK 的独立目录，再放入隔离游戏的 `mods` 下：

```sh
python tools/export_mod_example.py /tmp/isaac_lan_api_example
```

示例只用于开发，包含主动给予硬币的操作。无 LAN、单人游戏或主客机均使用同一入口；联机验证时两端都安装示例以提供主机处理器。

## 安装范围

纯本机 UI 只需使用者安装；Stats+ 与 EID 不要求主机安装对应 UI。GoodTrip 的主机动作由 LAN 内置提供，地图 UI 仍可仅由使用者安装。新增物品、角色、实体、房间或资源，仍需各端安装相同内容。

API 不自动复制 `GetData()`、任意自定义状态、源码、配置或资源，也不提供第三方预测事件通道。只在本机 UI 接口执行的代码不会成为主机玩法逻辑。当前内置兼容范围见[Mod 兼容清单](https://github.com/BMingSY/isaac-lan/blob/main/docs/mod-compatibility.md)。

完整方法、身份、动作限制与清理约定见[API 2 参考](https://github.com/BMingSY/isaac-lan/blob/main/docs/mod-api-reference.md)。
