# 原版玩家、输入与道具组件离线记录 — 2026-10-28

候选为 `d1f7cb2`，分支 `refactor/multiversion-backends`，未合入 `main`。范围为玩家创建／分配、共享输入路由、道具与复活接口；原版完整后端仍未完成。本轮按用户要求没有启动游戏、安装 DLL、操作游戏资料或执行实机验收，不涉及实例重启与资料恢复。

## 检查范围

| 检查 | 结果与边界 |
| --- | --- |
| 玩家创建 `75856e8` | 两个 `native.player-input-*` 通过：创建／初始化／奖励／HUD 顺序，伴生角色两次扩容后的列表重取，重复加入、无效参数及原生创建失败 |
| 共享输入 `d2c88bf` | 两个 `native.input-backend-*` 通过：原生查询到共享路由、模拟量与按键沿、暂停意图、预测、鼠标目标、实际输入编码、模态界面、重开映射和退出／重连 |
| 道具与复活 `d1f7cb2` | 两个 `native.item-backend-*` 与 `native.item-effects` 通过：双版本不同参数数量、确认拾取调用点、祝福记录与失败清理、掉落物所有权、充能、复活房间、激光清理及 Hook 冲突后的回滚重试 |
| 关联检查 | `native.pause-menu`、`native.mouse-input`、`native.mouse-j835` 通过；六个输入相关 portable/Lua 测试，以及 luck_game、clear-charge、transition-charge 通过 |
| Windows x86 Release | J460 DLL 与上述独立夹具构建通过；没有可安装的 J835 DLL |
| 分层与版本 | 32 项 pytest 通过；格式与 `git diff --check` 通过；没有 PowerShell 改动 |
| 原程序静态核对 | J835 60 个入口签名及重定位掩码全部匹配目标程序 SHA-256 `04469d0c3d3581936fcf85bea5f9f4f3a65b2ccf96b36310456c9626bac36dc6` |

输入夹具初次编译因测试命名空间别名和条件变量声明失败，随后修正并通过；一次格式检查发现该夹具的换行格式，修正后复查通过。原版道具池参数缺失、玩家管理器与向量位置不同均通过独立合成 ABI 夹具验证；这些测试不加载游戏代码，不能证明实际角色、场景或画面正确。

## 产物与证据

| 产物 | SHA-256 |
| --- | --- |
| `isaac_lan_probe.dll` | `f822d50a4d9372d439b2bb2935c2d20daa97e2f7aa674bac11fe97bc5562f267` |
| `isaac_lan_player_input_j460_test.exe` | `ffe69a497825de53289c66ce196fa741a6f43875baf6e7384d12ab72b39f1611` |
| `isaac_lan_player_input_j835_test.exe` | `62d3d8ff1ab5e5c799f449b97cb26bd45d68812cf3f1732ca208a8f21159be5e` |
| `isaac_lan_input_backend_j460_test.exe` | `5720281ee8281d69cc25c73c1da4b779aefe47c2f31443ff26be1d0ef457b102` |
| `isaac_lan_input_backend_j835_test.exe` | `dd75a1410a5a17c7559ab7bac1e805b303592299256097d133cd9384ef1f5121` |
| `isaac_lan_item_backend_j460_test.exe` | `b235d48a08a87c845b279e0de36f23ecdca216a4ea19963660f92a7d45f847cd` |
| `isaac_lan_item_backend_j835_test.exe` | `7e8cc29d3851b130120d1f5c06f94dcbd4918964cf66dd8d55a32e619a23d966` |

原始资料留在忽略的 `j835-port` 产物组，证据标识为 `player-input-items-signatures`、`player-input-items-artifacts`、`decompiled-j835-player-input`、`decompiled-j835-items`、`decompiled-j835-items-r2`。不提交游戏代码、原始反编译输出、可执行文件或日志到文档目录。

## 未完成与未验证

- 房间生命周期、实体同步及其余原生能力与完整启动装配尚未完成；构建工具继续拒绝选择 J835 生成可安装后端。
- 本轮没有进行窗口／控制器实机检查、联机、Boss、路线、结局、角色、道具、Mod 或性能验收；离线组件通过不能表述为这些范围通过。
- 此前未解决的真实键盘菜单问题及启动探针失败保留在[输入与暂停记录](https://github.com/BMingSY/isaac-lan/blob/main/docs/history/repentance-input-components-20261027.md)引用的历史资料中，本轮未复测或宣告解决。
