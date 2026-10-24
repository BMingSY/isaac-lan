# 第三方 Mod 自动适配器

自动兼容让尚未主动接入 API 的旧 Mod 可以在 LAN 中使用已有功能。包装在目标 Mod 加载、初始化时安装，会贯穿后续单机和 LAN 会话；因此方法在未联机时调用原函数，在 LAN 中才使用本机视图或主机动作。保留单机行为是这些包装的运行约束，安装依据是目标身份和实际所需接口；版本／源码约束仅在确有接口差异时使用。

`IsaacLAN:RegisterAdapter(definition)` 返回停用函数。停用会清理本次 UI 安装和独立能力，但保留注册定义，不能在同一 Lua 环境重复注册同一 `id`；需要恢复时使用兼容开关。定义如下：

| 字段／回调 | 契约 |
| --- | --- |
| `id` | 唯一命名空间，字符及 64 字节上限与接入 ID 相同 |
| `adapterVersion` | 正整数，表示适配实现版本；不代替上游版本／指纹 |
| `modName` | 目标实际 `RegisterMod` 的名称，精确匹配 |
| `targets` | 支持配置数组，每项必须有 `workshopId`，可选 `metadataVersion`、`sourceHash` |
| `probe(target)` | 返回 `"ready"`、`"pending"` 或 `"unsupported", reason`；导出尚未完成时等待，接口不符时拒绝 |
| `install(target, api)` | 探测就绪后安装；必须返回清理函数，不修改上游磁盘源码 |
| `authority(api)` | 可选，注册独立主机动作；也必须返回清理函数，不依赖本机安装 UI Mod |
| `dispatch(target, record, ...)` | 可选，包装目标回调；保留参数与返回值，不处理的路径调用并返回 `record.original(...)` |

每个目标必须提供 `workshopId`。`metadataVersion` 和 `sourceHash` 为适配器主动选择的可选约束；内置 EID、Stats+、GoodTrip 适配按实际所需接口探测，不锁定发布版本或源码哈希。加载观察器结合实际 `RegisterMod` 实例、来源目录、启用状态和源码指纹确认目标。只存在目录、同名 Mod 或残留全局不会匹配。`target` 包含 `mod`、目录／版本／指纹和该来源加载的模块导出。`RegisterMod` 第二个参数不是 Mod 发布版本。

`workshopId` 为非空字符串；可选 `metadataVersion` 若提供也必须为非空字符串，`sourceHash` 若提供须为恰好 64 个小写十六进制字符。观察目标 `target` 的公开字段为 `mod`、`directory`、`workshopId`、`metadataVersion`、`sourceHash`、`modules`；`modules` 以实际 `require` 名为键保存来自该目录的已观察模块导出。安装阶段另提供 `target.addCleanup(fn)`。使用 `dispatch` 时，`record` 包含 `id`（游戏回调 ID）、`original`、`param`、`priority` 及包装函数 `wrapper`。

源码指纹为 SHA-256：先输入 `Isaac LAN/compat-source-v1` 与零字节，再按相对路径排序输入每个 `.lua` 的相对路径、零字节、文件 SHA-256 的十六进制文本和零字节。`gtconfig.lua`、`eid_config.lua` 是配置文件，不计入源码身份；其余 Lua 包含语言与服务实现。版本和源码变化仍可用于诊断；只有适配器明确提供对应约束时才影响目标匹配。

`probe` 返回 `ready`、`pending` 或 `unsupported` 及原因。只在 `ready` 后安装一次；`pending` 在初始化后及首次回调前重试。`install` 中可用 `api:Attach(target.mod, definition.id)` 获取归属于该适配器的句柄，不会触发主动接入优先规则；目标 Mod 在安装回调以外主动注册时才让出。`install` 必须返回清理函数并调用 `lan:Close()` 释放自己的句柄，可用 `target.addCleanup(fn)` 提前登记部分安装的清理，确保异常时回滚。`authority` 在加载时注册独立主机能力，不因尚未开局或缺少本机 UI Mod 跳过。

已登记的安装清理按后进先出执行，应只恢复仍由本适配器持有的方法和资源。兼容模块关闭后可重新开启，因此清理须能承受重复调用，重新安装不能重复加订阅或叠加包装。`probe`／`install` 抛错进入 `error`，安装未返回函数也视为失败；排查日志后再重新开启，不在每帧强行重装。独立能力清理与目标 UI 清理分别管理，目标主动接入只让出该实例，不自动推断独立能力的业务去留。

回调包装保留优先级、参数、原顺序与返回值；使用原函数 `RemoveCallback` 仍能移除包装。已有回调在原列表位置替换，不通过移除／重加改变顺序。方法清理只撤回仍属于该模块的修改；重连不重复安装。

### 兼容状态与开关

`IsaacLAN:GetAdapters()` 返回按 `id` 排序的数组，每项为下列字段，不包含原生对象：

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

独立开关通过 `IsaacLAN:SetAdapterEnabled(id, enabled)` 保存到游戏目录的 Mod 接入配置文件 `integrations.ini`，默认允许。主机要保留自己的 GoodTrip UI 并禁止所有人传送，可调用 `IsaacLAN:SetActionEnabled("isaac-lan.compat.goodtrip", "travel", false)`；该动作开关只在当前 Lua 环境生效，永久关闭内置主机能力可关闭对应兼容模块。

`enabled` 必须是布尔值。兼容开关成功返回 `true`；未知 ID 返回 `false, "compatibility_not_registered"`，配置写入失败返回 `false, "configuration_write_failed"`，重新开启时独立能力安装失败返回 `false, "authority_install_failed"`。`true` 只表示开关操作完成，UI 是否实际装好仍需查询状态。动作开关只作用于本机注册定义；全队是否能执行由主机公布的能力决定，客机无法用自己的开关授权主机动作。

主动接入的 Mod 使用 [SDK 快速开始](https://github.com/BMingSY/isaac-lan/blob/main/docs/third-party-mod-integration.md)，不需要注册自动适配器。
