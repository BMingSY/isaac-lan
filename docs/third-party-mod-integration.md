# 第三方 Mod 接入 API v1

Isaac LAN 提供本机视图、生命周期通知、主机动作和自动兼容注册。实现位于 [`src/bridge/api/`](../src/bridge/api/public.lua) 与 [`src/bridge/compat/`](../src/bridge/compat/registry.lua)，随 DLL 嵌入，在第三方 Mod 初始化前发布全局 `IsaacLAN`。

本版实现原设计的阶段 A（本机视图）和 B（玩法请求）。阶段 C 的补充状态、实体元数据、存档扩展和必需内容声明尚未提供；不会自动复制 `GetData()`、Mod 源码、配置或资源。动作传输使用协议 19，原生视图 schema 仍为 4，各端需要同一扩展构建。

## 安装与责任

| 使用方式 | 安装约定 |
| --- | --- |
| Stats+ 基础属性面板、EID 基础说明 | 谁需要界面，谁安装；主机不需要同样的界面 Mod |
| GoodTrip 地图界面 | 谁需要操作，谁安装；主机处理器随 LAN 提供，可以关闭 |
| 新物品、角色、实体、房间和资源 | 各端仍需一致的内容定义、资源与 ID 映射 |
| 第三方玩法动作 | 主机必须注册兼容版本的处理器并允许该动作 |

主机权威决定世界变化。客机没有 GoodTrip 时不会凭空获得地图界面；主机没有 GoodTrip 时仍可执行受支持客机界面的请求。未声明的 Mod 差异仍只提示，不会自动识别或阻止内容定义冲突。

通用 API 不包含目标 Mod 的名字或业务规则。内置适配器使用相同的注册句柄、视图与动作接口；对旧版本的服务、方法和回调包装只放在兼容目录。

## 注册与单机回退

```lua
local mod = RegisterMod("Example integration", 1)
local api = rawget(_G, "IsaacLAN")
local lan
if api and api.API_VERSION == 1 then
    lan = api:RegisterMod(mod, {
        id = "example.integration",
        integrationVersion = 1,
    })
end
```

在加载时注册一次，不因尚未联机跳过注册。`id` 是唯一命名空间，最长 64 字节，只接受字母、数字、下划线、点和连字符。`integrationVersion` 是接入方的正整数版本，与游戏 `RegisterMod` 的 API 版本不同。

同一 Mod、ID 和版本重复注册返回原句柄；不同实例占用同一 ID、同一实例占用多个 ID、重复动作定义会抛出明确错误。`lan:Unregister()` 移除自己的订阅和处理器，旧句柄不能重新添加订阅或动作，请求返回 `integration_unregistered`。目标 Mod 主动注册时，内置适配器让出该实例。

无 API 或 `IsActive()` 为 false 时沿用单机逻辑。联机但 `IsReady()` 为 false 时等待视图；联机缺少主机动作时关闭对应操作，不能回退到客机执行原玩法代码。

## 两个简短示例

以下片段承接上文注册得到的 `mod` 和 `lan`。

### 本机界面刷新

面板只缓存本机角色的原生属性，双角色仍各占一项；每次更新重新建立数组，复位时清空旧数据。

```lua
local panel = {}
if lan then
    lan:On("StateReset", function()
        panel = {}
    end)
    lan:On("ViewUpdated", function()
        panel = {}
        for i, player in ipairs(lan:GetLocalPlayers()) do
            panel[i] = { damage = player.Damage, tearDelay = player.MaxFireDelay }
        end
    end)
end
```

原有绘制回调在 LAN 就绪时读取 `panel`，准备阶段跳过绘制；无 API 或未联机时仍使用原有单机数据。`ViewUpdated` 已在本机视图内执行，无需再包一层 `WithLocalView`，也无需同步面板自己的状态。

### 向主机请求玩法动作

使用下文[主机动作与回执](#主机动作与回执)中的 `travel` 处理器，两端使用相同接入 ID。确认目标时调用 `requestTravel(index, originalTravel)`，第二个参数传入原来的单机传送函数。

```lua
local function requestTravel(index, originalTravel)
    if not lan or not lan:IsActive() then
        return originalTravel(index)
    end
    if not lan:IsReady() then
        return nil, "view_not_ready"
    end
    if not lan:HasHostAction("travel", 1) then
        return nil, "action_unavailable"
    end
    return lan:RequestAction("travel", {
        index = index,
        dimension = lan:GetLocalRoom().dimension,
    }, function(result)
        Isaac.DebugString(result.status .. ":" .. result.code)
    end)
end
```

请求 ID 只表示已提交；收到 `applied` 才表示完成。LAN 请求失败时向界面报告返回的错误码，`unknown` 时核对权威状态，不自动重试或调用原传送函数。

## 本机视图与身份

| 方法 | 行为 |
| --- | --- |
| `lan:IsActive()` | 是否处于 LAN 游戏会话，包括视图准备阶段 |
| `lan:IsReady()` | 已提交的本机视图是否属于当前整局与世界代次，角色和房间是否可读取 |
| `lan:IsAuthority()` | 是否为运行会话的房主 |
| `lan:GetLocalPlayers()` | 本机控制的原生角色数组；未就绪时为空 |
| `lan:GetOwnerId(player)` | 所属参与者 ID，从 1 开始；不是原生控制器编号 |
| `lan:GetPlayerId(player)` | 本次整局中的逻辑角色 ID，如 `p2:1`；未知对象返回 `nil` |
| `lan:GetLocalRoom()` | `{runId, worldEpoch, dimension, index}`；未就绪时 `nil` |
| `lan:GetContext()` | `{runId, worldEpoch, tick, revision, room, playerSignature}` 的副本 |
| `lan:WithLocalView(fn)` | 在本机房间、仅本机角色名单中执行函数，保留全部返回值 |

参与者身份沿用 LAN 稳定席位，重连保留。主角色与双角色使用同一参与者下的不同逻辑角色 ID；对象替换后重新绑定。ID 不使用显示时 `Isaac.GetPlayer(i)` 的临时顺序、实体地址或原生控制器值。辅助角色的角色集合变化必须使缓存失效；跨整局和世界重建的缓存还需包含 `runId`、`worldEpoch`。

`GetLocalPlayers()` 保留雅各和以扫等本机控制角色；队友不会因为同屏或同房混入。返回数组和上下文都是副本，原生角色对象仍可变。

`WithLocalView` 支持嵌套；异常时恢复原生房间、名单与上下文并重新抛出错误。未就绪时返回 `nil, "view_not_ready"`。它只影响包围的调用，不能清除第三方已有的玩家缓存，也不是 Lua 沙箱。仅用于读取世界和更新 UI 缓存，不加减道具、伤害、换房、消费随机序列或跨帧挂起。

## 生命周期

`lan:On(event, fn)` 返回取消订阅函数；所有事件都传入上下文副本。退出时仅发送清理通知。一个订阅报错会记录接入 ID 和事件并停用该订阅，其他订阅与原生状态应用继续执行。

| 事件 | 触发条件 |
| --- | --- |
| `StateReset` | 退出、重建、换层、回退；上下文附带 `reason` |
| `LocalPlayersChanged` | 本机角色、原生对象或角色类型变化 |
| `LocalRoomChanged` | 本机房间或维度变化；队友单独换房不触发 |
| `ViewUpdated` | 完整本机视图提交，角色、地图和房间可读取 |
| `SessionReady` | 首份视图或重建后的首份视图就绪 |

房主在模拟和迁移完成后通知，客机在完整状态应用及原生作用域恢复后通知；都在游戏主线程、下一次 UI 绘制前执行。顺序为需要的 `StateReset` → `LocalPlayersChanged` → `LocalRoomChanged` → `ViewUpdated` → 首次就绪的 `SessionReady`。除清理通知外，订阅默认在本机只读视图内运行。

`runId` 由房主生成并随开局／重连检查点传输。换层、R Key 与沙漏等重建推进 `worldEpoch`；`revision` 在代次内随提交递增。刷新采用脏标记与原生属性读取，不伪造 `MC_EVALUATE_CACHE` 或道具使用回调。

```lua
local dirty = true
lan:On("StateReset", function()
    dirty = true
end)
lan:On("LocalPlayersChanged", function()
    dirty = true
end)
lan:On("ViewUpdated", function(context)
    for displayIndex, player in ipairs(lan:GetLocalPlayers()) do
        -- 使用 player 的原生属性；显示序号为 displayIndex - 1。
        -- 缓存键包含 context.runId、context.worldEpoch 和 lan:GetPlayerId(player)。
    end
    dirty = false
end)
```

## 主机动作与回执

| 方法 | 行为 |
| --- | --- |
| `lan:RegisterAction(name, definition)` | 注册本命名空间处理器；返回注销函数 |
| `lan:HasHostAction(name, version)` | 主机是否公布并允许该业务版本 |
| `lan:RequestAction(name, payload, onResult)` | 返回请求 ID，或 `nil, code`；版本取自主机能力 |
| `lan:CreateOperation({poll, cancel})` | 创建异步句柄；`poll` 返回 `nil` 等待，或最终结果 |
| `lan:MovePlayer(context, destination)` | 权威处理器／其活跃异步操作中提交原生迁移，返回到达句柄或 `nil, code` |
| `IsaacLAN:SetActionEnabled(id, name, enabled)` | 允许／撤销本机注册的主机能力；运行时生效 |

`name` 最长 32 字节，字符约束与接入 ID 相同。定义包含正整数 `version`（1–65535）、`validate(payload)`、`execute(context, payload)`，可选 `cooldownTicks`（默认 15，范围 1–1800）。最多注册 16 个动作。定义在加载时注册；只有房主执行，主机自己的请求同样走队列、来源校验和去重。

`validate` 必须返回 `true` 才通过。`execute` 收到权威上下文：`ownerId`、`playerId`、`player`、源 `room`、`runId`、`worldEpoch`、`requestId`。发送者由传输连接绑定；载荷中的“玩家编号”“扣血结果”或客户端世界快照不作为权威事实。处理器在明确的请求参与者及其房间上下文内执行。

载荷允许布尔、有限数值、字符串、连续数组和字符串键记录；禁止 `nil` 值、函数、userdata、循环引用及元表。独立编码器限制整条消息 2048 字节、深度 6、128 个条目、字符串 512 字节、记录键 64 字节。超限或类型不符返回 `invalid_payload`，不会使用原生数组视图编码器静默丢字段。

提交侧最多 8 个未完成请求；传输侧每发送者最多 32 条待收消息、每秒 64 条；主机每参与者最多 8 条待处理动作，且同一参与者仅运行一个异步操作。请求和结果走可靠 TCP 消息，不参与可合并的世界快照队列。

请求包含整局、代次、实际源房间、随机请求代次和递增序号。主机再次检查源房间、业务版本、权限与冷却，然后执行。每发送者／请求代次保留高水位及最近 64 条结果；更旧的重复序号返回 `dedupe_expired`，不会再次执行。每世界代次每参与者最多接受 8 个请求代次，防止去重记录无限增长。

同步处理器返回 `{status, code}`，或返回 `CreateOperation`／`MovePlayer` 的句柄。异步完成在权威视图提交时、该参与者当前房间的作用域内检查。动作上下文只在处理器和该操作存续期间有效，不能当作长期修改世界的权限。

| 最终状态 | 含义 |
| --- | --- |
| `applied` | 已完成，如实际到达目标房间 |
| `rejected` | 校验或条件不满足，没有执行操作 |
| `cancelled` | 操作因复位、停用或死亡等终止；已经发生的代价不会自动逆转 |
| `unknown` | 断线、超时或执行异常后无法确认完整结果；先核对权威状态，不自动换新 ID 重试 |

提交侧 5 秒未确认返回 `unknown/timeout`；迁移 3 秒未到达返回 `unknown/arrival_unconfirmed`，异步操作总等待上限 5 秒。缺少能力返回 `action_unavailable`，视图未就绪返回 `view_not_ready`，拥塞返回 `request_queue_full` 或 `transport_unavailable`。旧代次、源房间改变、冷却或重复 ID 分别有 `stale_world`、`source_changed`、`rate_limited`、`request_id_reused` 等代码。结果回调报错只记录日志。

下面是可运行的主动接入示例；两端使用同一 ID。业务规则仍由房主定义：

```lua
lan:RegisterAction("travel", {
    version = 1,
    validate = function(payload)
        return type(payload) == "table"
            and math.type(payload.index) == "integer"
            and payload.index >= 0 and payload.index < 169
            and math.type(payload.dimension) == "integer"
            and payload.dimension >= 0 and payload.dimension <= 2
    end,
    execute = function(context, payload)
        local destination = Game():GetLevel():GetRoomByIdx(payload.index, payload.dimension)
        if payload.dimension ~= context.room.dimension or not destination
            or not destination.Data or not destination.Clear or destination.VisitedCount == 0 then
            return { status = "rejected", code = "destination_unavailable" }
        end
        local operation, code = lan:MovePlayer(context, payload)
        if not operation then
            return { status = "rejected", code = code }
        end
        return operation
    end,
})

-- 在自己的界面确认目标时调用；单机仍调用原逻辑。
if lan:IsActive() and lan:IsReady() and lan:HasHostAction("travel", 1) then
    local requestId, code = lan:RequestAction("travel", {
        index = 71,
        dimension = lan:GetLocalRoom().dimension,
    }, function(result)
        Isaac.DebugString(result.status .. ":" .. result.code)
    end)
end
```

## 自动兼容注册

自动兼容让尚未主动接入 API 的旧 Mod 可以在 LAN 中使用已有功能。包装在目标 Mod 加载、初始化时安装，会贯穿后续单机和 LAN 会话；因此方法在未联机时调用原函数，在 LAN 中才使用本机视图或主机动作。保留单机行为是这些包装的运行约束，安装依据仍是目标身份、支持版本和运行时探测。

`IsaacLAN:RegisterCompatibility(definition)` 返回停用函数。定义包含唯一 `id`、正整数 `adapterVersion`、目标注册名称 `modName`、`targets`、`probe(target)`、`install(target, api)`，以及可选 `authority(api)` 与回调 `dispatch(target, record, ...)`。

每个目标必须提供 `workshopId`、`metadataVersion` 和 64 字节 `sourceHash`。加载观察器结合实际 `RegisterMod` 实例、来源目录、启用状态和源码指纹确认目标。只存在目录、同名 Mod 或残留全局不会匹配。`target` 包含 `mod`、目录／版本／指纹和该来源加载的模块导出。`RegisterMod` 第二个参数不是 Mod 发布版本。

源码指纹为 SHA-256：先输入 `Isaac LAN/compat-source-v1` 与零字节，再按相对路径排序输入每个 `.lua` 的相对路径、零字节、文件 SHA-256 的十六进制文本和零字节。`gtconfig.lua`、`eid_config.lua` 是配置文件，不计入源码身份；其余 Lua 包含语言与服务实现。修改源码或新的上游版本必须增加独立支持记录。

`probe` 返回 `ready`、`pending` 或 `unsupported` 及原因。只在 `ready` 后安装一次；`pending` 在初始化后及首次回调前重试。`install` 中可用 `api:RegisterMod(target.mod, options)` 获取归属于该适配器的句柄，不会触发主动接入优先规则；目标 Mod 在安装回调以外主动注册时才让出。`install` 必须返回清理函数并注销自己的句柄，可用 `target.addCleanup(fn)` 提前登记部分安装的清理，确保异常时回滚。`authority` 在加载时注册独立主机能力，不因尚未开局或缺少本机 UI Mod 跳过。

回调包装保留优先级、参数、原顺序与返回值；使用原函数 `RemoveCallback` 仍能移除包装。已有回调在原列表位置替换，不通过移除／重加改变顺序。方法清理只撤回仍属于该模块的修改；重连不重复安装。

`IsaacLAN:GetCompatibilityStatus()` 返回各模块的 `id`、版本、状态、原因、目标身份和是否注册独立主机能力。状态为 `not_detected`、`pending`、`active`、`unsupported`、`disabled`、`error`；`active` 表示指纹、运行时探测和安装完成，功能验证范围见下表。

独立开关通过 `IsaacLAN:SetCompatibilityEnabled(id, enabled)` 保存到游戏目录的 `isaac-lan/integrations.ini`，默认允许。主机要保留自己的 GoodTrip UI 并禁止所有人传送，可调用 `IsaacLAN:SetActionEnabled("isaac-lan.compat.goodtrip", "travel", false)`；该动作开关只在当前 Lua 环境生效，永久关闭内置主机能力可关闭对应兼容模块。

## 内置模块

| 模块 | 源码配置 | 本版功能与边界 |
| --- | --- | --- |
| Stats+ | 2.1.3，创意工坊 2729900570 | `PlayerService` 使用本机角色；序号重新从 0 开始，保留双角色布局；对象变化重建服务，视图提交只读刷新普通属性缓存 |
| GoodTrip | 原版 1.2.8，1630477831 | 地图与输入保留本机；传送入口在任何副作用前提交动作；主机规则与 UI 分文件，主机无需安装原 Mod |
| EID | 元数据 5.23，运行时 5.24／980bb0b，836319872 | 原基础显示路径在本机角色与房间运行，更新自己的多人列表并清理目标缓存；保留本机语言、字体和配置 |

三者还必须匹配源码指纹，版本号相同但源码不同也不会强行安装；GoodTrip Fixed 等其他分支没有加入本版支持记录。

### Stats+

原版同时缓存队友并使用多人布局。适配器修改受支持版本的玩家服务来源，触发其自身服务重建，再读取已同步的伤害、射速等属性；不是把队友画到本机面板后再遮住。渲染、更新和相关缓存回调显式使用本机名单，队友缓存回调不进入本机 Provider。

射速上限 Provider 会临时添加／移除道具，LAN 会话中返回 `UNKNOWN` 并隐藏。D8 历史倍率也隐藏，不能把缺失使用历史当作真实倍率；伤害等安全派生倍率与普通属性继续按本机角色计算。单机仍使用原 Provider。未来补充权威历史时单独接入，不伪造道具使用或缓存事件。

### GoodTrip

[`client.lua`](../src/bridge/compat/goodtrip/client.lua) 只处理原版界面入口、本机缓存和请求结果；[`authority.lua`](../src/bridge/compat/goodtrip/authority.lua) 负责清房、已访问目标、隐藏地图、封闭挑战／小 Boss 房、追逐战、Mom 限制、挑战房血量、诅咒房代价及秘密房路径。

主机从实际请求角色读取数据，记录权威房间门提供的秘密房入口。无法确认所需秘密路径时明确拒绝 `secret_path_unknown`，不猜测入口。路径按原生迁移逐段完成，代价只在初始迁移接受后扣一次。死亡或路径中断有单独结果。固定目标迁移不会使用迷宫随机选房，也不在另一玩家模拟期间全局删除／恢复迷宫诅咒。

新入口不调用原传送函数，因此同一次点击不会再生成旧 `RoomRequest`。原生过门、道具及其他 Mod 的通用迁移入口保留。联机快捷重开关闭；动画使用 LAN 原生传送表现，主机冷却为 45 tick，不同步原界面动画配置。

### EID

不新增重复绘制回调，继续使用 EID 原有的输入、距离、可见性、说明注册和布局。`setPlayer()` 在本机视图建立列表，队友道具不会通过基础合作玩家列表影响本机描述。房间／世界复位后清理描述目标。

Flip 隐藏事实、动态 `EID_Description`、合成与随机预测没有新增权威数据通道，不能据此声称所有高级功能完整兼容。静态说明缺失仍需本机安装说明注册代码；内容 ID 不一致需要用户自行保持内容定义一致。

## 验证

无需游戏的 [`tests/bridge_api.lua`](../tests/bridge_api.lua) 验证独立编码、视图返回值与异常恢复、身份、事件顺序与错误隔离、能力撤销、实际完成回执、去重／重复 ID、失效源房间、超时，以及自动安装和原生接入优先。CMake 在找到 Lua 5.3 时将其加入 CTest；Linux CI 会运行。

[`tests/goodtrip_rules.lua`](../tests/goodtrip_rules.lua) 通过模拟权威环境验证特殊房间规则、诅咒代价只扣一次、死亡取消、迷宫下的固定目标，以及秘密房分段到达。

[`tests/net_test.cpp`](../tests/net_test.cpp) 的 `integrations` 用例验证真实 Winsock 通道、发送者绑定、消息顺序、不合并请求、结果接收范围、限额、整局身份和重连代次。

真实游戏使用原版文件的隔离拷贝：[`state_mod_ui.lua`](../tests/state_mod_ui.lua) 走地图与原生手柄输入；[`state_mod_integrations.lua`](../tests/state_mod_integrations.lua) 核对真实 Stats+ 玩家缓存及布局序号、EID 本机名单、客机 GoodTrip 请求、重复请求和最终到达。用 `--mod`、`--client-mod`、`--host-mod` 构造安装组合，见[开发与测试](development-and-testing.md)。

2026-10-08 的双实例游戏验证通过以下组合，均使用单向 75 ms 人工延迟：仅客机安装三个 Mod；两端均安装三个 Mod 并使用原生地图输入；两端均安装三个 Mod 且角色为雅各和以扫。双角色场景将测试脚本的 `character` 设为 `19`，验证两端各自两人的缓存、显示序号和逻辑 ID，以及客机传送后主机仍留在原房间。

这些用例不能替代全部特殊房间、角色、语言、回退及未知上游版本的验收。每次兼容范围扩展都需增加源码配置和对应游戏证据。
