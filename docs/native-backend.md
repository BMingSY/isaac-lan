# J460 原生能力参考

本文记录原生能力、调用边界与所有权，供修改版本后端时查阅。适用 Repentance+ `1.9.7.17.J460`，游戏 SHA-256 为 `7122ac28779925b24e23e2416f231322b1470388bd25e2c08665ad8d53b3ea4f`。

入口与签名以 [entrypoints.h](https://github.com/BMingSY/isaac-lan/blob/main/src/engine/versions/j460/entrypoints.h)、[signatures.inc](https://github.com/BMingSY/isaac-lan/blob/main/src/engine/versions/j460/signatures.inc) 为准，布局由版本后端持有。这里的地址不能用于其他游戏版本；桥接和兼容组件仅使用具名能力，不读取任意内存。

## 实体字段批量读写

[`entity_fields_plan(type, template)`](https://github.com/BMingSY/isaac-lan/blob/main/src/engine/versions/j460/entity_fields.cpp)将 Lua 同步组件提供的嵌套字段名数组编译为 userdata。仅支持泪弹、跟班和效果实体的具名属性白名单；`false` 为由 Lua 填充的占位，其他实体类型返回 `false`。模板最多 128 个节点、三层深度，不接受地址或偏移。计划只持有字段描述符，不持有游戏对象；线上的字段顺序仍由 Lua schema 决定。

`entity_fields_capture(entity:GetSprite(), plan)`返回同形数组。`entity_fields_apply(sprite, plan, value)`只允许客机调用；一次遍历校验整份数组的形状、类型、有限数值与整数范围，将普通值保存在固定大小的栈缓冲后，再按模板顺序写入。两者要求活动实体的借用 Sprite 与计划类型相符，返回后不保留 Sprite、实体或数组引用。对象分配、回收和实体身份仍由原有生命周期管理。

`entity_fields_encode(sprite, plan)` 将数值计划直接编码为与 `state_encode` 相同的数组字节，不生成中间 Lua 表；`entity_fields_apply` 也接受这种字节串。此路径仅支持上述三类实体的数值字段，最多 4864 字节，使用固定栈缓冲；解码按计划核对每个数组、数值范围和结束位置，完整校验后才写入该计划的字段。身份、位置、速度及引用仍单独供 Lua 同步组件使用。编码占位只能为 `false`，不接受精灵名称字段或任意内存数据。

`sprite_fields_plan(template)`／`sprite_fields_capture(sprite, plan)`／`sprite_fields_apply(sprite, plan, value)`使用同一模板边界处理精灵字段。支持文件名、动画名、帧、翻转、旋转、缩放、偏移及七个颜色通道；字符串与动画字段只读，动画切换、加载和完整层状态继续使用原有接口。接受借用或 Lua 自有 Sprite，不能将实体计划用于精灵。主动画帧按原版取 floor，叠加帧截断；无动画返回空名称与 `-1`。颜色写入与七参数 Lua `Color` 一致，完整 colorize 状态随后由 `sprite_state` 恢复。

J460 属性布局集中在 [`layout.h`](https://github.com/BMingSY/isaac-lan/blob/main/src/engine/versions/j460/layout.h)，属性与读写策略在 [`entity_fields.h`](https://github.com/BMingSY/isaac-lan/blob/main/src/engine/versions/j460/entity_fields.h)。`Size` 调用原 Lua 属性 setter（cdecl，RVA `0x471fa0`）；`Color` 构造 44 字节临时颜色值并调用原 setter（cdecl，RVA `0x471f70`），保留其虚方法及精灵颜色处理，不保留该临时指针；`CollisionDamage` 使用实体虚表 `+0x40`；泪弹 `Height`／`Scale` 调用原 thiscall setter（RVA `0x275fc0`／`0x276120`），保留游戏副作用。其余白名单字段采用相同的属性存储，身份、帧计数和实体标志只读；标志、引用、外观与兼容规则仍通过所属适配器应用。入口受版本签名校验，不能用于其他游戏版本。

## 实体引用与房间数据

角色服装姿态按路径与同名出现顺序映射到本机索引，未知路径使用基础层回退。[映射规则](https://github.com/BMingSY/isaac-lan/blob/main/src/core/occurrence_mapping.h)只接收普通字符串视图；版本后端在单次调用内借用原生名称，不跨调用缓存服装地址。Lua 表现层仅在增删服装后重新取得 Sprite 列表，渲染前仍恢复权威姿态。

`sprite_state(sprite)` 复制完整精灵层状态为字节串；客机的 `sprite_state(sprite, bytes)` 恢复状态，返回需要替换的贴图层数组，没有贴图变化时返回 `true`。返回值不持有原生引用；Lua 只在数组非空时替换贴图并调用 `LoadGraphics`。捕获缓冲预留容量不改变字段或编码字节。

精灵载荷以格式号 `2` 开头，主动画与叠加动画各保存存在标记、浮点帧、播放标记、当前／历史事件位图、图层与挂点层的 ID／帧索引。可移植契约见 [animation_pose.h](https://github.com/BMingSY/isaac-lan/blob/main/src/core/animation_pose.h)：最多 64 个图层、256 个挂点层，帧索引为 `-1` 或小于 65535 的整数；拒绝重复 ID、非法标记与非有限帧。J460 的动画状态 `+0x8/+0xc` 分别引用图层／挂点帧数组，动画数据 `+0x20/+0x24` 为挂点描述数组与数量，每项 16 字节，帧数位于项内 `+0xc`。事件位图位于动画状态 `+0x18/+0x1c`。所有数组由游戏持有，恢复只按本机 ID 与帧数边界写入；空层允许游戏自身使用的初始游标 `0` 和重置游标 `-1`，不将游标用作数组下标。不分配或替换原生数组。动画名未变化时直接恢复这些完整状态，名称变化仍调用游戏动画切换接口。

| 能力与实现 | 原生边界 | 校验与所有权 |
| --- | --- | --- |
| [持有炸弹](https://github.com/BMingSY/isaac-lan/blob/main/src/engine/versions/j460/held_bombs.h) `boss_held_bombs` | Lua API 不暴露 NPC `+0xbf0` 的持有容器；Hornfel 为两槽，Horny Boys 为三槽 | 读取本机实体索引，由兼容组件转换为同步 ID；客机写入校验 Boss、炸弹类型和槽数，使用游戏 resize 与 `EntityPtr.Assign`，容器仍由游戏析构 |
| [矿车引用](https://github.com/BMingSY/isaac-lan/blob/main/src/engine/versions/j460/entity_links.h) `entity_minecart` | 乘坐者 Entity `+0x3d4` 的反向引用不由矿车 `Child` 表达 | 仅接受矿车 Sprite／空值，使用原生引用注册与撤销；不调用会生成新矿车的玩法方法 |
| [角色持有引用](https://github.com/BMingSY/isaac-lan/blob/main/src/engine/versions/j460/entity_links.h) `actor_held_entity` | Player `+0x1410` 的 `EntityPtr` 供原生抱起渲染使用，独立于 `Parent`／`Child`；赋值位置 RVA `0x3d23e6` 受签名校验 | 读取返回本机实体索引，无对象时为 `-1`；同步组件转换为稳定 ID。写入仅限客机，接受角色和目标的借用 Sprite 或 `false`，拒绝非角色持有者和自引用；使用原生 `EntityPtr.Assign` 注册、替换和清空，目标释放时由游戏撤销引用，不调用拾取／投掷玩法 |
| [轨道布局](https://github.com/BMingSY/isaac-lan/blob/main/src/engine/versions/j460/rails.h) `room_rails` | `Room:GetGridEntity` 不包含 RailManager；房间 `+0x746c` 为 448 字节数组 | 客机整体验证长度、值、尺寸与所有者后写入；空轨道也恢复，Sprite 仍由房间持有 |
| 客机实体回收 | `Remove()` 不保证立即释放池槽位；J460 跟班池为 64 槽 | 在房间作用域内通过原生更新完成回收，更新前须启用客机 AI 拦截；不扩容原生池，不手工释放对象 |
| 玩家清房回调 | `Player::TriggerRoomClear`，RVA `0x3a8fd0`，`thiscall void(Player*)`；Lua 没有阻止原生清房效果的前置回调 | 联机客机房间启用期间跳过玩法触发，角色状态由权威快照恢复；主机、单人及原生加载保留原调用，不分配或替换角色对象 |
| 口袋槽、合成袋、药丸状态 | 原生载荷分别为 32、12、75 字节 | 在库存恢复后应用，完整校验载荷与玩家归属；写入限客机，主动对象与物品池仍由原版管理 |

实体链接在对象恢复完成后应用。原生能力只处理引用与布局，Boss 匹配和状态选择由 [compat/bosses/](https://github.com/BMingSY/isaac-lan/tree/main/src/bridge/compat/bosses) 负责。

房间转移请求可以携带目标房间中的落点，与入口门槽分开保存；明确的入口门槽优先。落点随单次请求消费，楼层和会话清理同时丢弃请求。后端读取 J460 Player `+0x20a9` 的联机幽灵标记、连接状态、房间键和坐标，将普通值交给[幽灵随队策略](https://github.com/BMingSY/isaac-lan/blob/main/src/compat/characters/ghost.h)；返回的队友坐标通过既有到达路径写入，不改变对象分配、释放或门的目的地。

## 激光路径呈现

[`laser_path(sprite)`](https://github.com/BMingSY/isaac-lan/blob/main/src/engine/versions/j460/rooms.cpp) 读取活动激光的采样状态、起点／终点、形状／缩放、采样数量与两组路径坐标。要求实体借用 Sprite，回溯所属对象后核对激光类型；不接受自有 Sprite 或其他实体类型，不跨调用保留指针。

`laser_path(sprite, bytes[, dx, dy])` 仅允许客机写入。可选偏移必须同时提供，只平移世界坐标，不修改形状、缩放或采样数量；调用方每次传入原始权威字节，避免重复渲染累积平移。公开 `EndPoint` 属性由桥接层同步设置。路径载荷沿用原格式，协议字段不增加。

J460 的采样状态位于实体 `+0x45d`，允许 `0`、`1` 与原生未初始化值 `255`；起点／终点位于 `+0x468` 至 `+0x474`，形状值为 `+0x478`、缩放为 `+0x4e0`，采样数量为 `+0x47c`，两个游戏自有向量位于 `+0x480`／`+0x48c`。采样数量及每个路径向量各限制 2048 个点，所有浮点数及平移结果必须有限；完整解析、边界和偏移校验完成后才写入。向量通过现有游戏分配接口调整，所有权和析构仍由游戏管理；可移植校验见 [laser_state.h](https://github.com/BMingSY/isaac-lan/blob/main/src/core/laser_state.h)。

## 转场与暂停

Lua `SetStage` 不能提供原生过场中延迟选层所需的来源房间；普通 `Game::StartRoomTransition` 同时选路并启动转场，不能直接作为客机结果回放接口。

[`room_routing`](https://github.com/BMingSY/isaac-lan/blob/main/src/engine/versions/j460/room_routing.h) 在 `Level::ChangeRoom` 的 RVA `0x3404ec` 同步提供最终房间索引、维度、入口及原生改送标志（当前原生栈帧 `EBP+0xb`）。改送标志也覆盖同一大房间的不同子格，不能仅通过标准房间索引是否改变推断。此处原生混乱诅咒的临时容器已析构，目的房间尚未初始化。调用方先选择或创建真实目标、迁移进入者并切换房间作用域；返回 `true` 继续原生初始化，返回 `false` 经 RVA `0x340814` 的原生公共尾部返回，再由联机运行组件执行已加载房间的进入效果。拦截保存通用寄存器、标志与 XMM0–7；公共尾部恢复原生 SEH 栈并清理两个栈参数。回调只在当前主线程调用中借用，错误在原生栈退出后重新抛出，不跨原生帧展开 C++ 异常。

已确定目的地的回放在 RVA `0x33fea8` 跳过混乱诅咒分支至 `0x34033e`，不改写诅咒位、不消耗该分支的随机数，覆盖普通诅咒与特殊种子的附加诅咒。抑制状态按调用栈恢复；单人及正常主机选路保持原生执行。活动诅咒按原生基础位、种子位及附加／移除种子效果合并。`Level::SwapRooms`（RVA `0x349270`，`thiscall bool(Level*, int, int)`）仅在原生混乱诅咒调用点检查活动房间保护，其他调用保留原行为；是否允许交换由[路线兼容策略](https://github.com/BMingSY/isaac-lan/blob/main/src/compat/routes/curses.h)决定。入口、返回点和分支均通过启动签名校验。

| 能力 | 入口与调用约定 | 约束 |
| --- | --- | --- |
| 换层来源上下文 | `Level::SetNextStage`，RVA `0x3467c0`，`thiscall void(Level*)` | 调用期间临时替换 `Level+0x18304` 来源索引，范围 `[-20, 168]`；返回恢复，事务完成／取消时失效，不切换房间对象 |
| 已决定的房间转场 | `RoomTransition.Start`，RVA `0x42ee40`，receiver 为 `Game+0x1b83c`，五个栈参数、被调方清理 20 字节 | 回放 index、direction、animation、player、dimension，保留原版尾部完成标志；不重新选择路线 |
| 暂停菜单 | `pauseMenuShow`、`pauseMenuHide`、`pauseMenuControls`、`optionsSave` | 菜单操作独立于整段 `Game::Controls`，临时使用本机显示名单，返回恢复，不接管菜单或角色所有权 |
| 原生菜单提示清理 | `input::resetMenuPrompts`，RVA `0x239b0`，`thiscall void(Manager+0x4a950, false)` | 联网启动销毁菜单后调用一次，被调方清理 4 字节，不影响随后暂停菜单提示 |
| 原生结束回放 | `Game::End`，RVA `0x2f9770`，`thiscall void(Game*, int id)` | `1` 为死亡结算，`2～14` 为结局；房主原生确认后发送可靠结束事件，客机在安全更新边界调用原入口。本机名单只在调用期间借用，不复制结算 Sprite、角色或原生容器；单人保留原调用 |
| 返回联机菜单 | `menu_context::returnToMain`，仅由待处理的联机返回请求调用 | 等待 `Manager+0x8` 为菜单场景、`+0x10` 为有效存档栏 `1～3` 且菜单对象存在；将 `MenuManager+0x40` 从标题／存档／主菜单页 `1～3` 设为主菜单 `3`，再显示联机界面。结局场景和其他菜单页不写入，不分配或释放原生菜单对象 |

`session_backend` 在原版 `Game::Controls` 返回后检查 `Game+0x265bc` 的重开淡出动作：`5` 为结算确认，`6` 为长按重开。只有运行层接收联机请求时才清除该动作、`+0x265b0` 的淡出透明度和 `+0x265c4` 的按住帧数；其他转场及单人调用原样保留。不会调用或复制带原生容器的 `Manager::RestartGame` 参数。

`input::restartHeld` 通过既有原生动作查询读取本机 `ACTION_RESTART=18`，不使用网络模拟输入；XInput 手柄同时按住双肩键和双摇杆时识别为重开组合。组合包含聊天／表情快捷键时，界面关闭其临时输入状态，以重开组合操作为先。运行层负责按住时长和松开后才可重复提交的规则，不改写角色控制器身份。

回退使用者源房只在完整权威房间、无借用作用域时激活；不激活客机远端存储壳，不跨清理持有 Room Scope。来源和回放参数由运行事务维护，选路与对象分配／释放由原版负责。

联机拦截 `Manager::SaveGame` 的文件写入时仍执行 `Game::CaptureState`。采集包含原生玩家离房清理，调用方随后恢复进房临时效果；两者必须配对。捕获结果只保存在原生 GameState 中，单人存档由会话备份保护，联机退出写入独立会话存档。

## HUD 与本机输入

`input_ready()` 在控制器锁内检查虚拟设备是否已启用、输入查询是否已安装及 ID 1–4 是否全部存在；仅借用原生设备列表，设备对象仍由游戏分配和释放。运行协调器在此条件满足后请求开局；角色的槽位绑定仍由 `input_assign` 与角色生命周期组件负责。

联机显式返回菜单时，`menu_context::returnToMain` 只在原生已重建菜单、已选存档栏且处于标题／选档／主菜单页时选择主菜单。不构造菜单对象，也不接管其他页面或未选存档的启动流程。

Lua API 不提供每个 PlayerHUD 的实际屏幕坐标，也不能独立选择百宝袋的材料来源和绘制位置。[player_hud.h](https://github.com/BMingSY/isaac-lan/blob/main/src/engine/versions/j460/player_hud.h)、[crafting_hud.cpp](https://github.com/BMingSY/isaac-lan/blob/main/src/engine/versions/j460/crafting_hud.cpp) 与 [challenge_hud.cpp](https://github.com/BMingSY/isaac-lan/blob/main/src/engine/versions/j460/challenge_hud.cpp) 提供受限能力。

| 能力 | 布局／入口 | 约束 |
| --- | --- | --- |
| `presentation_player_huds` | 四个主 PlayerHUD，步长 `0x6dc`，调用原生布局与位置函数 | 在本机视图内返回控制器、布局和坐标；过滤隐藏、空槽、无效值和屏幕外坐标，不持有原生对象 |
| 副手绘制 | RVA `0x4471c0`，`ECX=PlayerHUD*`、`XMM3=scale`、栈参数 12 字节 | 仅绘制本机 HUD，保留 receiver、透明度与其他口袋内容；挑战使用完整布局和缩放 1 |
| 完整副手位置 | 调用点 RVA `0x5a73ef`；逻辑宽高 RVA `0x878dc4/0x878edc`，HUD 偏移 `+0x594c/+0x5950` | 使用 `(width-28+offsetX, height-18+offsetY)`，临时栈 Vector 不改写调用方数据 |
| 百宝袋绘制 | RVA `0x449510`，`ECX=PlayerHUD*`、栈 `Vector*`、`XMM2=scale`，被调方清理 4 字节 | 保留寄存器与 SSE；仅借用目标 receiver，本机位置不变，不写入材料或预览缓存 |
| HUD 终点 | 绘制标记 RVA `0x5a4eae`，`Game::GetChallengeParams` RVA `0x306940` | 仅在指定 HUD 查询点提供标量目标视图，不进入玩法或原生容器析构 |
| 挑战完成 | `Game::FinishChallenge`，RVA `0x304f20` | 在可靠结束后的安全边界调用；原版 `Game::Challenge` 为 0，不写入同编号原版挑战解锁 |
| 移动预测输入 | `input::MovementPreviewScope` 借用当前本机 `InputFrame`；桥接通过 Lua `EntityPlayer:GetMovementInput()` 查询各身体 | 仅在客机呈现回调内覆盖本机控制器的移动与分离键查询，包含托管输入；离开作用域恢复，不消费按键边沿、不改权威输入或角色对象 |

百宝袋目标校验读取 PlayerHUD 绑定、HUD 的八个槽位、Player `+0x1618/+0x20a9`，并使用 `GetActiveItem` 确认持有。绘制只借用引用，不替换绑定、不持有角色或精灵。

## 控制台执行与输入

[session_backend.cpp](https://github.com/BMingSY/isaac-lan/blob/main/src/engine/versions/j460/session_backend.cpp) 提供具名 `executeConsole`，仅由运行层在已就绪的权威会话、有效连接槽和角色房间作用域内调用。`Console::RunCommand` RVA `0x28cdc0` 的 J460 ABI 为 `thiscall void(Console*, const NativeString*, bool silent, Player*)`；返回文字由同步 `Console.Print` 捕获，入口 RVA `0x2929e0`，ABI 为 `thiscall void(Console*, const NativeString*, unsigned color, unsigned fade)`。打印仍进入原版记录；捕获不跨命令保留游戏字符串引用。

命令字符串使用游戏自己的 assign／析构接口，遵循 MSVC 24 字节字符串布局，不能使用 MinGW 堆代替。结果立即复制为自有字符串，限制 16 KiB；嵌入层按 UTF-8 边界分段。`Game+console` 的状态字段 `+0` 仅在联机接管输入时清为关闭，离开联机恢复原版更新。原生入口纳入启动签名校验。

[chat_input.cpp](https://github.com/BMingSY/isaac-lan/blob/main/src/engine/versions/j460/chat_input.cpp) 接收本机窗口文字、剪贴板与 IME 消息，不向游戏投递输入文本。UTF-16／UTF-8 转换拒绝非法编码；IME 候选位置跟随编辑光标，失焦取消输入法组合并关闭输入。随机掷骰调用 `BCryptGenRandom` 并使用拒绝采样，不消耗游戏 RNG。编辑缓冲、手柄边沿和动作释放状态在所属组件清理，Lua 只接收普通值。

聊天输入适配的 `chat_ui_pointer(width, height)` 只在所属窗口处于前台且输入打开时返回鼠标位置和左键状态，客户区坐标换算为逻辑画面坐标；其他状态返回无效位置与松开状态。编辑期间左键事件由界面接管，客户区使用系统箭头光标；拖动范围、HUD 避让和位置状态属于 Lua 表现层。

`chat_ui_copy(text)` 仅在联机输入已启用、打开且所属窗口处于前台时写入 Windows 剪贴板，返回成功与否。文本限制为 2048 字节并校验 UTF-8，拒绝空文本、非法编码和控制字符；换行及制表符保留。消息复制与编辑器复制／剪切共用 `CF_UNICODETEXT` 写入路径：成功后内存交由 Windows 持有，失败时释放自有分配；消息复制不更改编辑器、网络状态或日志。

## 原版表情轮盘与气泡

[emotes.cpp](https://github.com/BMingSY/isaac-lan/blob/main/src/engine/versions/j460/emotes.cpp) 复用游戏已构造的轮盘 `Game+0x25108`，不分配、复制或析构其 Sprite、环形几何和候选容器。原版 `EmoteWheel.Update` RVA `0x4d1f20` 为 `thiscall void(Wheel*)`，原版绘制由 `Game.Render` 调用；选择、分页、开合动画保留原有行为。

轮盘的本机参与者查询 RVA `0x50b070` 只在调用原版更新的作用域内提供控制器视图：临时普通缓冲仅在 `+0x378` 指向只读控制器记录，控制器 ID 在 `+0xc`，范围 0～4。作用域结束即失效，既不加入官方在线名单，也不启动 Steam 连接。原版待发送字段 `Manager+0x4ccac` 在调用后读取并恢复，选中 ID 交给独立通信消息；官方模式下所有查询保留原调用。

角色的原版 Emote 组件位于 `Player+0x26d8`，`Show` RVA `0x30750` 为 `thiscall void(Emote*, int id, unsigned duration)`。桥接值 1～59 对应原生 ID 0～58，仅在已就绪、已连接的角色房间作用域内设置；相同表情重复发送重新开始计时。原版玩家更新与绘制管理动画和气泡寿命，所有原生对象仍由游戏拥有。离开界面关闭轮盘标量状态，不修改其原生容器。

原版轮盘的 D6／D20 选项分别为原生 ID 18／19，确认时由轮盘生成一次结果，待发送值分别为 22～27／28～47。通信转发这个结果编号，两端的原版 Emote 更新负责播放 `D6Roll`／`D20Roll`，再切换到对应的结果帧；接收端不重新掷骰。

客机的副本角色跳过权威玩法更新时，仍按原版角色更新节拍调用 `Emote.Update` RVA `0x303e0`（`thiscall void(Emote*)`）。该调用仅推进已存在组件的动画、结果帧和寿命，不分配对象或执行角色玩法；主机沿用原版完整更新，避免重复推进。入口纳入 J460 签名校验。

## 角色目录与个人资格

原版 Lua API 不提供完整角色菜单目录和可选判定。[characters::catalogue](https://github.com/BMingSY/isaac-lan/blob/main/src/engine/characters.h) 复制原生名称、画像与资格数据，Lua 不接收原生指针。

- 原版两页菜单表 RVA `0x724140`，每条 `0x18`、每页 18 条；画像页表 RVA `0x724120`。随机占位行按位置排除。
- Manager 的 PlayerConfig 向量位于 `+0x2a678/+0x2a67c`，记录大小 `0x148`。按原生 Mod 菜单规则排除 `hidden +0x128` 和子配置，里页使用配对 `+0x124`；不另维护固定 ID 或成就表。
- `MenuCharacter::Available` RVA `0x546cd0` 使用菜单记录作 receiver，栈参数为 0，被调方清理 4 字节。查询期间借入本机 642 个成就字节、523 个计数和 frontend scene；禁止在该作用域内执行 Lua、回调、存档或分配，返回前完整恢复。续玩只临时豁免已消耗的伊甸令牌。
- 校验配置范围、数量、ID、字符串长度和配对索引；入口和 Mod 枚举锚 RVA `0x54919e` 受签名校验。字符串立即复制，原生 MSVC 字符串由游戏销毁。

## 道具与效果

| 能力 | 边界与参考 |
| --- | --- |
| 错误道具定义与负编号库存 | 有序种子恢复、注册表和真实数量查询见[错误道具定义](https://github.com/BMingSY/isaac-lan/blob/main/docs/generated-item-definitions.md) |
| 全队恶魔／天使概率 | 原生查询 ABI、名单上下文与客机数值校验见[共享概率](https://github.com/BMingSY/isaac-lan/blob/main/docs/shared-deal-chances.md) |
| 共享道具生成查询 | 通过受限 PlayerManager 查询范围借用完整名单；达摩剑额外底座调用点 VA `0x6e0ade`，受伤与落剑仍查询实际持有者 |
| 小夜灯显示 | Room::Render 的 RVA `0x410dad` 查询按所在房间筛选；角色姿态携带 `Player+0x1ae4` 的有限角度，不改变减速判定 |
| 特殊房间描述符 | 列表编号允许特殊房间使用自己的负房间编号，普通房间使用非负下标；描述符仍通过原生查找取得 |
| 临时效果 | [temporary_effects.lua](https://github.com/BMingSY/isaac-lan/blob/main/src/bridge/compat/items/temporary_effects.lua) 通过原版 Lua API 按层数差值恢复巨大化和护盾；不重放使用动作 |

本页描述实现契约，不代表对应玩法已经验收通过。兼容状态维护在[道具清单](https://github.com/BMingSY/isaac-lan/blob/main/docs/item-effect-compatibility.md)，原生验证方法见[开发与测试](https://github.com/BMingSY/isaac-lan/blob/main/docs/development-and-testing.md)。
