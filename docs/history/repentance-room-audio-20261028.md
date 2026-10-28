# 原版忏悔房间边界与音频组件离线记录

2026-10-28，候选 `7a4aa3b76b8720f02b925c349ad46a745cf9fe13`，分支 `refactor/multiversion-backends`。房间进入边界与声音／音乐组件的 J460、J835 离线检查通过；这不是完整原版联机后端或实机验收。J835 仍无 `sources.cmake`，完整房间调度、实体同步、表现及启动装配尚未接通。

## 范围与结果

| 检查 | 结果 |
| --- | --- |
| Windows x86 Release J460 DLL | 构建成功；没有生成可安装 J835 DLL |
| `native.room-routing-j460`／`native.room-routing-j835` | 通过：实际 MinHook 安装与回滚、外部 Hook 保留、重试、重复安装、房间初始化／已加载房间跳过、改送标志、回调异常、缺失 Game／边界、嵌套拒绝及清理 |
| 房间寄存器与诅咒 | 通过：通用寄存器、标志、SSE／x87 与控制字保持；诅咒合并、抑制嵌套及异常恢复 |
| `native.audio-backend-j460`／`native.audio-backend-j835` | 通过：音效与音乐调用栈、听众路由、音效编码字节、时效与有界队列；嵌套房间、原生直接排队、跨房／跨层、重复快照、队列完成、会话重置及重连 |
| 音频失败处理 | 通过：原生选曲失败恢复临时 ID、拒绝异常音乐快照、Hook 失败仅清理自身并可重试 |
| 相关可移植／Lua 回归 | `bridge.shared-curses`、`core.resolved-room-curses`、`core.room-scope-ownership`、`core.audio-ownership`、`bridge.special-menu` 五项通过 |
| 分层与版本描述 | `test_layers.py`、`test_game_profiles.py` 共 32 项通过 |
| 原生静态核对 | J835 70 项入口签名及重定位掩码均匹配目标程序；新增房间边界十六字节签名和音频 ABI 已纳入目录 |
| 格式与差异 | `tools/format.py --check`、`git diff --check` 通过 |

测试程序只运行扩展组件及合成的原生调用边界，没有加载或启动游戏。静态分析使用已归属的 J835 程序，SHA-256 为 `04469d0c3d3581936fcf85bea5f9f4f3a65b2ccf96b36310456c9626bac36dc6`。不把合成调用栈与寄存器检查视作真实房间对象所有权、转场或音频播放验收。

## 失败与未验证项

首轮 Python 回归因命令环境未包含已有 `lua5.3` 路径失败，补齐工具 PATH 后 32 项通过。首轮音频夹具有两个错误：J835 的相邻字段哨兵覆盖了实际音量字段；同房队列用例把更新和渲染放在同一未退出的作用域。修正哨兵与实际调用顺序后，两版均通过；这些失败没有表明原生音量偏移存在错误。原生选曲异常时临时 ID 的恢复由共享组件中的作用域保证。

依照用户要求未启动游戏，因此本轮没有进程重启或隔离资料恢复操作；没有运行安装包、基础联机、路线、Boss、完整发行验收或性能专项。真实混乱诅咒、房间资源生命周期、音乐渐变和完整原版联机均待验证。既有问题边界沿用[玩家输入与道具组件记录](https://github.com/BMingSY/isaac-lan/blob/main/docs/history/repentance-player-input-items-20261028.md)，本轮未声称解决此前的真实键盘菜单输入问题。

## 冻结产物

| 文件 | SHA-256 |
| --- | --- |
| `isaac_lan_probe.dll` | `467a36bc0c8bf442e971b91a2f14cc9ba8e5732ba7348e0d63be78e7dc005b9c` |
| `isaac_lan_room_routing_j460_test.exe` | `328db57867f1a57ed8c44e6049acf7f0a1036f05dc7bf5dd1e2243b19b87798c` |
| `isaac_lan_room_routing_j835_test.exe` | `8afc6b4940e6c0bec96ca8fabd0a3094ab1044928ca2701abd9d8da594494120` |
| `isaac_lan_audio_backend_j460_test.exe` | `36b2afc89bfc8f7ad7f359acc7910dfbbbbed6de9288c418402b8b04fd6dd624` |
| `isaac_lan_audio_backend_j835_test.exe` | `fe780959a924487c643041220deaae40ed352cbcf09b410b1c971804e8e669b2` |

证据保留为忽略的测试产物：`room-audio-signatures.json`、`room-audio-artifacts.json`、房间／音频定向 Ghidra 导出及 CTest 输出。原始反汇编和游戏程序未提交到仓库。
