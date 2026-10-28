# 原版忏悔沙漏与命中反馈离线记录

2026-10-28，分支 `refactor/multiversion-backends`。沙漏检查点及命中反馈已接入 J835 绑定，并通过下述离线检查。J835 仍无 `sources.cmake`，完整房间调度、实体姿态与表现尚未接通，不能生成完整可安装联机 DLL。本记录不属于实机或发布验收。

## 候选与结果

沙漏候选为 `b2f8e898b56d960171e2c7f01c94b8b186bd9acc`，命中反馈候选为 `a93f8d244184b96014e8130cc03bcc62fbc5b18c`。两次均完成 Windows x86 Release J460 DLL 构建。

| 检查 | 结果 |
| --- | --- |
| `native.rewind-home-j460`／`native.rewind-home-j835` | 通过来源房准备、2–4 人恢复、Home／普通／贪婪原生选择、实际转场回放、提前返回、全部有效动画边界、异常与重复／取消／重置 |
| 沙漏原生边界 | 通过 stdcall／thiscall 参数、真实 Hook 冲突与重试、外部 Hook 保留、缺失上下文、原生计数尾部及相邻缓冲区保护；J460 编码与重构前冻结样本一致，J835 仅对缺失的 27 项计数补零 |
| 沙漏关联回归 | `core.compatibility-targets`、`core.room-transition-context`、`bridge.session_lifecycle`、`bridge.resume` 四项通过 |
| `native.combat-feedback-j460`／`native.combat-feedback-j835` | 通过真实 Hook 参数、64 位伤害标志、颜色返回点与 ESI 队列归属、EDI 结算边界、寄存器／标志／SSE／x87 保留，以及三处安装冲突回滚 |
| 命中事件与绘制 | 接触／拒绝／免疫、嵌套命中、队列搬迁、来源移除、身份替换、异常、跨层、过期、观看者筛选、固定编码与 Lua 限制通过；三种实体样式、嵌套和异常绘制后完整恢复实体字节 |
| 命中关联回归 | `presentation.hit-events`、`bridge.capture_generation`、`bridge.replica_pipeline` 三项通过 |
| 分层、版本与文档 | 两轮 `test_layers.py`、`test_game_profiles.py` 各 32 项通过；沙漏文档修改后的链接检查另行通过 |
| 静态入口核对 | 沙漏候选 87 项、命中候选 91 项 J835 入口签名与重定位掩码全部匹配目标程序 |
| 格式与差异 | 各实现提交前 `tools/format.py --check`、`git diff --check` 通过 |

测试运行扩展组件与合成的 x86 原生入口，没有加载游戏。原版程序 SHA-256 为 `04469d0c3d3581936fcf85bea5f9f4f3a65b2ccf96b36310456c9626bac36dc6`；入口、参数、队列与缓冲区依据实际指令、虚表及调用者核对。J835 原生 Home 条件、贪婪分支和转场尾部与 J460 不同，没有用 J460 逻辑替代原版选择。

## 失败与限制

命中夹具首次构建因动态拼接测试指令触发 GCC `stringop-overflow` 告警并被 `-Werror` 拒绝；将固定长度指令改为固定数组后，两版构建与测试通过，未屏蔽告警。沙漏夹具与两版命中运行没有未解决的失败。

按用户要求未启动游戏，没有重启或隔离资料恢复操作。合成调用不验证真实 GameState 副作用、伤害回调、房间对象生命周期或画面；安装包、完整联机、Boss／路线及发布默认范围均未执行。此前真实键盘菜单输入问题仍待验证，见[房间与音频记录](https://github.com/BMingSY/isaac-lan/blob/main/docs/history/repentance-room-audio-20261028.md)。

## 冻结产物

| 候选 | 文件 | SHA-256 |
| --- | --- | --- |
| `b2f8e89` | `isaac_lan_probe.dll` | `24cbcdaecececc3d278bc7dde1ecf4a11d9a7c17b9d7a4aef5d9549850a81c81` |
| `b2f8e89` | `isaac_lan_rewind_home_j460_test.exe` | `b78a6057fc7d94e325ee308d7dea4c184bdf5074dcc99d4f98ca9149e6f73788` |
| `b2f8e89` | `isaac_lan_rewind_home_j835_test.exe` | `02370f4f5500e74a92a0410ad97e78923bbe464d0e83bbcacdf0a1590dd989f8` |
| `a93f8d2` | `isaac_lan_probe.dll` | `9dced04df036a6fafd5b2f3c7bd5073bc5f764aca33e2eee23f067eb8e32369c` |
| `a93f8d2` | `isaac_lan_combat_feedback_j460_test.exe` | `0d91b52f4fba5b0d46e2bc7570ea22843d19a56e786a63c4fffbfae783ebba89` |
| `a93f8d2` | `isaac_lan_combat_feedback_j835_test.exe` | `d112769ecef8bf33f25ef77bd01d38fe133831a6eb864ddcfd37b15ba645b2e5` |

产物清单、沙漏冻结编码、两组 ABI／签名报告及定向反编译导出保留为忽略的测试产物，未提交原始游戏代码或二进制。
