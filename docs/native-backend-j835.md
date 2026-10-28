# J835 原生接口参考

原版《忏悔》`1.7.9b.J835` 尚无可构建的完整联机后端。[J835 目录](https://github.com/BMingSY/isaac-lan/tree/main/src/engine/versions/j835) 提供下述可独立测试的原生组件；完整房间调度、实体姿态、表现及启动装配尚未接通。CMake 和版本生成器仍拒绝将它们链接为可安装后端。可构建完整后端为 [J460](https://github.com/BMingSY/isaac-lan/blob/main/docs/native-backend.md)。

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

## 更新与渲染入口

[bootstrap.cpp](https://github.com/BMingSY/isaac-lan/blob/main/src/engine/versions/j835/bootstrap.cpp) 向[共享更新组件](https://github.com/BMingSY/isaac-lan/blob/main/src/engine/versions/common/bootstrap.cpp) 提供原生入口和对象布局。房间与运行组件决定执行范围、发布时机和本机视图；后端只连接这些组件与原函数。

| 操作 | J835 入口与 ABI |
| --- | --- |
| 房间更新 | `0x3bf630`，`thiscall void(Room*)`；来自 `Game::Update` 对当前房间的调用 |
| 半帧更新 | `0x2d0400`，`cdecl void()`；读取当前 Game，无栈参数 |
| Game 渲染 | `0x2ce770`，`thiscall void(Game*)` |

更新 Hook 成组创建并启用，失败仅撤销本组已创建的 Hook；渲染入口在更新组安装成功后单独安装。重复安装不会替换已有原函数，外部 Hook 冲突不会被移除。公开 `halfUpdate` 先询问运行层是否允许，完成成功更新后才调用完成通知；异常不会被当成已完成 tick 发布。

渲染顺序为本机输入作用域、视图呈现、前端视图准备、房间渲染、前端叠加；未被房间组件接管时调用原生渲染。返回和 C++ 异常均恢复输入作用域，原生 Game／Room 只在同步调用期间借用。

插值位置恢复沿 `Room+0x125c/+0x1264` 的渲染数组遍历，仅在 `Entity+0x16d` 为真时将 `+0x29c/+0x2a0` 复制回 `+0x294/+0x298` 并清除标记。无当前 Game／Room／数组时返回，不持有实体或数组指针。房间进入帧位于 `Room+0x11f0`，使用与游戏帧相同的 uint32 回绕语义。

诊断接口 `audit` 与 `trace_callback` 可核对当前楼层、房间、帧数、人数及有界回调栈；它们不控制正常玩法。J460 的独立双房间实验仍由 [room_probe.cpp](https://github.com/BMingSY/isaac-lan/blob/main/src/engine/versions/j460/room_probe.cpp) 管理原生对象，J835 不注册尚未适配的实验接口。完整原版房间调度仍需独立后端，不能用诊断实验替代。

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

原版按钮提示只由 `MenuManager::RenderButtonLayout` 绘制；原生开局清理会销毁该菜单，Manager 内没有 J460 的持久提示组。因此原版菜单提示重置适配不访问额外对象。共享输入组件尚需房间和完整启动后端装配，不能单独作为可安装的原版联机后端。

[鼠标适配](https://github.com/BMingSY/isaac-lan/blob/main/src/engine/versions/j835/mouse_input.cpp) 只借入 `Player::Controls` 内联鼠标块的 `0x3439ac`／`0x343ca2` 两个边界，保留其余玩家控制流程。该块以 EDI 接收角色、EBP 指向局部帧，鼠标生效位为 `EBP-0x150`，输出为 `-0x15c/-0x158`。物理查询借用独立的有界局部帧运行原生鼠标块，在结束边界直接返回，不继续执行玩家控制；嵌套查询按线程恢复前一借用帧。适配器不分配原生角色、不修改控制器身份，也不持有角色指针。

原版输出为像素差乘 `0.02`。组件按 `WindowClientHeight / referenceHeight × 0.65 × 0.02` 换算世界位移，再与公共查询的 `0.2` 标度互换；窗口高度来自无参数入口 `0x561100`，参考高度读取 RVA `0x7aa930`。原生鼠标块继续负责屏幕取整、镜像与镜头偏移；接收端按本机比例恢复原版输出。无效比例和非有限输出不写入局部帧。无联机覆盖时完整透传原生块，无有效指针时保留此前的输入局部值。边界回调保存并恢复通用寄存器、标志、SSE／x87 与控制字；该适配接入上述共享输入路由，完整运行仍依赖房间与启动装配。

## 玩家创建与控制器分配

[玩家绑定](https://github.com/BMingSY/isaac-lan/blob/main/src/engine/versions/j835/player_input.cpp) 连接[共享创建组件](https://github.com/BMingSY/isaac-lan/blob/main/src/engine/versions/common/player_input.cpp)。`PlayerManager` 位于 `Game+0x1ba40`，玩家向量位于 `Game+0x1ba50`，两者不能混用。创建 `0x518810` 为 `thiscall Player*(PlayerManager*, int type)`；分配 `0x36b140` 为 `thiscall void(Player*, int controller, bool companions)`，控制器字段为 `+0x154c`。LAN 控制器范围为 `1..4`。

创建后先分配控制器，再调用无栈参数的原生初始化 `0x380810`，随后通知所属开局奖励组件。初始化或奖励可能追加伴生角色并扩容向量，因此必须重新取得列表，为所有新增身体分配相同控制器和邻近主玩家的出生位置。位置为 `Entity+0x294/+0x298`，上一位置为 `+0x29c/+0x2a0`；两者同步设置。最后通过 `Game::GetHUD` 的 `0x127c0` 取得 `Game+0x3da4c`，调用 `0x506f10` 分配原生 HUD，两者都以 ECX 接收对象，无栈参数。

组件校验图像、当前 Game、槽位、类型范围和向量边界；游戏对象、角色及列表仍由游戏持有，不保留迭代器、不自行分配或释放。原生创建失败时不继续初始化；初始化期间 Game 失效时停止后续访问。失败不提供原生对象回滚，调用方不能将部分创建视为加入成功。开局奖励使用下述道具组件；完整使用仍依赖房间与启动装配。

## 道具发放与原生生命周期

[共享道具组件](https://github.com/BMingSY/isaac-lan/blob/main/src/engine/versions/common/item_effects.cpp) 接收 [J835 绑定](https://github.com/BMingSY/isaac-lan/blob/main/src/engine/versions/j835/item_effects.cpp)。原版没有忏悔＋的来源道具池字段；共享接口中的该值为 `0`，发放时不传入原版调用栈，不把原版掉落物的价格等相邻字段当作道具池。两端仍须同一版本，这个占位不用于跨版本转换。

| 能力 | J835 原生入口与约束 |
| --- | --- |
| 发放道具 | `0x32b260`，`thiscall void(Player*, int id, int charge, bool first, int slot, int data)`，清栈 20 字节；与 J460 的六个栈参数不同 |
| 拾取入队 | `0x32a500`，`thiscall void(Player*, ItemConfig*, int charge, uint8 flags, int data)`，清栈 16 字节；仅确认拾取返回点 `0x2c1610` 可通知上层分配策略，其他调用和饰品沿用原生队列 |
| 开局奖励 | 仅原生祝福发放返回点 `0x382207` 记录奖励；共享策略决定是否及向哪些槽位发放。重复加入不重复发放，开始失败清除部分记录 |
| 移除／重新发放 | 持有查询 `0x33af30` 接收道具与忽略变形标志；掉落 `0x3570e0` 接收道具、已有掉落物指针及移除变形标志，清栈 12 字节。临时掉落物由虚表 `+0x28` 的原生 Remove 管理，组件只复制 `+0x474` 充能与 `+0x4e8` VarData |
| 主动充能 | 容量 `0x357e40` 接收槽位；增加 `0x358030` 接收数量、槽位、提示、溢出与强制标志，清栈 20 字节。共享接口将后三个标志传为 false。原版充能类型从该槽的配置 `+0xac` 读取，与原生增加充能的判定一致；槽描述从玩家 `+0x14c4` 开始，步长 `0x1c` |
| 复活 | 道具 `0x367370`、饰品 `0x3687c0` 均以 ECX 接收角色并清理两个栈参数；饰品的第二个调用方暂存字原样转发。原生调用期间借用所属角色房间，已有作用域及单人场景保留原上下文 |
| 蓝色房间 | `0x31a1f0` 接收 Game 和来源房、目标房、门方向，清栈 12 字节，返回是否初始化成功；房间数据的创建与所有权由原生方法处理 |
| 离房激光 | 只处理玩家 `+0x13a0` 的原生激光引用，先 Remove，再以 fastcall `0x28cf00` 清空引用；不释放实体内存、不清除 `+0x1814` 的剩余持续时间 |

桥接仅接受八字节借用 Sprite 包装、当前权威房间内已连接的活动玩家，并核对玩家列表、类型 `+0x28`、存在位 `+0x16a` 和控制器 `+0x154c`。精灵位于实体 `+0x3c`，初始种子为 `+0x344`；不向 Lua 暴露这些地址。配置目录通过 cdecl `0x27930` 取得，再由 thiscall `0x2fe5e0` 查询道具，包括原生生成道具的处理；字符串立即复制，仍由游戏管理其存储。

安装将发放、入队及两种复活 Hook 全部创建后再启用；失败只撤销自己创建的 Hook 并清除旁路，允许重试。玩法效果、拾取分配和开局奖励规则仍属于上层兼容组件；本组件没有完成整个原版房间和实体后端。

错误道具注册表、原生生成与存档恢复、负编号库存查询的接口和所有权见[错误道具定义](https://github.com/BMingSY/isaac-lan/blob/main/docs/generated-item-definitions.md)。这部分复用共享定义组件，不改变现有同步字段、编码或扩展接口。

## 房间进入与混乱诅咒边界

[房间边界绑定](https://github.com/BMingSY/isaac-lan/blob/main/src/engine/versions/j835/room_routing.cpp) 连接[共享回调组件](https://github.com/BMingSY/isaac-lan/blob/main/src/engine/versions/common/room_routing.cpp)。`Level::ChangeRoom` 的 RVA `0x30d7fe` 位于最终索引、维度与入口确定之后，原生混乱诅咒的临时容器已经销毁，目的房间尚未初始化。回调读取 `Game+0x18194/+0x1819c/+0x181ac`；原生改送标志来自当前 `EBP+0xf`，不能使用 J460 的 `EBP+0xb`，也不能由标准房间索引变化推断。

回调只在当前主线程的同步调用中借用，返回 true 继续原生初始化；false 跳至 `0x30db01`，由原生公共尾部恢复 SEH 栈并清理两个栈参数。已加载房间的进入效果由调用方负责。缺失边界、缺失 Game 和回调异常在原生调用退出后报告；不跨原生帧展开 C++ 异常，不保留回调或游戏对象。拦截保存通用寄存器、标志、SSE／x87 状态及控制字。

已经确定目的地的回放通过作用域跳过 `0x30d1a8..0x30d650` 的整个混乱诅咒分支，包括改送和内容交换；不改写诅咒位、不消耗该分支的随机数。原生改送标志在分支之前已清零。作用域支持嵌套及异常恢复，普通主机选路继续执行原生分支。活动诅咒为 `(Game+0xc | Game+0x1c3170 | added) & ~removed`，附加／移除查询分别为无参数 cdecl `0x2ccc80`、`0x2cce10`；没有 Game 时返回零且不调用原生查询。

两个 Hook 全部创建后才启用，失败仅回滚本组件创建的 Hook，清除旁路并允许重试。这些边界不负责房间对象分配、释放或玩家迁移，尚不能替代完整 J835 房间后端。

## 声音与房间音乐

[声音绑定](https://github.com/BMingSY/isaac-lan/blob/main/src/engine/versions/j835/audio.cpp) 连接[共享声音组件](https://github.com/BMingSY/isaac-lan/blob/main/src/engine/versions/common/audio.cpp)。音效入口 `0x488de0` 为 `thiscall void(SFXManager*, int id, float volume, int delay, bool loop, float pitch, float pan)`，清理 24 字节栈参数；即使原生实现未消费某个参数，转发仍保留完整调用栈。音乐播放 `0x3a2070` 与渐变 `0x3a2170` 均接收 Music、ID 与 float 参数，清理八字节；房间选曲 `0x3a9f20` 以 ECX 接收 Room，无栈参数。

Music 位于 `Manager+0x29a78`，当前／排队曲目 ID 为 `+0x30c/+0x310`。进入房间的播放音量来自设置对象 `Manager+0x29df8` 的 `+0x18`，即原生选曲实际读取的位置。该字段属于设置对象，不作为 Music 的内部成员访问。房间键由当前楼层代次、`Game+0x1819c` 维度及 `+0x18194` 索引组成，借用 Room 指针来自 `+0x18190`。

作用域暂借当前／排队 ID，使后台房间完成原生选曲而不更换实际声道；离开前记录原生直接写入的队列，再恢复外层或实际播放 ID。未知房间在空 ID 下求值一次，失败恢复临时 ID。房间、Music、SFXManager 和实际音频流仍由游戏持有，不复制或释放流对象。嵌套视角恢复外层房间，重复快照不重新请求曲目，跨房加入正在播放的队列目标，跨层及会话重置不复用旧归属。

主机按房间听众记录带序号的声音事件，后台播放仅将本机音量降为零；副本不重新发送事件，也不让原生房间初始化覆盖已提交的权威音乐选择。声音编码及既有的时效、队列上限保持不变。三个 Hook 全部创建后启用，失败只撤销本组件创建的 Hook，清除旁路并允许重试。完整使用仍依赖 J835 房间调度和启动装配。

## 实体字段与 Sprite 属性

[版本绑定](https://github.com/BMingSY/isaac-lan/blob/main/src/engine/versions/j835/entity_fields.cpp) 向[共享字段组件](https://github.com/BMingSY/isaac-lan/blob/main/src/engine/versions/common/entity_fields.cpp) 提供原生布局、setter 和属性范围。模板、编码、完整校验、客机限制及对象借用遵循[实体字段契约](https://github.com/BMingSY/isaac-lan/blob/main/docs/native-backend.md#实体字段批量读写)。字段顺序仍由 Lua schema 决定，原生偏移不会进入同步载荷。

| 属性 | J835 原生边界 |
| --- | --- |
| `Size` | `0x40e460`，`cdecl void(Entity*, float)`；保留碰撞尺寸的原生更新 |
| `Color` | `0x40e430`，`cdecl void(Entity*, const Color*)`；44 字节临时值包含七个通道和置零的 colorize，由原 setter 调用实体虚方法 |
| `CollisionDamage` | 实体虚表 `+0x3c`，`thiscall void(Entity*, float)` |
| 泪弹 `Height`／`Scale` | `0x2500f0`／`0x250250`，`thiscall void(Tear*, float)`；保留高度及精灵缩放的副作用 |
| 掉落物 `Price` | `0x2b91e0`，`thiscall void(Pickup*, int)`；重复价格仍执行原生显示更新 |
| 掉落物 `ShopItemId` | Lua setter 直接写入 `Pickup+0x488` 的 int32；J460 的 -2 至 7 限制不适用 |

完整属性偏移集中在 [layout.h](https://github.com/BMingSY/isaac-lan/blob/main/src/engine/versions/j835/layout.h)。实体借用 Sprite 位于 `Entity+0x3c`，存活字节为 `+0x16a`；实体帧数为 `Game+0x1a30dc` 减 `Entity+0x280`，保留 uint32 回绕和有符号返回语义。身份、帧数、标志和精灵名称仍为只读字段。

Sprite 原生对象为 `0x114` 字节，Lua 自有 wrapper 为 `0x11c` 字节、借用 wrapper 为 8 字节。两版动画状态、44 字节颜色和 MSVC 字符串字段具有相同布局，但声明仍属于版本绑定。名称在调用内复制，动画数据、文本缓冲和临时 setter 参数不跨调用保留，不转移资源所有权。

`entity_npc_boss` 只允许客机恢复活动 NPC 的分类字节 `+0xb8d`，与 `EntityNPC::IsBoss`（`0x28f570`）一致。该标记独立于 Boss 类型编号，不触发 AI 或分配实体。完整实体姿态与其他原生引用接口不属于这一字段组件。

## 本机掉落物预览

[预览绑定](https://github.com/BMingSY/isaac-lan/blob/main/src/engine/versions/j835/pickup_preview.cpp) 通过[共享预览组件](https://github.com/BMingSY/isaac-lan/blob/main/src/engine/versions/common/pickup_preview.cpp) 调用 `0x2b81c0`，ABI 为 `thiscall void(Pickup*)`，无栈参数。原生方法读取当前玩家名单的道具，创建或移除预览并维护实体引用；组件不复制 LootList、Sprite 或其他原生对象，也不分配、释放预览资源。

联机玩法更新期间跳过原生预览更新，在本机视角就绪后借用本机玩家名单执行。Room 指针为 `Game+0x18190`；实体列表位于 `Room+0x1218`，渲染数组为列表 `+0x40`，数据／数量为数组 `+4/+0xc`。先复制本次类型为掉落物的实体指针，再依次调用原生更新，允许原生预览创建期间更换数组。无效视角、空 Game／Room／列表不执行更新；已经移除但仍在渲染列表中的掉落物仍交给原生方法清理预览，不能仅按活动位跳过。

这些指针只在当前同步视角调用内借用，不保留到下帧；房间切换、异常退出与重连沿用房间视角的恢复边界。Hook 失败清除自身旁路并允许重试，单人原生更新完整透传。该组件仍依赖尚未接通的完整 J835 房间调度。

## 暂停菜单

[暂停菜单绑定](https://github.com/BMingSY/isaac-lan/blob/main/src/engine/versions/j835/pause_menu.cpp) 为[公共菜单组件](https://github.com/BMingSY/isaac-lan/blob/main/src/engine/versions/common/pause_menu.cpp) 提供原生入口和布局。显示 `0x5178e0`、隐藏 `0x517810`、控制 `0x515ba0` 均为 `thiscall void(PauseScreen*)`，对象位于 `Game+0x10203c`；菜单对象及动画由游戏持有，后端不自行创建或销毁，也不强制改写隐藏动画的完成状态。

根页值为 `1`，选择字段为 `+8`，继续选项为 `1`、退出为 `2`；选项页值为 `2`。选项对象位于暂停菜单 `+0x806a8`，选择字段 `+4`，条目向量为 `+0x260` 的首尾及容量指针。选中 ID `1` 的确认操作会重新分配控制器，应由联机输入路由拦截；普通选项保留原生处理。越界选择或无效向量不能进入控制器分配路径。由同伴恢复游戏时，先调用 `thiscall void(OptionsConfig*)` 的保存入口 `0x4805a0`，接收 `Manager+0x29df8`，再隐藏选项页。

原版没有暂停菜单玩家索引，原生显示和控制读取 `Game+0x1ba50` 名单的首位角色，控制器字段为 `Player+0x154c`。本机菜单调用必须位于房间视图提供的临时名单中；菜单组件不交换或保留名单，不仿造忏悔＋的索引字段。重复暂停状态保留当前子页、选择及借用名单；退出房间视图后仍由房间组件恢复名单。该菜单绑定尚未构成完整 J835 房间视图实现。

## 角色目录与表现

[角色目录](https://github.com/BMingSY/isaac-lan/blob/main/src/engine/versions/j835/characters.cpp) 通过原生目录读取角色、里角色及 Mod 角色，复用两版共有的目录算法。原版选择条件入口为 RVA `0x4a1ea0`，`thiscall bool(record*, int)`；翻译入口为 RVA `0x56b880`，使用 `Manager+0x4a234` 的字符串表。选择条件在临时安装本机个人进度和菜单场景后求值，返回时恢复；伊甸继续游戏只临时豁免已经消耗的代币，不更改实际进度。目录只返回复制后的名称、资源路径和可选状态，不持有原生容器。完成标记使用共同的原版事件编号，替代身体映射到对应起始角色。

原版菜单与聊天使用游戏自带的 `font/cjk/lanapixel.fnt`，逻辑字号和缩放由版本描述声明。大厅面板使用两版共有的白色填充 Sprite，角色画像与完成标记沿用游戏资源。没有官方联机、原生表情轮盘或忏悔＋大厅美术时，不显示相关入口，也不加载对应资源。上述表现适配与原生联机后端的可用性独立。

候选入口可以参考 [REPENTOGON 1.0.12e](https://github.com/TeamREPENTOGON/REPENTOGON/tree/1.0.12e/libzhl/functions)，但参考特征码不是当前游戏的 ABI 保证。审计必须保留多重匹配并核对实际调用点、参数、返回值、对象布局与所有权；不把 J460 地址或字段偏移套入 J835。离线与实机边界见[开发与测试](https://github.com/BMingSY/isaac-lan/blob/main/docs/development-and-testing.md)。
