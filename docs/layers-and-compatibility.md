# 分层与玩法兼容

按职责选择修改位置。架构选型见[架构概览](https://github.com/BMingSY/isaac-lan/blob/main/docs/architecture.md)，具体协作约定见 [AGENTS.md](https://github.com/BMingSY/isaac-lan/blob/main/AGENTS.md)。

## 目录与依赖

| 位置 | 职责与边界 |
| --- | --- |
| [`src/app/`](https://github.com/BMingSY/isaac-lan/tree/main/src/app)、[`src/bridge/app/`](https://github.com/BMingSY/isaac-lan/tree/main/src/bridge/app) | 加载、组件注册与调用装配；玩法和状态规则交给所属组件 |
| [`src/net/`](https://github.com/BMingSY/isaac-lan/tree/main/src/net) | 协议、TCP／UDP、队列、压缩和可靠传输；不访问游戏对象 |
| [`src/runtime/`](https://github.com/BMingSY/isaac-lan/tree/main/src/runtime)、[`src/bridge/runtime/`](https://github.com/BMingSY/isaac-lan/tree/main/src/bridge/runtime) | 会话推进、存档、启动、房间／楼层生命周期及失效边界 |
| [`src/bridge/sync/`](https://github.com/BMingSY/isaac-lan/tree/main/src/bridge/sync) | 字段、采集代次、副本恢复、库存／实体／网格一致性 |
| [`src/compat/`](https://github.com/BMingSY/isaac-lan/tree/main/src/compat)、[`src/bridge/compat/`](https://github.com/BMingSY/isaac-lan/tree/main/src/bridge/compat) | Boss、角色、道具、路线与挑战规则；C++ 策略只接收普通值，Lua 适配使用游戏 API 或具名原生能力 |
| [`src/bridge/compat/mods/`](https://github.com/BMingSY/isaac-lan/tree/main/src/bridge/compat/mods) | 第三方 Mod 探测、接入和卸载，保留版本／源码匹配边界 |
| [`src/bridge/api/`](https://github.com/BMingSY/isaac-lan/tree/main/src/bridge/api) | 第三方公开契约；不暴露原生指针或任意内存读写 |
| [`src/presentation/`](https://github.com/BMingSY/isaac-lan/tree/main/src/presentation)、[`src/bridge/presentation/`](https://github.com/BMingSY/isaac-lan/tree/main/src/bridge/presentation) | 菜单、预测、镜头、外观和音画；不决定权威玩法 |
| [`src/bridge/lanbot.lua`](https://github.com/BMingSY/isaac-lan/blob/main/src/bridge/lanbot.lua)、[`src/bridge/lanbot/`](https://github.com/BMingSY/isaac-lan/tree/main/src/bridge/lanbot) | 读取已有视图并合成正常输入 |
| [`src/core/`](https://github.com/BMingSY/isaac-lan/tree/main/src/core) | 可离线执行的数据规则，不依赖游戏布局或 Hook |
| [`src/engine/`](https://github.com/BMingSY/isaac-lan/tree/main/src/engine)、[`src/engine/versions/j460/`](https://github.com/BMingSY/isaac-lan/tree/main/src/engine/versions/j460) | 能力接口、版本检测、原生调用、布局、Hook 与对象所有权 |
| [`src/diagnostics/`](https://github.com/BMingSY/isaac-lan/tree/main/src/diagnostics) | 日志、性能和隔离采集；诊断开关不控制玩法 |
| [`tests/`](https://github.com/BMingSY/isaac-lan/tree/main/tests)、[`tools/`](https://github.com/BMingSY/isaac-lan/tree/main/tools) | 回归夹具、构建与验收；不得成为生产玩法依赖 |

装配层注入运行、同步、兼容与表现组件。运行协调器通过 [`engine/session_backend.h`](https://github.com/BMingSY/isaac-lan/blob/main/src/engine/session_backend.h) 调用具名能力；J460 后端安装 Hook，回调只传普通值和限同步调用的原版操作，不向运行层暴露原生对象。Lua ABI 声明与符号加载共用 [`engine/lua_api.h`](https://github.com/BMingSY/isaac-lan/blob/main/src/engine/lua_api.h)。

会话视图、启动请求和存档保护分别由 [`session_state.h`](https://github.com/BMingSY/isaac-lan/blob/main/src/runtime/session_state.h) 中的状态组件持有，存档文件操作由 [`session_store.cpp`](https://github.com/BMingSY/isaac-lan/blob/main/src/runtime/session_store.cpp) 管理。会话协议状态留在主线程的 `net/session.cpp` 与 `net/peer.h`；`net/socket.h` 负责有界数据交接，`net/network_io.cpp`／`net/udp_io.cpp` 的网络线程独占连接、收发和实时压缩上下文。`net/world_transfer.h` 管理实时视图基线与分块，`net/reliable_transfer.h`／`net/reliable_receiver.h` 管理可靠大数据的分块与组装，`net/byte_worker.cpp` 执行存档字节任务；域名解析位于 `net/host_resolution.cpp`。

Lua 嵌入清单在 [`modules.txt`](https://github.com/BMingSY/isaac-lan/blob/main/src/bridge/modules.txt)。组件加载时只定义函数，依赖在全部组件加载后注入。[`app/main.lua`](https://github.com/BMingSY/isaac-lan/blob/main/src/bridge/app/main.lua)、[`app/world.lua`](https://github.com/BMingSY/isaac-lan/blob/main/src/bridge/app/world.lua)、菜单与预测入口单独装配。

## 状态所有权

| 状态 | 管理者 | 失效边界 |
| --- | --- | --- |
| TCP／UDP 队列、分块、视图基线 | 网络线程 | 关闭、连接或可靠事务切换 |
| 存档压缩／解压任务及完成结果 | 大数据工作线程与主线程结果票据 | 取消、会话退出或楼层事务替换；过期结果不能进入新会话 |
| 会话身份、输入确认、楼层代次 | 运行协调器 | 新会话、换层、重建和回退 |
| 桥接启动阶段与准备代次 | [`bridge/runtime/session.lua`](https://github.com/BMingSY/isaac-lan/blob/main/src/bridge/runtime/session.lua) | 关闭、取消；原生错误进入失败阶段 |
| 房间绑定、深度、借用的完整名单 | [`runtime/room_scope.h`](https://github.com/BMingSY/isaac-lan/blob/main/src/runtime/room_scope.h) 与 J460 `Scope` | 按栈顺序完成原生恢复与清理 |
| 房间、角色、精灵与 MSVC 容器 | J460 后端与游戏 | 原生替换、卸载或销毁 |
| 实体 `ID → EntityPtr`、库存应用缓存 | [`sync/replica.lua`](https://github.com/BMingSY/isaac-lan/blob/main/src/bridge/sync/replica.lua) | 实体删除、角色替换、新一局 |
| 公共字段、角色和编码片段缓存 | [`sync/capture.lua`](https://github.com/BMingSY/isaac-lan/blob/main/src/bridge/sync/capture.lua) | tick／楼层代次变化、转场、新一局 |
| 移动与预测轨迹 | 副本与移动表现组件 | 换房、转场、新一局 |
| 音效序号、装扮与表现缓存 | 对应表现组件 | 新一局；楼层相关缓存另按 epoch 失效 |
| 每名玩家的沙漏检查点 | 沙漏策略与后端 | 本人进房覆盖、新一局 |

角色身份、控制器身份和原生地址用途不同。角色身体替换后由后端维护名单与所有权，副本清理失效引用；兼容模块不另建连接或维护另一套楼层代次。

## 房间作用域

[`ScopeStack`](https://github.com/BMingSY/isaac-lan/blob/main/src/runtime/room_scope.h) 只管理逻辑绑定，不读取游戏内存。同房重入和跨房嵌套都增加深度，并借用最外层保存的完整名单；绑定不可复制或移动，乱序恢复／销毁会终止进程。

J460 `Scope` 按深度选择独立的临时名单，恢复原生标量与名单后先恢复父房间标识，待共享状态交换和临时分配清理完毕后再解除深度屏障。`TeamScope` 只临时切换完整名单。原生布局、Hook、MSVC 分配与释放仍在版本后端，逻辑退栈测试不能替代实机资源验收。房间迁移和渲染归属见[房间与表现](https://github.com/BMingSY/isaac-lan/blob/main/docs/rooms-and-presentation.md)。

## 采集与副本恢复

[`sync/capture.lua`](https://github.com/BMingSY/isaac-lan/blob/main/src/bridge/sync/capture.lua) 以 `(epoch, tick)` 标识一次不可变采集代次；同轮发布期间不得推进玩法。公共字段采集一次，角色基础状态与完整表现分别缓存，[`sync/room.lua`](https://github.com/BMingSY/isaac-lan/blob/main/src/bridge/sync/room.lua) 按房间复用实体／网格视图。声音、演出及道具表现仍按客机采集。缓存不跨 tick，不引入低频更新或脏标记。

[`sync/replica.lua`](https://github.com/BMingSY/isaac-lan/blob/main/src/bridge/sync/replica.lua) 的顺序为：

1. 等待楼层准备，解码并核对顶层 schema、tick 与 epoch。
2. 通过道具兼容组件恢复运行时道具定义，再注册布局、同步角色房间；换房时先清理旧移动记录。
3. 解析角色身份，在对应角色作用域内恢复库存、实体及角色附加状态。
4. 恢复共享药丸、诅咒、波次和开门概率，覆盖库存 setter 的原生副作用。
5. 更新地图，在本机房间作用域内恢复环境、实体、网格和房间状态。
6. 应用输入确认、音效和演出，成功后提交完成 tick 与角色显示记录。

字段校验由 schema 和所属组件承担。该流程不提供原生回滚：失败传播给运行协调器，不提交完成 tick，已发生的写入不会自动撤销。字段和传输限制统一见[同步契约](https://github.com/BMingSY/isaac-lan/blob/main/docs/synchronization.md)，启动及换层顺序见[会话恢复](https://github.com/BMingSY/isaac-lan/blob/main/docs/session-lifecycle.md)。

## 扩展边界

通用字段与一致性属于同步组件，特殊玩法属于对应兼容组件。策略接收普通值，Lua 适配调用游戏 API 或具名后端能力，装配层只注册与连接组件。特殊玩法不能向网络层泄漏游戏对象或匹配规则。

字段位置由 [fields.lua](https://github.com/BMingSY/isaac-lan/blob/main/src/bridge/sync/fields.lua) 和 schema 统一定义，游戏 ID 使用枚举或 [game_ids.h](https://github.com/BMingSY/isaac-lan/blob/main/src/compat/game_ids.h)。原生能力、校验和对象所有权见 [J460 参考](https://github.com/BMingSY/isaac-lan/blob/main/docs/native-backend.md)，变更所需检查见[开发与测试](https://github.com/BMingSY/isaac-lan/blob/main/docs/development-and-testing.md#修改后的契约检查)。

当前效果与支持范围分别维护在[角色](https://github.com/BMingSY/isaac-lan/blob/main/docs/character-compatibility.md)、[道具](https://github.com/BMingSY/isaac-lan/blob/main/docs/item-effect-compatibility.md)、[第三方 Mod](https://github.com/BMingSY/isaac-lan/blob/main/docs/mod-compatibility.md)和[挑战](https://github.com/BMingSY/isaac-lan/blob/main/docs/lan-challenges.md)参考中。对第三方开放的能力遵循独立的 [API 契约](https://github.com/BMingSY/isaac-lan/blob/main/docs/third-party-mod-integration.md)。
