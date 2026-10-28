# 原版忏悔挑战与百宝袋 HUD 离线记录

2026-10-28，分支 `refactor/multiversion-backends`。挑战目标和百宝袋 HUD 已有 J835 绑定，下述定向离线检查通过。J835 仍缺少完整房间、实体姿态和表现接入，没有 `sources.cmake`，不能生成可安装的完整后端；本记录不属于实机或发布验收。

## 候选与检查

挑战目标候选 `d021675d6ca5c783dac9cc66e235a279a476b7cf`；百宝袋候选 `8d5126977f670c0bace9e87db7815fd525d3bf72`。两次均完成 Windows x86 Release J460 DLL 构建。

| 检查 | 结果 |
| --- | --- |
| `native.challenge-hud-j460`／`native.challenge-hud-j835` | 两版通过目标字段、路线标志、普通／联机切换和重复调用；原生参数对象与无关帧字节保持不变 |
| 目标 HUD 原生边界 | 真实 MinHook 跳板的短分支两侧均通过；GPR、标志、SSE、x87 和控制字保留；两个安装位置的外部冲突、所属 Hook 回滚、重试与重复安装通过 |
| 目标关联回归 | `core.challenge-rules`、`bridge.challenges`、`bridge.challenge_menu` 三项通过 |
| `native.crafting-hud-j460`／`native.crafting-hud-j835` | 两版通过实际 Hook 跳板、2–4 人、HUD 顺序与栏位不一致、四个主动槽、幽灵、失去百宝袋、无效或缺失来源、普通会话与等待视图 |
| 百宝袋显示参数 | 两种分辨率、多种 HUD 偏移、正负缩放、J835 HUD 索引与伴生身体对齐例外、透明度、全部 SSE 寄存器、GPR／标志、原参数槽及对象不变性通过 |
| 百宝袋清理与关联回归 | 两处安装冲突回滚、外部 Hook 保留、重试、重复安装通过；`core.challenge-rules`、`bridge.challenges`、`bridge.crafting-bag` 三项通过 |
| 分层、版本及链接 | 两次 `test_layers.py`／`test_game_profiles.py` 各 32 项通过 |
| 只读入口核对 | 目标候选的 93 项、百宝袋候选的 96 项 J835 入口签名及重定位掩码匹配目标程序 |
| 格式和差异 | 两次实现提交前的 `tools/format.py --check`、`git diff --check` 通过 |

原版目标程序 SHA-256 为 `04469d0c3d3581936fcf85bea5f9f4f3a65b2ccf96b36310456c9626bac36dc6`。HUD 调用者、参数读取、返回清栈及布局由只读指令核对；没有以 J460 的参数读取函数、路线字段或副手 ABI 替代 J835。

## 限制与未验证项

本轮构建与测试没有未解决失败。按用户要求未启动游戏，没有重启、存档修改或隔离资料恢复操作。合成入口只验证扩展适配，不验证游戏实际 HUD 资源、材料／配方纹理、屏幕位置、真实联机推进或发布范围。此前真实键盘菜单输入问题仍待验证，见[房间与音频记录](https://github.com/BMingSY/isaac-lan/blob/main/docs/history/repentance-room-audio-20261028.md)。

## 冻结产物

下列 DLL 均为 J460 完整后端，J835 产物仅为独立组件夹具。

| 候选 | 文件 | SHA-256 |
| --- | --- | --- |
| `d021675` | `isaac_lan_probe.dll` | `b84fed6e99535dc19af1d764d1a85c35bf5353d21be243886a29f9f3670495b1` |
| `d021675` | `isaac_lan_challenge_hud_j460_test.exe` | `0da83ba51d95cd47f229215d404fd498477247301d01c53e77cb43a1708dd646` |
| `d021675` | `isaac_lan_challenge_hud_j835_test.exe` | `0f6d5ad1335b98694a5180601abb8e497781fe195a4d2b184e5d45a7a93b3bce` |
| `8d51269` | `isaac_lan_probe.dll` | `1c985078dd1ebd162e52e066403232ca561087c2560348637e7fe49a6b9b6443` |
| `8d51269` | `isaac_lan_crafting_hud_j460_test.exe` | `f4a7ebf48766d76f0d4388e56e80318ca80c9d1852c9acde3069226512adecd5` |
| `8d51269` | `isaac_lan_crafting_hud_j835_test.exe` | `93c572353cbd8d20f777e16430b4e78c2cab5b19d2662dd07649358f4ec37e69` |

产物清单、HUD 定向反编译导出、调用约定与签名报告保留为忽略的测试产物，未提交原始游戏程序或反编译代码。
