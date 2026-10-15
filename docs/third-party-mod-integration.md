# 第三方 Mod 接入 API v1

Isaac LAN 提供本机视图、生命周期通知、主机动作和自动兼容注册。实现位于 [`src/bridge/api/`](https://github.com/BMingSY/isaac-lan/blob/main/src/bridge/api/public.lua) 与 [`src/bridge/compat/mods/`](https://github.com/BMingSY/isaac-lan/blob/main/src/bridge/compat/mods/registry.lua)，随 DLL 嵌入，在第三方 Mod 初始化前发布全局 `IsaacLAN`。

当前公开能力包括本机视图、生命周期、主机动作和自动适配器注册。补充状态、实体元数据、存档扩展和必需内容声明尚未提供；不会自动复制 `GetData()`、Mod 源码、配置或资源。当前传输协议为 30，世界视图 schema 为 18，各端需要同一扩展构建；公开 API 版本仍为 1，与传输和视图版本分别维护，见[网络与状态同步](https://github.com/BMingSY/isaac-lan/blob/main/docs/synchronization.md)。

本文是接入方契约；当前 Stats+、GoodTrip、EID 清单与兼容后的效果见[第三方 Mod 兼容清单](https://github.com/BMingSY/isaac-lan/blob/main/docs/mod-compatibility.md)。原版[角色](https://github.com/BMingSY/isaac-lan/blob/main/docs/character-compatibility.md)和[道具／效果](https://github.com/BMingSY/isaac-lan/blob/main/docs/item-effect-compatibility.md)另有清单。

## 接口入口

所有方法使用冒号调用；`IsaacLAN` 是全局入口，`lan` 是本 Mod 注册后得到的句柄。句柄上的身份和视图方法读取同一份已提交本机视图，订阅与动作则归属该句柄的命名空间。

| 全局成员 | 返回／用途 |
| --- | --- |
| `IsaacLAN.API_VERSION` | 整数 `1`，加载时检查 |
| `IsaacLAN:RegisterMod(mod, {id, integrationVersion})` | 接入句柄 `lan`，绑定实际 `RegisterMod` 返回的 Mod 实例 |
| `IsaacLAN:RegisterCompatibility(definition)` | 自动适配器停用函数，契约见[自动兼容注册](#自动兼容注册) |
| `IsaacLAN:GetCompatibilityStatus()` | 按 `id` 排序的状态数组副本 |
| `IsaacLAN:SetCompatibilityEnabled(id, enabled)` | `true`，或 `false, code`；持久保存本机兼容开关 |
| `IsaacLAN:SetActionEnabled(id, name, enabled)` | `true`，或 `false, "action_not_registered"`；修改本机已注册动作开关，不持久保存 |

公开接口不包含 `_IsaacLan`、原生指针或任意内存读写。调用参数与重复注册等编程错误通常通过 Lua 异常报告；会话未就绪、能力缺失等预期运行结果通过返回值／动作回执报告，见[错误处理](#错误处理)。

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

同一 Mod、ID 和版本重复注册返回原句柄；不同实例占用同一 ID、同一实例占用多个 ID、重复动作定义会抛出明确错误。`integrationVersion` 不参与主机动作版本协商，也不会自动同步该 Mod 的状态。

`lan:Unregister()` 无返回值，可重复调用；移除自己的订阅和处理器并释放注册占位。旧句柄不能重新添加订阅、动作或异步句柄，`HasHostAction` 返回 `false`，`RequestAction`／`MovePlayer` 返回 `nil, "integration_unregistered"`。视图读取方法仍是全局视图查询，不应以此判断句柄是否有效。需要重新接入时再次 `RegisterMod` 获取新句柄。目标 Mod 主动注册时，内置适配器让出该实例。

注销不会撤回已经发送的请求，也不回滚已开始的世界写入；未完成请求仍可能收到最终回执或超时。接入方卸载时应清理自己的等待 UI，并让结果回调能安全处理已清理状态。

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
| `lan:GetOwnerId(player)` | 所属参与者 ID，从 1 开始；未知对象或未就绪时 `nil`；不是原生控制器编号 |
| `lan:GetPlayerId(player)` | 本次整局中的逻辑角色 ID，如 `p2:1`；未知对象返回 `nil` |
| `lan:GetLocalRoom()` | `{runId, worldEpoch, dimension, index}`；未就绪时 `nil` |
| `lan:GetContext()` | `{runId, worldEpoch, tick, revision, room, playerSignature}` 的副本；未就绪时 `nil` |
| `lan:WithLocalView(fn)` | 在本机房间、仅本机角色名单中执行函数，保留全部返回值 |

参与者身份沿用 LAN 稳定席位，重连保留。主角色与双角色使用同一参与者下的不同逻辑角色 ID；对象替换后重新绑定。ID 不使用显示时 `Isaac.GetPlayer(i)` 的临时顺序、实体地址或原生控制器值。辅助角色的角色集合变化必须使缓存失效；跨整局和世界重建的缓存还需包含 `runId`、`worldEpoch`。

`GetLocalPlayers()` 保留雅各和以扫等本机控制角色；队友不会因为同屏或同房混入。返回数组和上下文都是副本，原生角色对象仍可变。

| 上下文字段 | 含义与缓存用途 |
| --- | --- |
| `runId` | 房主生成的整局字符串标识；换新局时失效 |
| `worldEpoch` | 整数世界代次；换层、重建和回退时失效 |
| `tick` | 这次视图对应的权威模拟 tick，不是本机渲染帧 |
| `revision` | 本机提交序号；同一上下文连续提交递增，重建后的首份提交从 1 开始；不用于跨端比较 |
| `room` | `{runId, worldEpoch, dimension, index}`，维度与房间索引共同确定位置 |
| `playerSignature` | 包含逻辑角色、对象身份与角色类型的变化标记；作为不透明值比较，不解析其中原生对象信息 |

`GetOwnerId`／`GetPlayerId` 可以识别当前已登记的远端角色，但不会因此把远端角色加入 `GetLocalPlayers()`。逻辑角色 ID 表示该参与者当前的角色位置；对象替换或辅助身体集合变化时重新取对象，不能永久保存 userdata。

`WithLocalView` 支持嵌套；异常时恢复原生房间、名单与上下文并重新抛出错误。未就绪时返回 `nil, "view_not_ready"`。它只影响包围的调用，不能清除第三方已有的玩家缓存，也不是 Lua 沙箱。仅用于读取世界和更新 UI 缓存，不加减道具、伤害、换房、消费随机序列或跨帧挂起。

## 生命周期

`lan:On(event, fn)` 返回取消订阅函数，可重复取消；所有事件都传入上下文副本。它不补发注册前的事件，新订阅在下一次对应事件生效；Mod 在已有视图时注册，可先检查 `IsReady()` 并读取当前视图。退出时仅发送清理通知。一个订阅报错会记录接入 ID 和事件并停用该订阅，其他订阅与原生状态应用继续执行。

| 事件 | 触发条件 |
| --- | --- |
| `StateReset` | 退出、重建、换层、回退；上下文附带 `reason` |
| `LocalPlayersChanged` | 本机角色、原生对象或角色类型变化 |
| `LocalRoomChanged` | 本机房间或维度变化；队友单独换房不触发 |
| `ViewUpdated` | 完整本机视图提交，角色、地图和房间可读取 |
| `SessionReady` | 首份视图或重建后的首份视图就绪 |

房主在模拟和迁移完成后通知，客机在完整状态应用及原生作用域恢复后通知；都在游戏主线程、下一次 UI 绘制前执行。顺序为需要的 `StateReset` → `LocalPlayersChanged` → `LocalRoomChanged` → `ViewUpdated` → 首次就绪的 `SessionReady`。除清理通知外，订阅默认在本机只读视图内运行。

`StateReset` 接收上一份上下文并附带 `reason`，例如 `session_ended`、`world_rebuilt`、`new_run`；回调执行前已清空视图，不能再用其中的旧角色或房间读取世界。只清理自己的缓存。`SessionReady` 每次重建后都可能再次触发，不是每次 Lua 加载只触发一次。

`runId` 由房主生成并随开局／重连检查点传输。换层、R Key 与沙漏等重建推进 `worldEpoch`；`revision` 在代次内随提交递增。刷新采用脏标记与原生属性读取，不伪造 `MC_EVALUATE_CACHE` 或道具使用回调。

面板示例中的显示序号为 `i - 1`；缓存身份使用 `(runId, worldEpoch, GetPlayerId(player))`，并在 `LocalPlayersChanged` 时重新取原生对象。`ViewUpdated` 每份完整提交均可触发，不要把它当成一次性初始化通知。

## 主机动作与回执

| 方法 | 行为 |
| --- | --- |
| `lan:RegisterAction(name, definition)` | 注册本命名空间处理器；返回注销函数 |
| `lan:HasHostAction(name, version)` | 主机是否公布并允许该业务版本 |
| `lan:RequestAction(name, payload, onResult)` | 返回请求 ID，或 `nil, code`；版本取自主机能力 |
| `lan:CreateOperation({poll, cancel})` | 创建异步句柄；`poll` 返回 `nil` 等待，或最终结果 |
| `lan:MovePlayer(context, destination)` | 权威处理器／其活跃异步操作中提交原生迁移，返回到达句柄或 `nil, code` |
| `IsaacLAN:SetActionEnabled(id, name, enabled)` | 允许／撤销本机注册的主机能力；运行时生效 |

`name` 最长 32 字节，字符约束与接入 ID 相同。完整动作名由接入 ID 与 `name` 组成，不能用另一个 Mod 的命名空间发起请求。整个本机 Lua 环境最多注册 16 个动作，含内置处理器。定义在加载时注册；只有房主执行，主机自己的请求同样走队列、来源校验和去重。`HasHostAction(name, version)` 精确匹配业务版本，`RequestAction` 使用当前主机公布的版本；处理器须再次校验收到的业务数据。

| `definition` 字段 | 约束与执行位置 |
| --- | --- |
| `version` | 必填整数，1–65535；与 `integrationVersion`、`API_VERSION` 分开维护 |
| `validate(payload)` | 必填函数，房主调用；只校验载荷结构，必须返回 `true`，抛错或其他返回均为 `invalid_payload` |
| `execute(context, payload)` | 必填函数，在请求参与者的权威房间作用域执行；校验当前玩法条件后返回最终结果或异步句柄 |
| `cooldownTicks` | 可选整数，默认 15，范围 1–1800；同一动作按参与者记录，结构校验通过后开始计时 |

`validate` 必须返回 `true` 才通过。`execute` 收到权威上下文：`ownerId`、`playerId`、`player`、源 `room`、`runId`、`worldEpoch`、`requestId`。发送者由传输连接绑定；载荷中的“玩家编号”“扣血结果”或客户端世界快照不作为权威事实。处理器在明确的请求参与者及其房间上下文内执行。

当前动作以参与者主角色为入口：`playerId` 为 `p<ownerId>:1`，`player` 为该主角色；没有直接选择任意辅助身体的请求参数。`context.room` 是执行时核对过的来源位置，异步过程中不会自动改成新房间。不要把本机视图的 `context` 传给 `MovePlayer`。

载荷允许布尔、有限数值、字符串、连续数组和字符串键记录；函数、userdata、循环引用及元表不可编码。Lua 表中的 `nil` 表示字段不存在，不能用它传显式空值；空表按空数组编码，不保留“空记录”类型。数组必须从 1 连续编号，不能有洞或混合字符串键。`validate` 必须检查必填字段，不能依赖 `RequestAction` 自动拒绝缺省载荷。

独立编码器限制整条消息 2048 字节、深度 6、累计 128 个表条目、字符串 512 字节、记录键 64 字节。这些限制包含请求封装、身份与来源字段，不能把整个限额都分配给 `payload`。超限或不可编码时返回 `invalid_payload`，不会使用原生数组视图编码器静默丢字段。

提交侧最多 8 个未完成请求；传输侧每发送者最多 32 条待收消息、每秒 64 条；主机每参与者最多 8 条待处理动作，且同一参与者仅运行一个异步操作。请求和结果走可靠 TCP 消息，不参与可合并的世界快照队列。

请求包含整局、代次、实际源房间、随机请求代次和递增序号。主机再次检查源房间、业务版本、权限与冷却，然后执行。每发送者／请求代次保留高水位及最近 64 条结果；更旧的重复序号返回 `dedupe_expired`，不会再次执行。每世界代次每参与者最多接受 8 个请求代次，防止去重记录无限增长。

同步处理器返回 `{status, code}`，或返回 `CreateOperation`／`MovePlayer` 的句柄。异步完成在权威视图提交时、该参与者当前房间的作用域内检查。动作上下文只在处理器和该操作存续期间有效，不能当作长期修改世界的权限。

### 异步操作与迁移

`lan:CreateOperation({poll = function() ... end, cancel = function() ... end})` 创建不透明句柄，本身不会启动或排队；由 `execute` 返回后才被调度。`poll()` 不接收参数，返回 `nil` 继续等待，返回 `{status, code}` 完成；它在参与者届时所在房间执行。可选 `cancel()` 不接收参数，作为收尾函数在成功、失败、超时、停用或世界复位后调用，不只在 `cancelled` 时调用；应可安全重复清理，不假设其中仍有原先房间作用域。

`lan:MovePlayer(context, {index, dimension})` 只允许在当前 `execute` 或其活跃异步操作中，使用同一个权威上下文对象调用。`index` 必须为整数，范围 -20–168；`dimension` 必须为整数，范围 0–2。该范围只是接口上限，不保证对应房间存在或业务上可进入；访问权限、清房、路径和代价由处理器验证。接受迁移后返回的也是异步句柄，必须等待实际位置匹配才有 `applied/arrived`。

迁移句柄的收尾只尝试撤销仍在队列中的该目标迁移，不将已到达的玩家送回来源，也不返还已扣代价。创建迁移后不要在完成前修改传入的 `destination` 表。注册时返回的动作注销函数移除能力；已运行操作在后续提交时以 `cancelled/action_disabled` 收尾。

| 最终状态 | 含义 |
| --- | --- |
| `applied` | 已完成，如实际到达目标房间 |
| `rejected` | 校验或条件不满足，没有执行操作 |
| `cancelled` | 操作因复位、停用或死亡等终止；已经发生的代价不会自动逆转 |
| `unknown` | 断线、超时或执行异常后无法确认完整结果；先核对权威状态，不自动换新 ID 重试 |

提交侧 5 秒未确认返回 `unknown/timeout`；迁移 3 秒未到达返回 `unknown/arrival_unconfirmed`，异步操作总等待上限 5 秒。缺少能力返回 `action_unavailable`，视图未就绪返回 `view_not_ready`，拥塞返回 `request_queue_full` 或 `transport_unavailable`。旧代次、源房间改变、冷却或重复 ID 分别有 `stale_world`、`source_changed`、`rate_limited`、`request_id_reused` 等代码。结果回调报错只记录日志。

`onResult(result)` 接收 `{kind="result", requestId, runId, worldEpoch, status, code}` 的副本，不含任意业务返回载荷。每个未完成请求最多回调一次；晚到或重复结果不再次通知。视图就绪时回调在本机视图内执行，断线／复位等未就绪状态下也可能收到回调，应先检查 `IsReady()`。`RequestAction` 直接返回 `nil, code` 时未登记请求，不会再调用 `onResult`。

处理器抛错时，该动作会被停用并回报 `unknown/handler_error`；已经执行的世界写入不会回滚。返回非法同步结果则为 `unknown/invalid_handler_result`。`poll` 抛错或超时分别为 `unknown/operation_error`、`unknown/operation_timeout`，非法异步结果为 `unknown/invalid_operation_result`。

下面的主动接入片段承接上文注册示例，仅在 `lan` 存在时执行；两端使用同一 ID。这里只允许同维度的已访问清房目标，实际 Mod 应补充自己的门锁、路径、代价等规则：

```lua
if lan then
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
end

-- 在自己的界面确认目标时调用；单机仍调用原逻辑。
if lan and lan:IsActive() and lan:IsReady() and lan:HasHostAction("travel", 1) then
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

`IsaacLAN:RegisterCompatibility(definition)` 返回停用函数。停用会清理本次 UI 安装和独立能力，但保留注册定义，不能在同一 Lua 环境重复注册同一 `id`；需要恢复时使用兼容开关。定义如下：

| 字段／回调 | 契约 |
| --- | --- |
| `id` | 唯一命名空间，字符及 64 字节上限与接入 ID 相同 |
| `adapterVersion` | 正整数，表示适配实现版本；不代替上游版本／指纹 |
| `modName` | 目标实际 `RegisterMod` 的名称，精确匹配 |
| `targets` | 支持配置数组，每项为 `{workshopId, metadataVersion, sourceHash}` |
| `probe(target)` | 返回 `"ready"`、`"pending"` 或 `"unsupported", reason`；导出尚未完成时等待，接口不符时拒绝 |
| `install(target, api)` | 探测就绪后安装；必须返回清理函数，不修改上游磁盘源码 |
| `authority(api)` | 可选，注册独立主机动作；也必须返回清理函数，不依赖本机安装 UI Mod |
| `dispatch(target, record, ...)` | 可选，包装目标回调；保留参数与返回值，不处理的路径调用并返回 `record.original(...)` |

每个目标必须提供 `workshopId`、`metadataVersion` 和 64 字节 `sourceHash`。加载观察器结合实际 `RegisterMod` 实例、来源目录、启用状态和源码指纹确认目标。只存在目录、同名 Mod 或残留全局不会匹配。`target` 包含 `mod`、目录／版本／指纹和该来源加载的模块导出。`RegisterMod` 第二个参数不是 Mod 发布版本。

`workshopId`、`metadataVersion` 为非空字符串，`sourceHash` 是恰好 64 个小写十六进制字符。观察目标 `target` 的公开字段为 `mod`、`directory`、`workshopId`、`metadataVersion`、`sourceHash`、`modules`；`modules` 以实际 `require` 名为键保存来自该目录的已观察模块导出。安装阶段另提供 `target.addCleanup(fn)`。使用 `dispatch` 时，`record` 包含 `id`（游戏回调 ID）、`original`、`param`、`priority` 及包装函数 `wrapper`。

源码指纹为 SHA-256：先输入 `Isaac LAN/compat-source-v1` 与零字节，再按相对路径排序输入每个 `.lua` 的相对路径、零字节、文件 SHA-256 的十六进制文本和零字节。`gtconfig.lua`、`eid_config.lua` 是配置文件，不计入源码身份；其余 Lua 包含语言与服务实现。修改源码或新的上游版本必须增加独立支持记录。

`probe` 返回 `ready`、`pending` 或 `unsupported` 及原因。只在 `ready` 后安装一次；`pending` 在初始化后及首次回调前重试。`install` 中可用 `api:RegisterMod(target.mod, options)` 获取归属于该适配器的句柄，不会触发主动接入优先规则；目标 Mod 在安装回调以外主动注册时才让出。`install` 必须返回清理函数并注销自己的句柄，可用 `target.addCleanup(fn)` 提前登记部分安装的清理，确保异常时回滚。`authority` 在加载时注册独立主机能力，不因尚未开局或缺少本机 UI Mod 跳过。

已登记的安装清理按后进先出执行，应只恢复仍由本适配器持有的方法和资源。兼容模块关闭后可重新开启，因此清理须能承受重复调用，重新安装不能重复加订阅或叠加包装。`probe`／`install` 抛错进入 `error`，安装未返回函数也视为失败；排查日志后再重新开启，不在每帧强行重装。独立能力清理与目标 UI 清理分别管理，目标主动接入只让出该实例，不自动推断独立能力的业务去留。

回调包装保留优先级、参数、原顺序与返回值；使用原函数 `RemoveCallback` 仍能移除包装。已有回调在原列表位置替换，不通过移除／重加改变顺序。方法清理只撤回仍属于该模块的修改；重连不重复安装。

### 兼容状态与开关

`IsaacLAN:GetCompatibilityStatus()` 返回按 `id` 排序的数组，每项为下列字段，不包含原生对象：

| 字段 | 含义 |
| --- | --- |
| `id`、`adapterVersion` | 适配器 ID 与实现版本 |
| `state`、`reason` | 当前状态和原因字符串 |
| `authority` | 布尔值，独立能力安装是否已返回清理函数；不是“当前端是否房主”，也不表示每个动作均已启用 |
| `target` | 匹配目标的 `{workshopId, metadataVersion, sourceHash, directory}`，尚未绑定目标时为 `nil`；不含 Mod 句柄 |

| `state` | 含义／常见原因 |
| --- | --- |
| `not_detected` | 等待实际目标加载，如 `waiting_for_mod` |
| `pending` | 身份已匹配，等待运行时导出或初始化，如 `initializing` |
| `active` | 探测及安装完成，`installed`；不代表所有功能验收通过 |
| `unsupported` | 名称被观察到但版本／源码不匹配、重复目标实例或运行时接口不符 |
| `disabled` | 配置关闭、停用函数调用或目标主动接入，如 `configuration`、`unregistered`、`native_integration` |
| `error` | 探测、安装或独立能力安装异常；完整错误见日志 |

未匹配版本时 `target` 可能仍为 `nil`，应结合 `state/reason` 判断，不能只看 `target` 是否存在。

独立开关通过 `IsaacLAN:SetCompatibilityEnabled(id, enabled)` 保存到游戏目录的 Mod 接入配置文件 `integrations.ini`，默认允许。主机要保留自己的 GoodTrip UI 并禁止所有人传送，可调用 `IsaacLAN:SetActionEnabled("isaac-lan.compat.goodtrip", "travel", false)`；该动作开关只在当前 Lua 环境生效，永久关闭内置主机能力可关闭对应兼容模块。

`enabled` 必须是布尔值。兼容开关成功返回 `true`；未知 ID 返回 `false, "compatibility_not_registered"`，配置写入失败返回 `false, "configuration_write_failed"`，重新开启时独立能力安装失败返回 `false, "authority_install_failed"`。`true` 只表示开关操作完成，UI 是否实际装好仍需查询状态。动作开关只作用于本机注册定义；全队是否能执行由主机公布的能力决定，客机无法用自己的开关授权主机动作。

## 错误处理

注册／调用契约错误通过 Lua 异常报告，适合开发阶段修正，不应当作网络重试条件：

| 错误族 | 典型代码 |
| --- | --- |
| 接入注册与句柄 | `invalid_registration`、`invalid_integration_id`、`invalid_integration_version`、`duplicate_integration_id`、`mod_already_registered`、`integration_unregistered` |
| 视图与订阅 | `invalid_view_function`、`invalid_subscription` |
| 动作定义与异步调用 | `invalid_action_name`、`invalid_action_definition`、`invalid_action_cooldown`、`duplicate_action`、`action_limit`、`invalid_result_callback`、`invalid_operation`、`move_outside_action` |
| 自动适配器 | `invalid_compatibility_definition`、`duplicate_compatibility_id`、`invalid_compatibility_handler`、`invalid_compatibility_target`、`invalid_enabled` |

预期运行失败通过返回值／回执处理：

| 位置 | 代码 | 接入方处理 |
| --- | --- | --- |
| `RequestAction` 直接返回 `nil, code` | `view_not_ready`、`action_unavailable`、`request_queue_full`、`invalid_payload`、`transport_unavailable`、`integration_unregistered` | 不进入“已提交”状态；按原因等待新视图、关闭操作或修正数据 |
| `MovePlayer` 返回 `nil, code` | `invalid_destination`、`move_rejected`、`stale_world`、`integration_unregistered` | 处理器返回相应失败；不要继续扣费或伪造到达 |
| 主机拒绝请求 | `source_changed`、`action_unavailable`、`operation_busy`、`rate_limited`、`invalid_payload` | 读取当前权威状态，待用户重新发起符合条件的操作 |
| 去重／代次限制 | `request_id_reused`、`dedupe_expired`、`generation_limit`、`stale_world` | 不修改旧 ID 的内容，不把未知完成结果换 ID 自动重试 |
| 操作失效／结果未知 | `action_disabled`、`owner_unavailable`、`timeout`、`arrival_unconfirmed`、`handler_error`、`invalid_handler_result`、`operation_error`、`operation_timeout`、`invalid_operation_result` | 以 `status` 判断确定性，核对权威结果并清理本机等待状态 |

世界复位也可能将原因（如 `world_rebuilt`、`session_ended`）作为回执 `code`；业务处理器可自定义字符串代码，建议非空且简短。`code` 不单独决定最终状态，例如过期世界可在不同阶段得到 `rejected` 或 `cancelled`；始终同时读取 `status`。

## 内置模块

当前内置 Stats+、原版 GoodTrip 与两组 EID 版本配置；兼容后的效果见[第三方 Mod 兼容清单](https://github.com/BMingSY/isaac-lan/blob/main/docs/mod-compatibility.md)。

## 验证

无需游戏的 [`tests/bridge_api.lua`](https://github.com/BMingSY/isaac-lan/blob/main/tests/bridge_api.lua) 验证独立编码、视图返回值与异常恢复、身份、事件顺序与错误隔离、能力撤销、实际完成回执、去重／重复 ID、失效源房间、超时，以及自动安装和原生接入优先。CMake 在找到 Lua 5.3 时将其加入 CTest；Linux CI 会运行。

[`tests/goodtrip_rules.lua`](https://github.com/BMingSY/isaac-lan/blob/main/tests/goodtrip_rules.lua) 通过模拟权威环境验证特殊房间规则、诅咒代价只扣一次、死亡取消、迷宫下的固定目标，以及秘密房分段到达。

[`tests/net_test.cpp`](https://github.com/BMingSY/isaac-lan/blob/main/tests/net_test.cpp) 的 `integrations` 用例验证真实 Winsock 通道、发送者绑定、消息顺序、不合并请求、结果接收范围、限额、整局身份和重连代次。

真实游戏使用原版文件的隔离拷贝：[`state_mod_ui.lua`](https://github.com/BMingSY/isaac-lan/blob/main/tests/state_mod_ui.lua) 走地图与原生手柄输入；[`state_mod_integrations.lua`](https://github.com/BMingSY/isaac-lan/blob/main/tests/state_mod_integrations.lua) 核对真实 Stats+ 玩家缓存及布局序号、EID 本机名单、客机 GoodTrip 请求、重复请求和最终到达。用 `--mod`、`--client-mod`、`--host-mod` 构造安装组合，见[开发与测试](https://github.com/BMingSY/isaac-lan/blob/main/docs/development-and-testing.md)。

既有实机结果见[已报问题回归](https://github.com/BMingSY/isaac-lan/blob/main/docs/history/issue-regressions.md)和[支线与回退回归](https://github.com/BMingSY/isaac-lan/blob/main/docs/history/side-route-regressions.md)。这些用例不能替代全部特殊房间、角色、语言、回退及未知上游版本的验收。每次兼容范围扩展都需增加源码配置和对应游戏证据。
