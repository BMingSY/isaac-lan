# J835 原生接口参考

原版《忏悔》`1.7.9b.J835` 尚无可构建的完整联机后端。[J835 目录](https://github.com/BMingSY/isaac-lan/tree/main/src/engine/versions/j835) 提供版本／资源描述、存档编解码、会话原生绑定、共享输入路由及设备／查询适配、暂停菜单、玩家创建／分配和角色目录组件，以及 Lua 初始化入口资料；房间、实体同步、开局奖励和启动装配尚未接通。组件可单独参与离线测试，CMake 和版本生成器仍拒绝把它们链接为可安装后端。可构建完整后端为 [J460](https://github.com/BMingSY/isaac-lan/blob/main/docs/native-backend.md)。

目标游戏程序 SHA-256 为 `04469d0c3d3581936fcf85bea5f9f4f3a65b2ccf96b36310456c9626bac36dc6`，架构为 Windows x86。版本标记、PE 节区、Lua DLL 和资料目录以 [profile.json](https://github.com/BMingSY/isaac-lan/blob/main/src/engine/versions/j835/profile.json) 为准。两端须使用相同游戏和扩展构建，不能与忏悔＋混联。

`LuaEngine::Init` 为 `thiscall void(LuaEngine*, bool)`，入口和签名位于 [entrypoints.h](https://github.com/BMingSY/isaac-lan/blob/main/src/engine/versions/j835/entrypoints.h) 与 [signatures.inc](https://github.com/BMingSY/isaac-lan/blob/main/src/engine/versions/j835/signatures.inc)。初始化完成后的 Lua 状态指针位于 `LuaEngine + 0x18`，只可借用；状态的创建、重置和销毁仍由游戏持有。初始化可能在同一进程内重复发生，不能将先前状态的引用、注册表键或回调复用于新状态。该入口资料不授权其他布局读写，也不代表完整 ABI 验收。

Lua ABI 为 5.3，符号加载复用 [lua_api.h](https://github.com/BMingSY/isaac-lan/blob/main/src/engine/lua_api.h)。该游戏导入表没有 `SteamAPI_RestartAppIfNecessary`；隔离启动不能把该导入的存在当成必要条件。资料隔离仍须在游戏入口前完成，不能在 Lua 初始化后才更改存档位置。

## 存档与进度

[save.cpp](https://github.com/BMingSY/isaac-lan/blob/main/src/engine/versions/j835/save.cpp) 使用游戏的原生序列化格式，不能读取忏悔＋的存档。`Manager`、`Game` 和 `GameState` 都由游戏持有；后端只在同步调用期间借用对象。入口签名和重定位掩码与其他原生入口一起校验。

| 操作 | J835 ABI | 布局与限制 |
| --- | --- | --- |
| 采集 | `thiscall void(Game*, GameState*)`，RVA `0x2cc850` | 默认目标为 `Manager+0xf34`；包含玩家离房处理，调用方须配对恢复进房临时状态 |
| 清理 | `thiscall void(GameState*)`，RVA `0x520160` | 解码前清理已有原生内容；不替换对象本身 |
| 编码 | `thiscall bool(GameState*, Context*)`，RVA `0x521a00` | 临时流字段为 `GameState+0x1fac8`，输出上限 8 MiB |
| 解码 | `thiscall bool(GameState*, Context*)`，RVA `0x524320` | 仅一个栈参数，被调方清理 4 字节；J460 的额外布尔参数不适用 |

两版共用 [x86 内存流](https://github.com/BMingSY/isaac-lan/blob/main/src/engine/versions/common/save_stream.h)，`Context` 为 28 字节，原生读写回调返回元素个数。流与字节缓冲由扩展持有，不能交给游戏释放；越界寻址、短读、只读流写入和分配失败会使整个操作失败，流指针在返回和 C++ 异常退出时恢复。

原生解码失败处理可能请求删除存档文件。[文件名作用域](https://github.com/BMingSY/isaac-lan/blob/main/src/engine/versions/common/save_file_names.h) 在内存流解码期间临时清空四个本地／Steam 文件名槽，随后逐字节恢复原生字符串和其所有权。文件名偏移在 [layout.h](https://github.com/BMingSY/isaac-lan/blob/main/src/engine/versions/j835/layout.h) 中集中声明。此保护不提供 GameState 内容回滚：失败后会话必须中止恢复，不能把部分加载状态视为完成。

进度位于 `Manager+0x14`；成就数组从 `+0x38` 开始，共 638 字节，计数数组从 `+0x2b8` 开始，共 496 个 uint32。[进度复制组件](https://github.com/BMingSY/isaac-lan/blob/main/src/engine/versions/common/progress.h) 只读写这些元素，共同网络结构的剩余元素补零，不触及相邻收藏记录或按忏悔＋的数组长度访问原版对象。

个人进度持久化先标记 `Progress+0` 为脏，再调用 RVA `0x4848f0`，ABI 为 `thiscall void(Progress*, bool backup)`，传入 `true`。原生方法检查初始化标记，保存日期备份，并按 Steam 接口及游戏设置选择云端或本地文件；流的打开、关闭和所有权仍由游戏管理。不能直接调用需要有效输出流的序列化入口 `0x4836a0`。只读作用域临时设置 `Progress+1`，嵌套返回时恢复原值。

## 会话原生绑定

[版本绑定](https://github.com/BMingSY/isaac-lan/blob/main/src/engine/versions/j835/session_backend.cpp) 为[共享会话实现](https://github.com/BMingSY/isaac-lan/blob/main/src/engine/versions/common/session_backend.cpp) 提供入口、字段、重开动作和持久化调用。上层仍通过具名回调决定联机存档、退出和重开规则。安装先创建全部 Hook，再启用；失败只移除本组件已经创建的 Hook，允许重新安装，不清理其他组件。

| 操作 | J835 入口与 ABI |
| --- | --- |
| 存档／删除／Rerun | `0x4b3850`／`0x4b3b70`／`0x4b3bb0`，无参数、调用方清栈 |
| 执行开局／菜单请求 | `0x4b3fd0`／`0x4b43d0`，`thiscall void(Manager*)` |
| 新局请求／Game 开局 | `0x4b3470`／`0x2c97e0`，栈参数为角色、挑战、92 字节 Seeds 值、难度；被调方清理 `0x68` 字节，入口不使用 ECX |
| 游戏更新／控制 | `0x2cdcf0` 为 `thiscall void(Game*)`；`0x2cda60` 无参数 |
| 暂停重置 | `0x515b50`，`thiscall void(Game+0x10203c)` |
| 种子解析 | `0x53e080`，`cdecl uint32(const NativeString*)`；输入是九字节 `XXXX XXXX`，不会取得字符串所有权 |
| 种子构造／设值 | `0x53bc50`／`0x53e220`，接收 ECX 中的 Seeds；设值另取一个 uint32 栈参数 |

Seeds 含游戏管理的容器；传值调用由原生入口消费一次，扩展转发结构没有析构函数，不重复释放、跨调用保留或自行分配该容器。上述接口只借用当前 Manager／Game，不创建或销毁游戏对象。

继续标记位于 `Manager+0x209c4`，继续请求位于 `+0x1ea6c1`；删除路径标记为 `+0x1ea814`。菜单请求为 `+0x1ea818`，目标为 `+0x1ea81c`；退出目标值为 `2`。过场请求标记为 `+0x1ea830`，只有该标记清除且场景 `Manager+8` 为游戏值 `2` 时才认为过场完成。

控制调用返回后检查 `Game+0x1c31b0`：动作 `4` 为死亡后重开，`5` 为长按重开。仅当运行层接受请求时清除动作、`+0x1c31a8` 的淡出透明度和 `+0x1c31b4` 的按住帧数；其他动作及拒绝的请求保持原样。换层采集读取关卡／类型、`Game+0x1bb1c` 的十四个楼层种子及 `+0x1c3168` 的两字路由标记；应用只写种子和标记，实际转场仍由原生房间能力推进。

控制台对象位于 `Game+0x1bb60`，输入状态在对象 `+0x20`。输入入口 `0x263550` 为 `thiscall void(Console*)`，命令入口 `0x2655c0` 为 `thiscall void(Console*, const NativeString*, bool silent, Player*)`，打印入口 `0x26aec0` 为 `thiscall void(Console*, const NativeString*, unsigned color, unsigned fade)`。命令执行要求已就绪的权威会话和角色房间作用域。24 字节 MSVC 字符串通过原生 assign `0x7c80` 与析构 `0x7be0` 配对管理；结果复制为自有字符串，限制 16 KiB，同步嵌套与返回恢复前一捕获目标，不保留原生文本引用。

## 输入设备与查询适配

[设备绑定](https://github.com/BMingSY/isaac-lan/blob/main/src/engine/versions/j835/input_devices.cpp) 使用原生扫描 `0x59d3b0` 和轮询 `0x59d720`，两者均无参数、调用方清栈。`InputManager::Update` 的 `0x56a150` 接收 ECX 中的管理器。三个入口通过[公共设备组件](https://github.com/BMingSY/isaac-lan/blob/main/src/engine/versions/common/input_devices.cpp) 串行化完整遍历、回调与释放过程；同线程原生连接回调可以重入轮询，离开联机后继续保护设备断开清理。

输入管理器是 RVA `0x7e7c98` 的内嵌对象，其指针列表首尾为 `+4/+8`，元素四字节；设备 ID 位于 `+8`。只有至少四个正编号设备都存在时才分配联机 ID `1..4`，保留键盘、其他设备和容器顺序。退出只恢复仍在列表内且仍使用所分配编号的设备；不解引用已移除对象，不覆盖原生独立更改的编号。设备及容器由游戏创建和销毁，组件只保存恢复所需的身份记录，不取得所有权。

[输入查询适配](https://github.com/BMingSY/isaac-lan/blob/main/src/engine/versions/j835/input_queries.cpp) 把三个原生入口连接到后端内部的统一查询接口。按住 `0x56a520` 和按下沿 `0x56a5e0` 的 ABI 为 `thiscall bool(InputManager*, int action, int controller, int* source)`；模拟量 `0x56a6c0` 参数相同，通过 x87 返回 float。适配器保持动作、控制器和来源指针的顺序，将模拟量转为同步输出参数，再还原原生 float 返回值。

物理输入旁路只接受这三个已安装入口对应的查询标识，通过原函数 trampoline 调用，不重新进入联机路由、不执行任意回调地址。参数与输出对象只在调用期间借用；适配器不分配、销毁或持有原生设备。安装失败只撤销自己创建的 Hook 并清除旁路，允许重试；重复安装不会替换现有旁路。

两版游戏自带枚举中的前十六个动作与菜单方向 `20..23` 相同；原版重开为 `16`，没有原生表情动作。差异集中在 [input_actions.h](https://github.com/BMingSY/isaac-lan/blob/main/src/engine/versions/j835/input_actions.h)，不能把忏悔＋的 UI 动作编号直接传给原版。[共享输入路由](https://github.com/BMingSY/isaac-lan/blob/main/src/engine/versions/common/input.cpp) 通过 [J835 绑定](https://github.com/BMingSY/isaac-lan/blob/main/src/engine/versions/j835/input.cpp) 使用上述组件：物理采集、虚拟 XInput、权威输入、按键沿消费、暂停意图、呈现预测和退出恢复共用实现。上层请求的重开动作映射为原版 `16`，不存在的表情动作直接返回未触发；原生进入路由的动作编号保持原样，不做二次映射。采集以 `Manager+0x4a264` 的渲染帧编号去重，网络输入仍使用相同的十六动作与世界坐标鼠标目标契约。

原版按钮提示只由 `MenuManager::RenderButtonLayout` 绘制；原生开局清理会销毁该菜单，Manager 内没有 J460 的持久提示组。因此原版菜单提示重置适配不访问额外对象。共享输入组件尚需房间、开局奖励和完整启动后端装配，不能单独作为可安装的原版联机后端。

[鼠标适配](https://github.com/BMingSY/isaac-lan/blob/main/src/engine/versions/j835/mouse_input.cpp) 只借入 `Player::Controls` 内联鼠标块的 `0x3439ac`／`0x343ca2` 两个边界，保留其余玩家控制流程。该块以 EDI 接收角色、EBP 指向局部帧，鼠标生效位为 `EBP-0x150`，输出为 `-0x15c/-0x158`。物理查询借用独立的有界局部帧运行原生鼠标块，在结束边界直接返回，不继续执行玩家控制；嵌套查询按线程恢复前一借用帧。适配器不分配原生角色、不修改控制器身份，也不持有角色指针。

原版输出为像素差乘 `0.02`。组件按 `WindowClientHeight / referenceHeight × 0.65 × 0.02` 换算世界位移，再与公共查询的 `0.2` 标度互换；窗口高度来自无参数入口 `0x561100`，参考高度读取 RVA `0x7aa930`。原生鼠标块继续负责屏幕取整、镜像与镜头偏移；接收端按本机比例恢复原版输出。无效比例和非有限输出不写入局部帧。无联机覆盖时完整透传原生块，无有效指针时保留此前的输入局部值。边界回调保存并恢复通用寄存器、标志、SSE／x87 与控制字；该适配尚需完整输入路由装配。

## 玩家创建与控制器分配

[玩家绑定](https://github.com/BMingSY/isaac-lan/blob/main/src/engine/versions/j835/player_input.cpp) 连接[共享创建组件](https://github.com/BMingSY/isaac-lan/blob/main/src/engine/versions/common/player_input.cpp)。`PlayerManager` 位于 `Game+0x1ba40`，玩家向量位于 `Game+0x1ba50`，两者不能混用。创建 `0x518810` 为 `thiscall Player*(PlayerManager*, int type)`；分配 `0x36b140` 为 `thiscall void(Player*, int controller, bool companions)`，控制器字段为 `+0x154c`。LAN 控制器范围为 `1..4`。

创建后先分配控制器，再调用无栈参数的原生初始化 `0x380810`，随后通知所属开局奖励组件。初始化或奖励可能追加伴生角色并扩容向量，因此必须重新取得列表，为所有新增身体分配相同控制器和邻近主玩家的出生位置。位置为 `Entity+0x294/+0x298`，上一位置为 `+0x29c/+0x2a0`；两者同步设置。最后通过 `Game::GetHUD` 的 `0x127c0` 取得 `Game+0x3da4c`，调用 `0x506f10` 分配原生 HUD，两者都以 ECX 接收对象，无栈参数。

组件校验图像、当前 Game、槽位、类型范围和向量边界；游戏对象、角色及列表仍由游戏持有，不保留迭代器、不自行分配或释放。原生创建失败时不继续初始化；初始化期间 Game 失效时停止后续访问。失败不提供原生对象回滚，调用方不能将部分创建视为加入成功。该组件不替代尚未实现的 J835 开局奖励与房间／启动装配。

## 暂停菜单

[暂停菜单绑定](https://github.com/BMingSY/isaac-lan/blob/main/src/engine/versions/j835/pause_menu.cpp) 为[公共菜单组件](https://github.com/BMingSY/isaac-lan/blob/main/src/engine/versions/common/pause_menu.cpp) 提供原生入口和布局。显示 `0x5178e0`、隐藏 `0x517810`、控制 `0x515ba0` 均为 `thiscall void(PauseScreen*)`，对象位于 `Game+0x10203c`；菜单对象及动画由游戏持有，后端不自行创建或销毁，也不强制改写隐藏动画的完成状态。

根页值为 `1`，选择字段为 `+8`，继续选项为 `1`、退出为 `2`；选项页值为 `2`。选项对象位于暂停菜单 `+0x806a8`，选择字段 `+4`，条目向量为 `+0x260` 的首尾及容量指针。选中 ID `1` 的确认操作会重新分配控制器，应由联机输入路由拦截；普通选项保留原生处理。越界选择或无效向量不能进入控制器分配路径。由同伴恢复游戏时，先调用 `thiscall void(OptionsConfig*)` 的保存入口 `0x4805a0`，接收 `Manager+0x29df8`，再隐藏选项页。

原版没有暂停菜单玩家索引，原生显示和控制读取 `Game+0x1ba50` 名单的首位角色，控制器字段为 `Player+0x154c`。本机菜单调用必须位于房间视图提供的临时名单中；菜单组件不交换或保留名单，不仿造忏悔＋的索引字段。重复暂停状态保留当前子页、选择及借用名单；退出房间视图后仍由房间组件恢复名单。该菜单绑定尚未构成完整 J835 房间视图实现。

## 角色目录与表现

[角色目录](https://github.com/BMingSY/isaac-lan/blob/main/src/engine/versions/j835/characters.cpp) 通过原生目录读取角色、里角色及 Mod 角色，复用两版共有的目录算法。原版选择条件入口为 RVA `0x4a1ea0`，`thiscall bool(record*, int)`；翻译入口为 RVA `0x56b880`，使用 `Manager+0x4a234` 的字符串表。选择条件在临时安装本机个人进度和菜单场景后求值，返回时恢复；伊甸继续游戏只临时豁免已经消耗的代币，不更改实际进度。目录只返回复制后的名称、资源路径和可选状态，不持有原生容器。完成标记使用共同的原版事件编号，替代身体映射到对应起始角色。

原版菜单与聊天使用游戏自带的 `font/cjk/lanapixel.fnt`，逻辑字号和缩放由版本描述声明。大厅面板使用两版共有的白色填充 Sprite，角色画像与完成标记沿用游戏资源。没有官方联机、原生表情轮盘或忏悔＋大厅美术时，不显示相关入口，也不加载对应资源。上述表现适配与原生联机后端的可用性独立。

候选入口可以参考 [REPENTOGON 1.0.12e](https://github.com/TeamREPENTOGON/REPENTOGON/tree/1.0.12e/libzhl/functions)，但参考特征码不是当前游戏的 ABI 保证。审计必须保留多重匹配并核对实际调用点、参数、返回值、对象布局与所有权；不把 J460 地址或字段偏移套入 J835。离线与实机边界见[开发与测试](https://github.com/BMingSY/isaac-lan/blob/main/docs/development-and-testing.md)。
