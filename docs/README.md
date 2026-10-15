# 技术文档

安装和联机操作见[项目 README](https://github.com/BMingSY/isaac-lan/blob/main/README.md)。下面按当前任务查阅；历次构建、通关轮次和失败证据统一放在[历史验收索引](https://github.com/BMingSY/isaac-lan/blob/main/docs/history/README.md)。

## 从这里开始

| 任务 | 文档 |
| --- | --- |
| 理解整体方案 | [架构概览](https://github.com/BMingSY/isaac-lan/blob/main/docs/architecture.md) |
| 选择修改位置、核对所有权与恢复顺序 | [分层与玩法兼容](https://github.com/BMingSY/isaac-lan/blob/main/docs/layers-and-compatibility.md) |
| 构建、离线回归、失败回放、集中实机验收 | [开发与测试](https://github.com/BMingSY/isaac-lan/blob/main/docs/development-and-testing.md) |
| 排查日志、性能、资源和堆异常 | [诊断参考](https://github.com/BMingSY/isaac-lan/blob/main/docs/diagnostics-and-resource-testing.md) |

## 实现参考

| 主题 | 文档 |
| --- | --- |
| 输入、快照、预测、压缩与背压 | [网络与状态同步](https://github.com/BMingSY/isaac-lan/blob/main/docs/synchronization.md) |
| 开局、换层、存档、重连与回退 | [会话与状态恢复](https://github.com/BMingSY/isaac-lan/blob/main/docs/session-lifecycle.md) |
| 房间上下文、迁移、HUD、音画与 Mod 回调 | [分房与本机显示](https://github.com/BMingSY/isaac-lan/blob/main/docs/rooms-and-presentation.md) |
| 跟班、公共道具、角色、口袋槽、合成袋与重开 | [队伍兼容](https://github.com/BMingSY/isaac-lan/blob/main/docs/party-compatibility.md) |
| 挑战定义、终点、循环观察与扩展接口 | [联机挑战](https://github.com/BMingSY/isaac-lan/blob/main/docs/lan-challenges.md) |
| 全队开门概率及原生查询 ABI | [共享恶魔／天使房概率](https://github.com/BMingSY/isaac-lan/blob/main/docs/shared-deal-chances.md) |
| 里 Lost 的原版生成规则与反汇编依据 | [生成特性参考](https://github.com/BMingSY/isaac-lan/blob/main/docs/tainted-lost-item-generation.md) |
| 当前原版角色效果的额外处理与边界 | [角色兼容记录](https://github.com/BMingSY/isaac-lan/blob/main/docs/character-compatibility.md) |
| 道具、饰品、卡牌、药丸、诅咒、传送与回退 | [道具与效果兼容记录](https://github.com/BMingSY/isaac-lan/blob/main/docs/item-effect-compatibility.md) |
| Stats+、GoodTrip、EID 的精确目标、适配与限制 | [第三方 Mod 兼容记录](https://github.com/BMingSY/isaac-lan/blob/main/docs/mod-compatibility.md) |
| 第三方本机视图、生命周期和主机动作 | [Mod 接入 API v1](https://github.com/BMingSY/isaac-lan/blob/main/docs/third-party-mod-integration.md) |
| 托管命令和支持范围 | [LANBOT 使用说明](https://github.com/BMingSY/isaac-lan/blob/main/docs/lanbot.md) |
| 托管观察、规划、战斗与输入契约 | [LANBOT 实现与约束](https://github.com/BMingSY/isaac-lan/blob/main/docs/lanbot-design.md) |

维护时在所属文档更新当前契约，其他页面用链接引用；测试结果注明构建、夹具和范围后放入 [`history/`](https://github.com/BMingSY/isaac-lan/tree/main/docs/history)。历史失败不改记为通过，未执行项目不因文档整理而变为已验收。代码协作与发布要求见 [AGENTS.md](https://github.com/BMingSY/isaac-lan/blob/main/AGENTS.md)。
