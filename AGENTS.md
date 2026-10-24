# 代码结构与修改位置

先按改动的职责选择模块，不以调用入口或现有大文件的位置决定归属。整体依赖与所有权见 [docs/layers-and-compatibility.md](https://github.com/BMingSY/isaac-lan/blob/main/docs/layers-and-compatibility.md)。

| 要修改的内容 | 应修改的位置 | 边界 |
| --- | --- | --- |
| 自动加载、启动装配、组件注册与调用顺序 | [`src/app/`](https://github.com/BMingSY/isaac-lan/tree/main/src/app)、[`src/bridge/app/`](https://github.com/BMingSY/isaac-lan/tree/main/src/bridge/app) | 组合已有组件，不承载新的玩法规则 |
| UDP、消息、分块、压缩、连接与协议 | [`src/net/`](https://github.com/BMingSY/isaac-lan/tree/main/src/net) | 不访问游戏对象，不识别 Boss、角色或道具 |
| 状态字段、采集／应用、编码、库存、实体与网格一致性 | [`src/bridge/sync/`](https://github.com/BMingSY/isaac-lan/tree/main/src/bridge/sync) | 负责通用同步契约，特殊玩法通过注入兼容组件处理 |
| 会话推进、存档／恢复、换层屏障、房间与角色生命周期 | [`src/runtime/`](https://github.com/BMingSY/isaac-lan/tree/main/src/runtime)、[`src/bridge/runtime/`](https://github.com/BMingSY/isaac-lan/tree/main/src/bridge/runtime) | 协调执行时机与状态失效，原生对象的分配／释放由后端处理 |
| Boss、道具、角色、路线与挑战的特殊规则 | [`src/compat/{bosses,items,characters,routes,challenges}/`](https://github.com/BMingSY/isaac-lan/tree/main/src/compat)、[`src/bridge/compat/`](https://github.com/BMingSY/isaac-lan/tree/main/src/bridge/compat) 对应分类 | C++ 策略接收普通值；Lua 适配使用游戏 API 和具名原生能力 |
| 第三方 Mod 的探测、注册、接入与卸载 | [`src/bridge/compat/mods/`](https://github.com/BMingSY/isaac-lan/tree/main/src/bridge/compat/mods) | 保留目标来源识别、实际接口探测和清理边界；不以非必要的版本／源码哈希限制兼容，不修改上游 Mod 源码 |
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
- 原生改动在所属能力参考中说明接口限制、布局与所有权、校验边界；改动原因和验证结果写入 PR 或验收记录，不追加到设计文档。
- 网络层不得识别 Boss、角色或道具；可移植兼容策略不得读取原生内存或安装 Hook。
- 增加状态字段时同时更新采集、应用、schema、嵌入模块清单和相关文档，并核对协议版本与扩展指纹。
- 回归覆盖实际触发链路、重复状态、跨房／跨层及清理边界；原生机制和画面按下方约定集中验收。

# 代码编写约定

- 遵循 `.editorconfig` 与现有格式工具：代码四空格缩进，YAML 两空格；提交前运行 `tools/format.py --check`，PowerShell 使用 `tools/format_powershell.ps1 -Check`。
- PR 标题必须使用与改动性质匹配的类型前缀，如 `feat:`、`fix:`、`docs:`、`refactor:`、`test:` 或 `chore:`。
- 按职责和状态所有权拆分组件，不按行数机械拆文件。装配入口只连接组件；共享实现放公共模块，不从某个具体工具入口导入。
- 状态由所属组件统一初始化、失效和清理；区分会话、楼层、视图和退出事务，不能在退出回调前提前清理存档保护。
- 跨模块数据使用具名字段或统一字段常量；完整显示名称放数据表，枚举使用具名常量，不散落数字状态或重复拼接规则。
- 有业务含义的数字（状态、动作、字段位置、阈值和原生偏移）使用所属模块的具名常量；复用现有枚举，跨语言值由单一来源导出或做契约校验。原生布局常量按对象归入版本后端，不在调用处重复偏移。明显的零值、循环步长和简单坐标不必机械包装。
- 紧凑同步数组保持明确的字段契约；高频采集可保留有字段注释的顺序构造，避免额外查表与分配。纯重构须验证编码字节和恢复顺序一致；改变字段布局时同步更新版本、指纹和消费者。
- 游戏布局、ABI 与 Hook 留在版本后端，通过具名、范围受限的能力与同步回调连接上层；共用 Lua ABI 声明和符号加载，不复制函数签名或暴露任意地址读写。
- 依赖通过参数显式注入；保持模块加载无副作用。新增组件更新嵌入清单、构建注册和分层检查。
- 抽取重复的生命周期、协议与测试基础设施，保留各组件自身规则；避免为尚不存在的扩展增加通用框架。
- 测试检查外部行为、契约和失败清理，避免仅匹配实现文本或重复实现自身逻辑。

# 文档边界与游戏内界面

- 未经用户明确允许，不得向 `README.md` 新增任何内容；功能实现、BUG 修复或“文档随实际行为更新”不构成该授权。
- 文档描述当前事实，先给结论，只保留必要操作、契约和限制。设计文档不是变更日志；禁止写历史演进、版本升级经过、逐轮修复、调试流水、测试成绩或尚未实施的方案。
- 架构／设计文档只解释当前目标、模块职责、数据流、状态所有权、生命周期、关键取舍和限制。不逐项罗列道具／Boss 特判，不堆原生偏移、补丁原因或 PR 经过。
- 接口参数、字段布局、原生 ABI、校验与所有权放所属参考文档或源码；角色、道具、Mod 的具体效果与当前兼容状态放对应清单。设计文档用链接引用，避免重复维护。
- 修改已有设计时重写相关段落，使其独立描述最终设计；不得在文末追加“某版本新增／修复”的补丁段落。删除过时或重复内容，同时核对必要契约和链接，不能把仍有效的安全边界一起删掉。
- 测试操作与默认范围统一放开发／测试文档。需要长期保留的验收结果放 `docs/history/`，按日期与候选构建记录结论、范围、失败／未验证项和证据标识；历史或演进说明也只能放该目录或 PR／提交记录，不能混入设计文档。
- 原始日志、截图、录像、转储和大报告留在测试产物或 CI 附件中，不提交到文档目录。更改测试范围不得回写旧验收结论或隐去已知失败。
- 文档审阅必须检查：是否只描述当前设计、是否混入历史／专项细节、是否重复其他文档、链接与源码是否一致。不能只替换“新增”“修复”等词语而保留流水账结构。
- 文档中的项目文件或目录链接统一使用本仓库 GitHub `main` 分支地址；不写本机路径或未提交验收产物地址，用文件名、日期、轮次或用途说明替代。
- 游戏内只保留必要的名称、操作、状态和错误信息；详细说明放在 `README.md` 或 `docs/`。不添加用户未要求的提示、菜单说明面板或预留说明字段。

# 发布文案约定

- 版本描述按实际变化选择“新特性”“BUG修复”“体验优化”分类；没有对应内容时省略该分类，不凑新特性。
- 版本描述以“上一次已发布版本的标签到本次拟发布提交”为变更范围，汇总这段范围内的实际变更，不只描述最近一次提交或 PR。
- GitHub Release、Steam 创意工坊说明、更新日志等对外文案，必须先在对话中展示完整拟发布文本，交给用户审阅。
- 等用户明确确认该文案后，才能发布或更新。笼统的“发布一下”“发布更新”不等于批准尚未展示的文案。
- 未确认的文案不得自行发布，也不得通过上传安装包或推送公开仓库绕过审阅；可以先完成本地修改、打包和验证。
- 已确认的文案如果再次改动，需要重新审阅；未改动的已批准文案无需重复确认。
- 文案保持简洁，只写玩家能感知的变化、核心功能和必要操作，不列异常成因、内部同步机制或逐项排查细节。除非用户要求，不添加测试建议、未验证兼容性声明、手动下载版本链接或冗余操作说明。
- 创意工坊说明可以附 GitHub 源码链接。
- Steam 创意工坊更新复用[发布流程](https://github.com/BMingSY/isaac-lan/blob/main/docs/steam-workshop-release.md)，沿用现有条目和已确认文案，发布后下载核对。

# 测试约定

- 日常开发、调试和回归默认使用无需启动游戏的测试，包括离线 Lua／Python、C++、协议和传输测试。发现问题后优先补充可复现的离线用例。
- BUG 修复、需求新增和日常重构只验证本次改动及其直接影响的链路，不要求每个 PR 跑全量实机。能离线验证的先离线；涉及原生行为或画面时，在代码、构建和离线检查完成后集中验证受影响的实机场景。
- 在 PR 中说明改动范围、所选检查及结果；影响范围无法确认时扩大相关回归范围。开发专项与发布验收分别安排、分别记录，不因发布范围包含相关改动就重跑专项，也不以局部通过替代发布默认范围。
- 能共用游戏进程的检查复用同一次启动；联机场景主机和客机各启动一次，尽量复用进程和连接。用例之间清理夹具、恢复状态，避免互相影响。
- 只有验证退出、重新启动、启动时加载等确实需要关闭游戏的场景，或进程异常无法恢复时，才单独关闭／重启，并记录原因。无需退出游戏的会话变化优先在现有进程中完成。
- 现有实机工具不保证所有场景自动合并为一次启动，执行前应按上述约定安排场景，不能直接将默认分组反复启动作为日常测试流程。
- 若当前任务明确要求不启动游戏，最终实机检查也保留为待验证，不自行启动；离线通过不等于实机验收通过。

# 发布前验收范围

默认发版验收只检查安装与基础联机、全部原版 Boss、结局路线和正常路线推进。**不附带道具／角色／Mod 专项、全道具／卡牌／药丸遍历或性能压力测试。**

错误技、达摩剑、创世纪、小夜灯，EID／举袋／水流／切窗口暂停，道具与弹幕压力，以及输入响应／镜头，均不列入发版检查清单，也不因相对上个版本有相关改动而自动追加。修复这些问题时按开发测试约定做定向回归；用户明确要求追加发版专项时再执行。

- 确定候选提交及相对上次发布的范围；执行 `python tools/test.py --profile full`，完成 Windows x86 构建、网络／原生 ABI 测试和安装包校验。冻结 DLL、夹具和安装包，记录提交与 SHA-256。
- 实机只使用有归属标记的隔离目录和独立端口，运行前备份配置、存档及日志，不控制用户手动游玩的实例。由一个执行者调度普通玩法／Boss 分片，可并行分组，不使用多个 agent 分别操作实机。
- 复用每组主客机进程与连接，用例间清理夹具。真实键盘／菜单检查独占焦点；确需性能专项时单独运行。必要重启须记录原因。

| 默认必跑范围 | 入口与验收内容 |
| --- | --- |
| 安装包与基础联机 | [run_release_acceptance.py](https://github.com/BMingSY/isaac-lan/blob/main/tools/run_release_acceptance.py)：安装／自动加载、正常输入的战斗与拾取、分房／换层、沙漏回退、暂停，以及单人保存 → 联机 → 单人继续的存档与独立背包保护 |
| 全结局路线 | [run_endings.py](https://github.com/BMingSY/isaac-lan/blob/main/tools/run_endings.py)：羔羊、???、Delirium、Mega Satan、Mother、上行至 Beast；羔羊用 `--first-floor`，Mother 两端实际经过水一／二、矿一／二、陵墓一／二，核对结局、清理与本地进度恢复 |
| 全部原版 Boss | [run_bosses.py](https://github.com/BMingSY/isaac-lan/blob/main/tools/run_bosses.py) 覆盖 [boss_catalog.json](https://github.com/BMingSY/isaac-lan/blob/main/tests/fixtures/boss_catalog.json) 全部条目；与结局、贪婪结果交给 [check_boss_coverage.py](https://github.com/BMingSY/isaac-lan/blob/main/tools/check_boss_coverage.py) 汇总，主客机均无缺项；原生阶段机制须实际触发，不能只直接击杀 |
| 贪婪与路线机制 | [run_special_routes.py](https://github.com/BMingSY/isaac-lan/blob/main/tools/run_special_routes.py) 选择 `greed`、`greedier`、`knife`、`hornfel`：两种贪婪模式全程、矿车／逃亡、持有炸弹、跨层与重连 |

- 发布记录只列本次发布检查范围；开发专项结果单独引用。历史记录保留执行时的原始范围与结论，不因新规则删除旧失败。
- 同时核对主客机断言、日志和必要画面；原生 Boss／转场／退出使用工具支持的 `--heap-check` 保留异常证据。正常关闭所属实例，恢复隔离资料并逐文件核对哈希。
- 失败先保留原始证据，补离线复现；修复重建后复测受影响组，影响范围不明时扩大默认回归。只有开始记录、缺少一端结果、崩溃或未完成的用例不能计为通过；复测另开一轮，不覆盖旧失败。
- 在 `docs/history/` 留下验收摘要，记录日期、候选与哈希、实际范围、逐项结果、重启原因和恢复结果；性能数据仅在执行性能专项时记录。区分已修复、仍可复现、偶发未定位和未验证，保留范围外的已知问题；默认项通过不能表述为所有道具或性能均已验证。
