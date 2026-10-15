# 开发与测试

日常先做离线回归，原生机制与画面集中到最终验收。离线通过不代表实机通过；任务要求不启动游戏时，实机项记为未执行。协作和发布约定见 [AGENTS.md](https://github.com/BMingSY/isaac-lan/blob/main/AGENTS.md)。

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

1. 完成代码、离线检查和构建，列出待验证行为、预期及准备条件。
2. 主客机各启动一次，共用兼容场景；用例之间清理夹具、恢复状态。只有启动／退出检查或进程无法恢复时才重启，并记录原因。
3. 分别记录通过、失败、阻塞、未执行及证据。冻结 DLL、脚本和哈希，使用新的输出目录；保留双端日志、状态、连续帧和退出结果。

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

| 入口或场景 | 用途 |
| --- | --- |
| `gameplay` | 连续运行兼容的输入、复活、蓄力、沙漏、门与镜头场景 |
| `normal`／`tools/manual_gameplay.py run` | 从菜单和正常手柄输入验证走门、战斗、拾取、暂停与换层 |
| `local-movement input-response motion mirror-camera` | 输入相位、持续移动、惯性、网格和镜像；首帧响应不能单独代表手感 |
| `tools/run_response_acceptance.py` | 一对隔离进程、一条连接集中验证 60 Hz 输入、半帧应用、连续移动、过门、暂停恢复、主动边沿、蓄力与镜头；中途从零附加延迟切换到双向各 10 ms |
| `item-presentation` | 同房、分房及同时使用时的道具／卡牌／药丸演出归属与去重 |
| `tools/run_special_routes.py --case ...` | 特殊角色、路线、共享状态及通关夹具；可串联多个 `--case` |

现有工具并未自动合并所有分组，执行前仍需安排进程复用。`--latency-ms 75` 为两个方向各附加 75 ms，不能等同所有公网／frp 情况；`--goodtrip` 可传入原样 Mod 目录。

独立分组须使用独立目录、存档、进程、端口和输出；延迟中继还占用相邻端口，例如两组选 30220／30230。前台键盘步骤顺序执行。跑圈路线曾出现并发加载异常，原因未确定，目前保留串行，见[原验收记录](https://github.com/BMingSY/isaac-lan/blob/main/docs/history/party-compatibility-validation.md#验证记录)。

画面由隔离进程渲染缓冲区采集，遮挡窗口也可记录。至少对照双端的队友过门、背景／大房间镜头、角色身体／蓄力、房间播报及完整换层动画；采样间隙和黑帧候选不能证明没有短暂闪屏。操作与录像归档见 [`tools/NORMAL_GAMEPLAY.md`](https://github.com/BMingSY/isaac-lan/blob/main/tools/NORMAL_GAMEPLAY.md)，性能和堆检查见[诊断参考](https://github.com/BMingSY/isaac-lan/blob/main/docs/diagnostics-and-resource-testing.md)。

## 修改后的契约检查

| 改动 | 必须核对 |
| --- | --- |
| 输入 | 持有值与边沿、本机 UI 归属、过期输入释放 |
| 状态字段 | 采集／应用、原生值转换、类型界限、schema 与协议／指纹 |
| 房间／角色 | 上下文恢复、所有权、替换身份、后台房间表现 |
| 会话／楼层 | 准备屏障、事件先于新视图、重连位置、回退清理 |
| 表现 | 本机归属、原版多人栏位、连续转场画面 |

历次实际执行结果集中在[历史验收索引](https://github.com/BMingSY/isaac-lan/blob/main/docs/history/README.md)，不在开发流程中累计测试数量或通关轮次。
