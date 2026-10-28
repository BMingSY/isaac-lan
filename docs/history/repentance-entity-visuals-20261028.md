# 原版跟班视图离线检查（2026-10-28）

候选 `abe212c67c737f77a884c5d8994cb4c9c8056ac0` 的 J460 DLL、两版实体视图原生夹具和三个直接 Lua 消费者通过。J835 尚无完整房间、玩家描边和前端装配，仍不是可安装后端。按用户要求未启动游戏，无进程重启或实机资料恢复；跟班身体、绳索画面及 Needle 真实渲染未验证。

目标 PE `1.7.9b.J835` 的 SHA-256 为 `04469d0c3d3581936fcf85bea5f9f4f3a65b2ccf96b36310456c9626bac36dc6`。只读核对 Familiar 渲染、身体与绳索组件的 RTTI／构造／析构、绳索绘制和 Needle 图层准备。原版附加数据为 `+0xe18`，身体／绳索虚表分别为 RVA `0x746348/0x73fffc`，不得沿用 J460 布局。证据组 `decompiled-j835-visuals-r2`、`-r6` 和 `familiar-rtti.json`；128 项已登记签名匹配样本字节／重定位掩码。

| 检查 | 结果与证据标识 |
| --- | --- |
| Windows x86 Release | J460 DLL、两版 entity-visuals 夹具构建通过 |
| 原生夹具 | `entity-visuals-native-r1.log` 两项通过：固定字节、五个身体 Sprite、完整图层预检、绳索环绕／空状态、空指针与非有限坐标拒绝、重复绘制、异常恢复、组件替换／移除、thiscall 清栈与寄存器 |
| Lua 消费者 | `entity-visuals-consumers.log`：`bridge.special-visuals`、`presentation.tethers`、`bridge.entity-codec` 三项通过 |
| 结构与资料 | 分层／版本资料 32 项通过，包含文档链接 |
| 格式 | 383 个 C++、370 个 Lua、125 个 Python 和 9 个 CMake 文件通过 |
| 入口核对 | `entity-visuals-all-signatures.json`：128 项匹配 |

首轮编译发现夹具的两个 Lua 字符串函数返回类型不符，改为 `const char*` 后构建通过；说明为 `entity-visuals-development-failures.txt`。没有失败的原生测试轮次。夹具调用模拟原生函数验证 ABI 和资源边界，不执行游戏绘制、纹理加载或 AI。

| 冻结产物 | SHA-256 |
| --- | --- |
| `isaac_lan_probe.dll` | `41086eba0fad7ca312b08e8e0df0f9439bc63bd688f156ab833c1859d2808672` |
| `isaac_lan_entity_visuals_j460_test.exe` | `94ec1807f51a62b4eb470be2c9aec339f2f4dc9e065ea2aba98d760db4ae0fba` |
| `isaac_lan_entity_visuals_j835_test.exe` | `9f5011b44be1b59dbb1a0e141e33005ad42bd9d4472c9d9c8341115d057b9835` |

原始证据与冻结产物留在忽略的测试目录，清单为 `entity-visuals-artifacts/manifest.json`。范围外保留 J460 真实键盘菜单丢失端口数字的已知未验证问题；原版完整联机、Boss 和路线验收均未执行。
