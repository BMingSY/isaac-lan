# 原版玩家轮廓离线检查（2026-10-28）

候选 `b04bd0119c343d1f9f12d96287022538acc5520b` 的 J460 DLL、两版轮廓夹具及三个既有引用／轨道测试入口通过。J835 尚无完整房间和前端装配，仍不是可安装后端。按用户要求未启动游戏，无进程重启或实机资料恢复；真实装扮、幽灵、受击颜色及多房间画面未验证。

目标 PE `1.7.9b.J835` 的 SHA-256 为 `04469d0c3d3581936fcf85bea5f9f4f3a65b2ccf96b36310456c9626bac36dc6`。只读核对玩家内部渲染、颜色压栈与 Entity 渲染：身体和特殊精灵可复用原生描边，幽灵分支需在正常绘制前调用四个方向的 Sprite 绘制。证据组 `decompiled-j835-outlines`、`-r2`；135 项已登记签名与样本字节／重定位掩码一致。

| 检查 | 结果与证据标识 |
| --- | --- |
| Windows x86 Release | J460 DLL、两版轮廓和既有 hornfel／rails／entity_links 夹具构建通过；三个旧入口补齐版本绑定依赖 |
| J460 与旧入口 | `player-outlines-native-r1.log` 中四项通过：原有轮廓分支、配色、作用域及引用／轨道回归 |
| J835 轮廓 | `player-outlines-native-r2.log` 通过：逐 Hook 冲突回滚、完整临时 ColorMod、资格判断、名单重排／断开、嵌套／异常、幽灵四方向／颜色栈／屏幕坐标、GPR／标志／x87／MXCSR／SSE 及原生 ABI |
| 结构与资料 | 分层／版本资料 32 项通过，文档更新后链接检查通过 |
| 格式 | 387 个 C++、370 个 Lua、125 个 Python 和 9 个 CMake 文件通过 |
| 入口核对 | `player-outlines-all-signatures.json`：135 项匹配 |

首轮编译发现方向数组少一个闭合括号，已修正。原生 r1 的 J835 行为断言完成后，夹具使用不支持的 `MH_RemoveHook(MH_ALL_HOOKS)` 清理方式而失败；改为逐个删除所属 Hook 后 r2 通过。原始失败日志及 `player-outlines-development-failures.txt` 保留，r1 不计为 J835 通过。模拟原生函数只验证边界，不代表真实绘制验收。

| 冻结产物 | SHA-256 |
| --- | --- |
| `isaac_lan_probe.dll` | `cc233109ca5b005454323f3137d24d617aeada453284db6031d8e90c8070e7f4` |
| `isaac_lan_player_outlines_test.exe` | `c77f61fb1e83b87dea1be26d5b8b633576a939b03230068aaa798870f1c2bb3a` |
| `isaac_lan_player_outlines_j835_test.exe` | `e67472d0b67a3567809808b95c328e5d5bf247214aed4183d8924a415049203d` |
| `isaac_lan_hornfel_test.exe` | `db9d73b043592479c3172a6df9f0f8330a0f1fecccd7176655c191c1da137c2c` |
| `isaac_lan_rails_test.exe` | `e00037ee823d3372ee793647b0e697dd83784a1e8fce7ff11fe71f4602ea62ca` |
| `isaac_lan_entity_links_test.exe` | `3a129afef208b61266543a514f8c48877be1f8a6ecce5f0fd151bfb866ab1eca` |

原始证据与冻结产物留在忽略的测试目录，清单为 `player-outlines-artifacts/manifest.json`。范围外保留 J460 真实键盘菜单丢失端口数字的已知未验证问题；原版完整联机、Boss 和路线验收均未执行。
