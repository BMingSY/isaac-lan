# 原版忏悔 Home 与道具演出离线记录

2026-10-28，分支 `refactor/multiversion-backends`。Home 更新门控和道具演出已有双版本组件，以下定向离线检查通过。J835 仍无完整房间、实体姿态、前端及启动装配，也没有 `sources.cmake`；不能生成可安装的完整联机后端，本记录不是实机或发布验收。

## 候选与结果

| 候选 | 范围与结果 |
| --- | --- |
| `19d66bddfa5542bf5e9f2dd856afe6ed366eb94e` | `native.scene-update-j460/j835` 两项通过；覆盖主客机及结束状态反复切换、J835 内联继续位置、原生对象不变、栈、GPR／标志／SSE／x87／控制字和 Hook 冲突清理 |
| `da63542e0d082ecfbe3296d2ba6552c9173dd6b3` | `native.item-presentation-j460/j835` 两项通过；覆盖 14 个 Hook 的逐个冲突、栈与寄存器、对象构造／配置数／析构、加载失败、Mega Mush 动画转移、主客机文字归属、翻译与显示标志、规则提示的借用列表和索引校验 |
| 道具演出生命周期 | 大书及自定义文字固定字节、整批解析失败、重复／过期／跨代次事件、屏幕嵌套及异常、重置／Game 失效、Home 集合／姿态、借用 Sprite 与参数拒绝通过 |
| 直接消费者 | 道具候选的 `core.compatibility-targets`、`core.localized-text`、`bridge.presentation` 三项通过；Home 门控候选的 `core.intro-barrier`、`bridge.presentation` 两项通过 |
| 构建与检查 | 两个候选的 Windows x86 Release J460 DLL 构建通过；分层／版本检查各 32 项通过，格式与差异检查通过；当前 122 项 J835 入口签名及重定位掩码匹配目标程序 |

目标原版程序 SHA-256 为 `04469d0c3d3581936fcf85bea5f9f4f3a65b2ccf96b36310456c9626bac36dc6`。核验只读取程序：J835 自定义文字清栈 16 字节且没有玩家参数，原有 J460 接口清栈 12 字节；原版大书为 47 个配置，独立声明对象大小和 Mega Mush Sprite 位置。规则提示索引回放先检查本机分类树大小，再调用不自带越界检查的原版入口。接口限制与所有权见[原生参考](https://github.com/BMingSY/isaac-lan/blob/main/docs/native-backend-j835.md#道具演出与屏幕状态)。

## 失败与未验证项

Home 门控夹具首次编译因 J835 专用 helper 在 J460 中未使用而失败，添加版本条件后通过。道具夹具首次编译存在模拟 Lua 回调参数和缺少头文件的问题；此时的 CTest 两项没有可执行文件，均未运行，不计为通过。

道具原生执行 R1 中，J460 因夹具对内嵌全局对象施加了过严对齐断言而终止；J835 退出但未输出诊断。修正该断言，并修正 x86 调用探针对嵌套药丸／卡牌调用的恢复栈保存后，R2 两版通过；补充重置／Game 失效及固定文字字节后，R3、R4 两版均通过。各轮日志保留为独立产物，未覆盖 R1 失败，最终没有未解决的本轮离线失败。

按用户要求没有启动游戏，没有游戏重启或存档／隔离资料恢复操作。夹具使用合成原生方法和资源，不能验证真实动画、美术、治疗、对象引用移除或 Home 路线推进。完整联机、Boss 和路线尚未实机验收；此前真实键盘菜单输入问题保持待验证，见[房间与音频记录](https://github.com/BMingSY/isaac-lan/blob/main/docs/history/repentance-room-audio-20261028.md)。

## 冻结产物

DLL 均为 J460 完整后端，J835 可执行文件只用于组件夹具。反编译、只读签名报告、原生 R1–R4 日志及失败记录保留在忽略的测试产物中。

| 候选 | 文件 | SHA-256 |
| --- | --- | --- |
| `19d66bd` | `isaac_lan_probe.dll` | `3a6f861b8f6abc45e56a6f0aa437e55c59fcbea23fd2c86d464e4923008f2584` |
| `19d66bd` | `isaac_lan_scene_update_j460_test.exe` | `7c40c89afb16f9923b4c64e9948c5e2171ee71a378980d5376e40e4fb9ef2885` |
| `19d66bd` | `isaac_lan_scene_update_j835_test.exe` | `4f92b7ad4bd076c4879ad23f7d065be0eff34942be7d231abe9e4ea202161edc` |
| `da63542` | `isaac_lan_probe.dll` | `9e1ae3c5a19ba62d2b86ad87fab542f52009825307ce4876ce6e83b6d324505c` |
| `da63542` | `isaac_lan_item_presentation_j460_test.exe` | `2813231ad370b3b420b43a3f8d05ff4ce55800c8bd115db78a90f3f73a0dbcd4` |
| `da63542` | `isaac_lan_item_presentation_j835_test.exe` | `2536aecb93a486b9be9fd7a74e91415458aa3514c6ec82b13ffbf3521dafc06c` |
