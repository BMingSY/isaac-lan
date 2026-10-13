# 历史验收与调查

这里保存各轮构建、夹具、结果和失败记录，版本号与测试数量属于当时的运行。当前实现和执行命令见[技术文档](https://github.com/BMingSY/isaac-lan/blob/main/docs/README.md)；这些记录不代表最新代码已经实机验收。

验收日志、DLL、录像和转储通常不入库。记录以日期、轮次和文件名标识原始证据，不附本机目录地址。

## 同步、兼容与路线

| 记录 | 查阅内容 |
| --- | --- |
| [分层重构](https://github.com/BMingSY/isaac-lan/blob/main/docs/history/layer-refactor-validation.md) | 原分层批次的基线、原生入口对比和十项集中场景 |
| [共享状态](https://github.com/BMingSY/isaac-lan/blob/main/docs/history/shared-state-bugfix-validation.md) | 诅咒、地下室返回、教条预警及中断轮次 |
| [共享开门概率](https://github.com/BMingSY/isaac-lan/blob/main/docs/history/shared-deal-chances-validation.md) | 原生概率、门类型、跨房／换层与通关证据 |
| [队伍兼容与合成袋](https://github.com/BMingSY/isaac-lan/blob/main/docs/history/party-compatibility-validation.md) | 跟班、商店、公共效果、口袋／药丸、死亡证明、跑圈、安装器及合成袋覆盖边界 |
| [Issue 回归](https://github.com/BMingSY/isaac-lan/blob/main/docs/history/issue-regressions.md) | 用户反馈、定向补测与各批次验收范围 |
| [暂停菜单](https://github.com/BMingSY/isaac-lan/blob/main/docs/history/pause-menu-validation.md) | 本机菜单与设置、暂停恢复、离队重连和保存续玩 |
| [角色与支线](https://github.com/BMingSY/isaac-lan/blob/main/docs/history/side-route-regressions.md) | 特殊角色、矿车／追逐、回溯与最终 Boss 汇合 |
| [贪婪模式](https://github.com/BMingSY/isaac-lan/blob/main/docs/history/greed-mode-validation.md) | 波次、购物、七层流程、最终战及夹具调试 |
| [六条结局](https://github.com/BMingSY/isaac-lan/blob/main/docs/history/ending-regressions.md) | 六路线固定条件、原生结局与增量同步验收 |

## 性能与原生诊断

| 记录 | 查阅内容 |
| --- | --- |
| [世界视图带宽方案](https://github.com/BMingSY/isaac-lan/blob/main/docs/history/world-state-bandwidth-plan.md) | 协议 25 时期的无损增量设计、预算和测量条件 |
| [百变怪性能调查](https://github.com/BMingSY/isaac-lan/blob/main/docs/history/delirium-performance-investigation.md) | 共享带宽对照、四人回放命令、结果与未定位异常 |
| [测试夹具堆损坏](https://github.com/BMingSY/isaac-lan/blob/main/docs/history/heap-corruption-regression.md) | 菜单越界写入证据、启动前解锁修复、退出及堆观察验证 |

## LANBOT

| 记录 | 查阅内容 |
| --- | --- |
| [初版接入](https://github.com/BMingSY/isaac-lan/blob/main/docs/history/lanbot-initial-validation.md) | 控制台、本机接管、人工切换及最初覆盖边界 |
| [普通路线](https://github.com/BMingSY/isaac-lan/blob/main/docs/history/lanbot-verification.md) | 定向行为、保护／加速通关和失败履历 |
| [九蜘蛛演示](https://github.com/BMingSY/isaac-lan/blob/main/docs/history/lanbot-spider-demo.md) | 无射击场景、扣血时间及录像位置 |
| [走位优化](https://github.com/BMingSY/isaac-lan/blob/main/docs/history/lanbot-dodge-optimization.md) | 近身敌群策略迭代、原生模型差异与演示问题 |
| [贪婪挑战](https://github.com/BMingSY/isaac-lan/blob/main/docs/history/lanbot-greed-challenge.md) | 指定配装双人／四人通关、分配策略与进店入口专项 |

固定种子、保护或加速夹具的通过不能推广为随机裸装通关；单场正常退出也不能排除所有间歇原生错误。后续结果应明确新增覆盖，不覆盖原失败记录。
