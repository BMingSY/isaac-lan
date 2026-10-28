# 原版忏悔 HUD 坐标与演出离线记录

2026-10-28，分支 `refactor/multiversion-backends`。玩家 HUD 坐标、胜利圈提示和入场演出已有双版本组件，以下定向离线检查通过。原版 J835 仍缺少完整房间、实体姿态、道具演出、前端及启动装配，没有 `sources.cmake`，不能生成可安装的完整后端；本记录不是实机或发布验收。

## 候选与范围

| 候选 | 检查与结果 |
| --- | --- |
| `6a41b279946b0bc8e8a3155faabc55c61c21c783` | `presentation.player-hud` 在 Linux 与 Windows 通过；`bridge.ping_hud`、`bridge.battle-royale-hud` 通过，覆盖两版坐标、可见性、无效视口及栏位身份 |
| `adb763c385f8e6c987de5285491bdd4b43efa326` | `native.victory-prompt-j460/j835` 两项通过；主客机权限、挑战拒绝、输入消费、动画阶段、只读字符串、邻接字段、Game 替换、thiscall 和安装冲突清理通过；`bridge.special-menu`、`bridge.challenges` 通过 |
| `a2e11cf48e0e10b5979b02b29fdcf6dd4d05aead` | `native.presentation-j460/j835` 两项通过；背景房间、控制恢复的房间／楼层／结束边界、集合、嵌套与异常清理、Game 释放、固定事件字节、去重／过期／断线、实体引用接口、HUD 桥接和小夜灯调用者隔离通过 |
| 演出关联回归 | `core.intro-barrier`、`bridge.presentation`、`presentation.player-hud`、`bridge.ping_hud`、`bridge.battle-royale-hud` 五项通过 |
| 构建与静态检查 | 三个候选的 Windows x86 Release J460 DLL 构建通过；分层／版本检查各 32 项通过，新增文档链接单项复查通过；提交前格式检查和差异检查通过 |
| 只读入口核对 | 胜利圈候选 99 项、演出候选 103 项 J835 入口签名及掩码匹配目标程序；另核对 J460 新登记的入场入口，J835 入场／推进／控制恢复的清栈分别为 8／0／4 字节 |

目标原版程序 SHA-256 为 `04469d0c3d3581936fcf85bea5f9f4f3a65b2ccf96b36310456c9626bac36dc6`。指令与调用者核对采用只读程序分析。J835 的入场角色通过原生 EntityPtr 赋值登记，未沿用 J460 的直接全局指针写法；J835 的胜利圈提示没有 Steam 投票字段。

## 失败与未验证项

演出夹具首轮编译因模拟 Lua 回调返回类型不匹配而失败，修正为 const 字符串返回并补齐 reset 参数。首轮执行的预期事件生成器误用小端，按现有协议的大端字节修正后，两版完整用例通过；生产序列化未更改。原始失败输出保留在开发测试记录中，最终无未解决的本轮离线失败。

按用户要求没有启动游戏，没有重启、修改游戏存档或隔离资料恢复操作。夹具中的原生方法、动画和对象释放均为模拟；实际美术、实体引用移除、Boss 入场、胜利圈推进和完整房间生命周期仍未实机验证。此前真实键盘菜单输入问题保持待验证，见[房间与音频记录](https://github.com/BMingSY/isaac-lan/blob/main/docs/history/repentance-room-audio-20261028.md)。

## 冻结产物

DLL 均为 J460 完整后端；J835 可执行文件只是独立组件夹具。原始反编译、指令和签名报告及下列产物保留在忽略的测试产物中。

| 候选 | 文件 | SHA-256 |
| --- | --- | --- |
| `6a41b27` | `isaac_lan_probe.dll` | `57daff6eb3647f354c6416339636d5057e876c3547d04cc21de5f26227d135a6` |
| `6a41b27` | `isaac_lan_player_hud_test.exe` | `db2814e0960c1c4e8a5fb43478842ec02e880506965f646dcae9453ab5b37091` |
| `6a41b27` | `isaac_lan_player_hud_test` | `5466fe77d2dff494fe1d8980d6a9ed5dc0c0020706e8f10d41a459c067fb98ce` |
| `adb763c` | `isaac_lan_probe.dll` | `d7d661b846e5a64b772e6d779e1ccea425890fbd6cdea074716c859ca37897b9` |
| `adb763c` | `isaac_lan_victory_prompt_j460_test.exe` | `5f487e6a868d2cb38fff7cbff3dbb81e25dad8e2088889fd551df5aae543fa6e` |
| `adb763c` | `isaac_lan_victory_prompt_j835_test.exe` | `5cbc6f032d5ce107f2686205886285dc65bd04b3657732ecbf7441a37c69890f` |
| `a2e11cf` | `isaac_lan_probe.dll` | `71cdea703e589f4053b34a14dc1a1783c40cff5218349e90d31e220d266ceb27` |
| `a2e11cf` | `isaac_lan_presentation_j460_test.exe` | `8c8697c7440353e825c10ab1dda65c23d29c582003b4585280d692c806f2951a` |
| `a2e11cf` | `isaac_lan_presentation_j835_test.exe` | `408cc882a568fb84eb7cdfb3da7e508929cbafe519b24c81c77022afbf9be31b` |
