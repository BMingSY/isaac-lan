# 原版角色姿态与阴影离线检查（2026-10-28）

候选 `7de4b2875a4f2f4edc53fa55076e0f9c4043d03d` 的 J460 DLL、两版实体姿态夹具和七项直接消费者检查通过。J835 仍缺少完整房间、其余实体视图和前端装配，不能据此安装或宣称完整兼容。按用户要求未启动游戏，无进程重启或实机资料恢复；实际武器、服装与阴影画面仍待验证。

原版 PE 为 `1.7.9b.J835`，SHA-256 `04469d0c3d3581936fcf85bea5f9f4f3a65b2ccf96b36310456c9626bac36dc6`。只读核对角色绘制、服装、武器查询、受击与小夜灯字段，以及实体阴影和高度；不调用游戏函数。证据组为 `decompiled-j835-visuals` 至 `-r4`、`visual-fields-accesses.json`，高度参考既有实体 setter 证据。

| 检查 | 结果与证据标识 |
| --- | --- |
| Windows x86 Release | J460 DLL 与两版 `entity-pose` 夹具构建成功 |
| 原生布局夹具 | `entity-pose-native-r1.log` 两项通过：固定编码、五武器槽、x87 查询、负蓄力上限、缺失／不匹配武器、服装重排／重名／缺失、逐字节截断、非法值、重复快照、对象替换和资源边界 |
| 直接消费者 | `entity-pose-consumers.log` 七项通过：服装映射、实体编码、攻击演出、服装、步行、角色形态与兼容目标 |
| 结构与资料 | 分层／版本资料 32 项通过，包含文档链接 |
| 格式 | 365 个 C++、370 个 Lua、125 个 Python 和 9 个 CMake 文件通过 |

前置构建曾因源清单漏登记新组件、引用尚不存在的玩家类型常量失败；补齐登记与具名常量后重建。MinGW 在内联向量增长时报告数组边界警告，编码器预留正常姿态容量后构建通过，固定字节由夹具核对。失败摘要 `entity-pose-development-failures.txt` 保留，失败构建不计为测试通过。

| 冻结产物 | SHA-256 |
| --- | --- |
| `isaac_lan_probe.dll` | `244ecebc27023b4ecc0d413c087424cc79d5b2d0ec3f85f5dc867273b0667f2e` |
| `isaac_lan_entity_pose_j460_test.exe` | `60d894610da4ad4e2f930dc3c1ef499b2dc9c820773a0a55c57ef29e0b2a2f9d` |
| `isaac_lan_entity_pose_j835_test.exe` | `90b81a5f9c3e5ccb7c962b40c1b53735b04bd7db9de28c029364594ba7343a08` |

日志与产物留在忽略的测试目录，清单为 `entity-pose-artifacts/manifest.json`。此轮不验证实机跨房／跨层、真实 AI 与美术资源生命周期。范围外保留 J460 真实键盘菜单丢失端口数字的已知未验证问题；完整原版联机、Boss 与路线未执行。
