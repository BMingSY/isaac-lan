# 开发与测试

BUG 修复、需求新增和日常重构按影响范围执行离线回归与必要的局部实机验证。发版默认只覆盖基础联机、全部 Boss 和正常结局／路线，不重复开发专项。离线通过不代表实机通过；任务要求不启动游戏时，实机项记为未执行。协作和发布约定见 [AGENTS.md](https://github.com/BMingSY/isaac-lan/blob/main/AGENTS.md)。

## 构建与产物

构建命令见[项目 README](https://github.com/BMingSY/isaac-lan/blob/main/README.md#源码构建)：C++20、Windows x86 工具链，以及指定版本的 Dear ImGui／MinHook 源码。CMake 默认启用 `BUILD_TESTING`，只构建产物可设为 `OFF`。

| 产物 | 用途 |
| --- | --- |
| `winmm.dll` | 自动加载与系统导出转发 |
| `isaac_lan_probe.dll` | 原生后端、网络与嵌入 Lua |
| `isaac_lan_check.exe` | 安装时校验游戏 PE、版本及布局 |
| `isaac_lan_net_test.exe` | 无需游戏的真实 Winsock 测试 |
| `isaac_lan_lab.exe` | 隔离实例启动与验收 |

[`tools/build_package.py`](https://github.com/BMingSY/isaac-lan/blob/main/tools/build_package.py) 打包前三项、安装脚本、README、FAQ 和许可证。游戏文件、存档、测试产物与构建目录不提交。加载器在扩展初始化后恢复游戏入口，游戏对象／Lua／网络轮询在主线程处理。原生改动须核对调用约定、布局、签名和所有权，见[分层约定](https://github.com/BMingSY/isaac-lan/blob/main/docs/layers-and-compatibility.md)。

## 离线测试

需要 Python 3.10+、CMake、C++ 编译器和 **Lua 5.3**；Lua 版本不符时检查失败。Linux 原生编解码对照另需 Lua 5.3 开发库（Ubuntu 的 `liblua5.3-dev`；非标准安装可设置 CMake 的 `LUA_INCLUDE_DIR`／`LUA_LIBRARY`）。安装 Python 依赖，并将 [StyLua 2.0.2](https://github.com/JohnnyMorganz/StyLua/releases/tag/v2.0.2) 放入 `PATH`：

```sh
python3 -m venv .deps/checks
.deps/checks/bin/pip install -r tools/requirements-ci.txt
.deps/checks/bin/python tools/test.py
```

统一入口执行格式、语法、`offline` 标签的 CTest 和 pytest，复用 `build-offline`，不会导入游戏启动器或读取游戏存档。

| 选项 | 用途 |
| --- | --- |
| 默认 `--profile fast` | 日常和 PR；属性测试生成预算 25 例、状态机最多 20 步 |
| `--profile full` | 扩展检查；预算 200 例、状态机最多 60 步 |
| `--list` | 只列 Python 用例 |
| `--list-engine` | 按文件名发现实机入口和 Lua 场景；不执行场景 |
| `--sanitizers` | 为可移植 C／C++ 构建启用 ASan／LSan／UBSan；CI 使用此选项 |
| `--jobs N` | 构建、CTest 和 pytest 的并行数；默认最多 4，`--jobs 1` 顺序执行 |

CI 的 Linux 离线检查与 Windows 交叉编译同时运行；Windows 测试依赖编译产物。构建使用 ccache，缓存按工具链和构建配置隔离；工具依赖按固定版本缓存。pytest 使用独立进程调度用例，失败回放按 worker 分目录保存。

Windows 测试清单以 CMake 的 `add_test` 注册为唯一来源。[bundle_ctest.py](https://github.com/BMingSY/isaac-lan/blob/main/tools/bundle_ctest.py) 打包原生可执行文件、参数、标签、超时和调度属性，生成可搬移的 CTest 目录；Lua 用例由 Linux 检查运行。Windows runner 用 CTest 并行执行该清单，各用例使用独立工作目录，保留 JUnit 和失败日志。网络加载超时、结局与过场保活仍检查真实时间，独立用例的等待可重叠；UDP 丢包和大包恢复同样包含在注册清单中。

Hypothesis 还会运行缓存失败样例和缩减步骤，上述预算不是精确执行次数。按改动选择局部检查：

```sh
.deps/checks/bin/python -m pytest -m state -q
.deps/checks/bin/python -m pytest -m behavior -q
.deps/checks/bin/python -m pytest tests/offline/test_behavior.py -k saved_stall -q
.deps/checks/bin/python tools/check_scripts.py
```

只运行可移植 C++／Lua 检查，无需 Windows 工具链或游戏依赖：

```sh
cmake -S . -B build-core -G Ninja \
  -DISAAC_LAN_BUILD_ENGINE=OFF -DCMAKE_BUILD_TYPE=Debug
cmake --build build-core
ctest --test-dir build-core --output-on-failure
```

| 层次 | 覆盖 | 边界 |
| --- | --- | --- |
| C++／Lua 组件 | 编码、协议、存档、作用域、生命周期、库存、实体与 API | 不验证原生 ABI、物理和画面 |
| pytest／Hypothesis | 工具、生成动作序列、持续移动与固定失败回放 | 模型给出独立预期；不等同游戏引擎 |
| Windows 传输 | 真实 UDP、输入事件、积压、重连、事务顺序及 UDP 丢包／乱序 | 不启动游戏 |
| 隔离实机／正常操作 | 原生机制、入口与连续画面 | 结果限定于所用版本、夹具和采样范围 |

离线场景通过 [`tests/offline/lua_worker.lua`](https://github.com/BMingSY/isaac-lan/blob/main/tests/offline/lua_worker.lua) 执行生产 Lua，[离线夹具](https://github.com/BMingSY/isaac-lan/tree/main/tests/fixtures) 提供有限接口和虚拟时间。新问题优先补能复现它的离线用例，再决定原生验收范围。

Lua 夹具的输入编解码统一使用 [`tests/support/input.lua`](https://github.com/BMingSY/isaac-lan/blob/main/tests/support/input.lua)：`neutral` 提供空输入，`buttons` 构造按键掩码，`encode`／`decode` 读写 `values`、`triggered` 和 `pointer`。动作索引与 `ButtonAction` 一致，玩家槽位从 0 开始；场景不自行拼接字段或计算字节偏移。实机启动器将该模块注入为 `_IsaacLanTestInput`，与场景一起冻结到测试脚本；离线测试通过同一模块注入依赖。`bridge.input-wire` 对照生产 C++ 编码，检查字段、默认值和多玩家布局，协议调整集中修改该模块并通过契约校验。

Linux 的 `bridge.native-codec` 在真实 Lua 5.3 中加载生产 C++ 绑定，执行原生与 Lua 参考编码的逐字节对照、共享片段、边界／非法输入、分配失败及恢复检查；它通过统一离线入口运行，sanitizer 同时检查绑定和缓冲区的释放。性能比较使用 Release 构建，方法见[诊断参考](https://github.com/BMingSY/isaac-lan/blob/main/docs/diagnostics-and-resource-testing.md#编解码基准)。

聊天改动的直接回归为 CTest `presentation.chat-input`、`presentation.chat-render`、`bridge.chat`、`bridge.chat-dice`、`diagnostics.*`、`bridge.resume`，以及 Windows `presentation.chat-native-input`（输入法组合状态下开关、按键重复与焦点释放）、`presentation.chat-background`、`net.communication`／`net.integrations`：覆盖 UTF-8 编辑、输入释放、背景配置与 PNG 加载／回退、HUD 避让、拖动与尺寸变化、输出可见性、混合骰与奖惩骰、掷骰去重、同房／同维度筛选、原版命令分发和过期上下文。掷骰与房间共享使用 [state_chat_dice.lua](https://github.com/BMingSY/isaac-lan/blob/main/tests/state_chat_dice.lua)，在同一连接中核对普通／混合／奖惩骰、同房接收、分房隔离和汇合后的接收；保留两端画面并对照完整结果。原生执行与画面使用 [state_chat.lua](https://github.com/BMingSY/isaac-lan/blob/main/tests/state_chat.lua)，由隔离双端 runner 加载并保留双端画面；夹具开启属性栏、物品栏和最大 HUD 偏移，并通过原版轮盘选择 D6。输出 `CHAT KEYBOARD_READY` 后，对各自所属窗口依次输入 `~`、A、Enter、`~`；随后聚焦主机，打开输入并将记录区域向右上拖动，再关闭输入。960×540 客户区可使用 [lab_window.ps1](https://github.com/BMingSY/isaac-lan/blob/main/tools/lab_window.ps1) 的 `-Action Drag -Value '220,350:300,320'`，其他尺寸按客户区像素换算。完成键盘与拖动操作后，在两端隔离游戏目录的 `isaac-lan/chat-interaction.done` 写入完成标记；夹具等待该标记后检查结果，避免窗口操作耗时造成提前断言。完成标记为 `LAN_NETWORK PASS chat console`。背景检查可在一端配置自定义 PNG、另一端保留默认值，对照默认纯色、自定义图片和透明度。实机需核对遮挡、光标、D6 滚动与结果画面及双端相同结果；系统输入法候选仍需单独核对，脚本通过不能代表 IME 或画面通过。

`/tp` 的离线定向回归为 `bridge.teleport`、`bridge.chat`、`bridge.resume`、`bridge.party-startup` 与 `bridge.layers`；覆盖实际聊天请求链路、坐标方向、大房间与缺角、维度隔离、已生成特殊房间、重复请求、队友落点及跨层／退出清理。原生迁移与画面使用 [state_teleport.lua](https://github.com/BMingSY/isaac-lan/blob/main/tests/state_teleport.lua)，由 [run_teleport.py](https://github.com/BMingSY/isaac-lan/blob/main/tools/run_teleport.py) 在一组受保护的主客机进程中验证，指定 `--host`、`--client`、`--build`、`--output`、独立 `--port`，使用 `--heap-check --record` 保留异常与画面证据。

## 失败记录与回放

统一运行按当轮归档保存阶段日志、耗时、`summary.json`、`ctest.xml`、`pytest.xml` 和失败请求。回放命令：

```sh
.deps/checks/bin/python tools/replay_offline.py "$ISAAC_FAILURE_RECORD"
```

旧输出只作诊断。确认失败条件后，将请求加入 [`tests/offline/replays/`](https://github.com/BMingSY/isaac-lan/tree/main/tests/offline/replays) 并写明确预期，不能把已知错误固化为正确答案。

## 格式与 CI

代码采用四空格缩进，Actions YAML 为两空格；规则见 `.editorconfig` 和各格式配置。

```sh
PATH="$PWD/.deps/checks/bin:$PATH" python tools/format.py
PATH="$PWD/.deps/checks/bin:$PATH" python tools/format.py --check
```

Windows PowerShell 检查使用 PSScriptAnalyzer 1.24.0：

```powershell
Install-Module PSScriptAnalyzer -RequiredVersion 1.24.0 -Scope CurrentUser -Force
./tools/format_powershell.ps1 -Check
```

[`ci.yml`](https://github.com/BMingSY/isaac-lan/blob/main/.github/workflows/ci.yml) 在 Linux 检查格式、语法、离线场景和 ASan／LSan／UBSan，在 Windows 构建 x86 产物、校验安装包并执行真实传输测试。PR 默认 `fast`，手动 CI 可选 `full`；报告及失败请求作为产物保存。Windows 流程由 [`build-windows.yml`](https://github.com/BMingSY/isaac-lan/blob/main/.github/workflows/build-windows.yml) 复用，均不需要游戏文件。

Windows 构建后，在能运行 Windows EXE 的环境执行：

```sh
ctest --test-dir build-win32 --output-on-failure
./build-win32/isaac_lan_net_test.exe floor-rejoin
```

测试程序不带用例名时运行全部传输测试，通过标记为 `ALL STATE TRANSPORT TESTS PASSED`。

## 最终实机验收

### 用例与执行工具

[`engine_test.py`](https://github.com/BMingSY/isaac-lan/blob/main/tools/engine_test.py) 提供统一发现、计划和执行入口；套件保留各自的参数与验收条件：

```sh
python tools/engine_test.py list
python tools/engine_test.py plan special-routes -- --case motion --case floor-items
python tools/engine_test.py run special-routes -- \
  --host "$ISAAC_HOST_LAB" --client "$ISAAC_CLIENT_LAB" \
  --build build-win32 --output "$ISAAC_RUN_OUTPUT" \
  --case motion --case floor-items --heap-check
```

`list` 和 `--list-engine` 通过 [`discovery.py`](https://github.com/BMingSY/isaac-lan/blob/main/tools/testing/discovery.py) 自动扫描 `tools/run_*.py` 和 `tests/state_*.lua`；排除底层后端 `run_network_engine.py`，并兼容 `manual_gameplay.py`、`validate_replica.py` 两个旧入口。新增、删除或重命名文件后，下次发现立即生效，无需登记清单。套件名由文件名去掉 `run_` 前缀、将下划线换为短横线得到，例如 `run_release_acceptance.py` 对应 `release-acceptance`。

发现过程不导入执行器或执行 Lua。`plan` 只显示选中入口和命令；`run` 才调用该入口，路径、参数和准备条件由入口校验。文件被发现不代表它能与其他场景组合，也不代表已执行或通过。场景选择、顺序与完成条件在所属执行器／构建器中维护；进程复用与焦点安排见下方验证约定。

公共实现位于 [`tools/testing/`](https://github.com/BMingSY/isaac-lan/tree/main/tools/testing)：启动命令和子进程收尾由 `engine.py` 管理，原生资料准备函数放在 `profiles.py`，报告由 `results.py` 写入。具体入口保留场景选择、必要准备与效果断言，调用公共模块，不从其他执行入口导入共享实现。原有 `run_*.py` 命令可直接使用。

组合 Lua 场景返回 `{ done = function, cleanup = function }`：`done` 返回布尔值，只有实际断言完成才能返回 `true`；`cleanup` 可省略，负责所属文件、外部 Mod 包装和输入适配的释放。共享的 [`scenario.lua`](https://github.com/BMingSY/isaac-lan/blob/main/tests/support/scenario.lua) 隔离场景参数、跟踪场景注册的回调并保证清理只执行一次；准备或执行失败也清理已注册回调。场景参数通过数据传入，组合器不替换场景源码，也不依赖内部完成变量名或 PASS 日志判断结束。

连续玩法组合器在同一局内切换兼容场景，保持绝对网络 tick，仅为夹具转换相对时间；路线组合器在同一组进程中等待原生退出与菜单恢复后再切换。独立启动配置、真实键盘焦点和性能隔离要求仍属于套件执行边界，不能将任意套件直接合并。

`special-routes` 可组合 `local-hud` 和 `guest-visuals` 检查跨房、换层与角色外观；`--record-relay` 配合正数 `--latency-ms` 保存原始传输；`datagrams.bin` 按大端 `double 时间戳 + u8 方向 + u16 长度 + 原始报文` 记录。`item-audit` 与 `special-routes` 默认验证自动加载；若测试宿主的 DLL 搜索策略阻止本地代理加载，可显式选择 `--injected`，只向刚创建的有归属隔离进程注入。该模式不计为自动加载验收，启动参数保留在报告中。

`entity-fields` 使用泪弹、跟班和效果实体，对照游戏 Lua 属性、原生数组与数值块的读写结果，检查完整动画往返、错误输入不写入及外层编解码；它不作性能验收，可与其他功能场景共用进程。`lazarus` 在启动前仅为隔离客机准备所需角色解锁，并在进入联机前核对菜单可选项；存档仍由套件备份和恢复。

`action-prediction` 用正常客机输入和实际拾取覆盖主动、卡牌、正负药丸、道具／饰品／卡牌／药丸拾取及举起类主动，核对房主使用回调、拾取结果、两端动作姿态和客机连续帧移动。`--latency-ms 75` 为两个方向各增加 75 ms；延迟中继本身增加约 150 ms RTT。它检查动作期间及结束后的移动连续性，不预测道具效果或提前确认拾取。

`attached-motion` 用正常客机移动、点按、蓄力和松键覆盖骸骨、妈刀、圣剑、硫磺火、科技、科技 X 与虚空之喉。它检查武器相对预测身体的位置、激光世界路径／终点及命中特效，并确认独立激光不被绑定到身体。推荐与 `--latency-ms 75 --record-client --heap-check` 配合；场景逐项核对两端实际生成的攻击，不以仅完成会话视为通过。

`attack-response` 测量普通泪弹、硫磺火、妈刀、科技 X、多发与圣剑的按键至朝向、初次泪弹、蓄力和松键显示时间，核对预测弹接管及真实实体归属；`attack-mirror` 在水层镜面房间复用普通泪弹检查。使用 `--latency-ms 40 --performance --record-client --heap-check`，中继每方向延迟 40 ms，合计约 80 ms RTT。可与 `attached-motion` 在同一对进程运行；画面需对照镜像位置与接管前后弹幕。离线检查为 `presentation.attack-prediction`、`presentation.attacks` 及 Windows `native.pause-menu`，覆盖冷却、重复确认、取消、换武器、超时、视图清理和输入作用域恢复。

`tear-trajectory` 用正常射击输入覆盖静止、横向往返、0.6／1.6 弹速、尿一／妈妈的高跟鞋改变射程及快速点射。每组停止射击后等待确认完成，要求产生的预览全部接管，并分别核对超时、碰墙和落地计数。与 `attack-mirror` 复用进程检查镜面；沿用每方向 40 ms 的中继。离线 `presentation.tear-motion` 对照 [tear_motion.csv](https://github.com/BMingSY/isaac-lan/blob/main/tests/fixtures/tear_motion.csv) 中的原生轨迹，验证弹速、惯性和纵向运动；`presentation.attack-prediction` 对照原生小数冷却的发射时刻。

`weak-network` 用正常客机输入核对八次主动道具使用不丢失、不重复，以及状态／库存恢复和停止后的预测收敛。使用 `--latency-ms 45 --relay-control tests/fixtures/udp_weak_network.json --case weak-network --case motion` 在同一对进程检查碰墙／松键。[UDP 中继](https://github.com/BMingSY/isaac-lan/blob/main/tools/datagram_relay.py)实际丢弃完整报文、复制报文并按抖动后的时间重排；停传窗口表示突发丢包，排队超过 500 ms 或容量上限也会丢弃。[配置](https://github.com/BMingSY/isaac-lan/blob/main/tests/fixtures/udp_weak_network.json)包含基础 RTT 90 ms、每方向 ±20 ms 抖动、双向限速、5% 丢包和 2% 重复。现场 Ping 还包含调度开销；无损对照移除丢包、抖动与限速。离线 `net.udp-loss` 通过真实套接字覆盖缺片、重排、重复、可靠按键计数、压缩基线恢复和换层。`net.udp-large-recovery` 使用约 88 KiB 的变化区，在 180 tick 测量窗口后另行停传 30 tick，确认视图已滞后，再恢复中继并要求 8 秒内收到停传之后的新状态；测量窗口中的吞吐与已收到视图间隔仍单独检查，恢复期间继续丢包／复制并逐字节核对内容。它不将低频恢复判定为可游玩的刷新率。

弱网报告同时记录到达时的状态年龄、相邻应用间隔和按时间加权的视图年龄；后者计入等待下一份状态期间持续变旧的时间，避免降低发送频率后仅靠到达样本得出改善结论。时间来自同一 Windows 机器上的隔离主客机，不能直接用于不同机器而未校准的时钟。对照须使用相同场景和中继配置，分别冻结构建及夹具，保留每轮失败和恢复记录。

受保护的实机入口在 `finally` 中等待所属后端收尾，再恢复资料并核对哈希，统一输出 `report.json`、`restored.json` 和 `junit.xml`。报告的 `schema_version` 为 `1`，`status` 区分 `passed`、`failed` 和 `error`，保留各套件原有双端证据和详细结果。JUnit 表示整次套件结果；道具效果、路线与 Boss 覆盖仍读取详细报告。未完成的子项、原生异常或恢复失败不能由一个完成标记覆盖。

### 验证安排

1. 完成代码、离线检查和构建，列出行为、预期与准备条件；日常 PR 只跑相关场景，发布执行下表默认范围，并列明必要专项。
2. 主客机各启动一次，共用兼容场景；用例之间清理夹具、恢复状态。只有启动／退出检查或进程无法恢复时才重启，并记录原因。
3. 分别记录通过、失败、阻塞、未执行及证据。冻结 DLL、脚本和哈希，使用新的输出目录；保留双端日志、状态、连续帧和退出结果。

### 默认发版范围

先执行 `python tools/test.py --profile full`、Windows x86 构建、网络／原生 ABI 测试与安装包校验，冻结候选及产物哈希。实机默认检查以下范围：

| 范围 | 入口与通过条件 |
| --- | --- |
| 基础联机 | [run_release_acceptance.py](https://github.com/BMingSY/isaac-lan/blob/main/tools/run_release_acceptance.py)：安装／自动加载、战斗／拾取、分房／换层、五类沙漏、暂停及单人／联机存档隔离 |
| 全部结局 | [run_endings.py](https://github.com/BMingSY/isaac-lan/blob/main/tools/run_endings.py)：羔羊（`--first-floor`）、???、Delirium、Mega Satan、Mother、上行至 Beast；双端实际完成路线、原生结局、清理和进度恢复，Mother 经过完整支线楼层 |
| 全部 Boss | [run_bosses.py](https://github.com/BMingSY/isaac-lan/blob/main/tools/run_bosses.py)：完整 [boss_catalog.json](https://github.com/BMingSY/isaac-lan/blob/main/tests/fixtures/boss_catalog.json)，包含原生阶段机制；用 [check_boss_coverage.py](https://github.com/BMingSY/isaac-lan/blob/main/tools/check_boss_coverage.py) 合并 Boss、结局与贪婪结果，主客机均无缺项 |
| 正常路线机制 | [run_special_routes.py](https://github.com/BMingSY/isaac-lan/blob/main/tools/run_special_routes.py) 选 `greed`、`greedier`、`knife`、`hornfel`：两种贪婪全程、矿车／逃亡、持有炸弹、跨层与重连 |

Boss 整组时限按用例数量预留加载与转场时间，单项进度断言独立生效。整组因人工停止或总时限结束且双端正常退出、资料恢复成功时，覆盖工具可通过 `--partial-arena` 读取原始双端日志，只保留已完成且无重复的单项断言；缺少一端、断言失败和异常退出不计入。原整组报告保持失败，剩余用例用 `--case` 补跑，再汇总全部覆盖。

错误技、达摩剑、创世纪、小夜灯，EID／举袋／水流／切窗口暂停，道具与弹幕压力，输入响应／镜头，以及全道具／卡牌／药丸／角色／Mod 遍历均不列入发版检查，也不因版本包含相关改动而自动追加。用户明确要求时再增加发布专项。已有开发回归结果可以引用，旧验收记录和未决问题保持原结论。完整规则见 [AGENTS.md](https://github.com/BMingSY/isaac-lan/blob/main/AGENTS.md#发布前验收范围)。

## 开发专项入口

房间共享效果使用 [run_room_rules.py](https://github.com/BMingSY/isaac-lan/blob/main/tools/run_room_rules.py)，指定 `--host`、`--client`、`--build`、`--output` 和独立 `--port`，可加 `--heap-check --record`。工具固定模拟 80 ms RTT，在同一对进程中验证清房充能、分房、主动槽位、充能修正、沙漏回退、普通掷骰与运气挑战，然后仅为启动时读取本机偏好重启一次；两个端口分别用于主机与延迟代理。全部结束后恢复隔离资料，任一阶段失败不计通过。离线对应 `bridge.clear-charge`、`bridge.luck_game`、`presentation.connection-settings`、`core.room-options-marks`。

特殊房间集合使用 [run_teleport.py](https://github.com/BMingSY/isaac-lan/blob/main/tools/run_teleport.py) 的 `--gather` 模式，复用同样的隔离目录、构建、产物与端口参数，配合 `--heap-check --record`。一组主客机验证走门、Joker 和 `/tp` 触发集合、普通房与普通红房不触发、特殊房离开与重入、地图外房间、同时进房和换层后再次集合；双端均确认到达后才继续。离线对应 `bridge.special-room-gather`、`bridge.teleport`、`bridge.clear-charge`、`bridge.luck_game`、`bridge.challenge_menu`、`presentation.connection-settings`、`core.room-options-marks` 与 Windows `net.room-options`。

运气游戏使用 [run_luck_game.py](https://github.com/BMingSY/isaac-lan/blob/main/tools/run_luck_game.py)，指定 `--host`、`--client`、`--build`、`--output` 与独立 `--port`，可加 `--heap-check --record`。同一组主客机覆盖挑战开局、开局吞下禁令、非主动底座拾取、购买代价与二选一、主动拾取跳过掷骰、主动转移充能、幸运上升药丸、换层赠送、分房发放、重连和妈腿奖杯退出；工具保护并恢复隔离资料。离线对应 `bridge.luck_game`、`bridge.challenges`、`bridge.challenge_menu`、`bridge.chat`、`core.challenge-rules` 与 Windows `native.item-effects`。

以下入口用于开发修复时的定向回归，不属于发版清单。只选择受改动影响、需要排查或用户明确要求的场景，记录具体用例，不自动运行整个专项目录。

| 领域 | 入口与范围 |
| --- | --- |
| 菜单输入与怪物显示 | [state_npc_motion.lua](https://github.com/BMingSY/isaac-lan/blob/main/tests/state_npc_motion.lua) 配合 `run_network_engine.py --frontend --menu-start --exercise-menu --exercise-lobby-chat --virtual-input --latency-ms 40 --native-record-both --heap-check`，使用独立端口并由 `ProtectedLabs` 保护资料。菜单驱动依赖 LuaDebug 的隔离输入文件，不能搭配 `--no-luadebug`；同一对进程验证地址中 M/F 不改音量／全屏、端口校验、种子编辑与大厅聊天，再采集蜘蛛、冲锋怪、攻击蝇的权威目标和双端轨迹。完成标记为 `LAN_NETWORK NPC_PROBE PASS native pursuit and display capture`；对照轨迹与画面，不以采集完成代替误差结论。离线 `presentation.npc-motion` 使用 [npc_motion.csv](https://github.com/BMingSY/isaac-lan/blob/main/tests/fixtures/npc_motion.csv) 回放原生轨迹，检查制动误差、跳包、重复状态与轨迹清理 |
| 输入与镜头 | [run_response_acceptance.py](https://github.com/BMingSY/isaac-lan/blob/main/tools/run_response_acceptance.py)：直连／约 20 ms RTT、输入预览、移动／过门、暂停、主动、蓄力和大房间／镜面；需要画面时用 `--record-view`。[run_special_routes.py](https://github.com/BMingSY/isaac-lan/blob/main/tools/run_special_routes.py) 的 `input-response-speeds` 在同一局测试 0.6、1.3、2 三档移速的加速、松键与转向；离线 `bridge.prediction` 对照原版运动采样。多身体预测用 [state_multi_actor_prediction.lua](https://github.com/BMingSY/isaac-lan/blob/main/tests/state_multi_actor_prediction.lua) 检查双子、骸骨切换及魂石身体的生成／退场 |
| 鼠标与地址记忆 | [run_mouse_input.py](https://github.com/BMingSY/isaac-lan/blob/main/tools/run_mouse_input.py)：指定 `--host`、`--client`、`--build`、`--output` 和独立 `--port`；真实鼠标步骤独占焦点。主客机分别点击并反向瞄准，检查原版四向泪弹、输入归属与松键；重启一对进程验证地址文件回填，第二轮同时用 Analog Stick 检查自由瞄准。两轮均保留双端画面和堆异常证据，结束恢复并核对隔离资料。离线对应 `presentation.connection-settings`、`bridge.challenge_menu`、`core.pointer-input`、`native.mouse-input`、UDP `net.render-inputs` 与 `net.floor-rejoin` |
| 客机重连 | [state_client_recovery.lua](https://github.com/BMingSY/isaac-lan/blob/main/tests/state_client_recovery.lua) 通过 `run_network_engine.py --frontend --menu-start` 复用一组进程，检查虚拟控制器延迟就绪、新局角色归属、客机单独传送进恶魔房后的主动重连、恢复失败后的手动重试、意外掉线恢复、菜单提示与离开；恢复后再验证投票重开及通关返回大厅的共同退出边界，不代替 Boss／结局路线验收。原生退出不重启进程。执行前用 `ProtectedLabs` 保护隔离资料，收尾后恢复并核对哈希 |
| 过门输入与预测 | [state_door_prediction.lua](https://github.com/BMingSY/isaac-lan/blob/main/tests/state_door_prediction.lua) 配合 `run_network_engine.py --frontend --menu-start --no-luadebug --virtual-input --latency-ms 40 --completion "PASS feedback observation complete" --native-record-both --heap-check`，指定隔离双端、输出目录与独立端口，由 `ProtectedLabs` 保护并恢复资料。同一组进程检查客机进入新房、返回驻留房间及主机单独过门；记录双端位置和客机权威目标，断言客机淡入前段没有隐形位移、恢复行走没有补跑积压输入。离线覆盖到达／取消淡入、延迟确认，以及原生半帧换房边界 |
| 特殊移动与幽灵落点 | [state_special_motion.lua](https://github.com/BMingSY/isaac-lan/blob/main/tests/state_special_motion.lua) 配合 `run_network_engine.py --frontend --menu-start --completion "LAN_NETWORK SPECIAL PASS movement and ghost arrival"`，使用独立端口、`--latency-ms 75 --heap-check --native-record-both`；同一组进程检查里骸骨静止／抱起／投掷、飞行越障、地下室，以及普通角色和死亡幽灵经 LTL 房间右侧入口的重复到达与换层清理。夹具使用固定种子并清除楼层诅咒；不代表全门位或诅咒路线覆盖。执行前后用 `ProtectedLabs` 保护并恢复资料 |
| 混乱诅咒走门 | [state_maze_routing.lua](https://github.com/BMingSY/isaac-lan/blob/main/tests/state_maze_routing.lua) 配合 `run_network_engine.py --frontend --menu-start --completion "LAN_NETWORK MAZE PASS"`，使用独立端口、`--latency-ms 75 --heap-check --native-record-both`。固定种子保留未清理的普通房间作为原生候选，终局房间的全队汇合按路线另行验收；以正常方向输入重复走门，检查原生随机落点、大房间子格归属、双端一致性、进入队友房间后的实体保留、幽灵随队及换层清理；不替换原生随机数或目的地选择。执行前后用 `ProtectedLabs` 保护并恢复资料 |
| EID、举袋与水流 | [run_client_scenes.py](https://github.com/BMingSY/isaac-lan/blob/main/tools/run_client_scenes.py)，需要完整举放检查时加 `--include-bag-transitions --record-view` |
| 道具与角色 | [run_item_issues.py](https://github.com/BMingSY/isaac-lan/blob/main/tools/run_item_issues.py) 或 [run_special_routes.py](https://github.com/BMingSY/isaac-lan/blob/main/tools/run_special_routes.py) 的相关场景；按实际改动选择持有者、房间和生命周期条件 |
| 反馈上传 | [run_feedback.py](https://github.com/BMingSY/isaac-lan/blob/main/tools/run_feedback.py)：指定 `--host`、`--client`、`--output`，可加 `--heap-check`；同一组主客机经聊天各提交一次 `/feedback`，由内置本地接收端核对请求头、zip 与清单、上一次启动日志和主客机身份，并确认 `/c feedback` 不上传、连续提交受限。夹具通过 `run_network_engine.py --feedback-endpoint` 写入隔离配置，不连接正式服务器；离线对应 `core.feedback-*`、`bridge.feedback` 与 `bridge.chat` |
| 客机房间与演出 | [run_special_routes.py](https://github.com/BMingSY/isaac-lan/blob/main/tools/run_special_routes.py) 可连续选择 `split-render`（五胞胎、圣剑、命运之矛的分房归属及换层）、`mirror-route`（白火、原生镜子门、镜像方向、气泡及死神名册奖励）、`ambush-audio`（挑战战斗、结束与后来进入）、`mother-controls`／`mother-guest`／`mother-together`（三种入场方式、两阶段横穿房间、关闭聊天及控制冷却恢复）、`reconnect-motion`（重连后普通输入横穿房间）、`dice-floor`（原生踩踏、变暗与震动、再次入房不重播）、`room-followers`（跟班重复进入已有房间）、`chain-traps`（真实陵墓刺球锚点及锁链画面）、`secret-exit-doors`（正常走水层入口、汇合与返回门方向）。同一组进程复用连接；第三方组合通过 `--mod`、`--host-mod`、`--client-mod` 指定，资料由工具保护并恢复。`mirror-camera` 和 `room-entry` 分别检查大房间／镜面移动与已加载房间的返回入口 |
| 联机挑战 | [run_lan_challenges.py](https://github.com/BMingSY/isaac-lan/blob/main/tools/run_lan_challenges.py)：`--suite access`／`gameplay`／`hud` 分别检查资格、规则、2–4 人显示与普通会话恢复 |
| 全队死亡结算 | [run_game_over.py](https://github.com/BMingSY/isaac-lan/blob/main/tools/run_game_over.py)：指定 `--host`、`--client`、`--output`，可加 `--record --heap-check`；同一双端进程检查参孙魂石、狂怒与里参孙的最后存活者死亡、普通死亡对照、额外生命、结算停留和原版退出。离线对应 `net.ending-events` 与 `net.ending-liveness` |
| 全队重开投票 | [run_restart.py](https://github.com/BMingSY/isaac-lan/blob/main/tools/run_restart.py)：指定 `--host`、`--client`、`--output`，可加 `--record --heap-check`；同一双端进程连续检查结算确认、手柄组合键、键盘长按 R，交替由主客机发起，核对未全票不重开、连接／选角保留和旧背包清除。键盘检查独占前台焦点；离线对应 `bridge.restart` 与 `net.restart` |
| 通关返回选人 | [run_network_engine.py](https://github.com/BMingSY/isaac-lan/blob/main/tools/run_network_engine.py) 配合 `--script tests/state_return_lobby.lua --completion "LAN_NETWORK RETURN_LOBBY PASS two endings" --frontend --menu-start --virtual-input`，指定隔离双端、输出目录和独立端口，可加 `--heap-check --native-record-both`；同一房间连续播放两次原生结局，检查自动显示选人页、重新准备、换角色和三次开局。此夹具直接请求结局，不计为 Boss／路线验收；离线对应 `net.return-lobby` 与 `bridge.challenge_menu` |
| 受伤移动与药丸归属 | [state_hurt_and_pills.lua](https://github.com/BMingSY/isaac-lan/blob/main/tests/state_hurt_and_pills.lua) 配合 `run_network_engine.py --frontend --menu-start --no-luadebug --virtual-input --latency-ms 40 --completion "PASS hurt movement and pill ownership" --native-record-both --heap-check`，指定隔离双端、输出目录与独立端口，由 `ProtectedLabs` 保护和恢复资料。复用同一组进程验证攻击蝇接触伤害、直接受伤期间的本机移动预测，以及重复速度下降、Bad Trip、I Found Pills、复古视野、麻痹、主机速度提升和分房大颗药丸；断言控制锁定、角色动作、提示文字和屏幕效果的归属，核对双端画面。离线对应 `bridge.motion-intervals` |
| 第三方 Mod | [state_mod_ui.lua](https://github.com/BMingSY/isaac-lan/blob/main/tests/state_mod_ui.lua)、[state_mod_integrations.lua](https://github.com/BMingSY/isaac-lan/blob/main/tests/state_mod_integrations.lua)；`special-routes --case mod-integrations --case mod-integrations-dual` 复用同一对进程验证普通／双角色视图、GoodTrip 去重到达和 API 2 选定身体回执；用 `--mod`／`--client-mod`／`--host-mod` 选择实际安装组合 |
| 性能与资源 | [诊断参考](https://github.com/BMingSY/isaac-lan/blob/main/docs/diagnostics-and-resource-testing.md)：与其他实机分组分开运行，区分实际负载、采集／应用、传输与原生开销 |

## 道具效果专项

[`run_item_audit.py`](https://github.com/BMingSY/isaac-lan/blob/main/tools/run_item_audit.py) 使用隔离主客机，逐项重新开局清除效果，复用组内进程。默认条件为主机同房、客机分房；药丸另覆盖普通和大颗形态。角色能力、概率生成、跨房／跨层／跨局奖励需要对应触发证据，不能仅凭成功获得道具或进程未崩溃判定兼容。

| 模式 | 检查范围 |
| --- | --- |
| `--mode effects` | 逐项效果、资源变化、真实输入与碰撞、持有者归属和双端同步；缺少断言或证据不能通过 |
| `--mode sweep` | 全清单获得／使用的基础流程；不能作为单独效果通过的证据 |
| `--mode mega` | 超级蘑菇使用、换房和结束恢复，覆盖四种持有者／房间条件 |
| `--mode stress` | 大量道具与弹幕压力，须单独执行且明确要求此范围 |

必填参数为 `--host`、`--client`、`--build`、`--output`；`--case` 选单项，`--context` 选持有者／房间条件，`--record` 留存画面，`--continue-after-failure` 在异常清理和资料恢复后另起进程继续。`--injected-bootstrap` 仅验收注入启动的玩法行为，不覆盖代理 DLL 自动加载和安装流程。

效果验收可按 `--shards N --shard 0` 至 `--shard N-1` 并行分片，各片使用相同选项和候选构建、独立主客机目录、`--port` 与输出目录。一个执行者统一调度，每片复用一对进程；根据 CPU 和 Windows 已提交内存余量控制并发数，不能只看空闲物理内存。真实键盘／焦点检查和压力测试仍独占执行。

逐帧证据保存在 `host-events.log` 与 `client-events.log`，游戏日志只记录用例边界和问题；报告按单个用例读取证据，保存结论与原始日志哈希，避免长批次汇总占用整批日志的内存。画面采集默认间隔 1000 ms；闪光等短暂效果可使用 `--record --frame-ms 33`，结合实际帧时间人工复核。

每轮冻结 DLL、生成夹具、配方和判定器；复测使用新输出目录。修正判定器后重审已有原始记录，应保留原判定、变更原因、前后哈希及新的审阅报告。触发前提不成立、夹具错误、缺少一端或退出未完成均保留为未通过，不直接归因于道具不兼容。更新 [`item_audit_findings.json`](https://github.com/BMingSY/isaac-lan/blob/main/tests/fixtures/item_audit_findings.json) 后用 `python tools/render_item_compatibility.py` 生成清单，`--check` 检查一致性；专项结果只写入 `docs/history/` 或 PR。

## 隔离执行与记录

高层工具使用 WSL 驱动 Windows 进程，主客机分别使用独立的隔离副本。示例中的 `ISAAC_GAME_DIRECTORY`、`ISAAC_HOST_LAB`、`ISAAC_CLIENT_LAB`、`ISAAC_RUN_OUTPUT` 和 `ISAAC_FFMPEG` 由运行者设置为游戏位置、两端副本、当轮输出和录像工具；每轮输出须使用新位置。首次创建两个副本：

```sh
python3 tools/prepare_lab.py --game "$ISAAC_GAME_DIRECTORY" \
  --build build-win32 --lab "$ISAAC_HOST_LAB"
python3 tools/prepare_lab.py --game "$ISAAC_GAME_DIRECTORY" \
  --build build-win32 --lab "$ISAAC_CLIENT_LAB"
```

准备工具不启动游戏，拒绝已有目标目录，写入 `.isaac-lan-lab` 标记并重定向存档。之后按清单运行：

```sh
python3 tools/validate_replica.py --cases gameplay normal \
  --output "$ISAAC_RUN_OUTPUT" --latency-ms 75 --ffmpeg "$ISAAC_FFMPEG"
```

示例的 `gameplay` 串联兼容的输入、复活、蓄力、沙漏与镜头场景，`normal` 使用菜单和正常手柄输入。它们是局部检查入口，不能替代上表全部 Boss 与结局覆盖。

现有工具并未自动合并所有分组，执行前仍需安排进程复用。`--latency-ms 75` 为两个方向各附加 75 ms，不能等同所有公网／frp 情况；`--goodtrip` 可传入原样 Mod 目录。

独立分组须使用独立目录、存档、进程、端口和输出；延迟中继还占用相邻端口，例如两组选 30220／30230。前台键盘步骤顺序执行。

画面由隔离进程渲染缓冲区采集，遮挡窗口也可记录。按本轮范围对照双端的战斗、过门、Boss 阶段和换层画面；显示专项另检查镜头、身体／蓄力和演出归属。采样间隙和黑帧候选不能证明没有短暂闪屏。操作与录像归档见 [`tools/NORMAL_GAMEPLAY.md`](https://github.com/BMingSY/isaac-lan/blob/main/tools/NORMAL_GAMEPLAY.md)，性能和堆检查见[诊断参考](https://github.com/BMingSY/isaac-lan/blob/main/docs/diagnostics-and-resource-testing.md)。

## 修改后的契约检查

| 改动 | 必须核对 |
| --- | --- |
| 输入 | 持有值与边沿、本机 UI 归属、过期输入释放 |
| 状态字段 | 采集／应用、原生值转换、类型界限、schema 与协议／指纹 |
| 房间／角色 | 上下文恢复、所有权、替换身份、后台房间表现 |
| 会话／楼层 | 准备屏障、事件先于新视图、重连位置、回退清理 |
| 表现 | 本机归属、原版多人栏位、连续转场画面 |

实机 runner 共用 [`lab_profile.py`](https://github.com/BMingSY/isaac-lan/blob/main/tools/lab_profile.py) 备份和恢复带归属标记的资料。恢复前确认进程已退出且备份哈希完整，恢复后逐文件核对；失败结果和原始证据保留在本轮测试产物中。发布验收摘要保存到 `docs/history/`，记录候选及哈希、实际范围、逐项结果、未决问题、重启和恢复；不把过程或成绩追加进设计文档。
