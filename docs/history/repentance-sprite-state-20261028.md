# 原版精灵状态离线检查（2026-10-28）

候选提交 `47986b292444ae7877f400f2f90df326e1c77f31` 的 J460 DLL 构建、两版精灵状态夹具及五项直接消费者检查通过。J835 仍缺少完整房间、其余实体姿态和前端装配，不能据此安装或宣称完整联机可用。按用户要求未启动游戏，实际资源加载、动画析构与画面未验证；没有进程重启或实机资料恢复操作。

范围为精灵图层、主／叠加动画与挂点帧，包含版本布局、固定字节、坏载荷的写入前拒绝和原生资源边界。原版 PE 为 `1.7.9b.J835`，SHA-256 `04469d0c3d3581936fcf85bea5f9f4f3a65b2ccf96b36310456c9626bac36dc6`；只读核对 Reset、图层渲染与裁剪字段，并匹配 123 个已登记入口的字节和重定位掩码。

| 检查 | 结果与证据标识 |
| --- | --- |
| Windows x86 Release | J460 DLL、J460／J835 精灵状态夹具均构建成功 |
| 原生夹具 | `sprite-state-native-r1.log`：两项通过；固定编码、重复恢复、逐字节截断、非法值、图层／挂点重排、纹理请求、资源相邻字段、Reset ABI 与数组释放 |
| 直接消费者 | `sprite-state-consumers.log`：`core.animation-pose`、`bridge.entity-codec`、`presentation.attachments`、`presentation.actor-walking`、`bridge.presentation` 五项通过 |
| 分层与版本资料 | `test_layers.py`、`test_game_profiles.py` 共 32 项通过；文档链接另行检查通过 |
| 格式 | 359 个 C++、370 个 Lua、125 个 Python 和 9 个 CMake 文件检查通过 |
| 入口核对 | `sprite-state-all-signatures.json`：123 项匹配；反编译证据组 `decompiled-j835-sprites`、`-r2`、`-r3` |

前置构建曾因抽取后遗留未使用函数、测试辅助函数与 `std::apply` 名称查找冲突，以及不同数组共用一个 `auto` 声明失败；均已修正后重新构建。首次格式检查发现 CMake 缩进不符，格式化后复查通过。失败摘要保留在 `sprite-state-development-failures.txt`，这些失败不计为通过轮次。

| 冻结产物 | SHA-256 |
| --- | --- |
| `isaac_lan_probe.dll` | `1a37d25ce15a7661fdb3f72d67c7670f630b57ef00931d02da81bbd941b0dc16` |
| `isaac_lan_sprite_state_j460_test.exe` | `ec500d40bbf656c9f59742d7c36c074b11de6db0d7add29ba0a86414421859bd` |
| `isaac_lan_sprite_state_j835_test.exe` | `3d0a865a8069c10d7b862f429558a17d822511647a10d23bb7b44c70ab2a4f7d` |

原始日志、反编译与产物保存在忽略的测试目录，清单为 `sprite-state-artifacts/manifest.json`。夹具只执行扩展和模拟原生入口，不证明真实游戏资源的全部生命周期。范围外保留 J460 真实键盘菜单丢失端口数字的已知未验证问题；原版完整联机、Boss 与路线验收均未执行。
