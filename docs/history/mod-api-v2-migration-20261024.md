# API 2 接入迁移（2026-10-24）

本次移除 API 1 兼容入口，将 Stats+、EID 和 GoodTrip 内置适配迁移到同一组公开接口。项目基线为 v0.5.1 后的 `18e59af5`。面向当前接入方的完整契约见 [API 参考](https://github.com/BMingSY/isaac-lan/blob/main/docs/mod-api-reference.md)，本文仅记录迁移映射。

| API 1 | API 2 |
| --- | --- |
| `RegisterMod(mod, {id, integrationVersion})` | `Attach(mod, id)`，或复制 SDK 后 `SDK.attach(mod, id)`；移除独立的 `integrationVersion` |
| `GetContext()` | `View()`，包含当前本机角色数组及 `networked` |
| 在 `ViewUpdated` 绘制 UI | `OnLocalRender(fn)`，按游戏渲染帧运行；`ViewUpdated` 仍用于提交后更新缓存 |
| `RegisterAction(name, definition)` | `Action(name, definition)` 返回动作对象 |
| `HasHostAction(name, version)` | 指定业务版本的动作对象调用 `IsAvailable()` |
| `RequestAction(name, payload, callback)` | `action:Request(payload, {player, onResult})`；始终返回请求对象，立即拒绝也完成回调 |
| `CreateOperation(definition)` | 权威处理器内 `context:Wait(definition)` |
| `MovePlayer(context, destination)` | 权威处理器或活跃操作内 `context:MoveTo(destination)` |
| `Unregister()`／动作注销函数 | `lan:Close()`／`action:Close()` |
| `RegisterCompatibility(definition)` | `RegisterAdapter(definition)` |
| `GetCompatibilityStatus()` | `GetAdapters()` |
| `SetCompatibilityEnabled(id, enabled)` | `SetAdapterEnabled(id, enabled)` |

处理器收到明确的 `context.player`；请求可选择本机辅助身体，主机核对连接与身体归属。结果支持 `data`；单机默认执行同一个处理器，异步 LAN 业务可通过 `solo` 提供原有单机实现。联机尚未就绪、结局或断开阶段均不会触发单机回退。

现有第三方主动接入 API 1 的 Mod 需要按表迁移，不提供旧方法别名。自动适配的原始 Mod 无需改源码；版本／哈希不作为内置适配器的强制门槛。自定义状态复制和第三方预测事件通道属于后续功能范围，本次没有实现这些接口。

网络统一为 ENet UDP：移除 TCP 连接分支、字节流队列、配置选择、延迟中继及专用回放工具。旧 `network.transport` 设置按未知配置项忽略，不阻止其余配置加载；端口仍使用原有 UDP 端口。网络协议从 43 调整为 44，包含所选身体与业务回执的动作契约；同一局需使用相同扩展构建。
