# 文档索引

安装和联机操作见[项目 README](https://github.com/BMingSY/isaac-lan/blob/main/README.md)，常见问题见 [FAQ](https://github.com/BMingSY/isaac-lan/blob/main/docs/faq.md)。文档归属与审阅规则见 [AGENTS.md](https://github.com/BMingSY/isaac-lan/blob/main/AGENTS.md#文档边界与游戏内界面)。

## 当前架构与设计

| 主题 | 文档 |
| --- | --- |
| 整体方案与关键取舍 | [架构概览](https://github.com/BMingSY/isaac-lan/blob/main/docs/architecture.md) |
| 依赖、所有权与扩展位置 | [分层与兼容](https://github.com/BMingSY/isaac-lan/blob/main/docs/layers-and-compatibility.md) |
| 输入、状态流、传输与背压 | [网络与状态同步](https://github.com/BMingSY/isaac-lan/blob/main/docs/synchronization.md) |
| 开局、存档、重连与换层 | [会话生命周期](https://github.com/BMingSY/isaac-lan/blob/main/docs/session-lifecycle.md) |
| 分房、预测、HUD 与音画 | [房间与表现](https://github.com/BMingSY/isaac-lan/blob/main/docs/rooms-and-presentation.md) |
| 文字输入、命令、输出与气泡 | [聊天与控制台](https://github.com/BMingSY/isaac-lan/blob/main/docs/chat-console.md) |
| 托管观察、规划与输入 | [LANBOT 设计](https://github.com/BMingSY/isaac-lan/blob/main/docs/lanbot-design.md) |

## 功能、接口与兼容参考

| 主题 | 文档 |
| --- | --- |
| 原生能力、ABI 与所有权 | [J460 后端](https://github.com/BMingSY/isaac-lan/blob/main/docs/native-backend.md) |
| 兼容效果与当前验证状态 | [角色](https://github.com/BMingSY/isaac-lan/blob/main/docs/character-compatibility.md)、[道具](https://github.com/BMingSY/isaac-lan/blob/main/docs/item-effect-compatibility.md)、[第三方 Mod](https://github.com/BMingSY/isaac-lan/blob/main/docs/mod-compatibility.md) |
| 专项能力契约 | [错误道具定义](https://github.com/BMingSY/isaac-lan/blob/main/docs/generated-item-definitions.md)、[共享开门概率](https://github.com/BMingSY/isaac-lan/blob/main/docs/shared-deal-chances.md) |
| 挑战规则与接入 | [联机挑战](https://github.com/BMingSY/isaac-lan/blob/main/docs/lan-challenges.md) |
| 第三方接口与示例 | [Mod API](https://github.com/BMingSY/isaac-lan/blob/main/docs/third-party-mod-integration.md) |
| 托管命令与范围 | [LANBOT 使用](https://github.com/BMingSY/isaac-lan/blob/main/docs/lanbot.md) |

## 开发与验收

| 主题 | 文档 |
| --- | --- |
| 构建、检查与默认发版范围 | [开发与测试](https://github.com/BMingSY/isaac-lan/blob/main/docs/development-and-testing.md) |
| 日志、性能口径与堆异常 | [诊断参考](https://github.com/BMingSY/isaac-lan/blob/main/docs/diagnostics-and-resource-testing.md) |
| 2026-10-17 候选版本验收，未通过 | [v0.4.2 验收记录](https://github.com/BMingSY/isaac-lan/blob/main/docs/history/release-validation-20261017.md) |

设计文档只描述当前架构；专项接口和效果查参考文档，已执行的测试结论查 `docs/history/`。原始日志与画面保留在测试产物或 CI 附件中。
