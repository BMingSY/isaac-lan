# 技术文档

这些文档描述当前源码的架构、公开接口与约束。安装和联机操作见[项目 README](../README.md)。

| 文档 | 内容 |
| --- | --- |
| [架构与技术选择](architecture.md) | 模块分工，状态同步、TCP 与原生 DLL 的选择依据 |
| [分层与玩法兼容](layers-and-compatibility.md) | 目录边界、状态所有权、Boss／角色／道具适配与扩展流程 |
| [分层重构验证记录](layer-refactor-validation.md) | 离线、Windows 构建与集中实机验收的范围和结果 |
| [共享状态修复验证](shared-state-bugfix-validation.md) | 共享诅咒、回溯地下室返回、教条预警的实现边界与回归结果 |
| [贪婪模式验证](greed-mode-validation.md) | 贪婪／超级贪婪波次、购物、换层与终点汇合的离线覆盖和实机记录 |
| [网络与状态同步](synchronization.md) | 输入、状态包、可靠事件、预测、校验与延迟 |
| [分房模拟与本机显示](rooms-and-presentation.md) | 房间上下文、实体归属、镜头、UI、音效与 Mod 回调 |
| [会话与状态恢复](session-lifecycle.md) | 开局、换层、暂停、存档、重连与回退事务 |
| [开发与测试](development-and-testing.md) | 源码入口、构建产物、隔离客户端、连续回归与画面检查 |
| [第三方 Mod 接入 API v1](third-party-mod-integration.md) | 本机视图、主机动作、自动兼容注册，以及 Stats+、GoodTrip、EID 的内置兼容与边界 |
| [LAN 人机托管使用说明](lanbot.md) | 原生控制台命令、目标模式、战斗风格、人工接管与实现边界 |
| [LAN 人机托管设计](lanbot-design.md) | 本地规划、实时走位、输入接管、后续实机验收与可选 Agent 扩展 |

维护时应同时更新对应代码和文档。具体字段、版本号与限制以源码为准；本文中的测试流程说明如何验证，不代表某次运行已经通过。
