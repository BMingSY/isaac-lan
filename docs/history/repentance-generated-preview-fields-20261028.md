# 原版忏悔动态道具、预览与实体字段离线记录

2026-10-28，分支 `refactor/multiversion-backends`。动态道具定义、负编号库存、本机掉落物预览和具名实体字段已具备 J835 绑定，并通过下述离线检查。J835 仍无 `sources.cmake`，不能生成完整可安装联机 DLL；完整房间调度、实体姿态及启动装配尚未接通。本记录不属于实机或发布验收。

## 候选与结果

生成物／预览与测试注册候选为 `5845476c6217a885d9ff3e3baaaea504946679a0`；实体字段候选为 `823efb2dc89f79376658dd423b99a0072a76f1ee`。两次均完成 Windows x86 Release J460 DLL 构建。

| 检查 | 候选与结果 |
| --- | --- |
| 动态道具定义与负编号库存 | 前一候选通过两版 `native.generated-items-*`：实际生成调用约定、1024 项上限、种子编码、重复前缀、冲突／倒退／异常输入、原生恢复调用点、客机生成限制、库存数量及名单／Sprite 校验 |
| 本机掉落物预览 | 前一候选通过两版 `native.pickup-preview-*`：真实 Hook 安装／冲突／重试、本机名单、原生预览修改渲染数组、非活动掉落物清理、换房、异常和退出／重连；`native.item-effects` 的关联预览用例通过 |
| 测试注册重构 | 前一候选的 25 个版本组件测试全部通过；重构前后 243 个 CTest 用例的名称、命令、标签和超时完全一致 |
| 实体字段 | 后一候选通过 `native.entity-fields-j460`／`native.entity-fields-j835`：四种实体的全部具名字段、表与二进制恢复、setter ABI 与调用顺序、重复价格、各版商店槽范围、只读字段、模板边界及失败前完整校验 |
| Sprite／NPC 与生命周期 | 后一候选通过：借用／自有 wrapper、字符串、主／叠加动画帧取整、空动画、数值边界、NPC 分类、角色限制、计划复用、新对象和新一局帧计数；嵌套字段字节与 Lua codec 固定样本一致 |
| 相关 Lua／可移植链路 | 动态道具的 `bridge.pocket-inventory`、`bridge.capture_generation`、`bridge.replica_pipeline` 通过；实体字段的 `bridge.native-codec`、`bridge.entity-codec`、`bridge.npc-state`、采集代次及副本恢复五项通过 |
| 分层、版本与文档链接 | 两轮 `test_layers.py`、`test_game_profiles.py` 各 32 项通过 |
| 静态原生核对 | 前一候选 75 项、后一候选 80 项 J835 入口签名与重定位掩码均匹配目标程序 |
| 格式与差异 | 各实现提交前 `tools/format.py --check`、`git diff --check` 通过 |

测试程序运行扩展组件、Lua 栈夹具和合成的 x86 原生边界，没有加载或启动游戏。原版程序 SHA-256 为 `04469d0c3d3581936fcf85bea5f9f4f3a65b2ccf96b36310456c9626bac36dc6`。字段依据原版 Lua 注册、getter／setter 和指令核对；第三方布局资料仅用于定位候选。

## 失败与未验证项

动态道具夹具首次编译因重构后残留的成员访问语法失败，掉落物夹具首次编译因局部数组与 `rooms` 命名空间冲突失败；更正后相应构建和回归通过。实体字段两版夹具及其补充的字节／生命周期用例均通过，没有以忽略失败或跳过版本取得结果。

按用户要求未启动游戏，没有重启或隔离资料恢复操作。原生内存布局的静态核对和合成调用测试不等于真实生成物资源、掉落物预览画面、实体副作用或完整联机验证。安装包、Boss／路线、发布默认范围及性能专项均未执行。此前的真实键盘菜单输入问题保持待验证，边界见[房间与音频记录](https://github.com/BMingSY/isaac-lan/blob/main/docs/history/repentance-room-audio-20261028.md)。

## 冻结产物

| 候选 | 文件 | SHA-256 |
| --- | --- | --- |
| `5845476` | `isaac_lan_probe.dll` | `e5a4f7c5e3470960ab9f155f7e419df48dd34ae5a169e39a2e6aeeaa702399e3` |
| `5845476` | `isaac_lan_generated_items_j460_test.exe` | `7385e23e9fa034576d1d368d044ae6fe322ec54ba722bf558ab2ebe7574cfb2f` |
| `5845476` | `isaac_lan_generated_items_j835_test.exe` | `f231e17e3e3ceff5596028d6e7a98136f19f24515485977b52c7d7afe49813ce` |
| `5845476` | `isaac_lan_pickup_preview_j460_test.exe` | `8fca659c85168d09899fa001e3c8ed2cee7d00d4a1dfc68b07cfa78b3c687917` |
| `5845476` | `isaac_lan_pickup_preview_j835_test.exe` | `e420966c5225a3c781e563c58b38a06e261b574d96bbe1065fd9716b2f29ce46` |
| `823efb2` | `isaac_lan_probe.dll` | `07e2f7115f96290dd447a3bec5148d055039482f63d18aeaa2d45105346ed13b` |
| `823efb2` | `isaac_lan_entity_fields_j460_test.exe` | `7fdbf4f2c4481c31e6095d08f42525e8b1839a2fa97337cd0e7c9f48a6d2394a` |
| `823efb2` | `isaac_lan_entity_fields_j835_test.exe` | `20955c97651422a8e4604b25705c6666d72a9a6b59133bacb1a6c10d2d9c93cd` |

证据保留为忽略的测试产物：两组产物清单、`generated-preview-signatures.json`、`entity-signatures.json`、`entity-property-abi.json`、属性注册引用及定向反编译导出。原始游戏代码、反汇编和二进制产物未提交到文档目录。
