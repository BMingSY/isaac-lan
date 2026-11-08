# 2026-11-08 网络与同步延迟 HUD 验证

候选为 `feat/network-sync-latency` 工作区，基于 `a2bbc5c8db81c17b4b6011f91b51430503eb4edc`。网络协议为 49，世界 schema 不变。本次只验证延迟测量、报告与显示，不属于完整发布验收。

| 产物 | SHA-256 |
| --- | --- |
| Windows x86 Release DLL，两轮相同 | `0cb4dd0a98a7eb1587e9705b494ef7f5d3c0e770a286a9a1d97bf3e5ccc67b62` |
| 第一轮夹具 | `37240dd4a6412405938e69dc8cf2f0cdbb9fcf7bac4af28bac4ced18024d5e70` |
| 第二轮夹具 | `929a961e067121260b72b2fc63310f0eef8875d4d778a9976da6fadf14ea62a5` |
| Repentance+ v1.9.7.17.J460 游戏程序 | `7122ac28779925b24e23e2416f231322b1470388bd25e2c08665ad8d53b3ea4f` |

## 离线检查

Windows x86 DLL、网络测试程序和实机工具构建通过；格式、脚本语法和差异空白检查通过。

- 6 项 Linux CTest：`runtime.latency`、`diagnostics.bounded-metrics`、`presentation.timeline`、`bridge.ping_hud`、`bridge.layers`、`bridge.prediction`。
- 11 项 Windows UDP CTest：`latency-hud`、`async-network`、`inputs-2/3/4`、`floor-rejoin`、`stage-events`、`restart`、`compatibility-versions`、`compatibility-rejoin`、`compatibility-wire`。

覆盖输入合并、重复／倒序确认、环形缓冲淘汰、过期样本转发、三人间报告、断线、旧楼层报告和重开清理。HUD 测试覆盖四人位置、未知数值、长数值和屏幕边界。预测使用的最近 RTT 不随显示值过期而清空。

## 实机结果

使用[延迟 HUD 夹具](https://github.com/BMingSY/isaac-lan/blob/main/tests/state_ping_hud.lua)，每轮只启动一组有归属标记的主客机，复用进程及连接完成换房、换层、隐藏 HUD、菜单覆盖和数值检查。中继每方向增加 25 ms；诊断性能日志关闭，双方每 500 ms 保存原生画面。该采集配置用于功能与计时验证，不作为帧率基准。

| 轮次／证据标识 | 结果 |
| --- | --- |
| `latency-hud-20261108/run-01` | 未通过。转房时观察器报告测量不一致（84 ms／149 ms）；渲染回调不能保证发生在当前状态应用提交之后。保留原始日志与画面，双方正常关闭并恢复隔离资料。 |
| `latency-hud-20261108/run-02` | 通过。将计时检查放在下一次应用开始、上一次 C++ 提交之后，使用独立壁钟计时；629 次比较的最大差值为 1.357 ms。同步暂停 5 秒后两端显示失效，网络仍有效；恢复后重新测得同步值。每次应用额外等待 100 ms 时，实机画面可见“网络 50 ms、同步 207 ms”。 |

第二轮重启是因为第一轮的测试断言中止了场景，需要修正观察器后重跑；生产 DLL 未改动。每轮均正常关闭两端，恢复 6 个隔离目录，逐文件核对原有 4 个文件的哈希。结束后没有残留游戏进程。

两端中文字体、HUD 归属和换层后的显示均通过画面核对。四人实机画面、广域网丢包和带宽受限情形未做本次专项验证；不能据此认定玩家反馈的卡顿根因。

## Ping／同步显示格式

同日将显示调整为 `Ping 50 ms / 同步 84 ms`，每项保留名称和单位，未知值仍使用 `—`。仅修改表现文案与对应离线断言，测量和协议未改。HUD 离线测试、Windows x86 构建、格式与差异检查通过。

第三轮 `latency-hud-20261108/run-03` 使用 DLL `c9c9ac13e442c9b0464d52258886309754240422ca14bd27d87866c216ca2b53`，夹具与第二轮相同；因显示代码重新构建，重新启动一组主客机完成同一 HUD 场景。两端断言通过，655 次计时比较的最大差值为 1.384 ms；正常数值、长数值、未知值和屏幕边界经画面核对。两端正常关闭，6 个隔离目录恢复，原有 4 个文件的哈希一致，无残留游戏进程。

## 最新主分支上的复验

PR 候选 `ec7f07ffdcce79e9433b234575052d4b52042f2b` 接在主分支 `15eaf29` 上，包含其启动和更新提示改动。格式、脚本检查及 Windows x86 构建通过；上述 6 项便携测试及 11 项 UDP 测试重新通过，并通过 `bridge.challenge_menu`、`presentation.update-notice`，核对菜单集成。

第四轮 `latency-hud-20261108/run-04` 使用 DLL `eeec6b5a3acba109b70b6a80ffd64b3752b5e6a412628c7214c698904a895078`，夹具与第三轮相同。因主分支的菜单与启动代码变化，重新启动一组主客机完成相同场景；两端断言和 HUD 画面通过，651 次计时比较的最大差值为 1.281 ms。两端正常关闭，6 个隔离目录及原有 4 个文件哈希恢复一致，无残留游戏进程。
