# 开发与测试

## 源码与产物

```text
README.md        用户说明与构建命令
AGENTS.md        仓库协作与发布文案约定
docs/            架构和开发文档
src/             原生扩展、传输与嵌入 Lua
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

新增原生接口时需要核对 RVA、调用约定、结构尺寸、分配／释放责任和角色生命周期。地址特征集中在 [`game_signatures.inc`](../src/game_signatures.inc)。新游戏版本需要重新验证这些条件，不只修改版本字符串。

安装与卸载由 [`package/install.ps1`](../package/install.ps1) 管理本扩展的 DLL 和安装记录，操作在同卷暂存并支持失败回滚。扩展不直接修改磁盘上的游戏 EXE。

## 测试分层

| 层次 | 验证内容 | 无法单独证明 |
| --- | --- | --- |
| 传输测试 | 输入边沿、状态合并、分块、控制命令、重连、加载期间换层与事务顺序 | 引擎对象与真实画面正确 |
| 隔离引擎场景 | 特定角色、门、道具、状态恢复及 UI 归属 | 正常操作时所有调用路径正确 |
| 双客户端正常操作 | 菜单开局、走门、战斗、拾取、用卡、暂停与换层 | 没有采样间隙中的短暂视觉问题 |
| 连续画面审查 | 闪屏、黑影、身体、蓄力条、镜头和 HUD | 仅凭单张截图证明整段动画正确 |

先完成与改动相关的层次，再根据未解决的问题扩大验证范围。文档修改不需要重新启动游戏。

## 传输回归

构建后，在能运行 Windows EXE 的环境执行：

```sh
./build-win32/isaac_lan_net_test.exe
```

通过标记为 `ALL STATE TRANSPORT TESTS PASSED`。需要检查多进程传输时，可在 Windows Python 中运行：

```sh
python tools/check_network_processes.py build-win32/isaac_lan_net_test.exe \
  --output artifacts/network-processes.json
```

这两个入口不启动游戏。

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

## 一场游戏里的连续回归

```sh
python3 tools/validate_replica.py \
  --output artifacts/regression-新编号 \
  --latency-ms 75 --ffmpeg /path/to/ffmpeg
```

`gameplay` 把兼容的定向用例串在同一场游戏里，保留游戏进程和连接，清理用例夹具后进入下一项。输入、复活、蓄力、沙漏、特殊门、重置层和镜头等不用每项重新启动。

保存续玩、掉线、加载期间换层等改变会话生命周期的用例保留独立运行。`normal` 再从原菜单和正常手柄输入走完一层；定向夹具不能替代这一步。

仅运行连续玩法用例可增加 `--cases gameplay`；只运行普通流程可使用 `--cases normal`。`--goodtrip /path/to/goodtrip` 原样复制 Mod 到隔离环境，并补充本机地图输入与传送回归。

`--latency-ms 75` 表示两个方向各增加 75 ms，模拟约 150 ms RTT。它不模拟所有公网拥塞、抖动和丢包，不能等同于真实 frp 链路。

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
