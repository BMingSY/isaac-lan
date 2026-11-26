# Mod API 2 参考

入口为 `IsaacLAN.API_VERSION == 2`；全部句柄和动作方法用冒号调用，SDK 工厂使用 `SDK.attach(mod, id)`。接入方式见[快速开始](https://github.com/BMingSY/isaac-lan/blob/main/docs/third-party-mod-integration.md)。

## 绑定和生命周期

`IsaacLAN:Attach(mod, id)` 绑定 `RegisterMod` 返回的实例。`id` 是各端共享的命名空间，只允许 ASCII 字母、数字、`_`、`.`、`-`，长度 1–64 字节。同一实例和 ID 重复绑定返回同一句柄；同名不同实例、同实例换 ID 抛错。句柄关闭后可重新绑定。

| 句柄方法 | 契约 |
| --- | --- |
| `IsAttached()` | 句柄是否尚未关闭 |
| `IsActive()` | 是否在进行中的 LAN 游戏内，包括视图准备阶段；大厅和结局阶段为 `false`，仍禁止单机回退 |
| `IsReady()` | 当前可读取本机视图；LAN 需要已提交当前代次，单机需要角色存在 |
| `IsAuthority()` | 进行中的 LAN 游戏房主或单机；大厅、结局及关闭后为 `false` |
| `View()` | 本机视图副本；未就绪时为 `nil` |
| `GetLocalPlayers()` | 本机控制的角色数组；包含双角色，未就绪时为空 |
| `GetOwnerId(player)` | 稳定参与者 ID，从 1 开始；未知对象为 `nil` |
| `GetPlayerId(player)` | 当前逻辑身体 ID，如 `p2:1`；未知对象为 `nil` |
| `IsLocalPlayer(player)` | 是否属于本机参与者 |
| `GetLocalRoom()` | LAN 的 `{runId, worldEpoch, index, dimension}`；单机或未就绪时为 `nil` |
| `WithLocalView(fn)` | 在本机房间与本机角色名单中执行读操作，保留全部返回值；未就绪时 `nil, "view_not_ready"` |
| `OnLocalRender(fn)` | 每个可用渲染帧调用 `fn(view)`，返回可重复调用的取消函数 |
| `GetHUDPlayers(options?)` | 读取已连接玩家各身体的血量、物品槽和资源，可选被动道具清单。未就绪时返回空数组 |
| `HideHUD(component, audience)` | 在本机隐藏选定参与者的一种 HUD 组件，返回恢复函数 |
| `OnHUDRender(component, audience, draw)` | 在该组件的绘制位置调用 `draw(panel)`，返回取消函数 |
| `OnHUDHearts(audience, draw)` | 等价于 `OnHUDRender("hearts", audience, draw)` |
| `RegisterMenuSetting(definition)` | 在本机大厅的「Mod 设置」页登记选项，返回撤销函数 |
| `On(event, fn)` | 订阅 LAN 生命周期，返回取消函数；无 LAN 时不产生事件 |
| `RequireEffectSync(variant, subtype?)` | 完整同步匹配的房间特效，返回可重复调用的释放函数，见下文 |
| `Action(name, definition?)` | 定义或取得动作对象，见下文 |
| `Close()` | 移除所属渲染回调、订阅、动作与注册；可重复调用 |

`View()` 的共同字段为 `players`、`ownerId`、`networked`、`tick`。单机 `tick` 是游戏帧数，所有本机身体属于参与者 1。LAN 还包含 `runId`、`worldEpoch`、`revision`、`room`、`playerSignature`：

| LAN 字段 | 用途 |
| --- | --- |
| `runId` | 房主生成的整局标识，换新局时失效 |
| `worldEpoch` | 世界代次；换层、沙漏、R Key 等重建时失效 |
| `tick` | 权威模拟 tick，不是本机渲染帧 |
| `revision` | 本机视图提交序号，重建后从 1 开始；不跨端比较 |
| `room` | 所在房间身份；维度与索引共同确定位置 |
| `playerSignature` | 角色集合／对象／类型变化标记，作为不透明值比较 |

身份不取临时显示顺序、控制器编号或实体地址。重连保留参与者席位，身体替换后要重新取得对象；跨世界缓存应包含 `runId`、`worldEpoch`。数组与表为副本，实体对象仍指向原生游戏对象，不应跨复位保存。身份查询也能识别已登记的远端身体，但不会把队友加入本机数组。

`WithLocalView` 支持嵌套、异常恢复；只在包围的调用内改变读取作用域，不清理 Mod 自己的缓存。不要在其中改世界、消费随机序列或跨帧挂起。`OnLocalRender` 自动包围此作用域，绘制频率不与网络提交频率绑定。回调出错会写日志并停用该回调，不停用其他 Mod。

| LAN 事件 | 触发条件 |
| --- | --- |
| `StateReset` | 退出／重建前的旧视图已清空，参数为旧上下文加 `reason`；只清理缓存 |
| `LocalPlayersChanged` | 本机身体集合、对象或角色类型变化 |
| `LocalRoomChanged` | 本机房间或维度改变，队友单独换房不触发 |
| `ViewUpdated` | 一份完整本机视图提交完成 |
| `SessionReady` | 第一份或重建后的第一份视图就绪 |

事件在游戏主线程、完整状态应用和原生作用域恢复后、UI 绘制前执行，按表中顺序触发需要的事件。除 `StateReset` 外在本机只读视图中调用。事件参数为提交上下文副本；取角色用 `lan:View()`。不会补发订阅前的事件；`SessionReady` 可在同局多次发生。订阅报错只停用该订阅。`StateReset` 时不能用旧对象访问世界。

## 联机 HUD 与大厅设置

这些接口只影响安装该 Mod 的这台机器。设置、隐藏请求和绘制回调可以在 Mod 加载时登记。房主与客机各自选择，加入或重连时无需交换选择。没有注册选项时，大厅省略「Mod 设置」入口。普通单机沿用游戏 HUD。兼容较早的 API 2 构建时，先检查对应的句柄方法是否存在。

用 `HideHUD(component, audience)` 隐藏组件，用 `OnHUDRender(component, audience, draw)` 替换绘制。两者支持相同的组件和受众。受众可以是 `"local"`（本机及其伴生身体）、`"teammates"` 或 `"all"`。例如 `local restore = lan:HideHUD("activeItem", "teammates")` 隐藏队友的主动道具，调用 `restore()` 即可释放这次请求。

| `component` | 绘制时机和专用字段 |
| --- | --- |
| `"hearts"` | 每个原生心格面板一次。`unknown` 表示未知诅咒，`isGhost` 表示合作幽灵，两种情况下都省略 `health`。其余情况下，`health.red/maxRed/soul` 以半心计，`blackMask` 沿用 `GetBlackHearts()` 的位掩码，另有 `bone/broken/rotten/eternal/golden` |
| `"activeItem"` | 每次绘制有物品的主动槽。用 `panel.activeItem` 读取 `slot`、道具 `id`、普通充能 `charge`、电池额外充能 `batteryCharge`，以及已占用槽的有效容量 `maxCharge` 和游戏充能类型 `chargeType` |
| `"trinket"` | 每次绘制有物品的饰品槽。`panel.trinket` 含 `slot` 和 `id`，保留金饰品标志 |
| `"pocketItems"` | 整组口袋物品共用一次绘制。`panel.pocketItems` 是显示顺序中的四个槽，每项含 `slot`、`kind`、`id`。种类为 `empty`、`card`、`pill` 或 `activeItem`。药丸 ID 是颜色并保留大药丸标志，口袋主动提供道具 ID 和对应的 `activeSlot`。接管口袋栏也会接管其中的图标 |
| `"ping"` | 每个已连接客机的延迟标签一次，按 `ownerId` 区分。字段 `networkMs` 和 `syncMs` 分别为网络和同步延迟的毫秒数，各自在尚无测量值时为 `nil` |

所有面板都有 `component`、`ownerId`、`isLocal`、`x`、`y`、`scale` 和 `alpha`。坐标是该次绘制传入的游戏逻辑屏幕锚点，物品图标可在锚点附近排版。缩放可带镜像符号，未提供透明度的组件取 1。按身体绘制的四个组件还有 `playerId` 和 `playerType`。双子属于同一参与者，各有自己的身体 ID。数组按 Lua 习惯从 1 取值，每个物品记录的 `slot`、`activeSlot` 沿用游戏的从 0 开始的槽号。

同一组件按注册顺序分派。回调返回 `true` 即接管这一次绘制，返回 `false` 或 `nil` 则继续尝试下一个回调，最后回退到默认界面。隐藏请求优先于自绘，注册自绘无需再调用 `HideHUD`。每个回调收到独立的数据副本，回调出错时停用该回调。回调内的游戏查询使用本机房间和角色名单。游戏省略的面板也会省略回调，例如双人联机的原版忏悔只绘制远端双子的主身体心格。

需要独立排版时，可以在 `OnLocalRender` 中调用 `GetHUDPlayers()`。每个身体提供身份、上表的血量字段、四个 `activeItems`、两个 `trinkets`、四个 `pocketItems` 和 `resources`。空槽的 `id` 为 0。`resources` 含 `coins/bombs/keys`、金炸弹与金钥匙标志 `goldenBomb/goldenKey` 以及 `soulCharge/bloodCharge`。使用 `GetHUDPlayers({includeCollectibles = true})` 才会读取被动道具及跟班清单 `collectibles`，每项为 `{id, count}`。同一视图提交内可重复读取。资源和被动清单可供 Mod 自绘，当前原位替换的组件列在上表。整队查询包含原生布局省略的身体，由 Mod 自选坐标，可用 `Game():GetHUD():IsVisible()` 跟随游戏 HUD 显隐。

例如，让每个玩家在大厅选择如何显示队友的主动道具。选择「充能」时只接管有道具的槽位。

```lua
local mode = 1
lan:RegisterMenuSetting({
    id = "team-active", name = "队友主动道具",
    choices = { "原版", "隐藏", "充能" },
    onChange = function(index) mode = index end,
})
lan:OnHUDRender("activeItem", "teammates", function(panel)
    if mode == 1 then return end
    if mode == 3 then
        local item = panel.activeItem
        Isaac.RenderText(tostring(item.charge + item.batteryCharge),
            panel.x, panel.y, 1, 1, 1, panel.alpha)
    end
    return true
end)
```

`RegisterMenuSetting` 的 `id` 是当前 Mod 内唯一的 1–64 字节标识，可用字母、数字、下划线、点和连字符。`name` 和至少两个 `choices` 是 Mod 提供的本地化文字。`selected` 为从 1 开始的初始索引，默认 1。玩家用左右键切换，确认或点击切到下一项，选中后调用 `onChange(index)`。登记时不会触发该回调。希望跨启动保留选择的 Mod 可用自己的存档读取和保存索引。各项按命名空间和局部 ID 排序，出错的选项会被移除。这些接口的撤销函数均可重复调用，关闭句柄、卸载或重载 Mod 会清理它拥有的注册。

## 大厅挑战

在 Mod 加载时用绑定句柄注册挑战。只需填写本 Mod 的局部 `id` 和菜单名称。不同 Mod 可以使用相同的 `id`，同一命名空间内每个 `id` 只能注册一次。下面的挑战要求四人，房主可以在大厅调整房间规则。

```lua
local lan = IsaacLAN:Attach(mod, "example.arcade")
local raid = lan:RegisterChallenge({ id = "raid", name = "风暴试炼", players = 4 })

lan:OnLocalRender(function(view)
    if view.challengeId == raid.id then
        -- 绘制本机的挑战界面。
    end
end)
```

`raid.id` 为完整标识 `"example.arcade:raid"`。各端按完整标识、规则版本、人数、角色、难度及规则锁定设置匹配，允许不同的加载顺序、本地化名称和额外安装的挑战。大厅资格表最多容纳 64 个挑战，包含内置挑战。

| 声明字段 | 用法 |
| --- | --- |
| `id`、`name` | 局部标识可用 1–64 个字母、数字、下划线、点或连字符，也接受 0–65535 的整数写法。整数 `1` 与字符串 `"1"` 表示同一标识。菜单名为 1–96 字节 |
| `version` | 可选，默认 1。修改不兼容的玩法或快照格式时提高版本，范围为 1–65535 |
| `players`、`character`、`difficulty` | 可选。人数指定 2–4 时须恰好满员，省略时支持任意 2–4 人。角色省略可自由选择。难度默认 0，可选 0–3 |
| `roomOptionsLocked` | 默认 `false`，沿用大厅已有的友伤、清房充能共享、道具掷骰分配和自动传送设置，房主仍可更改。设置为 `true` 时，本挑战关闭并锁定这些规则。切回可编辑模式时恢复房主的选择 |
| `step(ctx)` | 可选，房主每个模拟 tick 至多调用一次。`ctx` 含 `runId`、`worldEpoch`、`tick` 及以参与者 ID 为键的已连接主身体表 `players`。掉线席位为空，身体只在本次回调内有效 |
| `capture()`、`apply(value)` | 有自定义状态需要同步时成对提供。房主采集，客机应用完整快照。沿用动作载荷的类型与 2048 字节限制。初始化前可返回 `false`。重复应用同一快照不能重复结算 |
| `reset()` | 可选，挑战结束或卸载时清理资源和本机演出，可重复调用 |
| `canEnter(request)` | 可选，房主判断是否允许房间移动，返回布尔值。来源和目标由 `fromRoom`、`fromDimension`、`room`、`dimension` 指定，`slot` 是从 0 开始的席位 |

`challenge:Finish()` 仅在房主运行该挑战时提交全队结局。挑战使用临时会话，普通联机续玩档会保留。大厅允许提前选择挑战，开始和重新开局时核对人数。

创建或加入房间前完成注册。`challenge:Close()` 撤销声明，关闭绑定句柄也会撤销。大厅中卸载挑战会结束本机连接，游戏中卸载当前挑战会结束该挑战会话。兼容较早构建时可先检查 `lan.RegisterChallenge`。

## 房间特效

需要逐个读取某种房间特效的 Mod 可在绑定时声明 `lan:RequireEffectSync(variant, subtype?)`。两个参数均接受非负整数，省略子类型表示该变体的所有子类型。普通说明、界面和道具 Mod 可直接沿用默认同步。

```lua
local release = lan:RequireEffectSync(EffectVariant.BLOOD_PARTICLE, 99)
-- 在不再观察这类血花时调用
release()
```

房主声明为所有客机保留匹配的特效。仅客机声明时，房主收到请求后为该客机后续视图保留仍存活及新生成的匹配特效。其他特效沿用各自的同步规则。声明适用于当前和之后的房间、楼层及会话。多个句柄可以独立声明同一特效，最后一个声明释放后，新出现的特效恢复默认规则。`lan:Close()` 会释放该句柄的全部声明。单机和已经完整同步的特效都可以使用同一写法。兼容较早的 API 2 构建时，可先检查 `lan.RequireEffectSync` 是否存在。

## 动作与完成结果

`lan:Action(name, definition)` 创建动作对象；`lan:Action(name)` 取得已创建的对象，或创建版本 1 的远端引用。相同名字重复提供定义会抛错。远端引用要指定版本时传 `{version = n}`；它不提供本地处理器。名字长度 1–32 字节，字符约束与接入 ID 相同。

| 定义字段 | 契约 |
| --- | --- |
| `version` | 动作业务契约版本，默认 1，整数 1–65535；请求端与主机精确匹配 |
| `validate(payload)` | 仅校验载荷结构，必须返回 `true`；默认仅接受 `nil` |
| `execute(context, payload)` | LAN 只由主机执行；单机作为默认实现；返回最终结果或 LAN 异步操作 |
| `solo(context, payload)` | 可选，未联机时覆盖 `execute`；必须同步返回最终结果 |
| `cooldownTicks` | 主机按动作和参与者限制频率，默认 15，范围 1–1800；单机业务自行控制 |

动作版本描述请求／结果结构，独立于 Mod 发布版本和网络协议。UI Mod 不需要锁定上游版本或源码哈希。主机公布可用动作；只有当前版本一致且句柄就绪时 `action:IsAvailable()` 才为真。关闭后的动作为不可用。

`action:Request(payload?, {player?, onResult?}?)` 总是返回请求对象：`{status, id?, code?, result?}`。`status` 初始为 `pending`，结束后写入最终状态与 `result`。不指定 `player` 时选本机第一个身体；指定的身体必须属于本机。LAN 请求只携带稳定角色 ID，主机根据连接重新核对所属参与者并解析实体；其他人的身体不可选择。

`onResult(result)` 最多一次，包含 `{status, code, data?}`，LAN 已提交请求还包含 `requestId`、`runId`、`worldEpoch`。本地拒绝和单机执行可能同步完成；不要假定回调发生在 `Request` 返回后。主机业务数据放 `data`。关闭动作／句柄时，未完成请求以 `unknown/integration_closed` 通知，晚到回执不会重复通知，也不能据此认为主机执行被撤回。

| 最终状态 | 意义 |
| --- | --- |
| `applied` | 权威操作已完成，例如确实到达目标 |
| `rejected` | 未通过校验或条件，未执行操作 |
| `cancelled` | 操作因停用、复位等终止；已发生的代价不自动逆转 |
| `unknown` | 超时、断线或异常后无法确认完整结果；检查当前权威状态，不自动以新 ID 重试 |

主机自己的请求也经过队列与去重。主机在发起参与者的权威房间内调用处理器，`context` 包含 `player`、`playerId`、`ownerId`、`room`、`runId`、`worldEpoch`、`requestId`；单机只提供本机视图字段及所选角色身份。`validate` 仅检查结构，权限、代价、路径、清房等实时条件由 `execute` 核查。处理器报错返回 `unknown/handler_error` 并停用该主机处理器；已经执行的写入不回滚。

### 异步与迁移

`context:Wait({poll, cancel?})` 仅在当前主机处理器内创建操作；由 `execute` 返回后才调度。`poll()` 在参与者当前房间中调用，返回 `nil` 等待，或 `{status, code, data?}` 结束。`cancel()` 是收尾函数，在成功、失败、超时、停用和世界复位时均可能调用；应可重复清理，不依赖旧房间作用域。等待上限 5 秒。

`context:MoveTo({index, dimension})` 可在当前处理器或其活跃操作中提交参与者迁移，返回异步操作或 `nil, code`。索引 -20–168、维度 0–2 只是参数范围，是否存在、能否进入、路径和代价由 Mod 验证。只有实际位置匹配才完成为 `applied/arrived`；3 秒未到达为 `unknown/arrival_unconfirmed`。动作针对所选身体执行，但房间迁移以整个参与者为单位。迁移不会把已到达的参与者送回来源；完成前不要修改目标表。

这些方法仅在 LAN 权威动作上下文可用。需要独立单机行为时提供 `solo`，调用原有单机逻辑。上下文不是长期权限对象，不得留到其他回调使用。

### 传输边界与错误

请求和结果使用 ENet UDP 的可靠有序控制消息。身份由连接绑定，源房间与世界代次在执行前核对。允许的数据是布尔、有限数值、字符串、连续数组或纯字符串键表；不接受函数、实体、元表或循环引用。完整消息含头部最多 2048 字节，字符串最多 512 字节，键最多 64 字节，总表项最多 128，嵌套深度最多 6。无法编码的请求为 `rejected/invalid_payload`；不可编码结果为 `unknown/invalid_result_data`，不会因静默丢失等到超时。

全 Lua 环境最多注册 16 个处理器（含内置）；提交侧最多 8 个未完成请求，主机每参与者最多排队 8 个动作、同时运行 1 个异步操作。传输每发送者最多缓存 32 条扩展消息、每秒 64 条。请求 5 秒未确认得到 `unknown/timeout`。

| 常见代码 | 处理 |
| --- | --- |
| `view_not_ready`、`action_unavailable` | 等待视图／能力可用，更新 UI |
| `player_not_local`、`player_unavailable` | 从新视图取得本机身体，不复用已失效对象 |
| `invalid_payload` | 修正参数结构 |
| `request_queue_full`、`transport_unavailable` | 清理 UI 等待状态，避免自动无限重发 |
| `source_changed`、`stale_world` | 请求所属房间／世界已变化 |
| `rate_limited`、`operation_busy` | 参与者已有操作或未过冷却 |
| `action_disabled`、`owner_unavailable` | 主机能力或发起参与者已失效 |
| `timeout`、`handler_error`、`operation_error`、`operation_timeout`、`invalid_result_data` | 结果不确定，核对权威状态 |
| `request_id_reused`、`dedupe_expired`、`generation_limit` | 去重边界；不修改旧 ID 或对未知结果自动换 ID |

始终同时读取 `status` 和 `code`；世界复位原因和业务处理器也可提供代码。注册参数、重复 ID、错误的方法调用属于编程错误，会抛 Lua 异常；结果回调抛错仅记录日志。

## 自动适配管理

`IsaacLAN:RegisterAdapter(definition)`、`GetAdapters()`、`SetAdapterEnabled(id, enabled)` 用于自动兼容模块；定义、探测、清理、状态与持久开关见[适配器参考](https://github.com/BMingSY/isaac-lan/blob/main/docs/mod-adapter-development.md)。

`IsaacLAN:SetActionEnabled(id, name, enabled)` 修改本机已注册动作的开关，不持久保存；成功返回 `true`，不存在返回 `false, "action_not_registered"`。全队是否能执行由主机公布的能力决定。
