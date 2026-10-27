# 原版忏悔输入与暂停组件离线记录 — 2026-10-27

代码候选为 `17e8582`，分支 `refactor/multiversion-backends`，未合入 `main`。本轮覆盖原生输入查询、设备事务、暂停菜单和鼠标内联边界；不构成原版完整联机后端或实机验收。遵照用户要求，本轮未启动游戏、未安装 DLL、未修改游戏资料，不涉及实例重启或资料恢复。

## 范围与结果

| 检查 | 结果与边界 |
| --- | --- |
| Windows x86 Release | J460 DLL 与受影响组件夹具构建通过；没有生成可安装的 J835 DLL |
| 原版查询 `656a049` | `native.input-queries-j835` 通过，包含调用约定、模拟量返回、物理旁路与安装失败清理 |
| 两版设备 `b34b464`／`4b72d09` | 两个 `native.input-devices-*` 通过；重入、并发断开、退出恢复和外部 Hook 保留均由独立夹具执行 |
| 两版暂停 `4b72d09` | 两个 `native.pause-backend-*` 及 `native.pause-menu` 通过；包括选项编号、保存顺序、临时名单和重复状态 |
| 鼠标 `17e8582` | `native.mouse-j835`、`native.mouse-input` 通过；原版夹具验证寄存器、标志、SSE／x87 保持、采集旁路、嵌套与坐标换算。J460 暂停输入集成复查通过 |
| 分层／版本／PE 工具 | 查询阶段 46 项 pytest 通过；设备、暂停与鼠标阶段各自的 32 项分层／版本检查通过 |
| 原程序静态核对 | J835 的 41 个入口签名及重定位掩码匹配源程序；SHA-256 为 `04469d0c3d3581936fcf85bea5f9f4f3a65b2ccf96b36310456c9626bac36dc6` |
| 格式与差异 | `tools/format.py --check`、`git diff --check` 通过；本轮未修改 PowerShell |

输入查询的初版调用约定转换、鼠标夹具的 SSE 目标声明曾导致严格编译失败，均在对应候选提交前修正。上述 ABI 测试使用独立的合成 x86 映像，不加载游戏程序，不能证明实际角色、物理、镜头或菜单画面正确。

## 产物与证据

以下为本轮构建产物的 SHA-256；夹具包含各自实际编译时的组件，代码候选记录不表示执行了全量发版范围。

| 产物 | SHA-256 |
| --- | --- |
| `isaac_lan_probe.dll` | `ad07562754a4fb1ba4c228f4908bd59acd990c31635b74cc9cf853b82d7389fa` |
| `isaac_lan_input_queries_j835_test.exe` | `77ab488fbb4dfa29dfe01f18fb2c93693c7afeba435934840d623d8a74610a67` |
| `isaac_lan_input_devices_j460_test.exe` | `e02ec8249f3b50466b2edec690254a4bc36e5cfee3e08a083a37c9f571470bae` |
| `isaac_lan_input_devices_j835_test.exe` | `1b55f50e9b38dcdfb62adb6aa1d5cea2ad9104aea09842b4a3608c8b925af067` |
| `isaac_lan_pause_backend_j460_test.exe` | `486de9fb18960d50f7513d16f6145b958940af2094d486688706dc280e105da1` |
| `isaac_lan_pause_backend_j835_test.exe` | `4d02b692e49220d6eb679a2573e6ef288d81f1dfeb636de07bf75af3cca56ef5` |
| `isaac_lan_mouse_j835_test.exe` | `ededc3bf8bb3c5154e97a75e140701465f7cad2c5732b00dac986ae8a95ac6d2` |

原始静态资料及检查输出保留在忽略的 `j835-port` 测试产物组中：`input-query-signatures`、`input-pause-signatures`、`input-mouse-signatures` 和 `input-component-artifacts` 分别标识本轮入口与产物记录。反编译输出、游戏代码、原始日志和可执行文件均未提交文档目录。

## 未完成与未验证

- 原版玩家创建／控制器分配与完整输入路由、房间／实体同步、完整启动装配仍未完成；CMake 继续拒绝选择 J835 生成可安装后端。
- 原版鼠标内联块仅有静态审计与独立 ABI 夹具；实际窗口缩放、镜像、镜头、玩家身体及重复进出会话均未实机验证。
- 本轮未做联机、Boss、结局、道具、角色、Mod 或性能验收，也不将此前离线通过视作这些范围通过。
- 此前保留的启动探针失败和 J460 真实键盘菜单输入问题继续见[基础组件记录](https://github.com/BMingSY/isaac-lan/blob/main/docs/history/repentance-components-20261027.md)与[会话组件记录](https://github.com/BMingSY/isaac-lan/blob/main/docs/history/repentance-session-20261027.md)，本轮未复测或宣告解决。
