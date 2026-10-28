# 原版实体引用离线检查（2026-10-28）

候选 `299cbbb0fe53891c5b894e4e63732d08ad206cee` 的 J460 DLL、两版实体引用六项原生夹具和两项 Lua 消费者通过。J835 尚无完整房间、其余实体视图和前端装配，仍不是可安装后端。按用户要求未启动游戏，无进程重启或实机资料恢复；实际矿车、抱起物、Hornfel 与 Horny Boys 行为未验证。

目标 PE `1.7.9b.J835` 的 SHA-256 为 `04469d0c3d3581936fcf85bea5f9f4f3a65b2ccf96b36310456c9626bac36dc6`。只读核对矿车登记、抱起物投掷、两种 Boss 的炸弹渲染、NPC 构造及 deque 扩容，确认原生观察者登记和容器所有权。证据组 `decompiled-j835-visuals-r2`、`-r5`、`-r6`、`decompiled-j835-held` 和 `-r2`；126 项已登记签名与样本字节／重定位掩码一致。

| 检查 | 结果与证据标识 |
| --- | --- |
| Windows x86 Release | J460 DLL、两版 references、entity-links 和 held-bombs 夹具构建通过 |
| 原生夹具 | `references-native-r1.log` 六项通过：重复／替换／移除／清空引用、原生删除通知、跨块 deque、整组目标预检、空容器初始化、借用包装校验、权威端拒绝写入、fastcall 寄存器与 thiscall 栈清理 |
| Lua 消费者 | `references-consumers.log`：`bridge.hornfel`、`bridge.entity_links` 两项通过 |
| 结构与资料 | 分层／版本资料 32 项通过，包含文档链接 |
| 格式 | 377 个 C++、370 个 Lua、125 个 Python 和 9 个 CMake 文件通过 |
| 入口核对 | `references-all-signatures.json`：126 项匹配 |

首轮编译发现夹具缺少显式 `<vector>` 包含，已补齐；证据为 `references-development-failures.txt`。没有失败的原生测试轮次。模拟原生方法验证引用槽及观察者清理，但不能替代游戏对象真实析构与 Boss 机制验收。

| 冻结产物 | SHA-256 |
| --- | --- |
| `isaac_lan_probe.dll` | `18700f938e6c142246d2cac6789193d1bccbed20a1bc1c95a7d32db8ae5ba2c3` |
| `isaac_lan_references_j460_test.exe` | `5ade38058009cc867822db1155ea6bd61e05e1f3cbeecc8c609e691976fa1247` |
| `isaac_lan_references_j835_test.exe` | `ad03a88a1ab2977dcb154c26c4f19792c181c91861ecab24f72a1192cf938864` |
| `isaac_lan_entity_links_j460_test.exe` | `8a83e18b749656c5cc56f1214ffbf208383bd5fa9f5f46ed99b6211d2e52e33e` |
| `isaac_lan_entity_links_j835_test.exe` | `bcd881e5cda4e373da086aca9d85de182783cdc7b5c47d4ababe525f17cb650a` |
| `isaac_lan_held_bombs_j460_test.exe` | `663337dbc0770308130122d441971a9fc9b248f12da9afa9d585c5002328cc31` |
| `isaac_lan_held_bombs_j835_test.exe` | `40ba38c2a484f5a70fc39d8c8b73296f69d1f9342dea6ab4cedf72eff75fbd9b` |

原始证据与冻结产物留在忽略的测试目录，清单为 `references-artifacts/manifest.json`。范围外保留 J460 真实键盘菜单丢失端口数字的已知未验证问题；原版完整联机、Boss 和路线验收均未执行。
