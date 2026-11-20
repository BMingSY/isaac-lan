# 房间数据离线检查（2026-10-28）

候选 `538fe053d61cd51db8d48de85c4df8eaa37b72f3` 的两版房间数据夹具和 J460 DLL 构建通过。原版完整房间调度、创建／销毁和启动装配仍未接通。按用户要求未启动游戏，无重启或资料恢复；本记录不代表原版完整联机、真实地图绘制或路线验收通过。

只读样本 J835 SHA-256 为 `04469d0c3d3581936fcf85bea5f9f4f3a65b2ccf96b36310456c9626bac36dc6`。证据组 `decompiled-j835-room-data`、已有 `decompiled-j835-frontend/4e2e40.c` 和原生 getter 指令，核对描述符查询、507 格映射、特殊索引下界、保存记录步长、水流和缓存刷新。153 项签名在 `room-data-all-signatures.json` 中均与样本一致。

| 检查 | 结果与证据标识 |
| --- | --- |
| Windows x86 Release | `room-data-build-r4.log`：DLL 与两版夹具构建通过 |
| 原生组件 | `room-data-native-r2.log`：两版房间数据及地图共 4 项通过；覆盖固定快照、规范索引、新红房间／特殊房间、完整载荷拒绝、稳定配置地址、原生所有权、重复接收、别名／嵌套／异常恢复、换层缓存失效、Game 替换和销毁 |
| 可移植与 Lua | `room-data-core-r1.log`：个人地图、房间采集和房间映射共 3 项通过 |
| 结构／格式 | 分层与版本资料 32 项通过；420 个 C++、370 个 Lua、125 个 Python、9 个 CMake 文件格式通过 |

地图借用修正了同一原生描述符多次出现时的恢复顺序；活动缓存持有接收记录到作用域结束，重复接收或换层清理不提前释放它。首轮夹具构建（`room-data-build-r2.log`）因辅助函数名 `apply` 与 `std::apply` 的参数查找冲突失败，改名后构建与原生检查通过，原始失败保留。

| 冻结产物 | SHA-256 |
| --- | --- |
| `isaac_lan_probe.dll` | `8a63e59787f471cba2b36a419a82da557073b712c13ac88081adea3bb34ded42` |
| `isaac_lan_room_data_j460_test.exe` | `2e6d4821f69f85f86d4604b9e4d9aafa588702fcf67e9c8c93ff1418d5bb545b` |
| `isaac_lan_room_data_j835_test.exe` | `46fa6e539369cbba64f2b74051ebebd6f103b38553741e1dd55abf6b034e411a` |

产物清单为 `room-data-artifacts/manifest.json`，原始证据留在忽略的测试目录。范围外保留 J460 真实键盘菜单丢失端口数字的未验证问题；未执行发布验收或道具专项实机。
