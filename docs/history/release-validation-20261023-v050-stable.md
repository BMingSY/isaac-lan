# v0.5.0 稳定候选复核：2026-10-23

稳定候选的构建、完整离线回归、Windows 网络／原生检查与安装包校验通过。默认功能验收沿用经源码差异核对的上一候选证据，不计为新 DLL 重跑。用户确认 500 种道具属于极少数场景，选择不以此阻塞本次发布；原压力失败及已知风险仍保留。发布文案尚待用户确认，没有创建公开版本或标签。

## 候选与变更边界

生产候选 `82cd506cee0e8f4276b1f9dc04cac8f159a4df0f`，基于主线 `f3e189320df3af55f904c3b1460874c15b334d55`，仅将 `VERSION` 从 `0.4.2` 改为 `0.5.0`。发布变更范围为上次已发布标签 `v0.4.2` 至本候选。[PR #108](https://github.com/BMingSY/isaac-lan/pull/108)、[PR #109](https://github.com/BMingSY/isaac-lan/pull/109) 和[封面资源 #111](https://github.com/BMingSY/isaac-lan/pull/111) 已包含；[原生压力保护草稿 #112](https://github.com/BMingSY/isaac-lan/pull/112) 不包含在本次候选中。

相对已完成默认功能矩阵的 `cc5ca87d76cbba0fd520e5b0080e413b42399246`，生产源码只增加本地 `poll.transport` 字段，并按该字段显示大厅 UDP／TCP 端口标签。没有修改游戏同步字段、传输算法、原生 ABI、Boss、道具、角色、房间或路线行为；版本号相同。其他差异为暂停夹具、菜单测试和封面。原功能轮次与失败记录完整保留在[2026-10-22 验收记录](https://github.com/BMingSY/isaac-lan/blob/main/docs/history/release-validation-20261022-v050.md)。

## 本候选检查

| 范围 | 结果 | 证据标识 |
| --- | --- | --- |
| 完整离线回归 | 124 项 CTest、514 项 Python 测试及 19 项子测试通过；无失败或跳过，ASan／LSan／UBSan、格式与脚本语法通过 | `offline-01` |
| Windows x86 | Release 构建及 201 项 CTest 全部通过，包含 61 项网络、12 项原生 ABI；PowerShell 格式／语法通过 | `windows-build-01`、`windows-ctest-01`、`powershell-format-01` |
| 实际游戏文件校验 | `1.9.7.17.J460` 文件与原生入口签名通过；只读文件，没有启动游戏 | `native-signatures-01` |
| 大厅显示增量 | 实际菜单 Lua 的渲染输出在 UDP／TCP、主机／客机、空闲／大厅共 8 组输入下通过；原生字段来源经源码核对 | `menu-transport-01` |
| 安装包 | ZIP、版本、清单哈希、x86 PE 和系统依赖校验通过 | `package-01`、`package-check-01` |

离线执行开始时为主线加未提交的版本号，执行中将同一 VERSION 内容提交为 `82cd506`，源码字节没有变化。两组构建使用低优先级、双任务，没有运行新的游戏压力场景，也没有把本轮并行检查用于性能比较。

| 冻结产物 | SHA-256 |
| --- | --- |
| `isaac_lan_probe.dll` | `6ebc843c0cef9d4c0f1f5324a5343e5482db0dcd07287b43a99327bd20b5ff6a` |
| `winmm.dll` | `4fc438a6a89942a8a0808a0894ef7b98e113cbbccfbf7f55d97352a775e591d5` |
| `isaac_lan_check.exe` | `6111369df5831e1e455460776d34ccd81a3e59ee4fb04bb15f810fe5efea0fd1` |
| `isaac_lan_lab.exe` | `5b83e069425c9df1e79d6be6e9e2702bb4cf3bc7facbe06c11ce42c1a07954ae` |
| `isaac_lan_heap_watch.exe` | `17a88836facadedfd42f401dfe063e9be013c7fb8d90b73d61ac7174c5338df5` |
| `Isaac-LAN-v0.5.0-windows-x86.zip` | `7daf64084a17155364f8a63f0907eb314274cf293e36e123a8299c450d715d56` |
| 生产候选源码归档 | `d667e9609920f7b7da1095f13c3e58e4d045a4b4b42914b31e45cbb3a93c2f4f` |

`candidate` 清单记录源码、夹具、工具及二进制哈希；原始检查报告保留在 `v050-stable-20261023` 产物中。后续发布文案与验收记录的提交不改变上述生产源码和冻结二进制。

## 沿用的实机证据

下列结果仍归属于原候选 `cc5ca87`，其探针 DLL SHA-256 为 `1db9938c26aa44f64d64d10c0ae3817ea1c6de860f2d90ff31b840b56cabe0a1`。只因本地状态字段与大厅标签的变化，不重跑未受影响的玩法矩阵。

| 默认范围 | 原轮次与结果 |
| --- | --- |
| 安装与基础联机 | `installed-02`，8 项双端通过，包含自动加载、战斗／拾取、分房／换层、沙漏、暂停和单人→联机→单人存档保护 |
| 全部可玩原版 Boss | `bosses-shard0-01`／`bosses-shard1-01`，107／107 双端通过，含原生阶段机制 |
| 六条结局 | `routes-endings-01`，羔羊、???、Delirium、Mega Satan、Mother、Beast 均完成结局及清理；羔羊从第一层推进，Mother 双端经过完整支线 |
| 贪婪与路线机制 | 同轮 greed、greedier、knife、Hornfel 双端通过；汇总路线 Boss 14／14，无缺项 |
| 退出与恢复 | 四个最终功能组双端退出码 0、堆转储 0；六个隔离资料下 18 个保护目录逐文件哈希恢复通过 |

本轮没有启动新的自动化游戏验收进程。用户体验所用双端为原冻结候选，单向中继 40 ms，画面显示 81 ms、连接状态约 84–85 ms；进入正常开局后撤掉自动连接观察逻辑，交由用户操作。此观察不是本候选的功能或性能验收成绩；用户关闭两端后由独立管理程序恢复其隔离资料。

## 保留的问题

原候选在 500 种道具主动压力下出现停顿／断线，独立诊断轮有主机访问异常和客机堆损坏，不能降格为仅有低帧率。极限实体覆盖缺口、部分持续攻击采样不足及 TCP 弱网状态年龄超出观察线也保留原结论；按用户要求本次不继续 TCP 专项。原生压力保护及后续 500 种道具仍未按时完成的结果留在独立草稿，不把其局部改善计入此发布。

本次发布判断是采用已通过正常玩法范围的稳定候选并接受上述极端场景限制，不表示 500 种道具、全部角色／第三方 Mod 或所有性能均已验证。没有改写旧轮次、删除旧失败或新增 README／游戏内提示文字。
