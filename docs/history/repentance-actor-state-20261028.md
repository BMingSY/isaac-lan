# 角色附属状态离线检查（2026-10-28）

候选 `af61f42c4564a7fd420a89bcb75c494f510a0af6` 的两版角色状态夹具与 J460 DLL 构建通过。J835 完整房间调度与启动装配仍未完成；本记录不代表完整联机兼容。按用户要求未启动游戏，没有进程重启或资料恢复，真实角色动画、库存与百宝袋 HUD 待验证。

只读样本为 J835 `04469d0c3d3581936fcf85bea5f9f4f3a65b2ccf96b36310456c9626bac36dc6`。`decompiled-j835-actor-state`、`-r2` 和 `actor-state-lua-getters.json` 留存角色构造、口袋与里蓝人 getter、百宝袋写入和 HUD 缓存消费证据；未增加原生入口签名。

| 检查 | 结果与证据标识 |
| --- | --- |
| Windows x86 Release | `actor-state-build-r2.log`：DLL 与两版原生夹具构建通过 |
| 两版角色状态 | `actor-state-native-r1.log`：2 项通过，覆盖 Sprite 顺序／借用元数据、固定字节、重复状态、完整队伍／名单替换、截断及越界、非客机拒绝、无 HUD、只刷新所属 HUD 和 thiscall 栈平衡 |
| 结构与文档链接 | `actor-state-structure-r1.log`：分层及版本资料 32 项通过 |
| 格式 | `actor-state-format-r1.log`：408 个 C++、370 个 Lua、125 个 Python、9 个 CMake 文件通过 |

首轮构建发现注册列表的模板推导接受了函数类型，显式取函数指针后构建通过；保留 `actor-state-build-r1.log`。口袋、百宝袋和里蓝人快照用固定期望字节及整对象哨兵检查，未以生产偏移生成期望结果。

| 冻结产物 | SHA-256 |
| --- | --- |
| `isaac_lan_probe.dll` | `0fe5901cb3112bdcb9be6f9832854bf51eba61b8f4f06ca6367cdbd3ebd5a665` |
| `isaac_lan_actor_state_j460_test.exe` | `e4dc51221f4ec38343c376e1b72d47075e0490f8f6cdd628d2238104a64c0bfd` |
| `isaac_lan_actor_state_j835_test.exe` | `8a9c177c75ace77876712b480c78e22c8e80f2674ba0ee35b0808b8d5567a651` |

清单 `actor-state-artifacts/manifest.json` 与原始证据保存在忽略的测试目录。范围外保留 J460 真实键盘菜单丢失端口数字的未验证问题；未执行原版联机、Boss、路线或发布验收。
