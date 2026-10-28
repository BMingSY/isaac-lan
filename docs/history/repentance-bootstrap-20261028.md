# 原版忏悔更新与渲染入口离线记录

2026-10-28，分支 `refactor/multiversion-backends`，候选 `77270d018757c8200a25e6000ffb6b415db02f34`。共享更新与渲染装配已接入 J835 原生绑定；J460 的双房间诊断实验保持独立组件。J835 仍无 `sources.cmake`，完整房间调度、实体姿态及表现能力尚未接通，不能生成完整可安装联机 DLL。本记录不属于实机或发布验收。

## 范围与结果

| 检查 | 结果 |
| --- | --- |
| Windows x86 Release | J460 DLL 和两版更新／渲染夹具构建通过 |
| `native.bootstrap-j460`／`native.bootstrap-j835` | 通过实际 Hook 安装、第二入口冲突回滚、外部 Hook 保留、重试及重复安装拒绝；渲染入口独立安装检查通过 |
| 调用顺序与生命周期 | 普通／托管房间更新、半帧门控与完成通知、本机输入视图、渲染异常恢复、空上下文及重复插值恢复通过；失败的半帧不会发布完成通知 |
| J460 诊断实验 | 生产实验组件的前台／后台更新、双房间半帧与渲染上下文通过；前台和后台原生更新抛异常后均恢复完整三字玩家名单 |
| Lua 原生接口 | 真实符号查找和接口注册通过；帧计数回绕及有界诊断轨迹通过 |
| 可移植关联检查 | `core.bootstrap-profile`、`core.room-scope-ownership` 通过；分层、版本和文档链接检查共 32 项通过 |
| 静态入口核对 | 83 项 J835 入口签名与重定位掩码均匹配目标程序 |
| 格式与差异 | `tools/format.py --check`、`git diff --check` 通过 |

原版程序 SHA-256 为 `04469d0c3d3581936fcf85bea5f9f4f3a65b2ccf96b36310456c9626bac36dc6`。原生入口依据实际调用者、参数传递和返回指令核对。定位过程中排除了 `0x3b8b10`：它处理房间清空状态，不是房间更新入口；提交使用已核对的 `0x3bf630`。

## 限制与未验证项

按用户要求未启动游戏，没有游戏重启或隔离资料恢复操作。测试执行扩展组件及合成 x86 边界，不验证真实房间分配／销毁、画面、完整联机或发布默认范围。静态入口核对不能替代真实更新与渲染验证。

诊断实验的异常用例暴露原有前台更新失败时名单截断未恢复的问题，提交已补充作用域恢复并通过回归。此前真实键盘菜单输入问题仍待验证，参见[房间与音频记录](https://github.com/BMingSY/isaac-lan/blob/main/docs/history/repentance-room-audio-20261028.md)。

## 冻结产物

| 文件 | SHA-256 |
| --- | --- |
| `isaac_lan_probe.dll` | `c62c9cd4bd0aac615ade6de2511797992e7e56e0a6c5488fb0228939383bc32e` |
| `isaac_lan_bootstrap_j460_test.exe` | `9ed3212746362db52499aa6369b22c8dc9afde0fb76c606c8c5fe85287f3d4a4` |
| `isaac_lan_bootstrap_j835_test.exe` | `bec05151cb4897d29e9407ac30cf5d034384454285a30adddf3edfb60eccdb82` |

产物清单、`loop-signatures.json`、`loop-abi.json`、定向反编译导出和日志保留为忽略的测试产物，未提交原始游戏代码或二进制。
