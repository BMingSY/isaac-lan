# 代码结构与修改位置

先按改动的职责选择模块，不以调用入口或现有大文件的位置决定归属。整体依赖与所有权见 [docs/layers-and-compatibility.md](https://github.com/BMingSY/isaac-lan/blob/main/docs/layers-and-compatibility.md)。

| 要修改的内容 | 应修改的位置 | 边界 |
| --- | --- | --- |
| 自动加载、启动装配、组件注册与调用顺序 | [`src/app/`](https://github.com/BMingSY/isaac-lan/tree/main/src/app)、[`src/bridge/app/`](https://github.com/BMingSY/isaac-lan/tree/main/src/bridge/app) | 组合已有组件，不承载新的玩法规则 |
| TCP、消息、分块、压缩、连接与协议 | [`src/net/`](https://github.com/BMingSY/isaac-lan/tree/main/src/net) | 不访问游戏对象，不识别 Boss、角色或道具 |
| 状态字段、采集／应用、编码、库存、实体与网格一致性 | [`src/bridge/sync/`](https://github.com/BMingSY/isaac-lan/tree/main/src/bridge/sync) | 负责通用同步契约，特殊玩法通过注入兼容组件处理 |
| 会话推进、存档／恢复、换层屏障、房间与角色生命周期 | [`src/runtime/`](https://github.com/BMingSY/isaac-lan/tree/main/src/runtime)、[`src/bridge/runtime/`](https://github.com/BMingSY/isaac-lan/tree/main/src/bridge/runtime) | 协调执行时机与状态失效，原生对象的分配／释放由后端处理 |
| Boss、道具、角色、路线与挑战的特殊规则 | [`src/compat/{bosses,items,characters,routes,challenges}/`](https://github.com/BMingSY/isaac-lan/tree/main/src/compat)、[`src/bridge/compat/`](https://github.com/BMingSY/isaac-lan/tree/main/src/bridge/compat) 对应分类 | C++ 策略接收普通值；Lua 适配使用游戏 API 和具名原生能力 |
| 第三方 Mod 的探测、注册、接入与卸载 | [`src/bridge/compat/mods/`](https://github.com/BMingSY/isaac-lan/tree/main/src/bridge/compat/mods) | 保留目标版本／源码探测和清理边界，不修改上游 Mod 源码 |
| 对第三方公开的接口、动作与生命周期通知 | [`src/bridge/api/`](https://github.com/BMingSY/isaac-lan/tree/main/src/bridge/api) | 更新接口契约与接入文档，不暴露原生指针或任意内存读写 |
| 联机人机托管、观察、探索、寻路与避险 | [`src/bridge/lanbot.lua`](https://github.com/BMingSY/isaac-lan/blob/main/src/bridge/lanbot.lua)、[`src/bridge/lanbot/`](https://github.com/BMingSY/isaac-lan/tree/main/src/bridge/lanbot) | 读取现有视图并合成正常输入；不改权威玩法或同步规则，验收夹具放 [`tests/`](https://github.com/BMingSY/isaac-lan/tree/main/tests) 和 [`tools/`](https://github.com/BMingSY/isaac-lan/tree/main/tools) |
| 菜单、预测、插值、镜头、外观、音效与本机演出 | [`src/presentation/`](https://github.com/BMingSY/isaac-lan/tree/main/src/presentation)、[`src/bridge/presentation/`](https://github.com/BMingSY/isaac-lan/tree/main/src/bridge/presentation) | 不决定权威伤害、拾取、道具效果或房间目的地 |
| 与游戏版本无关的可移植数据规则 | [`src/core/`](https://github.com/BMingSY/isaac-lan/tree/main/src/core) | 保持可离线执行，不引入 Hook 或游戏内存布局 |
| 原生能力声明、版本检测与游戏后端 | [`src/engine/`](https://github.com/BMingSY/isaac-lan/tree/main/src/engine)、[`src/engine/versions/<版本>/`](https://github.com/BMingSY/isaac-lan/tree/main/src/engine/versions) | ABI、布局、原生调用、Hook 与对象所有权限定在版本后端 |
| 运行日志、诊断与隔离画面采集 | [`src/diagnostics/`](https://github.com/BMingSY/isaac-lan/tree/main/src/diagnostics) | 记录证据，不以诊断开关控制正常玩法 |
| 离线回归、实机夹具与构建／安装／验收工具 | [`tests/`](https://github.com/BMingSY/isaac-lan/tree/main/tests)、[`tools/`](https://github.com/BMingSY/isaac-lan/tree/main/tools)、[`cmake/`](https://github.com/BMingSY/isaac-lan/tree/main/cmake)、[`package/`](https://github.com/BMingSY/isaac-lan/tree/main/package)、[`.github/workflows/`](https://github.com/BMingSY/isaac-lan/tree/main/.github/workflows) | 按下方测试约定执行，工具不得成为生产玩法依赖 |
| 设计、同步契约、开发与验证说明 | [`docs/`](https://github.com/BMingSY/isaac-lan/tree/main/docs)；用户操作说明用 `README.md` | 文档随实际行为更新，对外发布文案遵循下方审阅约定 |

- 修复前先判断职责：通用字段与状态一致性放在 [`src/bridge/sync/`](https://github.com/BMingSY/isaac-lan/tree/main/src/bridge/sync)，Boss、道具、角色、路线和第三方 Mod 的特殊规则放在对应的 [`compat/`](https://github.com/BMingSY/isaac-lan/tree/main/src/compat) 分类。
- [`app/`](https://github.com/BMingSY/isaac-lan/tree/main/src/app) 负责装配组件和调用顺序，[`runtime/`](https://github.com/BMingSY/isaac-lan/tree/main/src/runtime) 负责会话、房间与楼层生命周期，[`presentation/`](https://github.com/BMingSY/isaac-lan/tree/main/src/presentation) 负责本机显示；不要把新玩法规则继续堆进装配入口。
- 优先复用现有原生接口和游戏 Lua API，尽量不修改 [`engine/versions/`](https://github.com/BMingSY/isaac-lan/tree/main/src/engine/versions)、网络传输、Hook 和原生所有权代码。
- 确实缺少原生能力时，可以在版本后端补充最小、具名、范围受限的读写接口或上下文维护；玩法匹配、效果选择和同步策略仍放在上层。
- 原生改动需在设计或 PR 中说明现有接口为何不足、涉及的布局与所有权、校验边界及验证结果。
- 网络层不得识别 Boss、角色或道具；可移植兼容策略不得读取原生内存或安装 Hook。
- 增加状态字段时同时更新采集、应用、schema、嵌入模块清单和相关文档，并核对协议版本与扩展指纹。
- 回归覆盖实际触发链路、重复状态、跨房／跨层及清理边界；原生机制和画面按下方约定集中验收。

# 代码编写约定

- 遵循 `.editorconfig` 与现有格式工具：代码四空格缩进，YAML 两空格；提交前运行 `tools/format.py --check`，PowerShell 使用 `tools/format_powershell.ps1 -Check`。
- 按职责和状态所有权拆分组件，不按行数机械拆文件。装配入口只连接组件；共享实现放公共模块，不从某个具体工具入口导入。
- 状态由所属组件统一初始化、失效和清理；区分会话、楼层、视图和退出事务，不能在退出回调前提前清理存档保护。
- 跨模块数据使用具名字段或统一字段常量；完整显示名称放数据表，枚举使用具名常量，不散落数字状态或重复拼接规则。
- 有业务含义的数字（状态、动作、字段位置、阈值和原生偏移）使用所属模块的具名常量；复用现有枚举，跨语言值由单一来源导出或做契约校验。原生布局常量按对象归入版本后端，不在调用处重复偏移。明显的零值、循环步长和简单坐标不必机械包装。
- 紧凑同步数组保持明确的字段契约；高频采集可保留有字段注释的顺序构造，避免额外查表与分配。纯重构须验证编码字节和恢复顺序一致；改变字段布局时同步更新版本、指纹和消费者。
- 游戏布局、ABI 与 Hook 留在版本后端，通过具名、范围受限的能力与同步回调连接上层；共用 Lua ABI 声明和符号加载，不复制函数签名或暴露任意地址读写。
- 依赖通过参数显式注入；保持模块加载无副作用。新增组件更新嵌入清单、构建注册和分层检查。
- 抽取重复的生命周期、协议与测试基础设施，保留各组件自身规则；避免为尚不存在的扩展增加通用框架。
- 测试检查外部行为、契约和失败清理，避免仅匹配实现文本或重复实现自身逻辑。

# 文案与游戏内界面

- 文档要简洁，不啰嗦；只写当前结论、必要操作、接口契约和限制，不带过程性内容。
- 不新增计划、进度、逐轮验收、调试流水或修复经过文档；过时、重复、无用的文档直接删除，并同步清理链接。仍有效的约束合并到所属正式文档。
- 验证范围与结果写入 PR；日志、画面、哈希和失败证据保存在测试产物或 CI 附件中，不在 `docs/` 累积过程记录。
- 不添加用户未要求的多余说明、提示或冗余文案，尤其是游戏内。
- 游戏内只保留必要的名称、操作、状态和错误信息；详细说明放在 `README.md` 或 [`docs/`](https://github.com/BMingSY/isaac-lan/tree/main/docs)。
- 不添加菜单说明面板，也不在配置中预留菜单说明字段。
- 文档中的项目文件或目录链接统一使用本仓库 GitHub `main` 分支地址；不写本机路径或未提交验收产物的地址，用文件名、日期、轮次或用途说明替代。

# 发布文案约定

- 每次版本描述按“新特性”“BUG修复”“体验优化”三个方面组织。
- 版本描述以“上一次已发布版本的标签到本次拟发布提交”为变更范围，汇总这段范围内的实际变更，不只描述最近一次提交或 PR。
- GitHub Release、Steam 创意工坊说明、更新日志等对外文案，必须先在对话中展示完整拟发布文本，交给用户审阅。
- 等用户明确确认该文案后，才能发布或更新。笼统的“发布一下”“发布更新”不等于批准尚未展示的文案。
- 未确认的文案不得自行发布，也不得通过上传安装包或推送公开仓库绕过审阅；可以先完成本地修改、打包和验证。
- 已确认的文案如果再次改动，需要重新审阅；未改动的已批准文案无需重复确认。
- 文案保持简洁，只说明 Mod 用途、核心功能和必要操作。除非用户要求，不添加测试建议、未验证兼容性声明、手动下载版本链接或冗余操作说明。
- 创意工坊说明可以附 GitHub 源码链接。

# 测试约定

- 日常开发、调试和回归默认使用无需启动游戏的测试，包括离线 Lua／Python、C++、协议和传输测试。发现问题后优先补充可复现的离线用例。
- BUG 修复、需求新增和日常重构只验证本次改动及其直接影响的链路，不要求每个 PR 跑全量实机。能离线验证的先离线；涉及原生行为或画面时，在代码、构建和离线检查完成后集中验证受影响的实机场景。
- 在 PR 中说明改动范围、所选检查及结果；影响范围无法确认时扩大相关回归范围。完整实机验收统一在发版前执行，不以局部通过替代发布验收。
- 能共用游戏进程的检查复用同一次启动；联机场景主机和客机各启动一次，尽量复用进程和连接。用例之间清理夹具、恢复状态，避免互相影响。
- 只有验证退出、重新启动、启动时加载等确实需要关闭游戏的场景，或进程异常无法恢复时，才单独关闭／重启，并记录原因。无需退出游戏的会话变化优先在现有进程中完成。
- 现有实机工具不保证所有场景自动合并为一次启动，执行前应按上述约定安排场景，不能直接将默认分组反复启动作为日常测试流程。
- 若当前任务明确要求不启动游戏，最终实机检查也保留为待验证，不自行启动；离线通过不等于实机验收通过。

# 发布前整体验收

每次准备发布版本，都必须执行以下整体验收，不能只凭 CI 默认 `fast` 检查或最近一次专项回归判定通过。逐项结果与原始证据保存在发布验收产物中。

- 先确定候选提交和相对上次发布的变更范围，执行 `python tools/test.py --profile full`，完成 Windows x86 构建、网络／原生 ABI 测试和安装包校验。冻结各轮使用的 DLL、夹具与安装包，记录提交及 SHA-256。
- 实机只使用有归属标记的隔离目录和独立端口，运行前备份配置、存档及日志；不控制用户手动游玩的实例。由一个执行者调度多组游戏实例并行跑普通玩法／Boss 分片，不使用多个 agent 分别跑实机。
- 按上方测试约定复用每组主客机进程与连接。性能检查单独运行，真实键盘／菜单检查独占焦点，避免并行实例污染帧率或抢占输入；需要重启时记录原因。

| 必跑范围 | 入口与验收内容 |
| --- | --- |
| 安装包与基础玩法 | [run_release_acceptance.py](https://github.com/BMingSY/isaac-lan/blob/main/tools/run_release_acceptance.py) 的全部用例：安装／自动加载、正常输入的战斗与拾取、分房／换层、五类沙漏回退、暂停菜单，以及单人保存 → 联机 → 单人继续的存档和独立背包保护 |
| 全结局路线 | [run_endings.py](https://github.com/BMingSY/isaac-lan/blob/main/tools/run_endings.py) 覆盖羔羊、???、Delirium、Mega Satan、Mother、上行至 Beast；羔羊使用 `--first-floor`。Mother 路线两端必须实际到达水一／二、矿一／二、陵墓一／二，并检查原生结局、会话清理和本地进度恢复 |
| 原版全 Boss | [run_bosses.py](https://github.com/BMingSY/isaac-lan/blob/main/tools/run_bosses.py) 跑完 [boss_catalog.json](https://github.com/BMingSY/isaac-lan/blob/main/tests/fixtures/boss_catalog.json) 的全部条目，可分片并行；与结局、贪婪结果一起交给 [check_boss_coverage.py](https://github.com/BMingSY/isaac-lan/blob/main/tools/check_boss_coverage.py) 汇总，主客机均无缺项。覆盖原生阶段机制，包括 Rotgut 全员吞入／返回和 Horny Boys 持有炸弹引用；不把直接击杀当作特殊机制通过 |
| 贪婪与支线机制 | [run_special_routes.py](https://github.com/BMingSY/isaac-lan/blob/main/tools/run_special_routes.py) 至少选 `greed`、`greedier`、`knife`、`hornfel`：两种贪婪模式全程、原生矿车／逃亡，以及 Hornfel 持有炸弹、跨层和重连；另补本版改动涉及的角色、道具、Mod 与生命周期专项 |
| 客机响应与镜头 | [run_response_acceptance.py](https://github.com/BMingSY/isaac-lan/blob/main/tools/run_response_acceptance.py) 全部七项：直连／约 20ms 往返延迟、输入预览、移动／过门、暂停、主动道具、蓄力武器、大房间镜头和镜面方向；用 `--record-view` 留下画面供核对 |
| EID 举袋与推动水流 | [run_client_scenes.py](https://github.com/BMingSY/isaac-lan/blob/main/tools/run_client_scenes.py) 使用 `--include-bag-transitions --record-view`，在同一对实例中覆盖持续举袋、EID 开／关、移动／静止反复举放，以及水一／二的实际推动水流；检查帧间隔、停帧、预测重置、水花副本标记及自然销毁 |

- 同时核对主客机断言、日志和实际画面；原生 Boss／换场／退出检查使用工具支持的 `--heap-check` 保留异常证据。用例结束后正常关闭所属实例，恢复隔离资料并逐文件核对哈希。
- 发现失败先保留原始证据，补离线复现、修复并重建，再集中复测受影响的组；影响范围无法确定时重跑整体。只有开始记录、缺少一端结果、崩溃或未完成的用例不能计为通过；保留旧失败报告，复测另开一轮。
- 发布验收产物记录日期、候选构建、逐项结果、性能数据、重启原因及恢复结果。区分已修复、仍可复现、偶发未定位和未验证；偶发崩溃复测未重现不等于已修复，已有失败也不能跳过或写成全绿。
