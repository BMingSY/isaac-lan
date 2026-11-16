# 简化发版检查：全结局与路线机制（2026-11-01）

本次按用户指定的“简单的发版检查（全支线通关）”执行，六条结局、两种贪婪模式、矿车与 Hornfel 的双端完成证据已齐全。期间修正四处验收工具问题，按用例汇总完成结果；不是整套一次连续通过，各失败及异常退出轮次均保留。最终上行复测正常退出、无异常转储，全部隔离资料恢复并通过逐文件哈希核对。未执行安装自动加载、基础联机专项和全部竞技场 Boss 遍历，不把本记录表述为完整默认发版验收；本次未发现需要修改生产候选的新问题。

## 候选与证据

- 上次发布为 `v0.6.1`。本次生产候选为 `3d2c6e23bf4993a5d11059bdd96d6d02a499e676`，包含 #141 的移动／落点／骸骨修复及 #142 的状态采集优化；#142 已合并，候选主分支 CI 通过（运行 `41296136600`）。
- 测试修订依次为选角前置 `6a8f695c3def34cdf519af8337d71865c2ab0ee0`、照片时序 `b3378c69a0e12bc0d5c0b4fbc5a5a66cf931e23d`、原生进房后摆放 `6b86b88593e6f4d0a60643960ffb57a66e7848f4`、单路线脚本拼接 `1d7b78da4e53684762bd52345de1bea2b5e04a73`。只修改测试工具与回归；生产源码、版本和打包输入与冻结候选一致。修订与本记录归入 #143。
- 扩展 DLL SHA-256：`b3ce3dda72791531712aa523126640ca9a86f8b8b215c8f85ef52de7f92597a8`。
- 候选包 `Isaac-LAN-v0.6.1-windows-x86.zip` SHA-256：`bea944b4139eae0990e846cc041b78d273b7b2670d8f9fcff5707cbee6c3a5ba`。它沿用尚未递增的本地版本号，并非重新发布的 v0.6.1；本记录不代表已创建新标签或发布。
- 加载器 SHA-256：`83a286acc7140255e349f7a6dc42a9493d7748eddeae89c8f717056bd10bc3f4`。
- 游戏为 Repentance+ `1.9.7.17.J460`，SHA-256：`7122ac28779925b24e23e2416f231322b1470388bd25e2c08665ad8d53b3ea4f`。
- 证据标识为 `release-routes-20261101`，含冻结源码、49 个二进制文件清单、安装包、逐端日志、录帧及 JSON/XML 报告。原始产物不提交到文档目录。

## 离线与构建

`tools/test.py --profile full` 通过：150 项 CTest、547 项 pytest 和 19 个子检查，证据为 `offline`。Windows x86 Release 构建及在 Windows 下执行的 141 项 CTest 通过，包含网络和原生 ABI 检查。双端游戏入口签名、安装包结构、x86 架构和依赖校验通过。

测试前置修订的定向回归为 81 项 pytest 和 21 个子检查，证据为 `fixture-after-02.log`。新增用例先在旧 helper 上失败；首次修订后测试因 PATH 缺少 Lua 而失败，补齐本地检查工具 PATH 后全部通过，原始失败日志保留。格式、脚本语法、PowerShell 格式及 `git diff --check` 通过。PowerShell 使用进程级 `-ExecutionPolicy Bypass`，没有修改持久策略。

照片时序修订补充 12 项状态机用例：三条相关路线分别覆盖客机提前持有照片、底座仍在、照片缺失、只有另一玩家持有。旧实现在三个提前拾取用例中复现失败，其余九项通过；修正后 `tests/test_tools.py` 与 `tests/test_native_harness.py` 共 83 项及 21 个子检查通过，证据为 `photo-before.log`／`photo-after.log`。

修订提交 `b3378c6` 的 CI 运行 `41298669699` 全部通过：包含 sanitizers 的离线 150 项 CTest、559 项 pytest 和 21 个子检查，以及 Windows 141 项 CTest；日志保存为 `fixture-ci.log`。

后续门口停留与脚本拼接问题均补充离线复现。门口用例需模拟异步换房完成时原生重新放置玩家；初版 mock 在请求发出时放置，被原有代码覆盖，未能复现，修正 mock 后旧实现失败、新实现通过。脚本拼接用例直接执行经过 `bundle_input` 的单路线产物，旧实现失败、新实现通过。最终定向结果为 85 项及 21 个子检查通过，证据为 `doorway-before-02.log`／`doorway-after-02.log`、`bundle-before.log`／`bundle-after.log`；格式与脚本语法检查通过。

最终测试代码 `1d7b78d` 的 CI 运行 `41300679311` 全部通过：包含 sanitizers 的 150 项 CTest、561 项 pytest 和 21 个子检查，以及 Windows 141 项 CTest；证据为 `final-fixture-ci.log`。

## 实机范围与结果

使用已有归属标记的 `all-room-gather-host-20261027-pr`／`all-room-gather-client-20261027-pr` 隔离对，由一个执行者调度；每轮复用同一对进程和连接。端口为 `34720/34721`，前三轮双向各延迟 40 ms，单路线复测按工具默认各 75 ms；开启堆异常监测及双端 500 ms 录帧。运行前备份配置、存档及日志，没有控制用户手动游玩的实例。

入口为 [run_special_routes.py](https://github.com/BMingSY/isaac-lan/blob/main/tools/run_special_routes.py)，通过 `--case endings --first-floor` 将六条结局与其他路线合并执行。采用工具的隔离注入入口：此前自动加载受本机 DLL 搜索策略阻挡，详见[开发专项记录](https://github.com/BMingSY/isaac-lan/blob/main/docs/history/2026-11-01-player-travel-and-forgotten.md)。本次没有修改该策略，也没有把注入成功记作安装自动加载通过。

上行定向复测使用 [run_endings.py](https://github.com/BMingSY/isaac-lan/blob/main/tools/run_endings.py) 的 `--route ascent`，为该入口补齐显式 `--injected` 选项，默认仍保留自动加载。

| 轮次／范围 | 结果 |
| --- | --- |
| `routes-01`：Greed、Greedier | 两端均完成 1–7 层；普通模式触发原生 Boss 阶段 0，困难模式触发阶段 0／1；两端均有胜利、原生退出回调、本地进度恢复和 PASS 标记 |
| `routes-01`：切换到矿车场景 | 客机选择未解锁的 Azazel 被拒绝，夹具断言失败；整轮保留失败，矿车、Hornfel 和六条结局未完成，不计通过 |
| `routes-02`：矿车、Hornfel、六条结局 | 矿车与 Hornfel 双端完成；羔羊在第六层的照片处理等待超时，结局未完成，整轮保留失败 |
| `routes-03`：矿车、Hornfel、六条结局 | 矿车、Hornfel 及羔羊、???、Delirium、Mega Satan、Mother 双端完成；上行第一层战后客机离开 Boss 房，夹具等待出口超时，整轮保留失败 |
| `routes-04`：上行单路线启动 | Lua 产物拼接导致初始化报 `attempt to call a table value`；未进入场景、客机未启动，不计通过 |
| `routes-05`：上行 | 双端完成正常楼层、阳片／特殊门、爸爸的便条、返程、Home、Dogma、四骑士及 Beast；均有原生胜利回调、会话清理和本地进度恢复，整轮通过 |
| 退出与恢复 | `routes-01`、`routes-05` 两端退出码及堆监测退出码均为 0；`routes-02`、`routes-03` 清理时双端需强制终止，退出码 `FFFFFFFF`、堆监测退出码 5；`routes-04` 主机由工具正常关闭、退出码及堆监测退出码为 0。各轮无转储，隔离资料逐文件哈希恢复通过，最终无残留所属进程 |

两种贪婪模式的已完成用例从 `routes-01`、矿车／Hornfel 及前五条结局从 `routes-03` 的归档日志独立提取。各结局均须同时满足双端胜利、会话清理、本地进度恢复；已完成用例不改变所在整轮的失败或异常退出状态。第三轮后的修正仅定向复测上行，最终汇总保留各轮原始状态及用例来源，不声称整套一次连续通过。

羔羊双端实际经过第 1–8、10、11 层，`CAMPAIGN_PASS first_floor=1` 完整；Delirium 双端经过第 8、9、12 层，包含 Hush 与虚空；Mother 双端经过水一／二、矿一／二、陵墓一／二，`missing_alternate_floors` 均为空。六条路线的双端 `win`、`cleanup`、`progress` 均为真，证据为 `route-summary.json`。该汇总同时保留 `all_rounds_passed=false`，不隐藏失败。

最终再次核对冻结清单内 49 个二进制文件及候选包 SHA-256，均未变化，生产源码／版本／打包输入差异为空。五轮恢复清单与第一轮原始基线一致，证据为 `restoration-verification.json`。

冻结执行脚本 SHA-256：

| 轮次 | SHA-256 |
| --- | --- |
| `routes-01` | `e10391ecb1006034e6559f03be5158c323e60c2cfc74444d664eeecea7f247ac` |
| `routes-02` | `7be2fd8bd68c25721d4ca18679b08780cfd842cb2a9f79f0039ed132366cfe67` |
| `routes-03` | `b60e08334b3e6b10b430e5e75c3a8c61c2a0210a312b4705b6ce115828e809bb` |
| `routes-04` | `50d947d235f390c41f0392b4c9c60aaf50a83576700b030d2a7c4d41485df76d` |
| `routes-05` | `fe9f570f492154033320259aab49360f9cc20640457bca85e3b123c4e07b844b` |

## 前置修订与重启

矿车夹具要求客机使用 Azazel，但原隔离存档未解锁该角色，现有结局夹具保留客机个人解锁状态。首轮在调用选角接口时被正常拒绝，错误位置为 `app/main.lua:601`；不是本次生产候选的断线或崩溃。

[progress_fixture.py](https://github.com/BMingSY/isaac-lan/blob/main/tools/progress_fixture.py) 现仅为明确选择矿车场景的受管客机准备所需解锁，并在游戏启动前写入已有校验与备份保护的隔离存档。主机及其他客机解锁字段保持原值；回归核对其他字节、计数与校验和。生产权限检查未放宽。首轮正常关闭并恢复资料后，因角色目录在启动时初始化而重新启动复测。

第二轮中，妈妈原生死亡后生成阴片，日志明确记录客机 `Adding collectible 328 (The Negative) to player 1`。夹具在战利品等待时间结束后才查找底座，没有识别已经拾取的阴片，最终报 `Route stalled at boss-loot stage=6:0`。修正只让夹具接受客机已持有目标照片的状态；仍须原生拾取目标照片，不生成照片或路由标记。失败结束了会话，且进程清理需要强制终止，因此保留异常退出并重新启动第三轮，不把第二轮记作正常退出通过。所有轮次使用同一冻结 DLL。

第三轮的上行第一层，日志记录 Little Horn 正常死亡后客机进入了相邻普通房间；画面与位置记录确认客机房间从 Boss 房 123 变为 110。夹具在那里清完杂兵并等待不存在的楼层出口，报 `Route stalled at boss-loot stage=1:2`。原有摆放发生在异步换房请求发出时，原生到达会覆盖位置。修正于确认到达、进入脚本战斗前将测试角色放到房间内部并清除速度；保留原生场景转场和终点移动检查。因失败已结束会话并需强制清理，改为单独复测尚未完成的上行路线。

第四轮未进入场景：单路线产物以括号表达式开头，拼接输入支持代码后被 Lua 当作上一调用的继续调用。为输入支持的末尾增加明确语句边界，补充同一拼接产物的离线回归后重启第五轮。第四轮错误来自场景初始化，工具超时后正常关闭主机，不将其描述为原生崩溃或成功启动。

## 画面与限制

- **仍可复现的既有画面差异**：Ultra Greedier 击败后，主机显示金色地面及金币贴花，客机保留木地板。`routes-01` 主机帧 1411／客机帧 1379 可见该差异；阶段二战斗抽查为主机帧 1396／客机帧 1363。结局和清理正常，画面差异未修复，与[上一版记录](https://github.com/BMingSY/isaac-lan/blob/main/docs/history/2026-10-28-v0.6.1.md)一致。
- Mother 双端抽查为 `routes-03` 主机帧 2465／客机帧 2431，Beast 为 `routes-05` 主机帧 1136／客机帧 1106；Boss、玩家和攻击可见，镜头与相邻动画帧有差异。抽查不代表逐帧动画一致。
- 上版首次安装启动 `0x35` 的偶发未定位退出保留；本次注入路线检查不覆盖该入口。
- 本次没有执行全部 107 个竞技场 Boss、安装自动加载／基础联机专项、道具／角色／第三方 Mod 专项或性能压力测试；不据此声称所有兼容性通过或给出 FPS 提升比例。
- 移动与骸骨开发回归独立见[专项记录](https://github.com/BMingSY/isaac-lan/blob/main/docs/history/2026-11-01-player-travel-and-forgotten.md)，不重复计入本次路线检查。
