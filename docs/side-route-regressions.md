# 角色与支线集中回归

本轮针对矿一客机崩溃、里拉撒路切换后模型停住，以及里小蓝人、矿二拿刀和死寂流程。先完成离线检查，再用一对隔离进程运行全部用例；每个用例保存退出并重新创建会话，复用游戏进程。失败后记录原因，只有进程无法恢复或需要重新加载 DLL／夹具时重新启动。

## 固定流程

```sh
python3 tools/test.py --profile full
cmake --build build-win32 --parallel 2
ctest --test-dir build-win32 -L offline --output-on-failure
python3 tools/run_special_routes.py \
  --host /mnt/d/isaac-lan-lab/client-002 \
  --client /mnt/d/isaac-lan-lab/client-003 \
  --build build-win32 \
  --output artifacts/special-routes-新时间戳 \
  --mod '/mnt/d/steam/steamapps/common/The Binding of Isaac Rebirth/mods/stats-plus_2729900570' \
  --mod '/mnt/d/steam/steamapps/common/The Binding of Isaac Rebirth/mods/external item descriptions_836319872' \
  --mod '/mnt/d/steam/steamapps/common/The Binding of Isaac Rebirth/mods/goodtrip_1630477831'
```

两端目录必须闲置并带 `.isaac-lan-lab` 标记；输出必须是新目录。工具备份并恢复两端 profile、游戏 data 和联机会话目录，逐文件核对哈希。运行时使用普通 Lua 沙箱及 75 ms 单向延迟，保留 DLL、集中脚本、两端日志、连续帧和逐项报告。`--case` 可选择诊断用例，默认按下面顺序执行全部四项。

| 用例 | 必须观察到的行为 |
| --- | --- |
| `lazarus` | 客机里拉撒路清房自动切换、连续主动 Flip，分房和合房、进入矿一 Boss 房，给予长子权后准备矿二、分房并交换两具身体；两种形态都有位置变化和身体／头部动画变化 |
| `poop` | 原生按键消耗粪便，火焰及神圣粪便生成，分房、合房和换层；客机每份快照的数量、六格队列与房主一致 |
| `knife` | 矿二原生开关、矿车入口、刀片 2 拾取、妈妈的影子追逐、返回原楼层；客机保留刀片并正常同步 |
| `hush` | 主机有死寂通关计数与虚空解锁，客机没有；??? 层原生两阶段 Boss、结算后的地狱／天堂／虚空入口；使用原生出口继续推进，全队换层 |

源楼层通过 `SetStage` 和 `StartStageTransition` 准备，里拉撒路用例也用此方式准备矿二以检查换层后的对象和动画。拿刀用例先给予刀片 1，作为原生生成矿车和黄色开关的前置条件。敌人通过伤害加速击败，角色使用免伤保护；不直接生成 Boss 奖励、出口、刀片 2 或矿车。拿刀和死寂用例的开关、拾取及出口使用原生碰撞，房间间使用原生换房接口。因此报告只覆盖表中的联机流程，并非完整从第一层开始的无辅助通关；里拉撒路用例不验收基甸波次战及其原生出口。

## 本轮证据

用户崩溃日志与转储归档于 `artifacts/mines-lazarus-manual-20261010/`。堆栈落在 `inventory.lua` 的 `ChangePlayerType`；里拉撒路形态切换实际替换原生玩家对象，客机不能把另一形态当作普通类型原地重建。

修复使用原生玩家替换、重新取得当前对象、清理被 `EntityPtr` 重定向的旧运动记录，并在原生切换后及时更新角色引用。角色列表恢复保留全局位置，借用的 UI 顺序不会写回游戏角色列表。里小蓝人的数量与队列使用绝对状态恢复，不再次施法或扣除消耗品。

矿车入口另在 `special-routes-engine-20261010-r22` 复现主机崩溃。原生 `Level::ChangeRoom` 在矿二从维度 0 进入维度 1 时，先读取出发房间的 descriptor/type，再初始化目标房间；新建联机 Room 原先缺少这两项。初始化前仅传递原生所需的两个标量，不复制房间容器。镜像／矿井别名 `-100`／`-101` 由原生查询解析，使用返回 descriptor 的实际维度与网格索引；协议和房间表不存别名。离线 `core.room-transition-context` 覆盖空 descriptor、往返维度、镜像别名和大房间格子的归一化。

死寂的奖励完全由原版处理。隔离测试主机准备既往通关计数和虚空解锁，客机保持未解锁；不在 Mod 中替换首次通关宝箱、不强制生成后续路线。`special-routes-engine-20261010-r21` 已观察到原生三个入口及全队继续换层，里小蓝人同轮通过。

集中脚本的修订记录：`r23` 拾取检查早于原生举手动画结束，失败后正常收回隔离进程；`r24` 实际完成刀片拾取、追逐及 `-101` 返回，但完成检查放在探索普通门之后，漏记完成，关闭本轮自有主机以重载修正脚本。两轮均恢复并核对隔离存档。`r25` 将原生拾取完成和返回检查顺序修正后再次集中运行，生产 DLL 不为这些检查额外发放刀片或更改路线。

`r25` 四项已在同一对进程中全部通过。随后原生函数审计发现长子权使两具身体都留在角色列表时，`PlayerManager::ReplacePlayer` 直接按全局索引交换；分房列表的位置不同会越界或交换错误对象。联机调用借用完整原生角色列表，再按原生结果刷新所在房间的列表，新增离线全局置换／房间视图用例。

`r26` 在新增长子权检查中复现客机漏掉备用身体：原生激活步骤在角色更新内，而客机跳过角色逻辑更新。收到主机额外角色时，客机使用已有备用身体，按原生步骤建立相互引用并通过原生接口加入角色／房间列表，再恢复其快照；不重新创建身体或重复执行角色逻辑。离线用例覆盖 `Isaac.GetPlayer` 缺失索引返回玩家零、备用身体的控制器和重复快照。`r27` 为加载新 DLL 启动一次隔离主客机，集中验证修复和其余三项。

`r27` 四项已在同一对隔离进程中全部通过，两端正常退出，隔离目录逐文件哈希恢复一致。使用 DLL SHA-256：`7c4d8d7407552f2530c429d12336cbbf17b47bb03aee1c91fcd956d5d37215a8`，实机报告为 `artifacts/special-routes-engine-20261010-r27/report.json`。两端联机日志共 431 条，全部包含时间、时区、等级和进程 ID，原生日志目录识别正确，各自只有一条 bootstrap 记录，无 ERROR 记录。

离线报告为 `artifacts/mines-lazarus-manual-20261010/offline-birthright-r2/summary.json`：38 项 C++／Lua 检查、61 项 Python 检查和 11 项子用例通过；J460 新增原生入口签名校验通过。Windows C++／传输／日志检查记录在同目录的 `windows-offline-mineshaft-r1.log` 和 `windows-offline-birthright-r1.log`。本轮四项结果不替代完整从第一层游玩的体验验收，也不重记此前六条结局路线报告。
