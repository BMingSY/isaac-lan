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
| `On(event, fn)` | 订阅 LAN 生命周期，返回取消函数；无 LAN 时不产生事件 |
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
