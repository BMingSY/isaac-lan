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

需要 Python 3.10+、CMake、C++ 编译器和 **Lua 5.3**；Lua 版本不符时检查失败。安装 Python 依赖，并将 [StyLua 2.0.2](https://github.com/JohnnyMorganz/StyLua/releases/tag/v2.0.2) 放入 `PATH`：

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
| `--sanitizers` | 为可移植 C++ 构建启用 ASan／LSan／UBSan；CI 使用此选项 |

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
| Windows 传输 | 真正的 TCP、输入边沿、积压、重连和事务顺序 | 不启动游戏 |
| 隔离实机／正常操作 | 原生机制、入口与连续画面 | 结果限定于所用版本、夹具和采样范围 |

离线场景通过 [`tests/offline/lua_worker.lua`](https://github.com/BMingSY/isaac-lan/blob/main/tests/offline/lua_worker.lua) 执行生产 Lua，[离线夹具](https://github.com/BMingSY/isaac-lan/tree/main/tests/fixtures) 提供有限接口和虚拟时间。新问题优先补能复现它的离线用例，再决定原生验收范围。

聊天改动的直接回归为 CTest `presentation.chat-input`、`presentation.chat-render`、`bridge.chat`、`diagnostics.*`、`bridge.resume`，以及 Windows `presentation.chat-background`、`net.communication`／`net.integrations`：覆盖 UTF-8 编辑、输入释放、背景配置与 PNG 加载／回退、HUD 避让、拖动与尺寸变化、输出可见性、掷骰去重、原版命令分发和过期上下文。原生执行与画面使用 [state_chat.lua](https://github.com/BMingSY/isaac-lan/blob/main/tests/state_chat.lua)，由隔离双端 runner 加载并保留双端画面；夹具开启属性栏、物品栏和最大 HUD 偏移，并通过原版轮盘选择 D6。输出 `CHAT KEYBOARD_READY` 后，对各自所属窗口依次输入 `~`、A、Enter、`~`；随后聚焦主机，打开输入并将记录区域向右上拖动，再关闭输入。960×540 客户区可使用 [lab_window.ps1](https://github.com/BMingSY/isaac-lan/blob/main/tools/lab_window.ps1) 的 `-Action Drag -Value '220,350:300,320'`，其他尺寸按客户区像素换算。完成键盘与拖动操作后，在两端隔离游戏目录的 `isaac-lan/chat-interaction.done` 写入完成标记；夹具等待该标记后检查结果，避免窗口操作耗时造成提前断言。完成标记为 `LAN_NETWORK PASS chat console`。背景检查可在一端配置自定义 PNG、另一端保留默认值，对照默认纯色、自定义图片和透明度。实机需核对遮挡、光标、D6 滚动与结果画面及双端相同结果；系统输入法候选仍需单独核对，脚本通过不能代表 IME 或画面通过。

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

错误技、达摩剑、创世纪、小夜灯，EID／举袋／水流／切窗口暂停，道具与弹幕压力，输入响应／镜头，以及全道具／卡牌／药丸／角色／Mod 遍历均不列入发版检查，也不因版本包含相关改动而自动追加。用户明确要求时再增加发布专项。已有开发回归结果可以引用，旧验收记录和未决问题保持原结论。完整规则见 [AGENTS.md](https://github.com/BMingSY/isaac-lan/blob/main/AGENTS.md#发布前验收范围)。

## 开发专项入口

以下入口用于开发修复时的定向回归，不属于发版清单。只选择受改动影响、需要排查或用户明确要求的场景，记录具体用例，不自动运行整个专项目录。

| 领域 | 入口与范围 |
| --- | --- |
| 输入与镜头 | [run_response_acceptance.py](https://github.com/BMingSY/isaac-lan/blob/main/tools/run_response_acceptance.py)：直连／约 20 ms RTT、输入预览、移动／过门、暂停、主动、蓄力和大房间／镜面；需要画面时用 `--record-view`。多身体预测用 [state_multi_actor_prediction.lua](https://github.com/BMingSY/isaac-lan/blob/main/tests/state_multi_actor_prediction.lua) 检查双子、骸骨切换及魂石身体的生成／退场 |
| EID、举袋与水流 | [run_client_scenes.py](https://github.com/BMingSY/isaac-lan/blob/main/tools/run_client_scenes.py)，需要完整举放检查时加 `--include-bag-transitions --record-view` |
| 道具与角色 | [run_item_issues.py](https://github.com/BMingSY/isaac-lan/blob/main/tools/run_item_issues.py) 或 [run_special_routes.py](https://github.com/BMingSY/isaac-lan/blob/main/tools/run_special_routes.py) 的相关场景；按实际改动选择持有者、房间和生命周期条件 |
| 联机挑战 | [run_lan_challenges.py](https://github.com/BMingSY/isaac-lan/blob/main/tools/run_lan_challenges.py)：`--suite access`／`gameplay`／`hud` 分别检查资格、规则、2–4 人显示与普通会话恢复 |
| 第三方 Mod | [state_mod_ui.lua](https://github.com/BMingSY/isaac-lan/blob/main/tests/state_mod_ui.lua)、[state_mod_integrations.lua](https://github.com/BMingSY/isaac-lan/blob/main/tests/state_mod_integrations.lua)；按支持版本及 `--mod`／`--client-mod`／`--host-mod` 安装组合选择 |
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
