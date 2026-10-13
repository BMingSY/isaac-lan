# PR #64 联机挑战审阅与验收记录

本记录对应 2026-10-13 对 [PR #64](https://github.com/BMingSY/isaac-lan/pull/64) 的审阅。原始 PR 提交为 `aa3918c2695a3c9c96856d45f099cf5d3719cd48`，对照的 `origin/main` 为 `7430c22bb2d9dbf72ce985eccf10e14db7f5593a`。下述本地修复尚不属于原始提交。

当前挑战名为 **恶魔形态**。用户要求的资格、普通存档选角、原版路线、仅羔羊奖杯通关、禁止跑圈、主客机统一右下副手及本机卡药保留，均已完成对应的离线和集中实机检查：资格第 11 轮通过；第 14 轮 2／3／4 人通关机制及可靠完成事件通过，但整轮因旧 Resume 夹具误判失败；修正夹具后的第 15 轮 HUD／重连／普通 Resume 专项整轮通过，四端退出码均为 0，受保护资料均恢复。没有把失败轮次改写为通过。

仍保留两个既有问题：第 08 轮首层分房沙漏的楼层分歧未修复；Python doorway 回归在原始 PR 和主分支均失败。单机 Continue 的完整游戏内恢复及 Beast 等其他终局演出没有单独实测，因此不宣称所有历史问题或全部边界均已验收。

第 09 轮后按用户要求简化实现：全员自己的存档均须解锁底片与里该隐，普通角色按各自存档过滤，路线沿用原版，删除全部自动改道及 Lua 转场。随后改为隐藏远端小 HUD 副手信息，在本机右下角显示下一位的材料和预览，同时保留本机其他口袋道具。**01–09 轮运行的是旧规则，不能证明当前实现通过实机。** 当前规则与原生边界见[联机挑战](lan-challenges.md)。

第 08 轮首层分房沙漏的楼层分歧尚未修复；第 09／12 轮同房对照通过不关闭该问题。第 10 轮的启动期空管理器读取已修复，并经第 11 轮四端启动和资格检查确认。

## 审阅修复

- **资格与角色选择。** 挑战 1001 定义版本提升为 2，要求每名玩家本机存档的底片成就 `78` 和里该隐成就 `476`；共享主机进度不参与资格判断。普通角色列表现复用原生菜单目录及可选判定，按各自存档读取并包含原生收录的角色 Mod；旧的固定 34 人名单与解锁成就表已删除。伊甸与里伊甸的新开局还检查令牌计数，续玩／重连只检查角色永久解锁，避免已消耗的令牌阻止恢复。
- **路线保持原版。** 保留可推进路线的原版楼层入口，Dark Room 羔羊房清场后改为奖杯；其他终局箱碰撞、原生结局和跑圈入口受挑战规则阻止；删除自动改目的层、`onEnding`、`routeEnding` 和挑战模块中的 `StartStageTransition`。早先针对虚空结局箱补目的地的修复已被这一简化替代。[原 Void 回归](../artifacts/pr64-native-offline-20261013/void-chest-regression.json)只保留为历史记录，不再代表当前行为或待实机要求。
- **明确区分挑战完成与普通结局。** 原生 ending `6` 本身是羔羊结局，不能仅凭该编号认定领取了挑战奖杯。可靠结束事件增加通用 `completed` 标记；只有权威奖杯完成请求使用 `Game::FinishChallenge`，普通局结局继续走原生结束流程，挑战仅允许奖杯完成。网络回归和第 14 轮 2／3／4 人通关实机均通过。
- **启动期目录查询。** 内嵌 Lua 模块初始化会查询挑战目录，早于原生 `Manager` 全局指针发布。新增个人资格读取最初直接解引用该指针，导致第 10 轮启动崩溃；现于管理器不可用时返回空资格，保留静态目录，待菜单与存档可用后重新读取，不缓存启动期空结果。
- **副手布局和二次开局纸片。** 新增原生副手外层过滤，保留本机卡药；袋子内层只借下一位 HUD receiver，保持本机位置。新增两层 ABI 回归已通过。二次开局的 BACK／SELECT 来自 Manager 内嵌提示组，原生菜单析构没有清理；在 ExecuteStart 返回后调用具名原生 reset，避免覆盖右下角。
- **终局跑圈。** 第 12 轮证实原先返回 `1` 代表确认跑圈；已改为原生拒绝值 `2`，同时拒绝挑战的主机／副本跑圈入口。
- **Windows CI 漏跑新增 HUD ABI 测试。** 工作流现把 `isaac_lan_crafting_hud_test.exe` 和 `isaac_lan_challenge_hud_test.exe` 纳入上传产物，并在 Windows 作业中执行、核对退出码及保存日志。本地原生测试已通过；此处不将工作流修改记为远端 CI 已执行。

第 08 轮发现的沙漏同步缺陷尚未修复。只读调用链核对表明相关延迟执行及主视口上下文代码已存在于 `origin/main`；尚未在主分支二进制上单独重跑该场景，详见[首层分房沙漏诊断](lan-hourglass-start-room-issue.md)。

## 初始离线与原生边界检查

以下为 01–09 轮所用旧实现的归档结果。资格门禁、普通选角过滤、路线删除与显式完成标记的新结果另行记录，不能用此表替代新实现的构建与回归。

| 检查 | 本轮结果 | 证据 |
| --- | --- | --- |
| 格式、脚本语法、离线配置与构建 | 通过 | [离线总报告](../artifacts/pr64-review-offline-20261013/summary.json) |
| CTest 离线 C++／Lua | 75 项通过，0 项失败 | [core.log](../artifacts/pr64-review-offline-20261013/core.log) |
| Python 回归 | 128 项通过，19 个子用例通过，1 项失败 | [scenarios.log](../artifacts/pr64-review-offline-20261013/scenarios.log)、[pytest.xml](../artifacts/pr64-review-offline-20261013/pytest.xml) |
| 百宝袋原生 x86 HUD ABI | 通过；包含接收对象、栈、SSE、显示条件与不修改材料检查 | [crafting-hud.log](../artifacts/pr64-native-offline-20261013/crafting-hud.log) |
| 挑战终点原生 x86 HUD ABI | 通过；包含指定调用点限制与清理 | [challenge-hud.log](../artifacts/pr64-native-offline-20261013/challenge-hud.log) |
| J460 入口与签名 | `1.9.7.17.J460` 入口校验通过 | [entrypoints.log](../artifacts/pr64-native-offline-20261013/entrypoints.log) |
| Windows 网络与状态传输 | 27 项通过；进程退出码 0 | [network.log](../artifacts/pr64-native-offline-20261013/network.log) |
| 旧 Void 宝箱修复回归 | 原实现失败，当时修复后通过；现已被原版路线简化替代 | [void-chest-regression.json](../artifacts/pr64-native-offline-20261013/void-chest-regression.json) |

Python 唯一失败为 `tests/offline/test_behavior.py::test_doorway_progress_across_movement_parameters`。反例参数为 `side=0, speed=160, radius=15, offset=3, distance=92`；360 步后仍未完成过门，状态为 `route_blocked`。同一反例在原始 PR 和上述 `origin/main` 基线得到完全相同的结果，见[基线对照](../artifacts/pr64-review-offline-20261013/baseline-comparison.json)。这是已复现的既有 lanbot 问题，未在本次挑战修复中修改；离线总报告仍保留 `passed=false`。

网络资源检查完成 45 次生命周期、5,760 份快照：私有内存前后均为 2,146,304 字节，句柄前后均为 113。该结果只覆盖对应离线传输测试，不替代游戏进程的资源验收。

原生离线报告归档在 `artifacts/pr64-native-offline-20261013/`，原始记录的 probe SHA-256 为 `f97d4c2a33707cc4c705a99928e2933cc055072d9ca67480096c6bd980e5555a`。实机 01–09 轮使用的修复后 DLL SHA-256 为 `9d43ed329d392b03cdcb13ad1e7e999fab730a98bd7ceff9c0d8acb3143a1634`；每轮另存该轮 Lua 脚本与哈希。该 DLL 不含第 09 轮后新增的资格门禁与路线简化。

## 资格与原版路线实现的离线结果

新结果归档在 `artifacts/pr64-access-offline-20261013/`。下表覆盖资格门禁、普通角色目录、原版路线保持与可靠结束标记；启动期空管理器保护随后完成了 Windows 重新构建，随后由第 11 轮确认实际启动。

| 检查 | 结果 | 证据 |
| --- | --- | --- |
| C++／Lua CTest | 76 项通过，0 项失败，含角色解锁与挑战门禁边界 | [core.log](../artifacts/pr64-access-offline-20261013/core.log) |
| Windows 网络与状态传输 | 28 项全部通过，含 `lobby-access` 与 `completed` 结束事件 | [network.log](../artifacts/pr64-access-offline-20261013/network.log) |
| Python 回归（Lua 5.3） | 133 项通过、19 个子用例通过；仍有 1 项既有 doorway 失败 | [scenarios-lua53.log](../artifacts/pr64-access-offline-20261013/scenarios-lua53.log) |
| 百宝袋／终点 x86 HUD ABI | 两项通过 | [crafting-hud.log](../artifacts/pr64-access-offline-20261013/crafting-hud.log)、[challenge-hud.log](../artifacts/pr64-access-offline-20261013/challenge-hud.log) |
| Windows 构建 | 新实现及启动保护均构建成功 | [build-windows.log](../artifacts/pr64-access-offline-20261013/build-windows.log)、[build-windows-startup-fix.log](../artifacts/pr64-access-offline-20261013/build-windows-startup-fix.log) |

其中 Python 失败仍为上文已在原始 PR／主分支复现的 `test_doorway_progress_across_movement_parameters`；不能把 133 项通过表述成全部离线测试通过。启动崩溃构建的 DLL SHA-256 为 `f0bf2c9454d0768cf0c8424ae4be78524a846ee01768b5defc8a2a4657268652`，补保护后待第 11 轮验证的 DLL 为 `277ee5d08c892ec7e18e3744b0df5164bb35a29cedf96289fc08e7c4a5eaf2ae`。

## 实机方法与失败轮次

当前入口为 `tools/run_lan_challenges.py`、资格夹具 `tests/state_lan_challenge_access.lua` 与玩法夹具 `tests/state_lan_challenges.lua`。旧自动路线夹具及 `--routes` 已删除，01–09 轮的实际脚本仍保存在各轮归档中。每轮启动一组隔离进程，玩法组内依次安排普通两人保存、两／三／四人挑战、普通两人续玩；切换会话复用进程。需要重新注入修订后的夹具时结束该轮并记录失败，再启动下一轮。

夹具只操作带 `.isaac-lan-lab` 标记的副本。工具备份并恢复 `profile`、`game/data`、`game/isaac-lan`，恢复后逐文件核对哈希。文件协调和存档字节比较需要隔离夹具的 Lua debug 模式，未更改生产 Lua 沙箱。源楼层和房间可由夹具准备，Boss 通过伤害加速击败；路线箱与最终奖励须通过实际游戏回调及碰撞推进。

01–09 轮四端初始成就数分别为 12、4、2、0，均未解锁 Womb；旧扩展路线要求妈妈／心脏等早期结局箱自然生成。新规则下，不具备底片或里该隐的存档应在大厅被拒绝，不再要求挑战为低解锁存档打开路线。新资格组在启动前准备四种不同条件的隔离存档，玩法组在启动前准备全员满足条件的隔离存档，结束后仍按原备份恢复。充袋继续通过原生采集，不直接写材料字节。

所有轮次原始目录保留在 `/mnt/d/isaac-lan-lab/pr64-challenges-20261013-NN/`。外层 `report.json` 记录场景与存档恢复结果，`engine/result.json` 记录启动、日志失败和进程退出码，`suite.lua` 与 `engine/test-harness.lua` 保留当轮脚本。

| 轮次 | 结果与停止原因 | 进程退出 | 隔离资料恢复 |
| --- | --- | --- | --- |
| [01](/mnt/d/isaac-lan-lab/pr64-challenges-20261013-01/report.json) | 失败；主机未到达 intro，启动退出码 `53`（`00000035`），未完成场景启动 | 异常退出 | `restored=true` |
| [02](/mnt/d/isaac-lan-lab/pr64-challenges-20261013-02/report.json) | 失败；夹具加载时访问被禁用的 `io`，日志为 `attempt to index a nil value (global 'io')` | 已启动主机退出码 0，`clean_exit=true` | `restored=true` |
| [03](/mnt/d/isaac-lan-lab/pr64-challenges-20261013-03/report.json) | 失败；重复发送准备选择导致 `Unexpected client message`，且在角色未全部激活时读取名单触发断言。后续夹具改为每次规则选择只发送一次，并等待在线角色名单 | 主机需强制终止，退出码 `FFFFFFFF`；另记录 heap watcher 退出码 5。其余三端退出码 0，整轮 `clean_exit=false` | `restored=true` |
| [04](/mnt/d/isaac-lan-lab/pr64-challenges-20261013-04/report.json) | 失败；充袋夹具生成的母刀未完成原生采集，断言 `Bag did not collect all eight native pickups` | 四端退出码 0，`clean_exit=true` | `restored=true` |
| [05](/mnt/d/isaac-lan-lab/pr64-challenges-20261013-05/report.json) | 失败；已观察原生 `subtype=4`、`animation=Swing` 的子刀，两名角色材料数仍为 0，最终断言 `Native swipe did not collect owned pickup for slot 0` | 四端退出码 0，`clean_exit=true` | `restored=true` |
| [06](/mnt/d/isaac-lan-lab/pr64-challenges-20261013-06/report.json) | 失败；两人满袋与同房／分房显示已核对。P2 死亡后，夹具把幽灵的 `entry[8]=false` 错当成空袋，触发 `Replica bag differs from authoritative actor` | 四端退出码 0，`clean_exit=true` | `restored=true` |
| [07](/mnt/d/isaac-lan-lab/pr64-challenges-20261013-07/report.json) | 失败；死亡／幽灵复制和固定栏位画面通过，双端记录实际 HUD 偏移 `1.0` → `0.0`。复活夹具仅调用 `player:Revive()`，未解除合作幽灵状态，触发 `Challenge actor remained a ghost` | 四端退出码 0，`clean_exit=true` | `restored=true` |
| [08](/mnt/d/isaac-lan-lab/pr64-challenges-20261013-08/report.json) | 失败；夹具复活后材料与栏位通过。沙漏导致主机进入 Home（stage 13），客机回到 stage 1，同为 epoch 1，生产代码报 `Replica floor initialization failed`；R Key 未实际执行 | 四端退出码 0，`clean_exit=true` | `restored=true` |
| [09](/mnt/d/isaac-lan-lab/pr64-challenges-20261013-09/report.json) | 失败；同房沙漏 epoch 1 和原生 R Key epoch 2 通过。随后妈妈路线调用旧 `challenge_lamb.lua:87 onEnding` 的 Lua `StartStageTransition`，主机在 Lua DLL 内访问违规 | 主机退出码 `C0000005`，heap watcher 退出码 5；其余三端退出码 0，`clean_exit=false` | `restored=true` |
| [10](/mnt/d/isaac-lan-lab/pr64-challenges-20261013-10/report.json) | 失败；新资格组未到大厅，内嵌 `runtime/challenges.lua:3` 查询 `net_challenges` 时解引用空管理器，读取地址 `0x4c` | 仅主机启动后退出 `C0000005`，`clean_exit=false` | `restored=true` |
| [11](/mnt/d/isaac-lan-lab/pr64-challenges-20261013-11/report.json) | 资格组通过：六种主客机拒绝组合、个人角色过滤、四人普通局及退出后的本地资格保持 | 四端退出码 0，`clean_exit=true` | `restored=true` |
| [12](/mnt/d/isaac-lan-lab/pr64-challenges-20261013-12/report.json) | 失败；两人满袋、同房沙漏、R Key 与原版路线至羔羊均通过，奖杯生成后原生跑圈意外进入新局，触发规则／难度断言 | 主机强制终止 `FFFFFFFF`，heap watcher 5；客机均 0，`clean_exit=false` | `restored=true` |
| [13](/mnt/d/isaac-lan-lab/pr64-challenges-20261013-13/report.json) | 失败；新版 HUD、原版路线、羔羊奖杯及 victory_lap=0 已观察；故意断线后夹具在同一次渲染继续使用旧 ready 状态，触发 Challenge rules were lost | 客机强制终止 `FFFFFFFF`，heap watcher 5；其余三端退出 0，`clean_exit=false` | `restored=true` |
| [14](/mnt/d/isaac-lan-lab/pr64-challenges-20261013-14/report.json) | 整轮失败；2／3／4 人通关、Void 清理和禁止跑圈均通过，最终 Resume 被夹具错误的独立金币假设阻断；3／4 人 HUD 仍待右下布局修订 | 四端退出 0，`clean_exit=true` | `restored=true` |
| [15](/mnt/d/isaac-lan-lab/pr64-challenges-20261013-15/report.json) | HUD 专项整轮通过：2／3／4 人所有本机副手统一右下、自有卡药、同／分房、幽灵复活、重连及普通 Resume；预期无结束事件 | 四端退出 0，`clean_exit=true`，177.03 秒 | `restored=true` |

第 05 轮主客机均记录普通联机保存及菜单清理完成；两人挑战中均记录 `EID_RECIPE_RESTRICTED present=true`。这些局部事实不代表充袋、画面或整轮挑战通过。第 03 轮的强制终止和第 01 轮的启动异常均保留原始判定，不能因存档成功恢复而改记为正常退出。

第 06 轮记录 P1 的袋子为八枚硬币、预览道具 `177`，P2 为八把钥匙、预览道具 `343`。同房和分房的主客机画面已核对：P1 只显示 P2 的八把钥匙及预览 `343`，P2 只显示 P1 的八枚硬币及预览 `177`，与固定观察环一致；分房后材料字节保持不变。证据保留在该轮 `engine/host/log.txt`、`engine/client/log.txt` 及各端 `frames/`。

第 06 轮在 tick 603 令 P2 死亡，随后客机检查失败。核对生产契约后确认：`compat/items/crafting_bag.lua` 对幽灵采集返回 `false`，应用阶段跳过其隐藏库存；`false` 在此不表示原生材料必须为十二个零字节。原生 getter 仍可能读到转换期间保留的字节，`tests/crafting_bag.lua` 已有明确禁止幽灵访问材料的回归且本次复跑通过。因此该断言失败属于夹具错误，未据此确认新的生产同步缺陷。后续夹具应核对幽灵标记与 `entry[8]=false`，对活体及复活后的角色继续严格比较材料和预览。

第 07 轮死亡／幽灵复制的严格断言已通过。[主机第 128 帧](/mnt/d/isaac-lan-lab/pr64-challenges-20261013-07/engine/host/frames/128.png)（tick 706）隐藏 P2 的袋子，但固定栏位文案仍为 P2；[客机第 92 帧](/mnt/d/isaac-lan-lab/pr64-challenges-20261013-07/engine/client/frames/92.png)（tick 703）继续显示 P1 的八枚硬币及预览 `177`。复活阶段失败的原因是夹具仅调用 `player:Revive()`，合作幽灵标记仍未解除。第 08 轮参照既有 `tests/state_reported_bugs.lua`，由隔离夹具调用 `native.actor_ghost(..., 0)`，再执行 `Revive()` 和 `AddHearts(6)`；这属于夹具触发复活，不是自然击败 Boss 后复活的验收证据。

第 08 轮客机在 tick 660 记录 `GHOST_BAG_OMITTED actor=1`，tick 724 记录 `REVIVED_BAG_MATCH actor=1`，复活后恢复严格材料／预览字节比较。[主机第 131 帧](/mnt/d/isaac-lan-lab/pr64-challenges-20261013-08/engine/host/frames/131.png)和[客机第 95 帧](/mnt/d/isaac-lan-lab/pr64-challenges-20261013-08/engine/client/frames/95.png)显示两名角色均为活体，主机仍查看 P2 的八把钥匙及预览 `343`，客机仍查看 P1 的八枚硬币及预览 `177`；栏位没有重排。

HUD 偏移需按实际值记录。第 06 轮尝试通过 Lua 写入 `1` 时，实际值不高于 `0.01`，不能把这次赋值当作成功切回偏移 `1`。第 07 轮双端日志均记录 `HUD_OFFSET_INITIAL actual=1.0`、`HUD_OFFSET_SET requested=0 actual=0.0`，两个实际值对应的羔羊终点与袋子画面已核对。这里验证的是初始实际值 `1.0` 到设置后的实际值 `0.0`。

上述画面判定只覆盖袋子、终点和固定观察栏位。06–09 轮实图底部另有原版 `BACK`／`SELECT` 大纸片覆盖，不能据这些局部结果宣称完整 HUD 布局已经验收。第 09 轮[普通会话帧 68](/mnt/d/isaac-lan-lab/pr64-challenges-20261013-09/engine/host/frames/68.png)（tick 90）底部正常，[二次启动后的帧 125](/mnt/d/isaac-lan-lab/pr64-challenges-20261013-09/engine/host/frames/125.png)出现覆盖，所以不能简单归因于所有虚拟手柄／首次菜单启动。`frontend.cpp`、J460 `input.cpp` 与 `run_network_engine.py` 在上述主分支和原始 PR 的 Git blob 完全相同；Lua 菜单隐藏分支也没有绘制这些纸片。随后核对转储：游戏 scene=2、MenuManager 指针为空，Manager 内嵌提示组的 currentY／targetY 仍为 0；Manager 绘制入口继续绘制这些纸片。现复用原生重置入口，在菜单销毁后的联网启动生命周期清理；第 13 轮确认纸片消失，改成单次清理后的第 14／15 轮再次确认正常。

第 08 轮 tick 916 使用沙漏时，P1 留在首访起始房间 84，P2 位于房间 97。主机延迟执行原生回溯时采用 P1 的房间上下文，误触 Home 转场；客机从房间 97 正常回到 stage 1。两端共用 epoch 1，但主机已为 stage 13，随后生产楼层断言正确报告分歧。这是实际同步失败。夹具的 `HOURGLASS_BAGS materials_preserved=true` 只验证袋子字节，不能证明完整回退成功；虽然后续记录 `r-key-wait`，原生日志没有 `floor_transaction=R_KEY`，不能记作已执行 R Key。

第 09 轮使用显式 `--hourglass-shared-room`，让两名角色在同一非起始房间执行沙漏对照，没有修改原生回溯代码。主机 `probe.log:53` 发送 epoch 1，双端分别在 21:30:36.544 和 21:30:36.692 记录 `floor_transaction=COMPLETE stage=1`；主机 `log.txt:1067` 确认 `stage=1 stage_type=0 room=84 epoch=1`。随后主机在 21:30:41.659 发送 epoch 2，双端均记录 `floor_transaction=R_KEY` 及 stage 1 完成，`log.txt:1092` 的严格材料检查通过。这些是实际回退／重启证据；同房对照没有覆盖或关闭第 08 轮分房缺陷。

第 09 轮在妈妈路线阶段崩溃。主机 `log.txt:1142` 的 Lua 栈明确为 `StartStageTransition` → `challenge_lamb.lua:87 onEnding` → `runtime/challenges.lua:63 step`；`probe.log` 记录 Lua5.3.3r.dll RVA `0xd3c1` 的 `c0000005`，完整转储保存在 `engine/host/heap-dumps/28864-1.dmp`。J460 原始 Lua 包装器 VA `0x8b8bb0` 只向原生调用压入两个参数，原生 `Game::StartStageTransition` VA `0x6fdc10` 按三个参数读取并以 `ret 12` 返回，导致返回后寄存器／栈恢复错位；给 Lua 调用补第三实参并不能修复该包装器。当前挑战实现已删除这个调用链，没有修改原生 ABI；旧轮次仍保留崩溃结论；第 14 轮新实现已通过原版完整路线。

第 10 轮主机 `probe.log` 在 `frontend_bridge=READY` 之前记录读取地址 `0x0000004c`，恰为零管理器指针加 PersistentGameData `0x14` 和成就数组 `0x38`。装配顺序为 `runtime::install` → `frontend::install` → Lua 初始化后的 `bindNative` → 加载 `app/main.lua` → 查询挑战目录；运行时已安装，提前的是原生管理器生命周期。修复只保护个人资格读取的启动边界，没有把所有角色或挑战默认开放。原始转储位于该轮 `engine/host/crash_dumps/`。

第 14 轮机制验收使用 DLL `e367a3954ba6bb7bc4d2221f207a2a56c128b485fcd393103f0935a96793d7d1`，已将菜单纸片重置限制为实际开局／Resume 后一次，并让羔羊奖杯的原生更新清理虚空入口、楼层地洞和天堂光柱。验收夹具在满袋后加入每人自己的卡牌／药丸，检查 Bag 未被替换；另显式生成原生 Void 地洞，等待正常回调移除；重连后重新进入羔羊房并重新查找奖杯。此轮各项及整轮结果分别见下表和本轮归档。

## 最终结果矩阵

资格以第 11 轮为准，通关机制以第 14 轮为准；固定右下布局与修正后的 Resume 检查以第 15 轮为准，均已通过。失败轮次仍保留失败结论，各构建与专项证据分别记录。

| 验收项 | 当前实机状态 | 证据 |
| --- | --- | --- |
| 所有玩家本机底片／里该隐资格 | 通过；六种主客机缺资格组合拒绝 | [11 轮报告](/mnt/d/isaac-lan-lab/pr64-challenges-20261013-11/report.json) |
| 普通角色按本机存档过滤，伊甸新局与续玩资格分开 | 个人列表、锁角拒绝、普通四人局通过；令牌耗尽恢复由离线用例覆盖 | 11 轮 PERSONAL_ACCESS／LOCKED_CHARACTER_REJECTED；network.log |
| 2／3／4 人强制里该隐，固定观察环 | 通过；2 人 key343→coin177，3 人增加 bomb123，4 人增加 heart45 | 14 轮各端 BAG／SPLIT_BAGS 与画面 |
| 所有主客机仅本机右下显示下一位袋子 | 15 轮 2／3／4 人所有本机端通过；旧 compact 布局已修复 | 15 轮三人 host184/client148/client2 112；四人 host246/client211/client2 174/client3 135 |
| 本机卡药保留、队友小 HUD 副手隐藏 | 15 轮 2／3／4 人库存断言和各端画面通过 | SAME_ROOM_POCKETS／SPLIT_ROOM_POCKETS／REPLICA_POCKETS |
| 底部挑战文字删除、加入提示仅“输入房主的 IP” | 通过 | 13 轮主机帧 12／110、客机帧 74；14 轮对应画面 |
| 第三方 Mod 配方面板 | 按用户要求移除挑战对 EID 的配方面板屏蔽，保持 Mod 原行为；旧轮次的屏蔽结果仅作为历史记录 | 原版 HUD 的观察环和显示限制保持 |
| HUD 偏移、菜单纸片清理 | 初始 1.0→0.0、多次开局、不同窗口宽度及最终全人数布局通过 | 14 轮 HUD_OFFSET 日志；无 BACK／SELECT 残留 |
| 幽灵／复活不重排栏位 | 通过；复活由原生隔离夹具触发，未覆盖自然 Boss 复活 | 14 轮 GHOST_BAG_OMITTED／REVIVED_BAG_MATCH |
| 沙漏回退与 R Key 保持规则 | 同房沙漏和 R Key 通过；首层分房沙漏仍有既有失败 | 14 轮 HOURGLASS_BAGS／R_KEY_BAGS；[分房诊断](lan-hourglass-start-room-issue.md) |
| 原版楼层入口、撒旦箱到暗室，不自动改道 | 2／3／4 人通过 | 14 轮 NATIVE_ROUTE_FLOOR／NATIVE_SATAN_CHEST |
| 羔羊只留奖杯，禁跑圈及清理 Void 入口 | 2／3／4 人通过；其他终局拦截由离线回归覆盖，未单独实测 Beast 演出 | 14 轮 VOID_EXIT_REMOVED／TROPHY_READY，均 victory_lap=0 |
| 客机领取奖杯，全队完成并返回菜单 | 2／3／4 人通过；四端 completed=1 事件数 3／3／2／1 | 14 轮各端 probe 和报告 challenge_completion |
| 掉线重连恢复规则、身份、材料 | 通过，恢复 P2 原槽并重返羔羊房领奖 | 14 轮 RECONNECT_IDENTITY_PRESERVED／RECONNECT_BAGS／RECONNECT_LAMB_ROOM |
| 挑战不覆盖普通联机存档，普通 Resume | 通过；15 轮普通资源精确恢复为每槽 coins20/bombs2/keys0 | 15 轮 ORDINARY_ARCHIVE_PRESERVED／ORDINARY_RESUME_RESOURCES actual=expected |
| 单机 Continue 游戏内恢复 | 尚未单独验证；隔离资料均恢复不能替代游戏内流程 | 保留待验证 |
| 自有进程正常退出、隔离资料恢复 | 11／14／15 轮全端退出 0、restored=true | 各轮 engine/result.json 和 report.json |

后续应继续保留失败轮次，只将已经观察并核对的项目更新为通过。已有离线结果、原生 ABI 测试和部分 EID 断言均不能替代尚未完成的游戏机制与画面验收。

第 13 轮主机帧 110、客机帧 74 核对了分房时右下角分别显示 P2 的八把钥匙／343 与 P1 的八枚硬币／177，远端副手区和底部挑战文字已隐藏。主机帧 12 显示新占位文案“输入房主的 IP”。该轮菜单纸片已消失，但只读复核发现 reset 在每帧执行，后续修成新局／Resume 完成后只消费一次，最终单次清理已由第 14／15 轮确认。第 13 轮到羔羊奖杯的所有原版楼层事务均成功，生成和展示时 victory_lap=0；重连夹具调用离开后须立即结束本次回调，避免用旧 info.ready 检查已经关闭的会话。

第 14 轮两人同／分房卡药检查已通过，主客机日志分别记录 SAME_ROOM_POCKETS／SPLIT_ROOM_POCKETS／REPLICA_POCKETS。主机帧 108（tick 402）显示 P2 的钥匙与 343 预览，旁边保留本机 Fool；客机帧 72（tick 401）显示 P1 的硬币与 177 预览，旁边保留本机蓝药。新的一次性提示重置下，BACK／SELECT 纸片未残留。整轮结论保留在第 14 轮归档中。

第 14 轮两人挑战完整流程已通过：VOID_EXIT_REMOVED 确认真实 Void 地洞清理、奖杯保留、victory_lap=0；客机 RECONNECT_IDENTITY_PRESERVED slot=1，重返羔羊房重新取得奖杯。主机 22:34:20.353 记录 ending_event=SENT id=6 completed=1，客机 22:34:20.379 记录 RECEIVED completed=1；两端 archive、个人进度及菜单清理断言通过，随后在同组进程进入三人挑战。

第 14 轮三人环形材料数据正确，但原生 3 人布局把本机副手放到左上并缩小，卡药图标也没有按两人局的右下布局显示。证据为主机帧 592、客机帧 555、第三端帧 521；因此本轮三／四人 HUD 不能记为验收通过。按用户再次确认，主机及每个客机都须只在本机右下副手栏显示袋子。当前继续完成第 14 轮机制检查，随后以修订原生绘制参数的构建运行独立 HUD 集中组，复用 2／3／4 人及普通 Resume，避免重复已经验证的整条路线。

第 14 轮最终为 failed、clean_exit=true、restored=true，四个进程均正常退出。两／三／四人奖杯机制及可靠完成事件全部通过，四端事件数为 3／3／2／1；普通 Resume 夹具错误地要求每人金币为 19+slot，而原版 co-op 使用共享资源池。普通保存帧 66 和恢复帧 1402 的金币均为 20，实际未见丢失。后续夹具只设置一次共享金币，在退出前断言并记录各槽真实金币／炸弹／钥匙，恢复时与记录严格比较。该修正与最终 HUD 组一起验证，不把本轮错误断言记作通过。

第 15 轮 HUD 专项使用 DLL `e146bcfb9a811d6bd4acac04146a6fdeaa0e98ba27b48c6637556cd73d337470`，原生完整右下定位使用逻辑宽高与本帧 HUDOffset，输入人数布局不影响本机副手位置。新版 x86 ABI 测试覆盖每个本机槽、两种逻辑分辨率、HUD 偏移、栈 Vector 生命周期及 caller 数据不变，均通过；第 15 轮实机通过。

第 15 轮最终 `passed=true`、`scenario_pass=true`、`clean_exit=true`、`restored=true`，耗时 177.03 秒，四个自有进程退出码均为 0。HUD 专项没有原生结束事件，四端 `events=[]` 与预期 0 完全一致。普通 Resume 日志 `actual=0:20:2:0;1:20:2:0 expected=0:20:2:0;1:20:2:0`，随后两端正常存退。全员资格、完整奖杯流程与最终显示分别对应 11／14／15 三组证据；最后一轮只改原生显示参数，没有重复已经完成的整条通关路线。

可直接复核最终四端画面：[主机](/mnt/d/isaac-lan-lab/pr64-challenges-20261013-15/engine/host/frames/246.png)、[P2](/mnt/d/isaac-lan-lab/pr64-challenges-20261013-15/engine/client/frames/211.png)、[P3](/mnt/d/isaac-lan-lab/pr64-challenges-20261013-15/engine/client2/frames/174.png)、[P4](/mnt/d/isaac-lan-lab/pr64-challenges-20261013-15/engine/client3/frames/135.png)。材料／预览依次为下一位的 key343、bomb123、heart45、coin177，自己卡药仍在右下，其他 HUD 不显示袋子。

后续按用户要求撤销挑战对 EID 百宝袋配方面板的屏蔽，删除相应用例和验收断言；EID 兼容适配恢复为主分支原实现。挑战仅调整原版 HUD，第三方 Mod 的配方显示不受挑战干预。上述旧轮次 EID_RECIPE_RESTRICTED 标记记录当时构建，不再代表当前行为。


## 原生角色目录选角的后续验收

按用户要求，固定 34 人目录、中文名称／动画映射和角色解锁成就表均已删除。菜单通过具名后端接口读取游戏的两页原生目录、Mod 普通／里配对、名称与画像；原版资格调用游戏自己的菜单可选函数，并使用本机进度。未新增要求各端启用完全相同 Mod 的门禁，网络沿用原有个人角色资格和兼容性契约。第三方 Mod 自身的菜单或玩法限制不由联机菜单重新定义。

当前离线结果在 `artifacts/pr64-catalog-offline-20261013/`：格式与脚本语法通过，Windows 构建通过；74 项 C++／Lua CTest、28 项网络、3 项原生 x86 ABI、37 项工具／入口 Python 测试（含 19 个子用例）及 4 项角色目录 runner 测试通过。测试数量减少是删除固定角色表和 EID 屏蔽用例，原生目录 ABI 回归改为 Windows 专项，Windows CI 同步执行该回归。原生测试覆盖 thiscall/ret4、字符串表 ret16、随机占位、Mod 配对／隐藏、个人进度与 scene 完整恢复、伊甸新局／续玩、动态目录刷新与异常范围拒绝。完整 Python 既有 doorway 失败仍以上文历史结果为准，本轮没有重新宣称全仓库测试全绿。

实机使用 XML-only `registered_characters` 夹具，由 `Isaac.GetPlayerTypeByName` 取得动态 ID。四端实际分别注册普通 `41`、里 `42`、带未解锁 achievement 字段的 `43` 和隐藏 `44`；普通、里和 `43` 被原生菜单收录，`44` 不出现在可选列表或目录中，锁住的原版里抹大拉也被拒绝。这些 ID 是运行结果，夹具和生产菜单不硬编码 Mod ID。画像夹具未提供菜单 ANM2，随机头像回退符合预期；Mod 自定义画像路径与动画另外由原生 ABI／Lua 菜单回归覆盖，不据此宣称所有角色 Mod 的玩法兼容性。

专用 runner 显式拒绝用户手动测试目录 `host-001/client-001`，实际使用空闲 `host-002/client-002/client-003/client-party-parallel-20261012`。每轮四端只启动一次，依次复用进程完成两人普通 Mod、三人普通／里／achievement 混选和四人里 Mod；菜单通过左右选择推进，实际角色、权威序列化和副本还原在同房与分房持续核对，普通存退后重新读取个人目录。两轮都完整恢复受保护资料，用户正在玩的两个实例没有被控制或重启。

| 轮次 | 逻辑与画面结果 | 退出与资料恢复 |
| --- | --- | --- |
| [目录 01](/mnt/d/isaac-lan-lab/pr64-character-catalog-20261014-01/report.json) | 2／3／4 人角色、菜单选择与同步逻辑通过；画面审阅发现较长 Mod 名称挤到相邻卡片，整体显示验收未通过，保留 `visual-review.json` | 四端退出 0、无 heap dump，`restored=true`；133.34 秒 |
| [目录 02](/mnt/d/isaac-lan-lab/pr64-character-catalog-20261014-02/report.json) | 名称按行和卡片宽度缩放后，所有逻辑与画面通过；重新启动仅为加载修订后的生产 DLL | 四端退出 0、无 heap dump，`restored=true`；130.51 秒 |

最终三人主机／客机／第三端画面为 [host142](/mnt/d/isaac-lan-lab/pr64-character-catalog-20261014-02/engine/host/frames/142.png)、[client117](/mnt/d/isaac-lan-lab/pr64-character-catalog-20261014-02/engine/client/frames/117.png)、[client2-92](/mnt/d/isaac-lan-lab/pr64-character-catalog-20261014-02/engine/client2/frames/92.png)，第四端里 Mod 菜单为 [client3-111](/mnt/d/isaac-lan-lab/pr64-character-catalog-20261014-02/engine/client3/frames/111.png)。所有名称保持原生值，长名称不覆盖邻卡。本轮只针对选角改动，未重复已由 11／14／15 轮验证的羔羊路线和百宝袋机制，也没有关闭上文已有沙漏问题。
