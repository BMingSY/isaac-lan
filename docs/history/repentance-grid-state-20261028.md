# 原版门与轨道离线检查（2026-10-28）

候选 `3ce5fa20ad8d3fdd0a60b2cfdf291e757f4a8217` 的 J460 DLL、两版网格／轨道四项原生夹具和三项直接消费者通过。J835 尚无完整房间、其余实体视图和前端装配，仍不是可安装后端。按用户要求未启动游戏，无进程重启或实机资料恢复；真实网格析构、特殊门玩法、矿车路线与轨道美术未验证。

目标 PE `1.7.9b.J835` 的 SHA-256 为 `04469d0c3d3581936fcf85bea5f9f4f3a65b2ccf96b36310456c9626bac36dc6`。只读核对网格立即删除、门创建和两版字段：原版附加 Sprite 为 `+0x164`，不能沿用 J460 的 `+0x27c`。轨道初始化确认所有者后跟随 448 字节数组。证据组 `decompiled-j835-grid`、`-r2` 和 `decompiled-j835-visuals-r5`；125 项已登记签名与样本字节／重定位掩码一致。

| 检查 | 结果与证据标识 |
| --- | --- |
| Windows x86 Release | J460 DLL、两版 grid-state 与 rails 夹具构建通过 |
| 原生夹具 | `grid-state-native-r1.log` 四项通过：轨道长度／值域／归属、空与重复状态、换房、门借用包装、已有门登记、立即删除后替换、失败目标回滚、thiscall 栈／寄存器及空 Game |
| Lua 消费者 | `grid-state-consumers.log`：`bridge.grids`、`bridge.room-capture`、`presentation.doors` 三项通过 |
| 结构与资料 | 分层／版本资料 32 项通过，包含文档链接 |
| 格式 | 371 个 C++、370 个 Lua、125 个 Python 和 9 个 CMake 文件通过 |
| 入口核对 | `grid-state-all-signatures.json`：125 项匹配 |

本轮没有失败的构建或测试；实际游戏行为与画面未计为通过。模拟原生方法保留分配／借用边界断言，但不能替代真实构造、析构和房间恢复验收。

| 冻结产物 | SHA-256 |
| --- | --- |
| `isaac_lan_probe.dll` | `322758df0f9f7959c6912e0e16dea31cd99c3b72f71f8f31862445c72dfac1bf` |
| `isaac_lan_grid_state_j460_test.exe` | `0f5f17703ab41e87cea23a9d745e6ef9af3f8db3e0c494e81d64dbe341dc1f05` |
| `isaac_lan_grid_state_j835_test.exe` | `edd1a09ddc818c9467de7fab491a28d5e489824656af99dd051df13f6fc55a11` |
| `isaac_lan_rails_j460_test.exe` | `cee7630ba75fc7f613833d4d6b9b6deabbe9bd1b4c9fd4a07441d6219ed971ab` |
| `isaac_lan_rails_j835_test.exe` | `9748a8fd9fd30a92a17247b3479ca34ee48327c107c0380539f2a1225e530be1` |

原始证据与冻结产物留在忽略的测试目录，清单为 `grid-state-artifacts/manifest.json`。范围外保留 J460 真实键盘菜单丢失端口数字的已知未验证问题；原版完整联机、Boss 和路线验收均未执行。
