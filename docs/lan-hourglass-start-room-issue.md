# 首层分房沙漏错误进入 Home 的诊断

2026-10-13，PR #64 集中实机验收第 08 轮发现既有沙漏问题。测试提交为
`aa3918c`，对照主分支为 `7430c22`。本记录仅描述诊断；尚未修复，也没有在
主分支二进制上单独重跑最小场景。不能将后续避开触发条件的验收视为此问题通过。

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

## 后续修复边界和验证要求

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
