# 激光路径离线检查（2026-10-28）

候选 `45d1059f77fb8df13afeda871380a65149f30593` 的两版激光路径夹具和 J460 DLL 构建通过。J835 完整房间调度和启动装配尚未完成；未验证完整联机兼容。按用户要求未启动游戏，没有重启或资料恢复，真实激光绘制和原生释放仍待实机验证。

只读样本 J835 SHA-256 为 `04469d0c3d3581936fcf85bea5f9f4f3a65b2ccf96b36310456c9626bac36dc6`。证据 `decompiled-j835-laser`、`-r2`、`-r3` 及 `decompiled-j460-laser`、`-r2` 核对初始化、路径字段、分配器与析构链；J460 `0x26980` 和 J835 `0x7de0/0x7e40` 指令确认大向量的对齐分配约定。`laser-state-all-signatures.json` 的 152 项登记签名均与样本一致。

| 检查 | 结果与证据标识 |
| --- | --- |
| Windows x86 Release | `laser-state-build-r2.log`：DLL、两版激光夹具构建通过 |
| 原生组件 | `laser-state-native-r2.log`：两版激光与角色状态共 4 项通过；覆盖固定编码、三态、重复平移、2048 点上限、255／256 点扩容阈值、分配失败保留旧数据、非法原生头、所有权及调用栈 |
| 可移植与 Lua | `laser-state-core-r2.log`：激光／里蓝人核心与口袋／百宝袋／里蓝人 Lua 共 5 项通过 |
| 结构／格式 | 分层与版本资料 32 项通过；414 个 C++、370 个 Lua、125 个 Python、9 个 CMake 文件格式通过 |

离线修正了现有路径恢复在大向量上未保留原生对齐分配头的问题，两版均按原生析构约定管理扩容。首轮 Linux 构建用了不存在的单项目标，`laser-state-core-build-r1.log` 保留；其后旧二进制结果不作为本轮验收，改为构建 `isaac_lan_core_test` 后另开 r2。

| 冻结产物 | SHA-256 |
| --- | --- |
| `isaac_lan_probe.dll` | `4f3b4adfec1297bdabc405bf076641e1bb9151fadae5a17fac1c2985ada284e8` |
| `isaac_lan_laser_state_j460_test.exe` | `3661fe4382a0dd858bf80cd7a89e62e3aa6ee7e485f9716672475758cb80ab95` |
| `isaac_lan_laser_state_j835_test.exe` | `b75a73791ecb2f3b0cf9fa2fa96e93bbb7bec3f1bf49d2c8b9f59cb6226ab349` |

产物清单为 `laser-state-artifacts/manifest.json`，原始证据留在忽略的测试目录。范围外保留 J460 真实键盘菜单丢失端口数字的未验证问题；未执行原版基础联机、Boss、路线或发布验收。
