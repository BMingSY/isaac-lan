# J835 原生接口参考

原版《忏悔》`1.7.9b.J835` 使用 [J835 后端](https://github.com/BMingSY/isaac-lan/tree/main/src/engine/versions/j835)，通过 `-DISAAC_LAN_BACKEND=j835` 构建完整联机 DLL、加载器与匹配的安装包。版本后端提供本页列出的入口、布局和 ABI 适配，共享组件负责房间调度、会话和表现作用域；构建及启动均按所选版本校验，不从 J510 借用地址。原版没有官方表情轮盘，`native_emotes=false`；LAN 文字聊天继续使用普通气泡。

目标游戏程序 SHA-256 为 `04469d0c3d3581936fcf85bea5f9f4f3a65b2ccf96b36310456c9626bac36dc6`，架构为 Windows x86。版本标记、PE 节区、Lua DLL 和资料目录以 [profile.json](https://github.com/BMingSY/isaac-lan/blob/main/src/engine/versions/j835/profile.json) 为准。两端须使用相同游戏和扩展构建，不能与忏悔＋混联。

`LuaEngine::Init` 为 `thiscall void(LuaEngine*, bool)`，入口和签名位于 [entrypoints.h](https://github.com/BMingSY/isaac-lan/blob/main/src/engine/versions/j835/entrypoints.h) 与 [signatures.inc](https://github.com/BMingSY/isaac-lan/blob/main/src/engine/versions/j835/signatures.inc)。初始化完成后的 Lua 状态指针位于 `LuaEngine + 0x18`，只可借用；状态的创建、重置和销毁仍由游戏持有。初始化可能在同一进程内重复发生，不能将先前状态的引用、注册表键或回调复用于新状态。该入口资料不授权其他布局读写，也不代表完整 ABI 验收。

原生文件打开观察使用游戏自己的 `fopen` 导入，成功的写入打开只通知日志组件，不借用、关闭或替换游戏 CRT 的 FILE 对象。J835 不导入 MSVC `_Fiopen`；共享组件仅在该导入存在时安装 C++ 流观察，存在但不可写的 IAT 槽仍使启动失败。安装失败恢复已替换的 stdio 槽，观察异常不改变原生返回值或 LastError。

Lua ABI 为 5.3，符号加载复用 [lua_api.h](https://github.com/BMingSY/isaac-lan/blob/main/src/engine/lua_api.h)。该游戏导入表没有 `SteamAPI_RestartAppIfNecessary`；隔离启动不能把该导入的存在当成必要条件。资料隔离仍须在游戏入口前完成，不能在 Lua 初始化后才更改存档位置。

## 主菜单入口

[前端绑定](https://github.com/BMingSY/isaac-lan/blob/main/src/engine/versions/j835/frontend.cpp)与 J510 共用[前端装配](https://github.com/BMingSY/isaac-lan/blob/main/src/engine/versions/common/frontend.cpp)和[菜单边界](https://github.com/BMingSY/isaac-lan/blob/main/src/engine/versions/common/menu_context.h)。选定存档后，第三项“联机模式”位于“继续游戏”和“挑战”之间，支持上下选择、确认和鼠标点击。确认后直接进入局域网联机，退出局域网页面即回到主菜单。

主菜单对象位于 MenuManager `+0x80fac`，选择字段为对象 `+4`，游戏持有的 Sprite 内嵌于 `+0x10`。主菜单的纸张绘制入口为 RVA `0x4d9f70`，使用 thiscall，无栈参数。文字和鼠标命中使用本次纸张绘制的屏幕坐标，即对象的位置 `+8/+0xc` 加上 MenuManager 的当前视图位置 `+0x3c/+0x40`。滑入和滑出期间都沿用这一坐标。绘制时按图层 ID 找到六项原生文字和指针，临时调整纵坐标，为联机入口留出一行，绘制后恢复全部坐标。图层缺失时沿用原生绘制。指针使用原生选中行。局域网界面盖住主菜单时，底下的纸张仍按同一布局绘制。

[原生菜单导航](https://github.com/BMingSY/isaac-lan/blob/main/src/engine/versions/j835/menu_navigation.cpp)保留游戏的选择字段、按键重复、选择音效和续玩条件。初始化时核对确认分派及上下循环的原始指令和六个原生动作，将游戏选择范围扩展到七行。确认表按原序保留六个动作，在第三项保留局域网入口。表由后端持有，在进程内存活至退出。检查不匹配时终止安装。

MenuManager 全局指针 RVA `0x7fd688`，页字段 `+0x38`；标题、存档、主菜单页为 1、2、3。入口要求 Manager 菜单场景、存档栏 1～3、主菜单页，且 MenuManager `+0x20` 输入阻塞、`+1` 启动请求和 Manager `+0x4a268` 阻塞均为空。主菜单更新 RVA `0x4d92c0` 使用 thiscall、无参数；菜单绘制 RVA `0x4e19d0` 无接收对象及栈参数。显式返回大厅只把标题／存档／主菜单页选择为主菜单，不分配菜单或跳过未选存档流程。Lua 状态重建时重新绑定回调并清理旧输入、菜单和地图视图。

## 小地图绘制

[小地图组件](https://github.com/BMingSY/isaac-lan/blob/main/src/engine/versions/common/minimap.cpp)使用[J835 绑定](https://github.com/BMingSY/isaac-lan/blob/main/src/engine/versions/j835/minimap.cpp)。原生地图为 `Game+0x1a2ab0`，大小地图配置为地图 `+0x18/+0x178`。更新、绘制、缓存入口分别为 `0x4e55f0/0x4e5e50/0x4e2e40`，均 thiscall、无栈参数。房间视角准备期间更新失效缓存，切换渲染目标前对全局 Renderer RVA `0x7c7a30` 调用 Flush `0x565030`，栈参数 false、清栈 4 字节；实际绘制不重建缓存。缓存只有在原生调用成功后才登记房间，Game 替换与断线清空旧归属。

配置的借用纹理、单元宽高、间距和锚点为 `+0x114/+0x124/+0x128/+0x130/+0x140/+0x144`。纹理宽高为 `+0x80/+0x84`。Draw RVA `0x55f990` 的 ECX 为纹理，栈参数为源四边形、目标四边形和四个角的颜色指针，清栈 24 字节；源 `+0x20` 的值 1 表示归一化纹理坐标，目标只有八个 float 坐标，alpha 来自颜色 `+0xc`，不能按 J510 的目标布局读取。

观察仅在当前地图绘制作用域内采集，返回普通屏幕坐标、裁剪、透明度、维度和队员标记；源纹理、颜色及四边形不被写入或持有。原生大小地图使用相同的四角透明度，适配取左上角值。嵌套／异常绘制恢复外层作用域，非有限坐标不进入叠加画面。地图三个 Hook 成组安装；纹理 Hook 在存在纹理时安装，冲突保留外部 Hook 并在后续绘制重试。

## 精灵状态

[精灵绑定](https://github.com/BMingSY/isaac-lan/blob/main/src/engine/versions/j835/sprite_state.cpp)复用[共享精灵状态组件](https://github.com/BMingSY/isaac-lan/blob/main/src/engine/versions/common/sprite_state.cpp)。`sprite_state`、`sprite_animation_length` 的范围、返回值及完整载荷校验见[精灵契约](https://github.com/BMingSY/isaac-lan/blob/main/docs/native-backend.md#实体引用与房间数据)。Sprite 大小 `0x114`，接受 8 字节借用包装或 `0x11c` 字节 Lua 自有包装；仅客机可恢复状态，返回后不保留对象引用。

主／叠加动画为 Sprite `+0x30/+0x50`，图层数组／数量为 `+0x7c/+0x80`，阴影层为 `+0x10c`。J835 图层步长为 `0x9c`，只有 `+0x78/+0x7c/+0x80/+0x84` 四个混合参数；标志 `+0x88`、裁剪偏移 `+0x8c/+0x90`，资源指针 `+0x94/+0x98` 不写入。格式 2 的第五混合槽采集为零，接收非零值即拒绝，不把它写到标志或资源字段。

动画状态的数据、图层帧和挂点帧指针为 `+4/+8/+0xc`；动画数据的图层／数量为 `+0x18/+0x1c`，挂点／数量为 `+0x20/+0x24`，总帧数为 `+0x30`。图层映射从 `+0x38` 开始；描述项步长 `0x10`，图层／挂点帧数分别位于项内 `+8/+0xc`。恢复按本机 ID 和帧数匹配，清空未匹配的挂点游标。两组动画和全部载荷在写入前完成校验。

`AnimationState::Reset` RVA `0x3740` 使用 ECX 接收状态、栈上一个动画参数并清栈 4 字节；空动画通过此入口解除当前动画及帧数组。字符串、图层定义、纹理和帧数组均由游戏管理，扩展只恢复受限标量；贴图变化返回普通路径供 Lua 调用现有游戏加载接口。

## 房间调度绑定

[房间绑定](https://github.com/BMingSY/isaac-lan/blob/main/src/engine/versions/j835/rooms.cpp)向[共享调度](https://github.com/BMingSY/isaac-lan/blob/main/src/engine/versions/common/rooms.cpp)提供原版入口、布局和少量 ABI 适配。Room 大小为 `0x777c`，构造／析构入口为 `0x3a80f0/0x3a89f0`；分配与释放沿用游戏 CRT。PlayerManager 位于 `Game+0x1ba40`，名单向量位于管理器 `+0x10`，不能把名单头作为管理器接收对象。备用身体通过 `0x518ab0` 注销名单，只搬移指针、不析构角色；销毁角色使用 `0x518af0`，接收角色指针和布尔参数并清栈八字节。

每个房间持有 Ambush `+0xc` 起的待执行波次向量及后续标量，根对象为 `Game+0x1c31b8`；前置 XML 配置保持游戏所有权。27 个进程渲染纹理句柄按原生双指针对整体交换和释放，不能只交换资源地址。 原版构造函数创建这些进程纹理，但此时仍是离开房间的作用域；目的房间激活后、原生 `Room::Init` 之前，解析边界调用 `0x3a91c0`（cdecl、无参数）补齐空槽。该入口按现有屏幕尺寸分配原生表面和引用所有者，保留非空句柄；已驻留房间、未受调度的原生换房和存储壳不额外调用。纹理创建失败时跳过原生初始化并把异常交还调度，不在下一帧绘制时补救已经使用的空纹理。原版 Boss 血条缓存为 `Game+0x1018f0/+0x1018f4/+0x1018f8`；没有 J510 `Game+0x1ad90` 的换房 Boss 缓存，也没有其结束／恢复控制使用的状态门，缺失槽不读写原生内存。

上层转场 `0x2d07d0` 与底层 `RoomTransition::Start` `0x3e9650` 均使用 thiscall、五个栈参数和二十字节清栈；后者以 RoomTransition 为接收对象。原版 Mom's Hand、Dogma 和死亡证明直接调用底层入口，仍须提交到房间调度；上层原函数转入底层时不重复拦截。迷宫等目的地解析继续由 `Level::ChangeRoom` 执行。

原版 `PlayerManager::NewRoom` 内联分派跟班 Variant 203／221，分别调用 `0x21f500/0x21f790`，均为无栈参数的 thiscall；其他跟班不调用这些方法。到达后的通用状态清理由 `Familiar::ResetRoomState`（`0x20b140`）执行。Dogma 过场使用 `0x4b3800`，stdcall 接收编号 25、cleanup=false，清栈八字节。

原生价格 `0x3d0950` 接收 Variant、SubType、ShopItemId，折扣 `0x3d16f0` 接收 ShopItemId、基础价格，分别清栈十二和八字节。两者均通过当前借用名单识别买家，没有 J510 的显式买家参数；适配只在所属房间的买家作用域中调用，保留原生负价格和折扣结果。

## 房间描述符与地图缓存

[楼层转场 Lua 绑定](https://github.com/BMingSY/isaac-lan/blob/main/src/engine/versions/j835/stage_transition_binding.h)修正原生注册的参数数量：`Game::StartStageTransition`（RVA `0x2d0aa0`）实际使用 thiscall 接收 bool、int、Player 指针并清栈十二字节，原绑定 `0x453660` 只压入两个参数。适配复用 `0x4536e0` 的三参数原生包装和闭包自身的方法指针；省略第四个 Lua 值时补 nil，显式玩家及额外参数保持不变。Hook 不持有 Lua 状态或角色，安装失败清理自身资源，状态重建后仍读取新闭包。

[房间数据绑定](https://github.com/BMingSY/isaac-lan/blob/main/src/engine/versions/j835/room_data.cpp)使用[共享组件](https://github.com/BMingSY/isaac-lan/blob/main/src/engine/versions/common/room_data.cpp)。编码、校验、稳定配置存储和缓存借用见[房间数据契约](https://github.com/BMingSY/isaac-lan/blob/main/docs/native-backend.md#房间描述符与地图缓存)。原生描述符查询 RVA `0x30e0f0` 使用 thiscall 接收索引、维度，清栈 8 字节；特殊房间只支持 `-18..-1`，更小索引在调用前拒绝，不能按 J510 范围写原生共享占位对象。

普通描述符数组为 `Game+0x14`、步长 `0xb8`；格子映射为 `+0x1796c`，房间数量为 `+0x1815c`。当前房间／索引／维度为 `+0x18190/+0x18194/+0x1819c`。描述符与配置标量偏移同上方契约，但保存实体记录步长是 `0x68`；小地图只读取六个具名字段，其余位置保持零值，不复制原生对象。别名或嵌套缓存逆序恢复借用，接收更新与换层清理不会提前释放正在绘制的记录。

水流向量为 `Room+0x7344/+0x7348`，帧钟为 `Game+0x1a30dc`。小地图缓存入口 `0x4e2e40` 使用 thiscall、无参数，两个目标为 `Game+0x1a2ac8/+0x1a2c28`；显示状态／计时为 `+0x101904/+0x10190c`。对象从本次调用的 Game 和调度作用域取得，缺少 Game、未启用或未初始化的房间不写入；不以原生内存地址作为网络身份。

## 角色附属状态

[角色查询绑定](https://github.com/BMingSY/isaac-lan/blob/main/src/engine/versions/j835/room_queries.cpp)调用 `PlayerManager::HasPlayerType`（RVA `0x1ef580`），ECX 接收管理器，栈上接收角色类型并清栈四字节，结果仅取 AL。原生查询遍历管理器 `+0x10/+0x14` 的名单并排除非零 Variant；不能按 J510 的玩家指针返回值解释 EAX，也不额外改变原版的幽灵筛选规则。[共享查询组件](https://github.com/BMingSY/isaac-lan/blob/main/src/engine/versions/common/room_queries.cpp)让房间策略按调用来源临时借用队伍名单，嵌套调用及异常均恢复外层状态；直接查询只使用当前名单，不重复进入共享策略。安装冲突保留外部 Hook，失败后可重试。该组件由完整房间调度装配。

[遗骸形态绑定](https://github.com/BMingSY/isaac-lan/blob/main/src/engine/versions/j835/forgotten_form.h)使用[共享形态恢复组件](https://github.com/BMingSY/isaac-lan/blob/main/src/engine/versions/common/forgotten_form.h)。原生切换入口 `0x38df20` 以 ECX 接收角色、栈上接收强制切换和播放效果两个布尔参数，清栈八字节。恢复只接受遗骸／游魂的有效配对，类型、合作幽灵和配对指针分别读取 `Player+0x130c/+0x1f88/+0x1cb8`；目标形态相同不重复调用，配对对象仍由游戏持有。该能力由房间组件调用。

[角色状态绑定](https://github.com/BMingSY/isaac-lan/blob/main/src/engine/versions/j835/actor_state.cpp)复用[共享组件](https://github.com/BMingSY/isaac-lan/blob/main/src/engine/versions/common/actor_state.cpp)，Lua 名称、快照字节和名单限制遵循[角色附属状态契约](https://github.com/BMingSY/isaac-lan/blob/main/docs/native-backend.md#角色附属状态)。附属 Sprite 为 `Player+0x36c/+0xf48/+0xe34`，七个蓄力条从 `+0x6a8` 开始、步长 `0x114`；服装向量为 `+0x1170/+0x1174/+0x1178`，步长 `0x130`。借用包装沿用原生 metatable，不接管动画资源。

四个口袋记录从 `+0x16c8` 开始、步长 8；百宝袋八个材料与预览 ID 为 `+0x1e44/+0x1e4c`；里蓝人 mana 与六字节资源队列为 `+0x1e50/+0x1e54`。仅完整名单中的客机玩家可恢复状态，整份载荷先校验再写入，不触及后续随机资源。百宝袋变化经 `Game::GetHUD`（RVA `0x127c0`、thiscall、无参数）取得 HUD，八个 PlayerHUD 步长 `0x6b0`，只设置绑定该角色的 `+0x6a1` 刷新位；重复状态不刷新，缺少 HUD 时保留已恢复材料供后续绑定使用。

## 激光路径

[激光绑定](https://github.com/BMingSY/isaac-lan/blob/main/src/engine/versions/j835/laser_state.cpp)使用[共享路径组件](https://github.com/BMingSY/isaac-lan/blob/main/src/engine/versions/common/laser_state.cpp)，编码、平移和完整校验遵循[激光路径契约](https://github.com/BMingSY/isaac-lan/blob/main/docs/native-backend.md#激光路径呈现)。采样状态为 `Laser+0x3ad`，原生初始化值为 255；起点／终点四个 float 从 `+0x3b8` 开始，形状／缩放为 `+0x3c8/+0x430`，采样数为 `+0x3cc`。两个 Vector2 向量位于 `+0x3d0/+0x3dc`，各由 begin/end/capacity 三个指针组成，每点 8 字节。

分配与带大小的释放入口为 `0x5eacf8/0x5eb08e`，均 cdecl；参数分别为字节数，以及指针、字节数。共享组件保留 MSVC 大向量的 4096 字节阈值、32 字节对齐及 `0x23` 字节额外空间，释放使用原分配指针，原生析构可继续接管。快照和原生容器完整校验后准备两组空间，分配失败不修改任何旧路径或实体字段；不重建激光、不执行伤害或转移实体所有权。

`pickup_flip_visual` 的道具底座阴影 Sprite 位于 `Pickup+0x51c`，可见标记位于 `+0x625`，分别由构造位置 `0x2b6cf0` 和绘制判断 `0x2bd0b5` 校验。读取只借用 Sprite，写入只允许客机设置布尔标记；不执行翻转或拾取，不转移 Sprite 所有权。

## 角色姿态与实体阴影

[实体姿态绑定](https://github.com/BMingSY/isaac-lan/blob/main/src/engine/versions/j835/entity_pose.cpp)复用[共享组件](https://github.com/BMingSY/isaac-lan/blob/main/src/engine/versions/common/entity_pose.cpp)。`actor_pose` 与 `entity_shadow` 的编码、校验和所有权遵循[实体姿态契约](https://github.com/BMingSY/isaac-lan/blob/main/docs/native-backend.md#实体引用与房间数据)，不跨版本交换会话。只接受实体借用 Sprite，写入限客机；捕获和恢复返回后不保留玩家、武器或服装指针。

| 对象 | J835 字段 |
| --- | --- |
| 实体 | Sprite `+0x3c`；阴影大小、XY 偏移与高度为 `+0x150/+0x154/+0x158/+0x2a8`，固定 16 字节 |
| 玩家绘制 | 两个姿态标志 `+0x12e8/+0x12ea`，闪烁计时 `+0x1288`，受击计时 `+0x1308`，小夜灯角度 `+0x1a04` |
| 武器 | 五槽从 `Player+0x1328` 开始；类型 `Weapon+0x2c`，三项蓄力／冷却 `+0xc/+0x10/+0x14`，修正标志 `+0x30` |
| 服装 | 向量首尾 `Player+0x1170/+0x1174`，步长 `0x130`；十五项映射 `+0x117c`、步长 `0x10`，项内索引／图层／优先级／身体标记为 `+0/+4/+8/+0xc` |

武器虚表第 6 项查询蓄力上限，以 ECX 接收武器，无栈参数，x87 返回 float。允许原生组合返回有限负数，该值只供显示预测；恢复不改上限，也不创建或替换武器。服装同名项按出现顺序映射，未知项退回基础层；原生字符串和 Sprite 保持原所有权。全部载荷与映射在写入前完成校验，新的玩家对象独立解析其服装列表。

## 网格、门与轨道

[网格绑定](https://github.com/BMingSY/isaac-lan/blob/main/src/engine/versions/j835/grid_state.cpp)复用[共享网格组件](https://github.com/BMingSY/isaac-lan/blob/main/src/engine/versions/common/grid_state.cpp)，接口范围与所有权见[网格契约](https://github.com/BMingSY/isaac-lan/blob/main/docs/native-backend.md#实体引用与房间数据)。当前房间为 `Game+0x18190`；网格表 `Room+0x24` 持有对象，`+0x724` 的八个门槽只借用指针，`+0x744` 保存对应网格索引。写入限客机，空 Game／房间不能执行原生调用。

| 原生操作 | J835 ABI／字段 |
| --- | --- |
| 立即删除网格 | RVA `0x3d9b00`，ECX 为房间，栈参数为 index、0、false，清栈 12 字节 |
| 创建门 | RVA `0x3ad410`，ECX 为房间，栈参数 slot，清栈 4 字节，AL 返回成功；重复已有槽返回 false |
| 网格与门 Sprite | 普通 Sprite `Grid+0x40`，附加 Sprite `Door+0x164`；类型／变种／索引为 `+4/+8/+0x24` |
| RailManager | 房间 `+0x734c` 为所有者指针，`+0x7350` 为 448 字节轨道网格；宽高为房间 `+0xc/+0x10` |

门包装仅引用现有动画，不能按忏悔＋的附加 Sprite 偏移访问原版对象。恢复已有门时验证其类型、索引和房间归属；清空槽表不销毁网格对象。原生创建失败恢复原目标索引。轨道数组全部校验后一次提交，空轨道同样恢复，不触及随后由游戏持有的 Sprite。房间变化后从当前 Game 重新解析对象，不保留跨房指针。

TNT 更新入口为 `0x2ee310`，以 ECX 接收网格、无栈参数，受启动签名校验。共享房间组件仅在客机跳过该原生更新，避免本机倒计时改写权威动画或重复爆炸；主机与单人继续原生调用。网格的内存、渲染和销毁仍由游戏持有，不读写倒计时字段。

## 跟班组件与实体绘制准备

[版本绑定](https://github.com/BMingSY/isaac-lan/blob/main/src/engine/versions/j835/entity_visuals.cpp)向[共享实体视图](https://github.com/BMingSY/isaac-lan/blob/main/src/engine/versions/common/entity_visuals.cpp)提供跟班组件与 Needle 绘制准备入口。Lua 名称、编码和权限遵循[能力契约](https://github.com/BMingSY/isaac-lan/blob/main/docs/native-backend.md#实体引用与房间数据)，不改变同步字段。实体身份来自 `Entity+0x3c` 的 8 字节借用 Sprite；附加数据位于 `Familiar+0xe18`，不能沿用 J510 的 `+0xee0`。

| 对象或入口 | J835 布局与 ABI |
| --- | --- |
| `IsaacsBodyData` | 虚表 RVA `0x746348`，对象 `0x578` 字节；五个 Sprite 从 `+4` 开始、步长 `0x114`，四个身体图层 ID 从 `+0x568` 开始 |
| `UmbilicalBabyData` | 虚表 RVA `0x73fffc`，对象 `0x158` 字节；deque 映射、容量、首项、数量分别为 `+8/+0xc/+0x10/+0x14`，Sprite 为 `+0x18` |
| 绳索绘制 | RVA `0x26810`，`thiscall void(Familiar*, Vector*, int part)`，清栈 8 字节；只借用点、Sprite 和当前房间绘制参数 |
| Needle 图层准备 | RVA `0x13c430`，`thiscall void(NPC*)`，无栈参数；原生 NPC 渲染在绘制该类型前调用，不推进 AI |

身体组件写入只提交完整验证后的四个图层 ID，其余 Sprite、纹理及动画资源仍由游戏持有。绳索原生 deque 每块一个 XYZ 点，快照按环绕索引采集；空、替换或移除组件按本次调用重新判断。绘制只建立调用内的只读容器视图，临时组件指针在返回和 C++ 异常时恢复，浅复制的 Sprite 不进入原生析构，不转移资源或实体所有权。原生入口接受正常房间上下文；组件不能脱离房间视角单独执行真实绘制。

## 原生实体引用

[引用绑定](https://github.com/BMingSY/isaac-lan/blob/main/src/engine/versions/j835/references.cpp)使用[共享引用组件](https://github.com/BMingSY/isaac-lan/blob/main/src/engine/versions/common/references.cpp)，对 Lua 提供 `entity_minecart`、`actor_held_entity` 与 `boss_held_bombs`。接口只接受实体的借用 Sprite／显式 false，捕获返回本机索引，由同步组件换算为同步 ID；不保留对象指针，写入限客机。

矿车引用为 `Entity+0x32c`，目标限定矿车且不得自引用；抱起物引用为 `Player+0x1358`，持有者必须是玩家。两者通过 `EntityPtr::Assign` RVA `0x28cf00` 赋值，ECX 为槽地址、EDX 为目标，无栈参数。相同值不重复登记；目标销毁时由游戏的观察者通知清空槽，不调用产生矿车、拾取或投掷的玩法方法。

Hornfel／Horny Boys 的持有炸弹容器位于 `NPC+0xb40`，分别限定两槽和三槽。MSVC deque 的代理、块表、块表容量、首元素与数量为 `+0/+4/+8/+0xc/+0x10`，每块四个 EntityPtr；块表容量要求 8–65536 的二次幂，逐项检查块和目标类型。空容器调用 RVA `0x3da10`，ECX 为 deque、栈上槽数、清栈 4 字节；该方法仅用于扩张到所需槽数。容器和代理仍由游戏释放，链接使用上述 Assign；完整检查目标后才开始初始化或赋值，不用原生 resize 的收缩路径清理引用。

## 入场演出与本机视图

[演出绑定](https://github.com/BMingSY/isaac-lan/blob/main/src/engine/versions/j835/presentation.cpp) 为[共享演出组件](https://github.com/BMingSY/isaac-lan/blob/main/src/engine/versions/common/presentation.cpp) 提供原生入口、字段与 HUD 坐标。入场事件按房间、维度和楼层筛选，固定每条 32 字节、网络字节序，保留至多 32 条和 90 帧；客机按序号去重。背景房间只通知观看者，主机所在房间才占用本机转场画面；终局集合使用既有 Boss 兼容策略和房间调度。

| 原生操作 | J835 入口与布局 |
| --- | --- |
| 开始入场 | `0x3e9ab0`，thiscall 接收 `RoomTransition*` 与两个 Boss ID，清栈 8 字节；转场对象为 `Game+0x1b6c0` |
| 原生推进 | `0x3ebfd0`，thiscall，无栈参数；模式 `+0` 的 2／3 为入场与退出阶段，Boss 标记是 `+0x328` 的单字节，不是 J510 的完整 Boss ID |
| 入场角色 | `RoomTransition+0x320` 是登记到实体的 EntityPtr；用已校验的 `0x28cf00` fastcall 赋值，ECX 为引用槽、EDX 为当前房间首位角色，保留移除时清空引用的原生机制 |
| 控制恢复 | `0x51dab0`，thiscall 接收 `Game+0x1ba40` 的 PlayerManager 与 true，清栈 4 字节；原生从管理器 `+0x10/+0x14` 的名单设置 `Player+0x360` |
| 房间入场来源 | Boss ID 为 `Room+0x1d1c/+0x1d20`，存活／延迟敌人数为 `+0x12c8/+0x12cc`；特殊房间入口遵循原生描述符检查 |
| 小夜灯本机查询 | 只筛选 `Room::Render` 内 RVA `0x3cc985` 对 `HasCollectible(425, false)` 的调用；按当前房间观看名单过滤，其他调用者与道具完整透传 |

回放前将转场目标 `+0x14/+0x18` 设置为当前房间／维度，角色按当前名单通过原生引用接口登记。入场推进只在主机、本机房间、状态就绪且未暂停时执行；同步房间模拟期间暂时隐藏模式，正常返回或异常离开恢复，不能覆盖新转场或已释放的 Game。客机完成确认只在事件原房间和非结束状态下恢复对应角色的控制；断线与超时释放等待。J835 不使用 J510 的附加控制保护字段。

HUD 桥接从 `Game+0x3da4c` 取得借用对象，使用下方的原版坐标规则；小地图只发布前端实际绘制观察到的普通值。两处演出 Hook 成组创建，冲突只撤销本组件 Hook；道具、百宝袋、挑战 HUD 和胜利圈提示各自管理安装，任一失败由启动装配中止。上述组件由共享房间调度和启动装配连接。

换层梦境的[动画跳过绑定](https://github.com/BMingSY/isaac-lan/blob/main/src/engine/versions/j835/animation_skip.cpp)复用[共享组件](https://github.com/BMingSY/isaac-lan/blob/main/src/engine/versions/common/animation_skip.cpp)。`NightmareScene` 位于 `Manager+0x211bc`，场景编号为 5，`+0` 为活动状态，`+0x5e8` 区分 Home 个人梦境。`Show`／`Update`／`Render` 入口为 `0x47e110/0x47ca00/0x47ce30`，均为 thiscall；Show 接收一个 bool 并清栈 4 字节，后两者无栈参数。Show 清空旧许可，Update 通过受限确认输入作用域等待当前动画的同意，Render 在原生画面后绘制联机 HUD。换层完成还要求 `Game+0x1ba0c` 的原生 StageTransition 状态归零。游戏对象和场景编号均由原生持有，接口按事件与楼层代次拒绝过期请求，三个 Hook 成组安装并在失败时回滚。

## 玩家轮廓

[J835 轮廓后端](https://github.com/BMingSY/isaac-lan/blob/main/src/engine/versions/j835/player_outlines.cpp)与 J510 共用[绘制作用域及配色](https://github.com/BMingSY/isaac-lan/blob/main/src/engine/versions/common/player_outlines.cpp)。只在本机房间绘制的 `withPlayers` 作用域内启用，至少两个在线槽位，角色 `+0x154c` 的控制器须属于在线槽位；嵌套调用、断开和异常离开均恢复外层名单。

普通身体资格边界为 `0x353a89`、颜色栈调用为 `0x353aef`；特殊精灵分别为 `0x35382e/0x353894`。EDI 是玩家，`[EBP+0xc]` 是主绘制标记，`[EBP-0x79]` 是全息分身标记。符合条件时只填写 `[EBP-0x3c]` 的 44 字节临时 ColorMod，将 ECX 指向它并继续原生颜色压栈。四方向身体、头部与装扮绘制及颜色出栈保留原生实现；全息分身、残影和作用域外调用沿用原生资格判断。

幽灵／宝宝在 `0x353c6c` 的正常 Sprite 绘制前借用当前 ESI 偏移，调用 `Entity::Render`（`0x288480`，thiscall 接收偏移指针、清栈 4 字节）绘制四个单位方向偏移。颜色压栈为 `0x2420`，ECX 接收 ColorMod、无栈参数；原生颜色 deque 位于全局 `0x7fec10`，首项／数量为 `+0xc/+0x10`。作用域结束或 C++ 异常时恢复原颜色数量和玩家 `+0x19c` 的临时屏幕坐标，再继续正常绘制。原生扩容和颜色块仍由游戏拥有，不复制容器或回收资源。

三条边界保存通用寄存器、标志、SSE、x87 和 MXCSR；只有进入颜色调用时按原生约定设置 ECX。安装成组回滚，冲突保留外部 Hook。对象、装扮颜色、官方联机状态与存档不写入，所有边界及原生调用均接受启动签名检查。

## 玩家不透明度

[J835 不透明度适配](https://github.com/BMingSY/isaac-lan/blob/main/src/engine/versions/j835/player_opacity.cpp)复用[共享设置和绘制名单](https://github.com/BMingSY/isaac-lan/blob/main/src/engine/versions/common/player_opacity.cpp)，Lua 参数与返回值见[不透明度契约](https://github.com/BMingSY/isaac-lan/blob/main/docs/native-backend.md#玩家不透明度)。有效控制器为 `Player+0x154c` 的 1～4，角色 Sprite 为 `+0x3c/+0x36c/+0xf48/+0xe34`，装扮向量为 `+0x1170/+0x1174`、步长 `0x130`、上限 4096。名单、临时弹幕倍率与嵌套绘制均在作用域退出时恢复，不跨房持有地址。

原版没有忏悔＋的在线透明度分支。Sprite 最终颜色边界为 `0x4079`，`[EBP-0xcc]` 为 Sprite，`[EBP-0xc8]` 是各原生着色路径实际用于提交 RGBA 的缓存 Alpha。完整颜色副本位于 `[EBP-0x12c]`，其 Alpha 已被缓存；适配只乘缓存值，不改完整颜色副本、实体、图层、全局颜色栈或原有着色。`Sprite::Render`（`0x51e0`）与 `RenderLayer`（`0x5250`）使用 thiscall，分别清栈十二和十六字节；只在已校验的实体／激光绘制返回点借入弹幕 Sprite 倍率，原生调用返回后立即退出，Mod 绘制回调保留原始颜色。

泪弹使用直接生成者，激光沿 `Entity+0x320` 生成者链取末端玩家；名单外或断开的归属不着色，最多检查 128 个链接，循环链不生效。分段光束、端点与直线光束在 `0x4d25d1/0x4d2bca/0x4d39d9`，阴影分段与端点在 `0x4d5fec/0x4d651f` 提交临时顶点颜色。每处第三个栈参数指向独立 RGBA 副本，只乘该副本的 Alpha；后续 shader 着色复制颜色 `+0x10` 起的通道，不重复乘 Alpha。生成者布局、调用点和最终颜色入口均由启动签名约束；UV、光束样本、命中状态和游戏对象所有权不变。

八个 Hook 成组安装，失败只撤销本组件创建的 Hook，可重试；重复安装要求同一映像。内联边界保存通用寄存器、标志、x87、XMM0–7 和 MXCSR，不将临时倍率保留到后续绘制。

## Home 场景推进

[场景更新绑定](https://github.com/BMingSY/isaac-lan/blob/main/src/engine/versions/j835/scene_update.cpp) 接入[共享更新门控](https://github.com/BMingSY/isaac-lan/blob/main/src/engine/versions/common/scene_update.cpp)。J835 没有独立的 BossOverlay 更新入口；`Game::Update` 在 RVA `0x2ce36e` 从 EDI 指向的 Game 读取 `+0x1cf20`，随后内联更新动画、处理 Home 路线标记，至 `0x2ce4c1` 进入下一更新块。

普通客机且尚未进入结束状态时，边界直接继续到后一更新块；主机及结束状态执行原始跳板。门控保存整数寄存器、标志位、SSE、x87 和控制字，不写入场景对象或 Game 字段，不创建、推进或持有动画。这样由主机消费路线标记，客机的显示姿态仍交给演出同步；道具／Home 姿态由下述共享演出组件提供。

入口与继续位置均在启动签名清单中。Hook 冲突保留外部 Hook，失败清理所属 Hook 与跳板，允许重试；重复安装被拒绝。原生 Game／BossOverlay 继续由游戏持有，不能把该内部边界作为可直接调用的函数。

## 道具演出与屏幕状态

[原版道具演出绑定](https://github.com/BMingSY/isaac-lan/blob/main/src/engine/versions/j835/item_presentation.cpp) 提供入口、布局和自定义文字适配；对象所有权、事件编码、显示权限及生命周期见[共享契约](https://github.com/BMingSY/isaac-lan/blob/main/docs/native-backend.md#道具演出事件与对象)。组件通过共享房间调度取得当前视图。

| 原生操作 | J835 入口与 ABI |
| --- | --- |
| ANM2／大书配置构造 | `0x24b0`／`0x50c800`，thiscall，无栈参数；大书析构 `0x50c890` 负责动画、配置字符串及登记的玩家引用 |
| 大书加载／更新 | `0x50c930`，thiscall 接收文件名并返回 bool，清栈 4 字节；`0x50d5b0` 接收结束标志，清栈 4 字节 |
| 大书显示／绘制 | `0x50dd70` 接收 ID、延迟及可空玩家，清栈 12 字节；`0x50db30` 无栈参数；均以 ECX 接收大书对象 |
| 道具文字 | `0x503830`，thiscall 接收玩家和 ItemConfig，清栈 8 字节；饰品查询 `0x2fe640` 接收 ID 并清栈 4 字节，返回借用配置 |
| 自定义文字 | `0x503460`，thiscall 接收标题、说明、粘附标志、诅咒标志，清栈 16 字节；没有玩家参数，使用当前角色动作作用域确定归属，两个显示标志通过种类 6 事件保留 |
| 规则提示／索引翻译 | `0x504200` 借用字符串链表，清栈 4 字节；`0x56ba70` 接收节名、语言和索引，清栈 12 字节 |
| 像素化／扭曲 | `0x320430` 以 ECX 接收 Game、栈上接收持续时间并清栈 4 字节；`0x395620` 以 ECX 接收玩家、无栈参数 |
| 药丸／卡牌作用域 | `0x3877a0` 接收效果、颜色和使用标志，清栈 12 字节；`0x376b80` 接收卡牌和使用标志，清栈 8 字节；ECX 均为玩家，参数原样转发 |
| Home 场景显示 | `0x1c130` 以 ECX 接收 BossOverlay，栈上为场景 ID，清栈 4 字节；实际更新使用上方内联门控 |

全局大书为 `Game+0x1bcc0`，大小 `0x1260`；配置共 47 个，从 `+0x11c` 开始、步长 `0x58`。普通／Mega Mush Sprite 为 `+8/+0x114c`，延迟 `+0x1144`，原生玩家引用 `+0x1148`；不能沿用忏悔＋的配置数和末尾字段。两类 Sprite 的加载、播放和帧位分别为 `+0x109/+0x44/+0x40`，自引用为 `+0x30/+0x50`。BossOverlay 位于 `Game+0x1cf20`，状态／ID／Sprite 为 `+0/+4/+8`。梦境位于 `Manager+0x211bc`，Home 标志／索引为 `+0x5e8/+0x3a0`，背景／气泡 Sprite 为 `+0x20/+0x134`，仅在 Manager 场景 5 时借用。

原版屏幕标量为 Game 的像素化 `+0x24363c/+0x243640`、扭曲 `+0x283c04/+0x283c08/+0x283c0c`、泛光 `+0x1c3148/+0x1c314c/+0x1c3150`。主机按控制器保存，卡牌／药丸及嵌套动作共用所属状态；绘制与动作作用域在异常时恢复，重置或 Game 释放不会将旧状态写入新对象。

原版索引翻译未检查迭代器越界。接收事件时，绑定先按原生规则将节名的 ASCII 大写和反斜线归一化，再只读检查 `StringTable+0xc` 分类树和对应字符串树的实际元素数；索引无效则使用捕获文字，禁止把越界索引传入原函数。树对象的头／数量为 `+0/+4`，节点的左／父／右指针为 `+0/+4/+8`、哨兵标志为 `+0xd`、键／值为 `+0x10/+0x14`。树和字符串均由游戏持有，绑定不保留节点、不修改容器。

## 胜利圈提示

[胜利圈绑定](https://github.com/BMingSY/isaac-lan/blob/main/src/engine/versions/j835/victory_prompt.cpp) 使用[共享提示组件](https://github.com/BMingSY/isaac-lan/blob/main/src/engine/versions/common/victory_prompt.cpp)。原生 Controls、Render、Hide 的 RVA 分别为 `0x3f21f0/0x3f1f30/0x3f2340`，均以 ECX 接收提示对象，无栈参数。只拦截当前 `Game+0x1c33fc` 的胜利圈提示；其他提示和单人会话保留原函数。

动画与播放位为提示对象的 `+0x34/+0x44`，选择和结果为 `+0x80218/+0x8021c`。动画名借用原生字符串，长度为 4 且内容为 `Idle` 才能确认；内联与堆字符串只读。原版没有 Steam 投票字段，不能访问 J510 的 `+0x130`。组件每次查询当前 Game，不缓存对象指针或接管动画、字体和字符串的所有权。

普通联机只由主机的已锁存菜单输入改变选择，结果 1 接受、2 拒绝，随后调用原生 Hide；客机不消费选择输入、不绘制该提示。联机挑战在各端等待 Idle 后拒绝，保持原生动画更新。对 Lua 的五个返回值依次为打开、选择、结果、原生投票、Idle，原版投票值恒为 false。两个 Hook 成组安装，失败仅清理本组件创建的 Hook，保留外部 Hook 并允许重试；重复安装被拒绝。换层与胜利圈推进仍由会话同步负责。

## 挑战目标 HUD

[目标绑定](https://github.com/BMingSY/isaac-lan/blob/main/src/engine/versions/j835/challenge_hud.cpp) 与 J510 共用[显示组件](https://github.com/BMingSY/isaac-lan/blob/main/src/engine/versions/common/challenge_hud.cpp)。目标由会话的挑战定义提供；原生 Game／每日挑战参数保持原样，借用视图仅供当前 HUD 绘制消费，不包含拥有所有权的字符串或容器。

`HUD::Render` 的存在位边界为 RVA `0x5050ab`，使用 DL 和栈帧 `EBP-0x99` 的无解锁标志。原生普通挑战和每日挑战分支在 `0x505584` 汇合，ECX 指向参数对象；此处替换为扩展持有的 164 字节标量视图，不 Hook 全局查询函数。终点为 `+0x40`，备用路线和秘密路线分别是字节 `+0x6d/+0x88`，对应 J510 目标类型 1／2；其余字段清零。J835 `+0x80` 属于诅咒掩码，不能按 J510 的路线类型写入。

两个边界保存标志、整数寄存器、SSE、x87 与控制字，只修改目标所需的保存槽。未启用联机挑战时保留原生指针与帧数据。Hook 成组安装，冲突撤销已创建的本组件 Hook，保留外部 Hook；重复安装被拒绝。此接口不改变挑战解锁、路线选择或通关条件。

## 楼层生成

[楼层生成绑定](https://github.com/BMingSY/isaac-lan/blob/main/src/engine/versions/j835/floor_generation.cpp)复用[共享分支组件](https://github.com/BMingSY/isaac-lan/blob/main/src/engine/versions/common/floor_generation.cpp)。房间数量与布局比较分别位于 RVA `0x30e4c1/0x30edf3`，均为比较 `Game+0x1c319c` 是否等于原生挑战 21 的七字节指令。Hook 安装在随后条件跳转处，保留原生比较；只有运行层请求大楼层时，将保存的算术标志改为相等，再通过原生跳板选择分支。通用寄存器、栈、SSE、x87 与 MXCSR 完整恢复，回调异常中止会话并保留本次原生分支。入口签名包含比较与跳转；两个 Hook 成组安装、失败回滚，相同配置可供外层装配重试。挑战编号、随机数、布局和分配过程均由原生持有。

## 玩家 HUD 绑定

[HUD 绑定](https://github.com/BMingSY/isaac-lan/blob/main/src/engine/versions/j835/frontend_hud.cpp)向[共享组件](https://github.com/BMingSY/isaac-lan/blob/main/src/engine/versions/common/frontend_hud.cpp)提供原生入口与布局。更新、后更新和绘制分别为 RVA `0x5027e0/0x502a20/0x504610`，均以 ECX 接收 HUD、无栈参数；在当前房间视角内执行。后更新和绘制前，从临时玩家名单选择四个主身体及其四个伴生身体，过滤子实体、已移除实体及重复双子，Soul B 不占伴生栏。

PlayerHUD 步长 `0x6b0`，借用玩家指针为 `+0`，刷新标记为 `+0x6a0`。仅绑定变化时调用 `PlayerHUD::Reset`（RVA `0x4f9780`、thiscall、无参数），随后设置目标指针及 `0x101` 刷新标记；不复制心容器、道具缓存或 Sprite。变化后对 `HUD+0xc45c4` 的 HistoryHUD 调用 `0x507c90`，栈参数为 true、清栈 4 字节。对象、容器及资源仍由游戏管理。

StatHUD／HistoryHUD 玩家查询入口为 `0x508370/0x508000`，以 ECX 接收对应 HUD，栈上一个玩家参数、清栈 4 字节。联机只接受本机控制器，历史栏查询额外使用本机玩家名单。StatHUD 从 `+0x114` 起有两个玩家缓存，步长 `0xcc`；发现旧队友缓存时调用 `0x508400` 原生 Reset，再执行查询。退出联机恢复原生选择行为，空对象不被解引用。五个 Hook 成组安装，冲突只撤销本组件已创建的 Hook。

[搬家盒图标绑定](https://github.com/BMingSY/isaac-lan/blob/main/src/engine/versions/j835/moving_box.cpp)在 `PlayerHUD::RenderActiveItem` 的 RVA `0x4fcd69` 接入原生空容器分支，EDI 为玩家，非空／空继续位置分别为 `0x4fcd6f/0x4fd0ec`。原生内容向量为 `Player+0x1c9c/+0x1ca0`；客机仅按同步布尔值选择图标，快照缓存同时核对实体初始种子，重置时清空。主机继续读取原生容器。边界恢复通用寄存器、标志、SSE、x87 与 MXCSR，不写向量、纹理或裁剪数据，不转移对象所有权；安装冲突保留外部 Hook，清理失败状态后可重试。

## 玩家 HUD 坐标

[坐标组件](https://github.com/BMingSY/isaac-lan/blob/main/src/engine/versions/j835/player_hud.h) 复用[借用与范围检查](https://github.com/BMingSY/isaac-lan/blob/main/src/engine/versions/common/player_hud.h)，只返回控制器栏位、布局和坐标。原生可见位为 `HUD+0xc3eb6`；仅查看前四个主 HUD，不保留指针或写入缓存。空槽、隐藏、无效控制器、非有限或非正视口尺寸及屏幕外位置均不返回坐标。

J835 没有独立的布局／坐标查询方法；`HUD::Render` 在心形绘制调用 `0x505965` 前按 HUD 数组顺序构造四个位置。令 `m=1-HUDOffset`，其坐标分别为 `(68-20*m, 24-12*m)`、`(width-135+24*m, 24-12*m)`、`(80-22*m, height-33+6*m)`、`(width-135+16*m, height-33+6*m)`。组件按原生规则先计算相对坐标，再为负坐标加上视口尺寸；布局编号为对应的 0–3 角位，联机身份独立取自绑定玩家的控制器。调用方须处于与 HUD 绘制一致的本机名单作用域。

## 百宝袋与副手 HUD

[百宝袋绑定](https://github.com/BMingSY/isaac-lan/blob/main/src/engine/versions/j835/crafting_hud.cpp) 复用[共享选择与绘制组件](https://github.com/BMingSY/isaac-lan/blob/main/src/engine/versions/common/crafting_hud.cpp)。八个 PlayerHUD 的步长是 `0x6b0`，`+0/+4` 借用玩家和所属 HUD，`+8` 是原生 short 索引。控制器和幽灵标志为 `Player+0x154c/+0x1f88`；`GetActiveItem` RVA `0xf3f10` 使用 thiscall 接收槽号并清栈 4 字节，查询 `Player+0x14c4+slot*0x1c`。适配只查询四个有效槽，不依赖 J510 的槽号保护。

| 绘制 | J835 ABI | 借用边界 |
| --- | --- | --- |
| 百宝袋 `0x500570` | `ECX=PlayerHUD`、`XMM2=scale`、栈 `Vector*`，清栈 4 字节 | 仅将 receiver 换为下一栏位的 HUD；原生材料、配方纹理和缓存由该玩家及游戏持有 |
| 副手 `0x4fe8e0` | `ECX=PlayerHUD`、`XMM2=有符号缩放`、`XMM3=透明度`、栈 `Vector*`，清栈 4 字节 | 保持本机 receiver、透明度和卡牌／药丸；借用临时坐标和完整缩放，不改写原调用方的 Vector |

完整右下角位置遵循原生调用 `0x505f28`：逻辑宽高为 RVA `0x7fec08/0x7fec68`，`m=1-Manager[0x29e3c]`，位置为 `(width-28+16*m, height-18+6*m)`。该选项位于 `Options+0x44`。副手原生入口对正数 HUD 索引翻转对齐，伴生身体通过 `Player+0x1d80` 的另一身体及双方 `+0x1550` 的索引决定例外；适配以缩放符号抵消该翻转，保持绝对缩放 1，不临时改写 HUD 或玩家索引。

普通会话沿用全部原生参数。联机挑战仅显示本机副手，材料目标必须属于不同栏位、不是幽灵且仍持有百宝袋；等待视图提交时隐藏。寄存器、SSE、栈参数和调用方坐标在借用结束后恢复。两个 Hook 成组安装，失败只清理本组件创建的 Hook 和借用指针，允许修复冲突后重试，重复安装被拒绝。

## 存档与进度

[save.cpp](https://github.com/BMingSY/isaac-lan/blob/main/src/engine/versions/j835/save.cpp) 使用游戏的原生序列化格式，不能读取忏悔＋的存档。`Manager`、`Game` 和 `GameState` 都由游戏持有；后端只在同步调用期间借用对象。入口签名和重定位掩码与其他原生入口一起校验。

| 操作 | J835 ABI | 布局与限制 |
| --- | --- | --- |
| 采集 | `thiscall void(Game*, GameState*)`，RVA `0x2cc850` | 默认目标为 `Manager+0xf34`；包含玩家离房处理，调用方须配对恢复进房临时状态 |
| 清理 | `thiscall void(GameState*)`，RVA `0x520160` | 解码前清理已有原生内容；不替换对象本身 |
| 编码 | `thiscall bool(GameState*, Context*)`，RVA `0x521a00` | 临时流字段为 `GameState+0x1fac8`，输出上限 8 MiB |
| 解码 | `thiscall bool(GameState*, Context*)`，RVA `0x524320` | 仅一个栈参数，被调方清理 4 字节；J510 的额外布尔参数不适用 |

两版共用 [x86 内存流](https://github.com/BMingSY/isaac-lan/blob/main/src/engine/versions/common/save_stream.h)，`Context` 为 28 字节，原生读写回调返回元素个数。流与字节缓冲由扩展持有，不能交给游戏释放；越界寻址、短读、只读流写入和分配失败会使整个操作失败，流指针在返回和 C++ 异常退出时恢复。

原版退出且不保存时会直接调用 `GameState::DeleteFile`（RVA `0x520ac0`，`thiscall void(GameState*)`）。联机存档保护生效且接收对象为当前 Manager 的活动存档时，只调用该对象原生的内存清理。引擎退出时随后将 `Manager+0xf28` 的磁盘校验和清零。会话在联机开局前保存该值，在个人进度写盘和菜单重新读取单人存档前恢复它。单人和其他存档对象仍使用原版文件操作。

原生解码失败处理可能请求删除存档文件。[文件名作用域](https://github.com/BMingSY/isaac-lan/blob/main/src/engine/versions/common/save_file_names.h) 在内存流解码期间临时清空四个本地／Steam 文件名槽，随后逐字节恢复原生字符串和其所有权。文件名偏移在 [layout.h](https://github.com/BMingSY/isaac-lan/blob/main/src/engine/versions/j835/layout.h) 中集中声明。原版读取还强制比较上次本机磁盘存档的校验值，没有 J510 的禁用进度匹配参数；内存恢复期间临时将 `Manager+0xf28` 设为载荷尾四字节异或 `0x96696996`，返回或异常时恢复原值。原生仍计算并校验载荷正文与尾部，损坏数据照常失败；不修改磁盘存档或持久化进度。此保护不提供 GameState 内容回滚：失败后会话必须中止恢复，不能把部分加载状态视为完成。

进度位于 `Manager+0x14`；成就数组从 `+0x38` 开始，共 638 字节，计数数组从 `+0x2b8` 开始，共 496 个 uint32。[进度复制组件](https://github.com/BMingSY/isaac-lan/blob/main/src/engine/versions/common/progress.h) 只读写这些元素，共同网络结构的剩余元素补零，不触及相邻收藏记录或按忏悔＋的数组长度访问原版对象。

通关计数在原版中使用 0／1／2 表示未完成、普通和困难，网络进度使用 0／1／3 的完成位。进度组件仅对完成标记的事件编号转换，其他累计计数保留原值；菜单临时借用个人进度时另存原始数组，退出作用域后精确恢复原生值。

原版 `Manager::RecordPlayerCompletion`（`0x4b5040`，stdcall、一个事件参数）在函数内部遍历角色。[会话适配](https://github.com/BMingSY/isaac-lan/blob/main/src/engine/versions/j835/session_backend.cpp)只观察 `0x4b5185` 的内部边界：原生已排除幽灵、依附身体和重复双子，ESI 为事件、EBX 为所选角色、EDI 为 Game，难度位于 `Game+0x243624`。描述表位于 RVA `0x7c5fe0`，每角色 18 对计数／成就编号。观察记录本局获得的普通／困难完成位，重复通关同样通知；心脏的普通完成不授予困难成就。只读进度不产生通知，原生更新和解锁仍完整执行。边界保存通用寄存器、标志、SSE、x87 与 MXCSR，回调异常交给会话中止处理，不能穿过原生栈帧。

个人进度持久化先标记 `Progress+0` 为脏，再调用 RVA `0x4848f0`，ABI 为 `thiscall void(Progress*, bool backup)`，传入 `true`。原生方法检查初始化标记，保存日期备份，并按 Steam 接口及游戏设置选择云端或本地文件；流的打开、关闭和所有权仍由游戏管理。不能直接调用需要有效输出流的序列化入口 `0x4836a0`。只读作用域临时设置 `Progress+1`，嵌套返回时恢复原值。

## 沙漏检查点与转场

[回退绑定](https://github.com/BMingSY/isaac-lan/blob/main/src/engine/versions/j835/rewind.cpp) 向[共享检查点组件](https://github.com/BMingSY/isaac-lan/blob/main/src/engine/versions/common/rewind.cpp) 提供缓冲区布局和原生调用。每个控制器保留一份序列化检查点，等待请求由[回退目标策略](https://github.com/BMingSY/isaac-lan/blob/main/src/compat/items/rewind_targets.h) 管理；恢复与换层发布仍通过运行和房间组件协调。

| 操作 | J835 入口与 ABI |
| --- | --- |
| 原生检查点采集 | `0x2d7f80`，`stdcall void(int door)`，清栈 4 字节；读取全局 Game，不接收对象参数 |
| 权威选路 | `0x2d07d0`，`thiscall void(Game*, int index, int direction, int animation, Player*, int dimension)`，清栈 20 字节 |
| 客机结果回放 | `0x3e9650`，相同五个栈参数，receiver 为 `Game+0x1b6c0` 的 RoomTransition |
| Home 换层 | `0x2d0aa0`，`thiscall void(Game*, bool same, int animation, Player*)`，清栈 12 字节；回退选中 Home 后传入 false、6、null |

两个原生缓冲区从 `Game+0x243648` 开始，步长 `0x20298`；选择编号为 `Game+0x283b78`。缓冲区有效位为 `+0`，GameState 为 `+4`，门、帧和计数数组分别为 `+0x1fad0/+0x1fad4/+0x1fad8`。只复制 496 个计数，既有网络载荷的剩余 27 项补零；接收非零尾项在原生写入前失败。恢复使第一缓冲区有效、第二缓冲区无效并选择第一项，不复制原生容器或代管析构。使用者的两个沙漏计数字段为 `Player+0x1cc8/+0x1ccc`，由原生恢复继续处理各主动槽与库存副作用。

主机先恢复完整名单和使用者的来源房上下文，再恢复 GameState 并调用原生选路。Home 只发布换层事务；其他结果记录 RoomTransition 的实际索引、方向、动画和维度，客机调用下层入口回放，不再按本机视角选路。只有原生动画 12 恢复检查点中的玩家位置，其他动画或原生提前返回保持实际落点。在贪婪和贪婪＋首访起始房使用沙漏时，J835 执行普通回退，双方恢复检查点保存的房间、库存与血量。Home 目的地也由游戏自行选择。J835 回放结束后直接交还游戏，转场尾部字段仅由 J510 后端维护。

全部载荷、校验和、位置与转场范围在原生恢复前检查；GameState 部分恢复仍不提供回滚，失败交给运行层中止。检查点重置只清除持有的字节与位置，不破坏调用栈内的 Home 捕获作用域。采集 Hook 在虚拟房间运行时阻止其他房间替换全局缓冲区，显式采集通过原函数执行；单人完整透传，安装失败只清理自己的 Hook 并允许重试。该组件不提供完整房间后端，实际使用仍依赖来源房激活和转场完成调度。

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

诊断接口 `audit` 与 `trace_callback` 可核对当前楼层、房间、帧数、人数及有界回调栈；它们不控制正常玩法。J510 的独立双房间实验仍由 [room_probe.cpp](https://github.com/BMingSY/isaac-lan/blob/main/src/engine/versions/j510/room_probe.cpp) 管理原生对象，J835 不注册尚未适配的实验接口。正式房间调度由原版绑定和共享调度组件提供。

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

控制调用返回后检查 `Game+0x1c31b0`：动作 `4` 为死亡后重开，`5` 为长按重开。仅当运行层接受请求时清除动作、`+0x1c31a8` 的淡出透明度和 `+0x1c31b4` 的按住帧数；其他动作及拒绝的请求保持原样。换层采集读取关卡／类型、`Game+0x1bb04` 的 Seeds 标量前缀（21 字、`0x54` 字节）及 `+0x1c3168` 的两字路由标记。前缀包含自定义局标志、开始种子、RNG、`+0x18` 起的十四个楼层种子和玩家初始化种子；Seeds `+0x54/+0x58` 的种子效果树指针与数量保持本机所有权，不采集或覆盖。应用只写标量前缀和标记，实际转场仍由原生房间能力推进。

控制台对象位于 `Game+0x1bb60`，输入状态在对象 `+0x20`。输入入口 `0x263550` 为 `thiscall void(Console*)`，命令入口 `0x2655c0` 为 `thiscall void(Console*, const NativeString*, bool silent, Player*)`，打印入口 `0x26aec0` 为 `thiscall void(Console*, const NativeString*, unsigned color, unsigned fade)`。命令执行要求已就绪的权威会话和角色房间作用域。24 字节 MSVC 字符串通过原生 assign `0x7c80` 与析构 `0x7be0` 配对管理；结果复制为自有字符串，限制 16 KiB，同步嵌套与返回恢复前一捕获目标，不保留原生文本引用。

## 输入设备与查询适配

[设备绑定](https://github.com/BMingSY/isaac-lan/blob/main/src/engine/versions/j835/input_devices.cpp) 使用原生扫描 `0x59d3b0` 和轮询 `0x59d720`，两者均无参数、调用方清栈。`InputManager::Update` 的 `0x56a150` 接收 ECX 中的管理器。三个入口通过[公共设备组件](https://github.com/BMingSY/isaac-lan/blob/main/src/engine/versions/common/input_devices.cpp) 串行化完整遍历、回调与释放过程；同线程原生连接回调可以重入轮询，离开联机后继续保护设备断开清理。

输入管理器是 RVA `0x7e7c98` 的内嵌对象，其指针列表首尾为 `+4/+8`，元素四字节；设备 ID 位于 `+8`。只有至少四个正编号设备都存在时才分配联机 ID `1..4`，保留键盘、其他设备和容器顺序。退出只恢复仍在列表内且仍使用所分配编号的设备；不解引用已移除对象，不覆盖原生独立更改的编号。设备及容器由游戏创建和销毁，组件只保存恢复所需的身份记录，不取得所有权。

[输入查询适配](https://github.com/BMingSY/isaac-lan/blob/main/src/engine/versions/j835/input_queries.cpp) 把三个原生入口连接到后端内部的统一查询接口。按住 `0x56a520` 和按下沿 `0x56a5e0` 的 ABI 为 `thiscall bool(InputManager*, int action, int controller, int* source)`；模拟量 `0x56a6c0` 参数相同，通过 x87 返回 float。适配器保持动作、控制器和来源指针的顺序，将模拟量转为同步输出参数，再还原原生 float 返回值。

物理输入旁路只接受这三个已安装入口对应的查询标识，通过原函数 trampoline 调用，不重新进入联机路由、不执行任意回调地址。参数与输出对象只在调用期间借用；适配器不分配、销毁或持有原生设备。安装失败只撤销自己创建的 Hook 并清除旁路，允许重试；重复安装不会替换现有旁路。

两版游戏自带枚举中的前十六个动作与菜单方向 `20..23` 相同；原版重开为 `16`，没有原生表情动作。差异集中在 [input_actions.h](https://github.com/BMingSY/isaac-lan/blob/main/src/engine/versions/j835/input_actions.h)，不能把忏悔＋的 UI 动作编号直接传给原版。[共享输入路由](https://github.com/BMingSY/isaac-lan/blob/main/src/engine/versions/common/input.cpp) 通过 [J835 绑定](https://github.com/BMingSY/isaac-lan/blob/main/src/engine/versions/j835/input.cpp) 使用上述组件：物理采集、虚拟 XInput、权威输入、按键沿消费、暂停意图、呈现预测和退出恢复共用实现。上层请求的重开动作映射为原版 `16`，不存在的表情动作直接返回未触发；原生进入路由的动作编号保持原样，不做二次映射。采集以 `Manager+0x4a264` 的渲染帧编号去重，网络输入仍使用相同的十六动作与世界坐标鼠标目标契约。

原版按钮提示只由 `MenuManager::RenderButtonLayout` 绘制；原生开局清理会销毁该菜单，Manager 内没有 J510 的持久提示组。因此原版菜单提示重置适配不访问额外对象。共享输入组件由房间和启动后端装配，按当前视图借用名单。

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
| 发放道具 | `0x32b260`，`thiscall void(Player*, int id, int charge, bool first, int slot, int data)`，清栈 20 字节；与 J510 的六个栈参数不同 |
| 拾取入队 | `0x32a500`，`thiscall void(Player*, ItemConfig*, int charge, uint8 flags, int data)`，清栈 16 字节；仅确认拾取返回点 `0x2c1610` 可通知上层分配策略，其他调用和饰品沿用原生队列 |
| 开局奖励 | 仅原生祝福发放返回点 `0x382207` 记录奖励；共享策略决定是否及向哪些槽位发放。重复加入不重复发放，开始失败清除部分记录 |
| 移除／重新发放 | 持有查询 `0x33af30` 接收道具与忽略变形标志；掉落 `0x3570e0` 接收道具、已有掉落物指针及移除变形标志，清栈 12 字节。临时掉落物由虚表 `+0x28` 的原生 Remove 管理，组件只复制 `+0x474` 充能与 `+0x4e8` VarData |
| 主动充能 | 容量 `0x357e40` 接收槽位；增加 `0x358030` 接收数量、槽位、提示、溢出与强制标志，清栈 20 字节。共享接口将后三个标志传为 false。原版充能类型从该槽的配置 `+0xac` 读取，与原生增加充能的判定一致；槽描述从玩家 `+0x14c4` 开始，步长 `0x1c` |
| 复活 | 道具 `0x367370`、饰品 `0x3687c0` 均以 ECX 接收角色并清理两个栈参数；饰品的第二个调用方暂存字原样转发。原生调用期间借用所属角色房间，已有作用域及单人场景保留原上下文 |
| 蓝色房间 | `0x31a1f0` 接收 Game 和来源房、目标房、门方向，清栈 12 字节，返回是否初始化成功；房间数据的创建与所有权由原生方法处理 |
| 离房激光 | 只处理玩家 `+0x13a0` 的原生激光引用，先 Remove，再以 fastcall `0x28cf00` 清空引用；不释放实体内存、不清除 `+0x1814` 的剩余持续时间 |

桥接仅接受八字节借用 Sprite 包装、当前权威房间内已连接的活动玩家，并核对玩家列表、类型 `+0x28`、存在位 `+0x16a` 和控制器 `+0x154c`。精灵位于实体 `+0x3c`，初始种子为 `+0x344`；不向 Lua 暴露这些地址。配置目录通过 cdecl `0x27930` 取得，再由 thiscall `0x2fe5e0` 查询道具，包括原生生成道具的处理；字符串立即复制，仍由游戏管理其存储。

`actor_smelted_trinkets` 使用[共享吞饰品组件](https://github.com/BMingSY/isaac-lan/blob/main/src/engine/versions/common/smelted_trinkets.h)，载荷与客机写入限制见[接口契约](https://github.com/BMingSY/isaac-lan/blob/main/docs/native-backend.md#道具与效果)。J835 的 `Player+0x1670` 为游戏持有的向量，每项两个 `i16` 计数，普通／金色位于 `+0/+2`。容器遍历与计数操作的签名 `0x368cba/0x368c8d` 校验该布局。恢复先验证全部条目，再原位更新计数并清零省略项；不调整容量、不触发使用道具、不改持有饰品或历史条目。计数变化后的属性刷新由同步层执行。

死亡证明的延迟返回使用[共享返回组件](https://github.com/BMingSY/isaac-lan/blob/main/src/engine/versions/common/death_certificate_return.cpp)和[J835 原生适配](https://github.com/BMingSY/isaac-lan/blob/main/src/engine/versions/j835/death_certificate_return.cpp)。倒计时为 `Game+0x285234`，来源房间／有符号维度为 `+0x1878c/+0x18790`；返回边界 `0x2ce54e`、完成后续点 `0x2ce598` 受启动签名校验。主机视口已离开道具区时，只为这次返回借入仍在线的道具区玩家，使用上层转场 `0x2d07d0`；来源房间为 `-2` 时沿用原版规则将维度归零。没有在线道具区玩家时仅消费倒计时；单人、客机和视口仍在道具区时继续原生分支。

返回适配保存通用寄存器、标志、x87、XMM0–7 和 MXCSR，异常终止会话且不跨原生帧展开；借入的房间和角色均不转移所有权。Hook 冲突不撤销其他组件的 Hook，失败可重试，重复安装只接受相同映像。

安装将发放、入队及两种复活 Hook 全部创建后再启用；失败只撤销自己创建的 Hook 并清除旁路，允许重试。玩法效果、拾取分配和开局奖励规则仍属于上层兼容组件。

错误道具注册表、原生生成与存档恢复、负编号库存查询的接口和所有权见[错误道具定义](https://github.com/BMingSY/isaac-lan/blob/main/docs/generated-item-definitions.md)。这部分复用共享定义组件，不改变现有同步字段、编码或扩展接口。

## 房间进入与混乱诅咒边界

[房间边界绑定](https://github.com/BMingSY/isaac-lan/blob/main/src/engine/versions/j835/room_routing.cpp) 连接[共享回调组件](https://github.com/BMingSY/isaac-lan/blob/main/src/engine/versions/common/room_routing.cpp)。`Level::ChangeRoom` 的 RVA `0x30d7fe` 位于最终索引、维度与入口确定之后，原生混乱诅咒的临时容器已经销毁，目的房间尚未初始化。回调读取 `Game+0x18194/+0x1819c/+0x181ac`；原生改送标志来自当前 `EBP+0xf`，不能使用 J510 的 `EBP+0xb`，也不能由标准房间索引变化推断。

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
| `Size` | 有实体配置时使用 `0x40e460`，`cdecl void(Entity*, float)`；无配置时调用 `0x2843a0`，`thiscall void(Entity*, float radius, Vector multiplier, int points)`，清栈 16 字节，保留原生碰撞尺寸更新 |
| `Color` | `0x40e430`，`cdecl void(Entity*, const Color*)`；44 字节临时值包含七个通道和置零的 colorize，由原 setter 调用实体虚方法 |
| `CollisionDamage` | 实体虚表 `+0x3c`，`thiscall void(Entity*, float)` |
| 泪弹 `Height`／`Scale` | `0x2500f0`／`0x250250`，`thiscall void(Tear*, float)`；保留高度及精灵缩放的副作用 |
| 掉落物 `Price` | `0x2b91e0`，`thiscall void(Pickup*, int)`；重复价格仍执行原生显示更新 |
| `SortingLayer`／`RenderZOffset` | `Entity+0x2b4/+0x2ac` 的 int32；不改变实体所属列表 |
| 掉落物 `ShopItemId` | Lua setter 直接写入 `Pickup+0x488` 的 int32；J510 的 -2 至 7 限制不适用 |

完整属性偏移集中在 [layout.h](https://github.com/BMingSY/isaac-lan/blob/main/src/engine/versions/j835/layout.h)。实体借用 Sprite 位于 `Entity+0x3c`，存活字节为 `+0x16a`；实体帧数为 `Game+0x1a30dc` 减 `Entity+0x280`，保留 uint32 回绕和有符号返回语义。身份、帧数、标志和精灵名称仍为只读字段。

Sprite 原生对象为 `0x114` 字节，Lua 自有 wrapper 为 `0x11c` 字节、借用 wrapper 为 8 字节。两版动画状态、44 字节颜色和 MSVC 字符串字段具有相同布局，但声明仍属于版本绑定。名称在调用内复制，动画数据、文本缓冲和临时 setter 参数不跨调用保留，不转移资源所有权。

尺寸恢复读取 `Entity+0x288` 的借用配置指针；无配置实体使用 `+0x2cc` 的原尺寸倍数和 `+0x170` 的碰撞点向量，在校验有限值、向量边界和点数后调用原生 setter，不自行分配或释放碰撞点。

NPC 身份通过 RVA `0x5ec34c` 的 MSVC `__RTDynamicCast` 导入跳板判定，Entity／EntityNPC 类型描述符位于 RVA `0x7eab18/0x7eab70`；描述符名与入口受签名校验，不用数值类型范围排除 Mod NPC。`entity_npc_boss` 只允许客机恢复活动 NPC 的分类字节 `+0xb8d`，与 `EntityNPC::IsBoss`（`0x28f570`）一致。该标记独立于 Boss 类型编号，不触发 AI 或分配实体。完整实体姿态与其他原生引用接口不属于这一字段组件。

## NPC 命中与受击绘制

[J835 命中绑定](https://github.com/BMingSY/isaac-lan/blob/main/src/engine/versions/j835/combat_feedback.cpp) 使用[共享事件和绘制组件](https://github.com/BMingSY/isaac-lan/blob/main/src/engine/versions/common/combat_feedback.cpp)。Lua 接口、序号、房间观看者过滤和字节布局遵循[命中反馈契约](https://github.com/BMingSY/isaac-lan/blob/main/docs/native-backend.md#npc-命中与受击绘制)，不改变原生伤害队列、HP 或回调返回值。

| 原生边界 | J835 ABI 与布局 |
| --- | --- |
| `NPC::TakeDamage` | `0x2ac370`，`thiscall bool(NPC*, float, uint64, EntityRef*, int)`，清栈 20 字节；来源实体位于 EntityRef `+0x24` |
| `Entity::SetColor` | `0x28a380`，`thiscall void(Entity*, Color*, int frames, int priority, bool fade, bool share)`，清栈 20 字节 |
| 伤害颜色调用 | 返回点 `0x286ff9`，ESI 为当前队列项，ECX 为实体；只接管这一来源的权威 NPC 闪烁，其他颜色调用完整透传 |
| 队列清空边界 | `0x28701d`，EDI 为实体；发布确认后由原生代码清空队列，旁路保留通用寄存器、标志和 SSE 状态 |

队列为 `Entity+8/+12` 的首尾指针，每项 `0x38` 字节；事件只保留队列索引及调用前取得的来源／目标身份，回调移除来源后不再解引用它。嵌套命中各自归属，真实颜色调用决定时长；队列无闪烁地结算时仍保持零时长，未结算或旧楼层观察按共享边界清理。

身份使用实体初始种子 `+0x344` 和索引 `+0x20`；本机绘制从房间渲染数组 `+0x125c/+0x1264` 借用实体，临时替换 Sprite `+0x3c` 的颜色 `+0xa8`。44 字节颜色在正常返回、嵌套绘制及 C++ 异常退出时恢复，不调用原生颜色入队方法，不持有或释放实体。Hook 安装成组回滚并保留外部 Hook，组件完整使用仍依赖 J835 房间调度与呈现。

## 本机掉落物预览

[预览绑定](https://github.com/BMingSY/isaac-lan/blob/main/src/engine/versions/j835/pickup_preview.cpp) 通过[共享预览组件](https://github.com/BMingSY/isaac-lan/blob/main/src/engine/versions/common/pickup_preview.cpp) 调用 `0x2b81c0`，ABI 为 `thiscall void(Pickup*)`，无栈参数。原生方法读取当前玩家名单的道具，创建或移除预览并维护实体引用；组件不复制 LootList、Sprite 或其他原生对象，也不分配、释放预览资源。

联机玩法更新期间跳过原生预览更新，在本机视角就绪后借用本机玩家名单执行。Room 指针为 `Game+0x18190`；实体列表位于 `Room+0x1218`，渲染数组为列表 `+0x40`，数据／数量为数组 `+4/+0xc`。先复制本次类型为掉落物的实体指针，再依次调用原生更新，允许原生预览创建期间更换数组。无效视角、空 Game／Room／列表不执行更新；已经移除但仍在渲染列表中的掉落物仍交给原生方法清理预览，不能仅按活动位跳过。

这些指针只在当前同步视角调用内借用，不保留到下帧；房间切换、异常退出与重连沿用房间视角的恢复边界。Hook 失败清除自身旁路并允许重试，单人原生更新完整透传。同步视角由 J835 绑定连接的共享房间调度提供。

## 暂停菜单

[暂停菜单绑定](https://github.com/BMingSY/isaac-lan/blob/main/src/engine/versions/j835/pause_menu.cpp) 为[公共菜单组件](https://github.com/BMingSY/isaac-lan/blob/main/src/engine/versions/common/pause_menu.cpp) 提供原生入口和布局。显示 `0x5178e0`、隐藏 `0x517810`、控制 `0x515ba0` 均为 `thiscall void(PauseScreen*)`，对象位于 `Game+0x10203c`；菜单对象及动画由游戏持有，后端不自行创建或销毁，也不强制改写隐藏动画的完成状态。

根页值为 `1`，选择字段为 `+8`，继续选项为 `1`、退出为 `2`；选项页值为 `2`。选项对象位于暂停菜单 `+0x806a8`，选择字段 `+4`，条目向量为 `+0x260` 的首尾及容量指针。选中 ID `1` 的确认操作会重新分配控制器，应由联机输入路由拦截；普通选项保留原生处理。越界选择或无效向量不能进入控制器分配路径。由同伴恢复游戏时，先调用 `thiscall void(OptionsConfig*)` 的保存入口 `0x4805a0`，接收 `Manager+0x29df8`，再隐藏选项页。

原版没有暂停菜单玩家索引，原生显示和控制读取 `Game+0x1ba50` 名单的首位角色，控制器字段为 `Player+0x154c`。本机菜单的显示、控制及只读状态查询使用房间视图提供的临时名单；菜单组件不交换或保留名单，不仿造忏悔＋的索引字段。重复暂停状态保留当前子页、选择及借用名单；退出房间视图后仍由房间组件恢复名单。

## 角色目录与表现

[角色目录](https://github.com/BMingSY/isaac-lan/blob/main/src/engine/versions/j835/characters.cpp) 通过原生目录读取角色、里角色及 Mod 角色，复用两版共有的目录算法。原版选择条件入口为 RVA `0x4a1ea0`，`thiscall bool(record*, int)`；翻译入口为 RVA `0x56b880`，使用 `Manager+0x4a234` 的字符串表。选择条件在临时安装本机个人进度和菜单场景后求值，返回时恢复；伊甸继续游戏只临时豁免已经消耗的代币，不更改实际进度。目录只返回复制后的名称、资源路径和可选状态，不持有原生容器。完成标记使用共同的原版事件编号，替代身体映射到对应起始角色。

菜单与聊天从原版中文资源目录 `resources-dlc3.zh/font/` 加载 TeamMeatFontExtended 的 10、12 和 16Bold 三种字号。完整资源路径让其他游戏语言也能显示局域网界面的中文。主菜单标题的 ANM2 描述只记录官方字形的位置，字体图像由游戏提供，渲染时整行旋转。大厅使用挑战菜单的图钉纸、种子菜单的便签和勾选标记，以及主菜单的指针。角色画像与完成标记沿用游戏资源。官方在线服务和原生表情轮盘按版本能力显示。

候选入口可以参考 [REPENTOGON 1.0.12e](https://github.com/TeamREPENTOGON/REPENTOGON/tree/1.0.12e/libzhl/functions)，但参考特征码不是当前游戏的 ABI 保证。审计必须保留多重匹配并核对实际调用点、参数、返回值、对象布局与所有权；不把 J510 地址或字段偏移套入 J835。离线与实机边界见[开发与测试](https://github.com/BMingSY/isaac-lan/blob/main/docs/development-and-testing.md)。
