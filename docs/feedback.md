# 反馈上传

玩家在游戏内提交问题描述，扩展把最近的日志打包上传到作者服务器，成功后返回反馈编号。反馈只由作者查看，不公开；上传在后台线程完成，不阻塞游戏。

## 入口

在联机大厅、联机游戏或等待期间，于[联机聊天](https://github.com/BMingSY/isaac-lan/blob/main/docs/chat-console.md)输入 `/feedback 问题描述`（别名 `/fb`）。原版控制台不提供该命令，`/c feedback` 也不会触发上传。

命令只在提交者本机执行，不发给其他玩家。描述不能为空，最多 4096 UTF-8 字节。同一时间只上传一条，两次提交至少间隔 30 秒。

## 收集范围

| 内容 | 包内路径 |
| --- | --- |
| 本次与上一次启动的联机日志目录（`startup.log`、各局 `runtime.log` 与 `performance.jsonl`） | `logs/<启动>/...` |
| 原版 `log.txt` | `game/log.txt` |
| `isaac-lan/config.ini` | `config/config.ini` |
| 描述、时间、扩展与游戏版本、会话阶段、已加载 Mod 名称、文件清单 | `feedback.json` |

包含上一次启动，是为了在崩溃重启后提交时仍带上崩溃那次的日志。每个文件只保留最新的 8 MiB，压缩后超过上限时逐步减半，最少保留 256 KiB；被截断的文件开头标明丢弃的字节数。

文本中的 Windows 用户目录（长路径与 8.3 短路径，`\`／`/`／`\\` 写法，不区分大小写）替换为 `%USERPROFILE%`，Steam `userdata\<数字>` 替换为 `userdata\<steamid>`。主机地址、端口、玩家名和存档种子保留，用于排查联机问题。

## 上传

请求为 `POST https://lzh-qwq.top/isaac-lan/feedback/v1/submit`，正文是 zip，附带 `X-Feedback-Submission`（每条反馈一个 UUID，重试复用）、`X-Feedback-Install`（每个安装一个 UUID，保存在 `isaac-lan/feedback/install-id`）和 `X-Feedback-Client`（`isaac-lan/<版本>`）。WinHTTP 优先使用系统代理设置。

| 结果 | 处理 |
| --- | --- |
| 服务器接受 | 显示编号，删除本地副本 |
| 无法连接或服务器 5xx | 同一幂等键在 5 秒、20 秒后各重试一次 |
| 格式错误、过大、频率超限、暂停接收 | 不重试，显示对应原因；暂停时显示服务器提供的说明 |

未被接受时，反馈包保留在日志目录旁的 `isaac-lan/feedback/` 中，提示里给出完整路径，可以直接发给作者。上传结果写入当前启动日志（`feedback_submitted` 或 `feedback_upload_failure`），不记录描述内容。

## 实验环境

隔离实验配置默认不上传。夹具需要验证上传时，在 `config.ini` 中加入未写入默认模板的 `[feedback] endpoint = <地址>`；地址必须是 `https://`，或指向本机的 `http://127.0.0.1:端口/...`、`http://localhost:端口/...`，其他值记录配置警告并停用上传。

## 代码位置

| 职责 | 位置 |
| --- | --- |
| zip、截断、脱敏、清单与响应解析（可离线测试） | [core/feedback.cpp](https://github.com/BMingSY/isaac-lan/blob/main/src/core/feedback.cpp) |
| 收集文件、后台上传与 Lua 绑定 | [diagnostics/feedback.cpp](https://github.com/BMingSY/isaac-lan/blob/main/src/diagnostics/feedback.cpp) |
| 提交与结果回送 | [bridge/diagnostics/feedback.lua](https://github.com/BMingSY/isaac-lan/blob/main/src/bridge/diagnostics/feedback.lua) |
| 聊天命令 | [bridge/runtime/chat.lua](https://github.com/BMingSY/isaac-lan/blob/main/src/bridge/runtime/chat.lua) |
