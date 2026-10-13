# 技术文档

安装和联机操作见[项目 README](../README.md)。下面按当前任务查阅；历次构建、通关轮次和失败证据统一放在[历史验收索引](history/README.md)。

## 从这里开始

| 任务 | 文档 |
| --- | --- |
| 理解整体方案 | [架构概览](architecture.md) |
| 选择修改位置、核对所有权与恢复顺序 | [分层与玩法兼容](layers-and-compatibility.md) |
| 构建、离线回归、失败回放、集中实机验收 | [开发与测试](development-and-testing.md) |
| 排查日志、性能、资源和堆异常 | [诊断参考](diagnostics-and-resource-testing.md) |

## 实现参考

| 主题 | 文档 |
| --- | --- |
| 输入、快照、预测、压缩与背压 | [网络与状态同步](synchronization.md) |
| 开局、换层、存档、重连与回退 | [会话与状态恢复](session-lifecycle.md) |
| 房间上下文、迁移、HUD、音画与 Mod 回调 | [分房与本机显示](rooms-and-presentation.md) |
| 跟班、公共道具、角色、口袋槽、合成袋与重开 | [队伍兼容](party-compatibility.md) |
| 全队开门概率及原生查询 ABI | [共享恶魔／天使房概率](shared-deal-chances.md) |
| 里 Lost 的原版生成规则与反汇编依据 | [生成特性参考](tainted-lost-item-generation.md) |
| 第三方本机视图、生命周期和主机动作 | [Mod 接入 API v1](third-party-mod-integration.md) |
| 托管命令和支持范围 | [LANBOT 使用说明](lanbot.md) |
| 托管观察、规划、战斗与输入契约 | [LANBOT 实现与约束](lanbot-design.md) |

维护时在所属文档更新当前契约，其他页面用链接引用；测试结果注明构建、夹具和范围后放入 `history/`。历史失败不改记为通过，未执行项目不因文档整理而变为已验收。代码协作与发布要求见 [AGENTS.md](../AGENTS.md)。
