# 开发与测试

## 源码与产物

```text
README.md        用户说明与构建命令
AGENTS.md        仓库协作、测试与发布文案约定
docs/            架构和开发文档
src/             按 app／net／runtime／engine／compat／presentation 分层的原生代码与嵌入 Lua
cmake/           32 位 Windows 工具链配置
package/         安装脚本
tests/           传输测试、引擎场景与测试夹具
tools/           构建安装包、隔离启动、回归和画面归档
third_party/     第三方许可证
```

构建步骤见[项目 README](../README.md#源码构建)。CMake 使用 C++20、32 位 Windows 工具链，并从外部路径读取 Dear ImGui v1.92.6 和 MinHook v1.3.4 源码。

| 产物 | 用途 |
| --- | --- |
| `winmm.dll` | 自动加载与原系统 winmm 导出转发 |
| `isaac_lan_probe.dll` | 引擎适配、网络与嵌入 Lua |
| `isaac_lan_check.exe` | 安装时读取 PE 并校验游戏版本与布局 |
| `isaac_lan_net_test.exe` | 实际 Winsock 传输测试，不启动游戏 |
| `isaac_lan_lab.exe` | 隔离游戏实例的启动与测试入口 |

`tools/build_package.py` 打包前三项、安装脚本、入口命令、根目录 README 和许可证。游戏文件、存档、测试记录与构建目录不提交到仓库。

## 原生加载与版本适配

自动加载器转发系统 `winmm.dll` 的导出，暂时阻止游戏入口继续执行，在工作线程完成扩展初始化后恢复入口。游戏对象、网络轮询和 Lua 状态在游戏主线程处理。

安装器校验目标是所支持版本的 32 位 PE，避免以整个 EXE 的哈希排除无关补丁。运行时在安装挂钩前核对所用入口的特征；关键入口确实变化时，不能继续使用旧布局。

新增原生接口时需要核对 RVA、调用约定、结构尺寸、分配／释放责任和角色生命周期。入口地址与特征分别集中在 [`entrypoints.h`](../src/engine/versions/j460/entrypoints.h) 与 [`signatures.inc`](../src/engine/versions/j460/signatures.inc)，共同使用具名地址常量。模块边界与扩展方式见[分层与玩法兼容](layers-and-compatibility.md)。新游戏版本需要重新验证这些条件，不只修改版本字符串。

安装与卸载由 [`package/install.ps1`](../package/install.ps1) 管理本扩展的 DLL 和安装记录，操作在同卷暂存并支持失败回滚。扩展不直接修改磁盘上的游戏 EXE。

## 测试分层

日常开发、调试和回归使用[离线测试流程](offline-testing.md)：`.deps/checks/bin/python tools/test.py`。该入口只运行无需游戏的检查。实机验证集中到最终验收，先列出本次所有待验证项目，再在同一次启动中完成兼容场景；只有确实需要关闭游戏的检查或无法恢复的进程异常才单独重启。

| 层次 | 验证内容 | 无法单独证明 |
| --- | --- | --- |
| Lua 接入测试 | 独立编码、本机作用域、生命周期、动作去重／回执与兼容注册 | 真实第三方服务和游戏回调正确 |
| 协议与存档单元测试 | 编解码、尺寸限制、截断与损坏数据、玩家位置、进度合并边界 | Windows 传输与引擎行为正确 |
| 离线状态与行为场景 | 生产 Lua 的资源应用、实体关系与去重、连续多帧过门／绕障碍、生成动作序列 | 原生特殊角色、死亡副作用、引擎物理与画面正确 |
| Python 工具测试 | 打包内容与哈希、归档校验、连续场景调度、延迟中继与正常关闭 | 真实游戏运行正确 |
| 传输测试 | 输入边沿、状态合并、分块、控制命令、重连、加载期间换层与事务顺序 | 引擎对象与真实画面正确 |
| 隔离引擎场景 | 特定角色、门、道具、状态恢复及 UI 归属 | 正常操作时所有调用路径正确 |
| 双客户端正常操作 | 菜单开局、走门、战斗、拾取、用卡、暂停与换层 | 没有采样间隙中的短暂视觉问题 |
| 连续画面审查 | 闪屏、黑影、身体、蓄力条、镜头和 HUD | 仅凭单张截图证明整段动画正确 |

先完成与改动相关的离线层次，再根据未解决的问题扩大离线覆盖，并将原生机制或画面检查登记到最终实机清单。文档修改不需要重新启动游戏。具体分组与记录要求见[日常测试与最终验收约定](offline-testing.md#日常测试与最终验收约定)。

## CI 与基础测试

推送到 `main` 和所有 PR 都运行 `.github/workflows/ci.yml`：

- 检查 C++、Lua、Python、CMake 和 PowerShell 格式，以及脚本语法。
- 在 Linux 上执行 pytest 工具／离线状态／连续行为测试，以及启用 AddressSanitizer／UndefinedBehaviorSanitizer 的协议、存档测试；保留测试报告与失败请求。
- 构建 Windows x86 完整产物，验证安装包，并在 Windows 上执行单元测试和真实 Winsock 传输测试。

Windows 构建与测试由 `build-windows.yml` 复用，标签发布也使用同一套检查。基础 CI 不需要游戏文件；真实引擎与画面回归仍按下文在隔离客户端运行。

无需 Windows 工具链或第三方源码即可运行协议与存档测试：

```sh
cmake -S . -B build-core -G Ninja \
  -DISAAC_LAN_BUILD_ENGINE=OFF -DCMAKE_BUILD_TYPE=Debug
cmake --build build-core
ctest --test-dir build-core --output-on-failure
```

Python 工具测试与脚本语法检查：

```sh
python3 -m venv .deps/checks
.deps/checks/bin/pip install -r tools/requirements-ci.txt
.deps/checks/bin/python -m pytest --offline-profile fast -q
.deps/checks/bin/python tools/check_scripts.py
```

语法检查需要 `luac`（Lua 5.3），并额外检查由连续回归工具生成的 Lua 场景。CMake 默认启用 `BUILD_TESTING`，只构建产物时可设为 `OFF`。

## 缩进与格式

项目代码使用四个空格缩进，GitHub Actions YAML 使用两个空格。编辑器规则见 `.editorconfig`；C++、Lua、Python 和 CMake 的格式规则分别由 `.clang-format`、`.stylua.toml`、`pyproject.toml` 和 `.cmake-format.json` 管理。

安装上节的检查依赖，并将 [StyLua 2.0.2](https://github.com/JohnnyMorganz/StyLua/releases/tag/v2.0.2) 放到 `PATH`，即可统一格式或只检查：

```sh
PATH="$PWD/.deps/checks/bin:$PATH" python tools/format.py
PATH="$PWD/.deps/checks/bin:$PATH" python tools/format.py --check
```

PowerShell 在 Windows 中使用固定版本的 PSScriptAnalyzer：

```powershell
Install-Module PSScriptAnalyzer -RequiredVersion 1.24.0 -Scope CurrentUser -Force
./tools/format_powershell.ps1
./tools/format_powershell.ps1 -Check
```

## 传输回归

构建后，在能运行 Windows EXE 的环境执行：

```sh
ctest --test-dir build-win32 --output-on-failure
```

CTest 分别报告协议、存档和传输用例。也可以运行全部传输测试或指定一个用例：

```sh
./build-win32/isaac_lan_net_test.exe
./build-win32/isaac_lan_net_test.exe floor-rejoin
```

通过标记为 `ALL STATE TRANSPORT TESTS PASSED`，此测试不启动游戏。

## 准备隔离客户端

完整游戏回归工具按 WSL 驱动 Windows 进程编写，需要 Windows 互操作。当前高层回归工具使用 `D:\isaac-lan-lab\host-001`、`client-001`，并读取仓库的 `build-win32`。

在 WSL 中，以实际游戏路径替换示例路径，分别创建两个全新的隔离副本：

```sh
python3 tools/prepare_lab.py --game /mnt/d/Games/Isaac \
  --build build-win32 --lab /mnt/d/isaac-lan-lab/host-001
python3 tools/prepare_lab.py --game /mnt/d/Games/Isaac \
  --build build-win32 --lab /mnt/d/isaac-lan-lab/client-001
```

工具复制游戏和资源，写入 `.isaac-lan-lab` 标记，并重定向测试存档。它拒绝复用已存在的目标目录，不会启动游戏。测试期间通过标记、路径和进程检查限制操作范围。

## 最终实机验收：一次启动里的连续回归

代码、离线检查和所需构建完成后，按验收清单集中运行下面的实机工具。联机场景主机与客机各启动一次，兼容场景复用同一批进程；需退出／重启的检查单独安排并记录原因。

```sh
python3 tools/validate_replica.py \
  --output artifacts/regression-新编号 \
  --latency-ms 75 --ffmpeg /path/to/ffmpeg
```

`gameplay` 把兼容的定向用例串在同一场游戏里，保留游戏进程和连接，清理用例夹具后进入下一项。输入、复活、蓄力、沙漏、特殊门、重置层和镜头等不用每项重新启动。

这是需要真实游戏的独立入口，用于最终验收。优先用离线场景验证规则，再将未覆盖的原生接口、角色机制和画面问题集中验证。默认入口仍包含独立运行的分组，尚未自动合并全部场景；执行前应安排兼容用例顺序，避免无需退出游戏的项目重复启动。

保存后退出并重新启动继续游戏等必须关闭进程的场景单独运行；掉线、重连、加载期间换层等无需退出游戏的会话变化优先复用已有进程。现有脚本仍可能独立运行这些场景，不能据此认定它们都必须重启。`normal` 从原菜单和正常手柄输入走完一层，安排在兼容的验收流程中；定向夹具不能替代这一步。

仅运行连续玩法用例可增加 `--cases gameplay`；只运行普通流程可使用 `--cases normal`。`--goodtrip /path/to/goodtrip` 原样复制 Mod 到隔离环境，并补充本机地图输入与传送回归。

`--latency-ms 75` 表示两个方向各增加 75 ms，模拟约 150 ms RTT。它不模拟所有公网拥塞、抖动和丢包，不能等同于真实 frp 链路。

输入响应定向回归可使用 `--cases local-movement input-response motion mirror-camera active-edges special-doors`。`input-response` 通过原生手柄绑定，在不同发送周期相位反复起步、转向和松手，记录原生输入、最后发送的输入、预测输入与显示位置；检查最新持有值在同一渲染帧进入预测，并立即改变本机预测速度；带惯性的反向移动需要先减速，因此方向反转的时间另行记录，不要求位置立即反向。这个时间不包含设备到游戏输入管理器的延迟。`motion` 检查持续移动、网格阻挡和松手后的收敛，使用同一条原生输入链路。

`--cases item-presentation` 生成真实拾取物，再使用原生手柄按键触发客机药丸、卡牌和怪物书。它检查同房间、分房间、双方同时使用时的演出归属，药丸／卡牌／主动效果只在房主执行一次，重复快照不会重播；另检查主机拾取提示与远端 Mega Mush 动画完成后的可见性。夹具保留两端原生画面，需要同时查看双方对应时刻的提示和全屏动画。

## 正常操作与画面证据

单独运行正常操作流程：

```sh
python3 tools/manual_gameplay.py run \
  --output artifacts/gameplay-新编号 \
  --latency-ms 75 --ffmpeg /path/to/ffmpeg
```

它从菜单创建和加入，按正常输入走门、战斗、拾取、用卡、暂停和换层。观察器只读取状态；该流程不靠直接调用换房、生成物品或击杀敌人来完成路线。

每轮冻结所用 DLL、脚本和哈希，保留操作记录、两端日志、检查点截图、状态 JSON、连续帧时间索引及录像。输出目录必须是新目录，不能把不同轮次的记录混在一起。

画面从隔离进程渲染缓冲区读取，因此窗口被另一客户端遮挡时仍可记录。采样间隔与丢帧会记录；正常流程约 10 fps，定向闪屏场景可以用更短间隔。黑帧检测只产生候选，不能证明所有闪屏已消失。

至少对照两端检查队友过门时本机背景、大房间镜头、角色身体／蓄力、房间播报，以及整段换层动画中的 HUD 归属。不要只检查到下一层后的静态结果。

分步操作、录像归档和检查点说明见 [`tools/NORMAL_GAMEPLAY.md`](../tools/NORMAL_GAMEPLAY.md)。

## 修改后应核对的契约

- 输入修改：区分持有值与按下边沿，确认地图和 UI 不接受队友操作。
- 状态字段修改：更新采集与应用两端，转换原生值，核对类型及界限。
- 房间修改：核对上下文恢复、对象所有权、角色替换和后台加载表现。
- 会话修改：验证加载前不参与模拟、换层事务先于新视图、重连使用最新房主位置。
- UI 修改：同时检查本机归属、原版多人栏位和换层过程。

协议或状态布局变更时，核对协议版本、schema 与扩展指纹；当前尚未提供跨旧版扩展的兼容层。

`local-movement` 使用原生手柄输入，记录每个渲染帧的显示位置、房主位置和原生速度，覆盖连续行走、松手减速和开门通道。过门后立即释放输入，断言角色曾到达真正的门口、进房后的位移未超过 25 个坐标单位。用于检查旧房间输入或预测惯性是否进入新房间，可分别加单向 10 ms 和 75 ms 延迟运行。应同时查看连续移动曲线和实际画面；输入首帧通过不能单独证明手感正常。
