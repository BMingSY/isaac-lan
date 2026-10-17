# 开发与测试

BUG 修复、需求新增和日常重构按影响范围执行离线回归与必要的局部实机验证；发版默认覆盖基础联机、全部 Boss 和正常结局／路线，专项按需执行。离线通过不代表实机通过；任务要求不启动游戏时，实机项记为未执行。协作和发布约定见 [AGENTS.md](https://github.com/BMingSY/isaac-lan/blob/main/AGENTS.md)。

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
| `--list-engine` | 只读取实机清单，不执行场景；脚本存在不代表已通过 |

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

聊天改动的直接回归为 CTest `presentation.chat-input`、`bridge.chat`、`diagnostics.*`、`bridge.resume`，以及 Windows `net.communication`／`net.integrations`：覆盖 UTF-8 编辑、输入释放、背景配置、输出可见性、掷骰去重、原版命令分发和过期上下文。原生执行与画面使用 [state_chat.lua](https://github.com/BMingSY/isaac-lan/blob/main/tests/state_chat.lua)，由隔离双端 runner 加载并保留双端画面；夹具输出 `CHAT KEYBOARD_READY` 后，对各自所属窗口依次输入 `~`、A、Enter、`~`，完成标记为 `LAN_NETWORK PASS chat console`。实机需另核对同房气泡、表情、背景透明度和系统输入法候选；只有脚本断言通过不能代表 IME 或画面通过。

## 失败记录与回放

统一运行按当轮归档保存阶段日志、耗时、`summary.json`、`pytest.xml` 和失败请求。回放命令：

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

默认不执行全道具／卡牌／药丸遍历、全角色／Mod 扫描或性能压力测试。已知问题继续保留在结果中，范围外未测项目不能写成通过。默认项及追加项的完整规则见 [AGENTS.md](https://github.com/BMingSY/isaac-lan/blob/main/AGENTS.md#发布前验收范围)。

### 按需专项

只有本次改动直接影响、排查相关问题或用户明确要求时，才选择对应专项；先说明理由和具体用例，不自动运行整个专项目录。

| 领域 | 入口与范围 |
| --- | --- |
| 输入与镜头 | [run_response_acceptance.py](https://github.com/BMingSY/isaac-lan/blob/main/tools/run_response_acceptance.py)：直连／约 20 ms RTT、输入预览、移动／过门、暂停、主动、蓄力和大房间／镜面；需要画面时用 `--record-view` |
| EID、举袋与水流 | [run_client_scenes.py](https://github.com/BMingSY/isaac-lan/blob/main/tools/run_client_scenes.py)，需要完整举放检查时加 `--include-bag-transitions --record-view` |
| 道具与角色 | [run_item_issues.py](https://github.com/BMingSY/isaac-lan/blob/main/tools/run_item_issues.py) 或 [run_special_routes.py](https://github.com/BMingSY/isaac-lan/blob/main/tools/run_special_routes.py) 的相关场景；按实际改动选择持有者、房间和生命周期条件 |
| 联机挑战 | [run_lan_challenges.py](https://github.com/BMingSY/isaac-lan/blob/main/tools/run_lan_challenges.py)：`--suite access`／`gameplay`／`hud` 分别检查资格、规则、2–4 人显示与普通会话恢复 |
| 第三方 Mod | [state_mod_ui.lua](https://github.com/BMingSY/isaac-lan/blob/main/tests/state_mod_ui.lua)、[state_mod_integrations.lua](https://github.com/BMingSY/isaac-lan/blob/main/tests/state_mod_integrations.lua)；按支持版本及 `--mod`／`--client-mod`／`--host-mod` 安装组合选择 |
| 性能与资源 | [诊断参考](https://github.com/BMingSY/isaac-lan/blob/main/docs/diagnostics-and-resource-testing.md)：与其他实机分组分开运行，区分实际负载、采集／应用、传输与原生开销 |

### 隔离执行与记录

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
