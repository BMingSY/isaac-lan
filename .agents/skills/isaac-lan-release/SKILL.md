---
name: isaac-lan-release
description: "准备和发布 Isaac LAN 新版本：按大小版本安排验收，通过 GitHub 自动发版 CI 发布正式包，同步 Steam 创意工坊版本和介绍顶部的当前版本说明。用于发版准备、发版验收、正式发布及发布中断后的核对。"
---

# Isaac LAN 发版

在仓库根目录操作。先读 [AGENTS.md](https://github.com/BMingSY/isaac-lan/blob/main/AGENTS.md)，按下列流程准备、验收并发布；仅请求准备或验收时，完成该阶段即可，不推标签或更新远端。

## 确定版本与范围

用户指定的大小版本分类和验收范围优先。未指定时，补丁号变化为小版本（如 `0.7.1 → 0.7.2`），次版本或主版本变化为大版本（如 `0.7.x → 0.8.0` 或 `1.0.0`）。

| 版本规模 | 实机验收范围 |
| --- | --- |
| 小版本 | 基本验收 + 全路线验收 |
| 大版本 | 小版本全部范围 + 全部原版 Boss |

大版本根据相对上次发布的实际变更，自行选定并执行必要的额外验收，无需等待用户逐项选择：安装器或加载器变化检查旧版安装／配置升级与工坊重启更新；会话或存档变化检查异常断线／退出及续玩；协议或传输变化检查版本兼容与弱网恢复；玩法兼容变化检查受影响的道具／角色／第三方 Mod；表现或高频链路变化检查输入／镜头、性能或压力。说明选项与变更的关系，影响范围不明时扩大相关回归，不机械遍历全部专项。可引用适用于本次候选的开发验收证据，避免重复执行；用户明确限定的范围优先。

核对上一次**已发布**标签、目标版本、候选提交及其完整差异。更新 `VERSION`；文案汇总从上次发布到候选的全部玩家可感知变化，不能只看最近一个 PR。

## 构建与验收

按[开发与测试](https://github.com/BMingSY/isaac-lan/blob/main/docs/development-and-testing.md#默认发版范围)执行离线 full、Windows x86 构建、网络／原生 ABI 检查及安装包校验。两种版本规模均保留这些检查，区别只在实机范围。冻结候选提交、DLL、夹具、安装包和 SHA-256。

- **基本验收**：使用 [run_release_acceptance.py](https://github.com/BMingSY/isaac-lan/blob/main/tools/run_release_acceptance.py) 的完整默认用例，包含安装／自动加载、正常输入、拾取、分房／换层、沙漏、暂停与单人／联机存档保护。安装包与构建必须匹配。
- **全路线验收**：六结局（羔羊、???、Delirium、Mega Satan、Mother、Beast）及普通贪婪、贪婪＋、矿车／逃亡、Hornfel。优先用 [run_special_routes.py](https://github.com/BMingSY/isaac-lan/blob/main/tools/run_special_routes.py) 组合 `--case knife --case hornfel --case greed --case greedier --case endings --first-floor`，`endings` 必须放最后；单独复测结局可用 [run_endings.py](https://github.com/BMingSY/isaac-lan/blob/main/tools/run_endings.py) 的 `--first-floor`。按[结局证据解析器](https://github.com/BMingSY/isaac-lan/blob/main/tools/testing/endings.py)逐路线核对双端胜利、清理、进度恢复和 Mother 完整支线楼层，不能只凭组合套件结束标记计为通过。
- **全 Boss，仅大版本**：使用 [run_bosses.py](https://github.com/BMingSY/isaac-lan/blob/main/tools/run_bosses.py) 覆盖完整目录并实际触发原生阶段；用 [check_boss_coverage.py](https://github.com/BMingSY/isaac-lan/blob/main/tools/check_boss_coverage.py) 合并 Boss、结局、贪婪报告，双端均无缺项。组合路线时，将上述解析器核对的六结局证据保存为标准 ending 报告，再交给覆盖工具，不以 special 套件的完成标记替代结局证据。

实机沿用仓库的隔离资料保护、独立端口、单一执行者调度及进程复用约定。启动前安排分组，不直接逐项运行会反复启动的入口。原生场景使用工具的 `--heap-check` 并保留必要双端画面；失败另开复测轮次，结束后正常退出、恢复资料并核对哈希。用户要求不启动游戏时，将实机项保留为待验证，不宣称验收通过或直接发布。

## 审阅文案与准备提交

将拟发布正文保存为 `.github/release-notes/vX.Y.Z.md`，按实际变化使用“新特性”“BUG修复”“体验优化”，省略空分类。先在对话展示完整拟发布文案，同时展示工坊介绍顶部的目标版本标题与替换文本，取得明确确认；已有批准且措辞不变时直接复用，不重复询问。措辞再次改动须重新审阅。

`VERSION`、已确认文案和生产代码须包含在最终发布提交中，必要时通过版本准备 PR 合入 `main` 并等待 CI 通过。验收记录默认保留在本地测试产物，不随版本准备提交，也不为记录单独提 PR 或合并；用户明确要求入库时才写入 `docs/history/`。保留失败、未验证项、已知问题和恢复结果，不改写旧记录。

## 通过 GitHub CI 自动发布

必须使用 [release.yml](https://github.com/BMingSY/isaac-lan/blob/main/.github/workflows/release.yml)。获准发布且上述准备完成后，在核对过的最终提交创建并推送与 `VERSION` 一致的 `vX.Y.Z` 标签；标签触发 **Build and release**，由其构建、运行 Windows 测试、打包并创建 GitHub Release。手动调度若使用分支只会构建，不会发布；需要恢复发布时使用已核对的标签。

等待该标签的 workflow 所有必需任务成功，确认运行的提交与冻结候选对应、Release 正文与确认文件一致，ZIP 和 `.sha256` 附件齐全。不能用本地 `gh release create`、手动上传安装包或本地构建结果绕过发布 CI。已有标签或 Release 时先核对状态，不移动标签或重复创建。

从 GitHub 下载**正式附件**，用 [check_release.py](https://github.com/BMingSY/isaac-lan/blob/main/tools/check_release.py) 校验版本、清单、哈希、架构和依赖，并与验收候选核对。哈希不同时先查明差异，不直接把候选验收结论套用到不同代码。后续工坊内容必须来自本次正式附件。

## 同步创意工坊

按[工坊发布流程](https://github.com/BMingSY/isaac-lan/blob/main/docs/steam-workshop-release.md)使用 `tools/workshop_release.py`，更新现有条目 `3817760679`（App ID `250900`）。`prepare` 会将 `metadata.xml` 的版本更新为目标版本，并从正式 ZIP 提取自动更新主体及清单。

**每次发版必须同时更新默认语言和简体中文介绍顶部的版本内容**，只更新上传文件或更新记录不算完成：

1. 读取远端两种语言的现有介绍，确认顶部实际旧版本。它可能落后于上次 Release，不能直接假定为上次标签。
2. 常规更新使用 `prepare --replace-notes-version <顶部实际旧版本>`，替换 `-----` 之前的旧版本说明，保留分隔线后的原项目介绍、反馈入口和源码链接；不累积历史版本段落。
3. 只有两种语言都没有版本前缀、需要首次建立顶部说明时才用 `--prepend-notes`。版本或结构不一致时先核查并准备修正后的完整文本，不能改用 prepend 堆叠说明或删除原介绍。标题、封面、标签与可见性沿用现值。
4. 检查 `metadata.xml`、更新清单、`reviewed-notes.md`、`steam-change-notes.txt`、两份 `description-*.txt` 和 `preparation.json`，确认目标版本、正式包哈希与已确认文案一致，再执行 `publish`。

两种语言均须取得成功回执且无待接受协议；随后重新下载逐文件核对，确认 Mod 版本、自动更新主体、两种语言顶部的目标版本与本次内容正确。按工具的 `verify` 复查标题、介绍和可见性，查看公开更新记录；网页限流时分别记录 API／下载结果和网页未核对项。上传中断或结果不明时先 `verify`，不重复上传或追加更新记录；恢复步骤见工坊文档。

若本次包含加载器／自动更新改动，或用户要求重启验证，再安排实际 Steam 启动检查：确认实际加载的版本路径和 DLL 哈希对应本次正式文件，正常关闭并恢复测试资料。报告发布链接、实际验收范围、工坊核对结果和未决项。
