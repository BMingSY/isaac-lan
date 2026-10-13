# 首层分房沙漏与全队 Home

2026-10-13，PR #64 集中实机验收第 08 轮发现既有沙漏问题。测试提交为
`aa3918c`，对照主分支为 `7430c22`。以下保留当时的失败证据与诊断；当时尚未修复，
也没有在主分支二进制上单独重跑最小场景。2026-10-14 的实现与验收另列于末尾，
不能用避开触发条件的旧验收代替新结果。

## 已发生的场景和证据

第 08 轮完整验收记录已归档。
J460 原生程序 SHA-256：
`7122ac28779925b24e23e2416f231322b1470388bd25e2c08665ad8d53b3ea4f`。

两名里该隐在地下室 I，P1 留在首次进入的起始房间 84，P2 从 84 前往房间 97，
然后在 97 使用发光沙漏。P2 具有回到 84 的联机检查点。此前的充袋、分房、
幽灵和复活检查已经完成；这些前置步骤不是下述原生 Home 分支的判定条件。

| 证据 | 内容 |
| --- | --- |
| 主机 `log.txt` 第 1039 行 | tick 916 使用沙漏，进入 `hourglass-wait` |
| 主机 `probe.log` | 21:22:07.339，`hourglass_event=SENT epoch=1` |
| 主机 `log.txt` 第 1042 行 | 原生 Frame 927 开始 stage transition，类型为 6 |
| 主机 `log.txt` 第 1044 行 | 原生初始化 stage 13、stageType 0，随后加载 Home |
| 客机 `probe.log` 第 48 行 | 21:22:07.564，收到可靠 floor event，epoch 1 |
| 客机 `probe.log` 第 50 行 | 21:22:08.478，回溯完成，stage 1 |
| 主机 `probe.log` 第 53 行 | 21:22:18.827，原生事务完成，stage 13 |
| 客机 `probe.log` 第 51 行 | 21:22:18.870，`Replica floor initialization failed` |

夹具在 tick 1097 才请求使用 R Key。主机记录没有 `floor_transaction=R_KEY`，
也没有为 Home 发送新的可靠楼层事件。故该次失败不能归因于 R Key 的楼层重置；
最早的错误是沙漏执行时主客机选择了不同原生转场。

## 已确认的调用链

1. `rooms.cpp` 的 `transition()` 在使用者所属房间上下文中接收 animation 12，
   调用 `rewind::request(slot)` 后返回。真正回溯延迟至 `finishFrame()`。
2. 房间作用域结束，`canonical()` 在主机选择 P1 的房间，在客机选择本机玩家的
   房间。因此本例主机当前原生房间为 84，客机为 97。
3. `rewind.cpp` 的 `startRewind()` 先调用 `rooms::beforeStart()`，保留当前原生
   房间作为完整队伍转场的根，关闭分房模拟，再恢复检查点缓冲。
4. `startRewind()` 调用原生 `Game::StartRoomTransition(..., animation=12, ...)`。
   该入口仍会根据调用进程的当前房间重新判断特殊路线，而不是只执行收到的回溯。
5. J460 VA `0x6fd87a..0x6fd8ca` 的分支检查 animation 12、stage 1、非水下／渗水
   的 stageType、当前房间为楼层起始房间，以及当前 Room 的首次进入标记。
   普通模式满足时直接调用 `StartStageTransition(false, 6, nullptr)` 前往 Home；
   Greed 模式另有原生分支。此处没有检查是否持有沙漏，也不检查 PR 的挑战规则。
6. 主机在 84 满足 Home 条件，客机在 97 不满足。此时 `beforeStart()` 已令
   `enabled=false`，`stageTransition()` 因而直接调用原生函数，不经过可靠楼层
   事件。两端仍共用 epoch 1，但主机变为 stage 13、客机仍为 stage 1。
7. [`src/bridge/runtime/floor.lua`](https://github.com/BMingSY/isaac-lan/blob/main/src/bridge/runtime/floor.lua) 在相同 epoch 下发现实际楼层与权威快照不符，
   正确地暴露错误并终止会话；不能放宽这个断言来掩盖分歧。

涉及的原生读取为 Game `+0x18300`（当前 Room）、`+0x18304`（当前房间索引）、
`+0x182d0`（起始房间索引）、Room `+0x1`（首次进入标记）、Game `+0/+4`
（stage/stageType）及 `+0x269c8`（模式）。上述分支来自实际 J460 可执行文件的
只读反汇编，没有临时修改这些字段。

## 与主分支的关系及最小复现

`git diff 7430c22 aa3918c -- src/engine/versions/j460/rewind.cpp` 为空。
`rooms.cpp` 中延迟 animation 12、`canonical()`、`beforeStart()` 和关闭分房时
直接执行原生 stage transition 的逻辑在两提交间相同；PR 对该文件的变更属于
挑战结束拦截、房间进入许可及具名挑战结束调用。回溯主体可追溯至
`6044e06`／`8aa99f4`，所以这个上下文缺陷已存在于主分支，不是本 PR 新增。

从已证实调用链提取的最小普通模式复现如下，尚待单独实机验证：

1. 两人开始普通地下室 I；P1 留在首次进入的起始房间。
2. 给 P2 发光沙漏，并让 P2 正常进入相邻房间，取得原生联机回溯检查点。
3. P2 在相邻房间使用沙漏；记录使用前后两端的当前房间、stage/type、worldEpoch、
   原生转场类型和 reliable floor event。
4. 预期正确结果是两端恢复同一个检查点；当前代码预计主机误进 Home、客机正常回溯，
   随后报告相同楼层初始化错误。

持有道具的步骤用于覆盖普通玩家操作，不用于规避 Home 分支。旧
[`tests/state_hourglass.lua`](https://github.com/BMingSY/isaac-lan/blob/main/tests/state_hourglass.lua) 在首次使用沙漏前已将 P1 移出起始房间，因此没有覆盖
“P1 留在起始房、P2 分房使用”这一上下文组合。

## 诊断时提出的修复边界和验证要求

权威端必须在使用者的实际源房间决定原生特殊路线。真正满足起始房 Home 条件的
操作仍应保留；可靠事件一旦选择了回溯，各端必须纯粹执行该回溯，不能再依据各自
视口重选 Home。不得通过临时改 stage／首次进入标记或忽略楼层断言解决。

可以复用已有 `Room::activate()` 和 `beforeStart()` 的所有权处理，在没有房间
作用域时选择权威使用者的真实源房间。但仅做这一步不足以覆盖所有客机：
`projectRemote()` 的 `replicaShell` 只构造存储对象，没有原生 Room 初始化，
其上下文数组也未填充。不能将它直接激活并作为原生转场根。现有 `beginFloor()`
选择本机玩家的已加载房间，没有为远端 shell 提供这种保障。

`beforeStart()` 会移动队伍、销毁附加房间并清空房间所有权映射，因此不能用
`Scope` 包裹它，让析构器随后访问已销毁的房间。若需要更低层的具名原生回溯
执行入口，必须单独校验 ABI、入口签名、Game 的原生 RoomTransition 所有权及
调用前后副作用；本次诊断没有新增该入口或修改后端。

离线回归应覆盖真实触发链：请求来自 P2 房间 97，延迟执行时主机视口为首次进入
的 84；其他客机视口也可能为 84，使用者房间则仅为 shell。断言权威路线只选一次、
可靠回溯执行不再次读取视口路线条件，并覆盖重复事件、清理、非法使用者以及真正
起始房 Home 的分支。既有 [`tests/floor.lua`](https://github.com/BMingSY/isaac-lan/blob/main/tests/floor.lua) 的同 epoch 错层报错应保留。
最终实机再复用同一组进程验证该最小场景、真正的 Home 路径、普通分房／跨层回溯
及三／四人含远端 shell 的情况。

## 2026-10-14 实现

用户明确规则：任何玩家的原生路线判定选择 Home，全队一起进入 Home。使用者在普通邻房用沙漏仍按原版回退，不因主机留在出生房而误选 Home。

- 房主在无房间作用域的帧边界激活实际使用者的完整源房，再沿现有所有权路径合并队伍和释放附加房。
- 原生 Game::StartRoomTransition 判定期间，现有 Stage Hook 暂存 Home 请求；判定返回后只发布 Home 或回退中的一项可靠事务。Home 不携带回退数据，也不恢复旧位置。
- 没有检查点的首访出生房仍可使用原版 Home 路线。完整权威房间通过原版条件边界检查后交给原生判断；同帧 Home 优先取消待执行回退，保留检查点。R Key 先消费重启标志再保存，修复原先 `stateReady()` 拒绝其检查点的问题。
- 回退载荷记录原生实际的房间转场参数；客机复用 `RoomTransition.Start` 回放，避免普通模式 Home、Greed 起始房特殊传送或其他视口条件重新选路线。原生特殊房直接进行房内传送而未启动 RoomTransition 的情况，载荷记录无转场，不在客机强制启动回退。
- 不修改首次进入标记、不暂改 stage/type，不放宽楼层一致性断言。协议仍为 28，世界 schema 仍为 15；不透明回退载荷的内部格式更新由扩展指纹隔离。

代码见[原生回退适配](https://github.com/BMingSY/isaac-lan/blob/main/src/engine/versions/j460/rewind.cpp)、[源房准备与已有 Stage Hook](https://github.com/BMingSY/isaac-lan/blob/main/src/engine/versions/j460/rooms.cpp)，入口、ABI 与所有权依据见[全队回退契约](https://github.com/BMingSY/isaac-lan/blob/main/docs/session-lifecycle.md#全队回退)。

离线结果：Windows 构建、J460 入口签名、74 项 C++／Lua、回退／换层／R Key 传输用例及全项目格式／语法检查通过。[原生回退 ABI 回归](https://github.com/BMingSY/isaac-lan/blob/main/tests/rewind_home_test.cpp)18 组通过，覆盖实际源房、Home／回退互斥、原生选定参数、Greed 参数、特殊房提前返回、真实 thiscall／ret20、标志、2／3／4 人载荷、非法范围、截断、重复、清理、Home 条件边界及取消请求后保留检查点。Windows CI 同步执行新增回归。

集中实机入口为[受保护 runner](https://github.com/BMingSY/isaac-lan/blob/main/tools/run_hourglass_home.py)与[场景夹具](https://github.com/BMingSY/isaac-lan/blob/main/tests/state_hourglass_home.lua)。第 03／04 轮合计完成九个会话的状态验收，第 05 轮四人复核通过。失败轮次保持原结论；每轮复用同一组进程，各会话回到菜单后继续，无需为人数或路线重新启动。

## 2026-10-14 集中实机记录

| 轮次 | 结果 | 清理与重启原因 |
| --- | --- | --- |
| 01 | R Key 后 P2 在首访出生房使用沙漏，没有发出任何楼层事件。确认 R Key 的待重启标志阻止了全队检查点保存；无检查点的 animation 12 又被无条件拦截 | 主客机强制结束，其余两端正常退出；无崩溃转储，所有受保护资料恢复一致。修复原生适配后重启以加载新 DLL |
| 02 | 无 R Key 的两人新局触发一次 Home；两端 stage 13/type 0，库存保留且普通移动通过。后续分房步骤因夹具只选 1×1 房间而失败，Home 的其他房间布局不符合这一条件 | 主客机强制结束，其余两端正常退出；无崩溃转储，所有受保护资料恢复一致。修改夹具后重新集中验收；生产 DLL 未改动 |
| 03 | 两人和三人共六个 Home／主机回退／客机回退会话完整通过。四人 Home 的转场、移动和分房通过，但 P4 主动离线后，夹具误把正确的活跃角色减员判为丢失，整轮失败 | 主机与 P4 正常退出，P2／P3 强制结束；无崩溃转储，所有受保护资料恢复一致。修正离线人数断言，下一轮只复跑未完成的四人三会话；生产 DLL 未改动 |
| 04 | 四人 Home／主机回退／客机回退三会话通过，Home 的 P4 离线重连恢复原槽和库存。各端可靠事件数符合预期 | 四端游戏与 heap watcher 退出码均为 0，无转储。外层 runner 在资料恢复前收到退出码 143，保留原生成功结果并单独执行备份恢复；逐目录校验全部一致 |
| 05 | 仅取消夹具受伤闪烁并加入 `Visible` 断言，四人三会话与 Home 重连再次通过。四端角色身体、实际房间、库存 HUD 与完成后的移动画面通过 | 四端游戏与 heap watcher 退出码均为 0，无转储；runner 整轮通过，所有受保护资料恢复一致 |

第 03／04 轮使用同一生产 DLL，SHA-256 为 `963f9c3ea0abfe43a80f7fbb3a69047a0599d17693b4e27fb7431a33edd003f3`。两人普通模式由 P2 从未重开的首访出生房触发 Home，三人 Hard 模式由 P1 触发，四人由 P4 触发；其余玩家可以在另一房间。Home 均只推进一次世界代次，保留 coins 27 和 Pentagram。普通回退均恢复 stage 1/type 0、coins 20、原生检查点位置、生命和每位玩家原有库存，移除检查点后的 Pentagram；每人正常输入移动及再次分房均通过。

初版夹具设置长受伤冷却避免前置战斗干扰。500ms 录像采样与原版 `damageCooldown % 6` 身体闪烁门控同相，回退前后都可连续采到只有影子的帧；原生普通与半帧更新均递减冷却，不能据此认定角色永久隐藏。夹具现沿用其他验收场景的 `FLAG_NO_DAMAGE_BLINK`，保留冷却保护并加入 `Visible` 断言，生产代码不修改闪烁行为。

画面复核记录：第 03 轮两人 Home 为主机帧 133／客机 107；第 05 轮四端依次为主机、P2、P3、P4，Home 帧 150／125／100／74，主机回退帧 215／189／164／138，客机回退帧 276／250／225／199。四人 Home 显示同一出生卧室、coins 27 与新增外观；普通回退显示同一地下室起始房、coins 20 与原有外观，没有黑屏或遗留隐藏身体。

本轮没有重跑 Greed、控制台回退或普通跨层回退的专门实机。Greed 参数与原生特殊房提前返回由离线 ABI 用例覆盖；Home 已验证真实跨层、分房和重连。原有 LANBOT doorway 问题与本次修复无关，仍保留。
