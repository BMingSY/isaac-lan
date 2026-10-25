# J460 原生能力参考

本文记录原生能力、调用边界与所有权，供修改版本后端时查阅。适用 Repentance+ `1.9.7.17.J460`，游戏 SHA-256 为 `7122ac28779925b24e23e2416f231322b1470388bd25e2c08665ad8d53b3ea4f`。

入口与签名以 [entrypoints.h](https://github.com/BMingSY/isaac-lan/blob/main/src/engine/versions/j460/entrypoints.h)、[signatures.inc](https://github.com/BMingSY/isaac-lan/blob/main/src/engine/versions/j460/signatures.inc) 为准，布局由版本后端持有。这里的地址不能用于其他游戏版本；桥接和兼容组件仅使用具名能力，不读取任意内存。

## 实体字段批量读写

[`entity_fields_plan(type, template)`](https://github.com/BMingSY/isaac-lan/blob/main/src/engine/versions/j460/entity_fields.cpp)将 Lua 同步组件提供的嵌套字段名数组编译为 userdata。仅支持泪弹、跟班、掉落物和效果实体的具名属性白名单；`false` 为由 Lua 填充的占位，其他实体类型返回 `false`。模板最多 128 个节点、三层深度，不接受地址或偏移。计划只持有字段描述符，不持有游戏对象；线上的字段顺序仍由 Lua schema 决定。

`entity_fields_capture(entity:GetSprite(), plan)`返回同形数组。`entity_fields_apply(sprite, plan, value)`只允许客机调用；一次遍历校验整份数组的形状、类型、有限数值与整数范围，将普通值保存在固定大小的栈缓冲后，再按模板顺序写入。两者要求活动实体的借用 Sprite 与计划类型相符，返回后不保留 Sprite、实体或数组引用。对象分配、回收和实体身份仍由原有生命周期管理。

`entity_fields_encode(sprite, plan)` 将数值计划直接编码为与 `state_encode` 相同的数组字节，不生成中间 Lua 表；`entity_fields_apply` 也接受这种字节串。此路径仅支持上述四类实体的数值字段，最多 4864 字节，使用固定栈缓冲；解码按计划核对每个数组、数值范围和结束位置，完整校验后才写入该计划的字段。身份、位置、速度及引用仍单独供 Lua 同步组件使用。编码占位只能为 `false`，不接受精灵名称字段或任意内存数据。

`sprite_fields_plan(template)`／`sprite_fields_capture(sprite, plan)`／`sprite_fields_apply(sprite, plan, value)`使用同一模板边界处理精灵字段。支持文件名、动画名、帧、翻转、旋转、缩放、偏移及七个颜色通道；字符串与动画字段只读，动画切换、加载和完整层状态继续使用原有接口。接受借用或 Lua 自有 Sprite，不能将实体计划用于精灵。主动画帧按原版取 floor，叠加帧截断；无动画返回空名称与 `-1`。颜色写入与七参数 Lua `Color` 一致，完整 colorize 状态随后由 `sprite_state` 恢复。

J460 属性布局集中在 [`layout.h`](https://github.com/BMingSY/isaac-lan/blob/main/src/engine/versions/j460/layout.h)，属性与读写策略在 [`entity_fields.h`](https://github.com/BMingSY/isaac-lan/blob/main/src/engine/versions/j460/entity_fields.h)。`Size` 调用原 Lua 属性 setter（cdecl，RVA `0x471fa0`）；`Color` 构造 44 字节临时颜色值并调用原 setter（cdecl，RVA `0x471f70`），保留其虚方法及精灵颜色处理，不保留该临时指针；`CollisionDamage` 使用实体虚表 `+0x40`；泪弹 `Height`／`Scale` 调用原 thiscall setter（RVA `0x275fc0`／`0x276120`），保留游戏副作用。掉落物 `Price` 调用原 thiscall setter（RVA `0x2e2570`），保留商店显示和特殊价格行为；`ShopItemId` 按原 Lua setter 限制在 -2 至 7。其余白名单字段采用相同的属性存储，身份、帧计数和实体标志只读；标志、引用、外观与兼容规则仍通过所属适配器应用。入口受版本签名校验，不能用于其他游戏版本。

`entity_npc_boss(npc:GetSprite(), boolean)` 仅供客机恢复活动 NPC 的 Boss 分类。J460 `EntityNPC::IsBoss`（RVA `0x2b8470`）读取 NPC `+0xc3d` 的独立布尔值；它与 `GetBossID()` 返回的类型标识不同。接口只接受借用 Sprite、原版 NPC 类型范围与布尔值，不接收地址、不保留引用，不运行 NPC AI。同步组件将 `IsBoss()` 与六个 scratch／目标坐标 float32 一起编码为 25 字节；完整校验后应用，原生血条仍按这些实体及血量计算。

## 实体引用与房间数据

角色服装姿态按路径与同名出现顺序映射到本机索引，未知路径使用基础层回退。[映射规则](https://github.com/BMingSY/isaac-lan/blob/main/src/core/occurrence_mapping.h)只接收普通字符串视图；版本后端在单次调用内借用原生名称，不跨调用缓存服装地址。Lua 表现层仅在增删服装后重新取得 Sprite 列表，渲染前仍恢复权威姿态。

`sprite_state(sprite)` 复制完整精灵层状态为字节串；客机的 `sprite_state(sprite, bytes)` 恢复状态，返回需要替换的贴图层数组，没有贴图变化时返回 `true`。返回值不持有原生引用；Lua 只在数组非空时替换贴图并调用 `LoadGraphics`。捕获缓冲预留容量不改变字段或编码字节。

精灵载荷以格式号 `2` 开头，主动画与叠加动画各保存存在标记、浮点帧、播放标记、当前／历史事件位图、图层与挂点层的 ID／帧索引。可移植契约见 [animation_pose.h](https://github.com/BMingSY/isaac-lan/blob/main/src/core/animation_pose.h)：最多 64 个图层、256 个挂点层，帧索引为 `-1` 或小于 65535 的整数；拒绝重复 ID、非法标记与非有限帧。J460 的动画状态 `+0x8/+0xc` 分别引用图层／挂点帧数组，动画数据 `+0x20/+0x24` 为挂点描述数组与数量，每项 16 字节，帧数位于项内 `+0xc`。事件位图位于动画状态 `+0x18/+0x1c`。所有数组由游戏持有，恢复只按本机 ID 与帧数边界写入；空层允许游戏自身使用的初始游标 `0` 和重置游标 `-1`，不将游标用作数组下标。不分配或替换原生数组。动画名未变化时直接恢复这些完整状态，名称变化仍调用游戏动画切换接口。

`sprite_animation_length(sprite)` 只读取当前主动画数据 `+0x30` 的总帧数，限制 `0..65535`，无动画返回 0。接受实体借用或 Lua 自有 Sprite，不分配资源、不推进实体；本地步行动画按该长度和原生 30 Hz 节拍保留小数帧。

`actor_pose` 的五个武器槽来自 `Player+0x13dc`。每个现有槽读取原生虚表第 6 项 `GetMaxCharge`（thiscall，浮点返回）和 `Weapon+0x34` 修正标志；蓄力上限必须有限，允许原生道具组合返回负值，只有正上限参与本地蓄力预测。写入只针对客机已存在且类型匹配的武器，不创建武器、不执行攻击；上限作为只读显示元数据，修正标志与蓄力一并恢复。武器记录格式见[状态同步](https://github.com/BMingSY/isaac-lan/blob/main/docs/synchronization.md#完整视图与实体身份)。

`familiar_body(sprite[, layers])` 限定跟班的原生身体组件，校验 `Familiar+0xee0` 虚表 RVA `0x764914`。读取返回四个大端有符号图层 ID 和五个借用 Sprite；Sprite 位于组件 `+0x4`，间距 `0x114`，图层位于 `+0x568`。写入仅允许客机，完整校验载荷、图层为 `-1` 或对应 Sprite 的有效图层后提交。Lua 道具适配复用普通 Sprite 编解码，先恢复使用道具时缓存的外观，再恢复绘制图层；不借用当前玩家外观，不执行跟班 AI，不分配或转移原生组件所有权。

`familiar_tether(sprite)` 限定跟班实体借用 Sprite，检查 `Familiar+0xee0` 的 `UmbilicalBabyData` 虚表 RVA `0x71d264`。返回最多 256 个 XYZ 点和绳索借用 Sprite，无此组件返回 `false`。组件 `+0x8/+0xc/+0x10/+0x14` 为原生 deque 的映射、容量、首项和数量，Sprite 位于 `+0x18`；映射容量限定为不超过 4096 的二次幂，所有坐标必须有限。

`familiar_tether_render(entitySprite, ropeSprite, bytes)` 仅允许客机绘制，完整校验点载荷后调用 J460 RVA `0x35290` 的原生绳索绘制方法。只在调用期间借用已有跟班及 Lua 自有绳索 Sprite，构造栈上只读 deque 视图并临时替换组件指针，返回即恢复。不构造／析构原生组件、不转移 Sprite 所有权、不执行跟班 AI 或武器更新。入口字节受启动签名校验。

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

角色换房时，后端从原房间的持久、普通、更新及效果列表中收集随行对象并按地址去重。附着效果由[道具转场策略](https://github.com/BMingSY/isaac-lan/blob/main/src/compat/items/room_transitions.h)按类型、变体和归属决定；归属沿 J460 `Entity.Parent`（`+0x3bc`）最多追溯八级，跟班归属使用 `Familiar.Player`（`+0x410`）。迁移先移除原房间各实体列表中的引用，再调用原生添加入口；对象仍由游戏持有和销毁，不复制效果、不重放道具使用。没有对应持有者的效果及房间独立效果不随角色迁移。

`rooms_with_player` 可以切换到客机的远端角色存储壳；该对象不保证网格尺寸、门或房间描述符已经初始化。房间内容只能在主机权威房间或客机当前可见房间查询，可见性须同时比较房间编号和 dimension。远端角色的库存、属性与位置仍可采集，不能将存储壳视为完整房间。

`rooms_teleport(slot, index, dimension)` 在房主更新安全边界请求传送一个已连接参与者，参数范围为槽位 0–3、房间索引 -20–168、维度 0–2。目标必须具有有效原生房间描述符；入口返回布尔值表示请求是否被接受，不表示已经到达。目标按已确定的房间处理，跳过混乱诅咒选路；迁移、受控身体、随行对象、进入效果和到达动画复用现有房间事务，不增加布局或对象所有权。排队时不启动离开动画，取消不会留下传送中的角色状态。上层负责目标选择、到达确认和失效清理，取消使用 `api_cancel_move`，不对旧楼层执行取消。该内部能力不属于第三方稳定 API。

`rooms_revive_player(slot)` 只接受 0–3 的所属玩家栏位，在主机房间系统启用、没有借用作用域、目标为联机幽灵且挑战允许 `round_revive` 时调用既有 `replicaRevivePlayerGhost` 原生入口。幽灵身份使用 [layout.h](https://github.com/BMingSY/isaac-lan/blob/main/src/engine/versions/j460/layout.h) 的 `player::coopGhost`；复活期间只借用该玩家及其身体的房间名单，不接受或返回原生地址，不自行分配、释放角色。复活时机、回血和资源保留由挑战组件决定。

`room_special_template(index, type, variant, seed)` 为主机未访问、未实例化、没有覆盖配置的主维度房间选择原生特殊房间模板。既有 `roomConfigRandomRoom` Hook 记录当前游戏所属的配置对象；接口限定特殊房间库、精确类型和原房间形状。`variant` 非负时指定精确变种，`-1` 时从普通模式模板中随机选择。既有连接的门掩码参与筛选，结果必须包含所有连接门位；选择不消耗房间权重，失败不替换原配置。描述符仅借用游戏配置指针，字符串、生成列表与房间对象仍由游戏持有；布局字段归入 [layout.h](https://github.com/BMingSY/isaac-lan/blob/main/src/engine/versions/j460/layout.h) 的 `roomDescriptor`／`roomConfig`。接口不传递地址、不构造或释放原生配置，不允许替换已加载房间；具体模板与调用时机由挑战地图策略决定。

`room_connections(index)` 在主机房间系统启用且没有借用作用域时读取主维度房间的实际门连接。索引限定为 0–168，返回八个门位的目标 `SafeGridIndex`；无门、地图外入口或缺失目标返回 `-1`，无效源房间返回 `false`。接口只返回普通整数，不加载房间或改变连接；上层可据此检查资源房的可达路径。

原生整队复活、死亡结算、楼层跳转和共享清房奖励在既有 Hook 内询问挑战的具名事件许可。Lua 错误使请求失败；单人及没有对应策略的挑战沿用原版行为。逐角色的道具复活不经过整队复活许可。`map_refresh()` 在房间系统启用期间仅刷新原生小地图显示缓存。个人地图在本机绘制前暂借显示／探索字段，绘制后恢复；既有玩家更新 Hook 以所属栏位暂借地图显示、四种揭图标志和全图可见状态，将原生拾取、卡牌／道具使用与受伤效果产生的探索变化交回所属玩家。玩家更新期间不替换权威访问次数，避免改变普通房间的玩法判定；原生对象与房间保存数据的所有权不变。

`actor_companions` 在空闲客机恢复亲子角色名单。每项为 `id:u32, index:u8, parent:u8, controller:u8, kind:u16, variant:u16, babySkin:i16`，均使用大端；开头为项目数 `u8`，上限 60。父项必须先于子项，控制器必须相同，ID 与索引不得重复。`babySkin` 由 Lua `GetBabySkin()` 采集，限定 `-1..71`，在父角色库存恢复前写入 J460 `Player+0x1aec`；布局由 `GetBabySkin`（RVA `0x2dae00`）签名校验。原生库存缓存通过变体和婴儿身份识别已有伴随角色。角色仍由原生玩家管理器分配、注销，不以本机地址作为线上身份。

房间转移请求可以携带目标房间中的落点，与入口门槽分开保存；明确的入口门槽优先。门槽在原生目的地解析之后、目标房间初始化之前恢复，门布局与角色落点使用同一入口；迷宫重定向保留原生选择的最终方向。落点随单次请求消费，楼层和会话清理同时丢弃请求。后端读取 J460 Player `+0x20a9` 的联机幽灵标记、连接状态、房间键和坐标，将普通值交给[幽灵随队策略](https://github.com/BMingSY/isaac-lan/blob/main/src/compat/characters/ghost.h)；返回的队友坐标通过既有到达路径写入，不改变对象分配、释放或门的目的地。

进入已有房间或重新接入停放的角色时，后端清空该角色 `Player+0x1b1c/+0x1b20` 的原生转场吸附目标。原生完整入房会将这个向量归零；角色更新对非零目标持续执行位置靠拢。写入仅针对已在迁移名单中的角色，在入房效果之前或重连落点设置时执行一次，不逐帧覆盖，也不改变速度、控制器或对象所有权。布局由 RVA `0x3a4bf2` 的原生清理指令签名校验。

进入已有房间的跟班在落点设置后调用 `Familiar.ResetRoomState`（RVA `0x22bb70`）。这复用原生房间入场对跟随历史、速度及临时状态的处理；仅主机对迁移名单中的跟班调用，不触及留在目标房间中的跟班，也不改变原生分配与回收的所有权。入口签名在启动时校验。

## 激光路径呈现

[`laser_path(sprite)`](https://github.com/BMingSY/isaac-lan/blob/main/src/engine/versions/j460/rooms.cpp) 读取活动激光的采样状态、起点／终点、形状／缩放、采样数量与两组路径坐标。要求实体借用 Sprite，回溯所属对象后核对激光类型；不接受自有 Sprite 或其他实体类型，不跨调用保留指针。

`laser_path(sprite, bytes[, dx, dy])` 仅允许客机写入。可选偏移必须同时提供，只平移世界坐标，不修改形状、缩放或采样数量；调用方每次传入原始权威字节，避免重复渲染累积平移。公开 `EndPoint` 属性由桥接层同步设置。路径载荷沿用原格式，协议字段不增加。

J460 的采样状态位于实体 `+0x45d`，允许 `0`、`1` 与原生未初始化值 `255`；起点／终点位于 `+0x468` 至 `+0x474`，形状值为 `+0x478`、缩放为 `+0x4e0`，采样数量为 `+0x47c`，两个游戏自有向量位于 `+0x480`／`+0x48c`。采样数量及每个路径向量各限制 2048 个点，所有浮点数及平移结果必须有限；完整解析、边界和偏移校验完成后才写入。向量通过现有游戏分配接口调整，所有权和析构仍由游戏管理；可移植校验见 [laser_state.h](https://github.com/BMingSY/isaac-lan/blob/main/src/core/laser_state.h)。

## 房间音乐

[`music_state()`](https://github.com/BMingSY/isaac-lan/blob/main/src/engine/versions/j460/audio.cpp) 返回当前房间的 13 字节音乐请求：`mode:u8`、`id:u32`、`parameter:f32`、`queued:u32`，均为大端，浮点按 IEEE 754 位模式编码。模式为无请求、Play 或 Crossfade，排队 ID 为零表示无后续曲目。写入仅限客机；拒绝未知模式、超出有符号整数范围的曲目 ID、非有限参数和长度不匹配，完整校验后替换请求。不传递流、资源或游戏对象指针。

J460 音乐管理器位于 `Manager+0x29fbc`，当前／排队 ID 分别为 `+0x30c/+0x310`，音量为 `+0x398`，布局常量归入版本后端。房间作用域借入该房间的两个虚拟 ID；房主在采集和作用域退出前保存原生直接写入的排队 ID，再恢复外层或实际播放 ID。未知房间以空 ID 选择曲目，不借用其他房间的缓存。实际流仍由游戏管理，不复制、释放或在后台房间播放。

客机只由已提交的权威请求选择房间音乐；原生房间初始化不能覆盖该请求。物理队列在作用域外自然完成，既不修改权威缓存，也不把重复快照视为新请求。进入另一房间时直接选择其排队曲目（若有）；同房的新请求保留原生过渡。

## 转场与暂停

Lua `SetStage` 不能提供原生过场中延迟选层所需的来源房间；普通 `Game::StartRoomTransition` 同时选路并启动转场，不能直接作为客机结果回放接口。

镜子过门调用 `Game::StartRoomTransition` 时，目标已从 `ROOM_MIRROR_IDX` 解析为实际描述符索引和维度；识别依据是 `RoomTransitionAnim.FADE_MIRROR`（18）。[镜像路线策略](https://github.com/BMingSY/isaac-lan/blob/main/src/compat/routes/mirror.h)仅对有效门槽位保留原门作为目标入口；屏幕反射不改变世界空间的门槽位。普通过门继续按相邻描述符选择入口。

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

联机拦截 `Manager::SaveGame` 的文件写入时仍执行 `Game::CaptureState`。采集包含原生玩家离房清理，调用方随后恢复进房临时效果；两者必须配对。捕获结果只保存在原生 GameState 中，单人存档由会话备份保护，联机退出写入独立会话存档。个人进度合并完成后，`session::persistProgress` 按原生顺序调用 `Progress::SaveCloud`（RVA `0x528ee0`）和 `Progress::SaveFile`（RVA `0x5294f0`），两者均为 `thiscall void(Manager+0x14)`，由原生打开并关闭流；不能直接调用需要已打开流的 `Serialize`。该接口只保存当前存档槽的进度，不分配角色或写入局内存档。

客机恢复与原生更新使用 `ProgressReadOnlyScope`，按栈保存并恢复 `Manager+0x14` 进度对象的 `+1` 只读位。J460 收藏记录更新（RVA `0x52a2d0`）与成就尝试（RVA `0x529a20`）均先检查此位；复制权威成就／计数不通过这些方法，因此不被拦截。作用域结束恢复原值，不改变主机进度、会话合并或退出持久化。

## HUD 与本机输入

`input_ready()` 在控制器锁内检查虚拟设备是否已启用、输入查询是否已安装及 ID 1–4 是否全部存在；仅借用原生设备列表，设备对象仍由游戏分配和释放。运行协调器在此条件满足后请求开局；角色的槽位绑定仍由 `input_assign` 与角色生命周期组件负责。

`input::finishUpdate` 在每个联机半帧开始前清除已消费的按键边沿。主机同时比较远端输入所属房间与 `rooms::captureLocations()` 返回的位置；完整更新后刚换房或缺少房间上下文的远端角色只保留过渡允许的持有值，收到目的地输入后恢复移动。该检查只读取位置快照并过滤已接受输入，不写角色、房间或原生容器；客机和主机本地槽位不受此过滤。

联机显式返回菜单时，`menu_context::returnToMain` 只在原生已重建菜单、已选存档栏且处于标题／选档／主菜单页时选择主菜单。不构造菜单对象，也不接管其他页面或未选存档的启动流程。

Lua API 不提供每个 PlayerHUD 的实际屏幕坐标，也不能独立选择百宝袋的材料来源和绘制位置。[player_hud.h](https://github.com/BMingSY/isaac-lan/blob/main/src/engine/versions/j460/player_hud.h)、[crafting_hud.cpp](https://github.com/BMingSY/isaac-lan/blob/main/src/engine/versions/j460/crafting_hud.cpp) 与 [challenge_hud.cpp](https://github.com/BMingSY/isaac-lan/blob/main/src/engine/versions/j460/challenge_hud.cpp) 提供受限能力。

| 能力 | 布局／入口 | 约束 |
| --- | --- | --- |
| `presentation_player_huds` | 四个主 PlayerHUD，步长 `0x6dc`，调用原生布局与位置函数 | 在本机视图内返回控制器、布局和坐标；过滤隐藏、空槽、无效值和屏幕外坐标，不持有原生对象 |
| `presentation_minimap` | 复用 `Minimap::Render` 内的纹理绘制观察，读取 `layout::mapConfig` 的纹理、格距和锚点及绘制 quad | 返回本帧实际绘制的小／大地图视图：网格原点中心、横纵格距、屏幕裁剪矩形、透明度和维度，均为普通值。只接受有限数值、正尺寸和轴对齐绘制；不绘制时返回空表；`_IsaacLanMinimapRender` 在本机原生地图绘制后调用，上层可使用当帧坐标追加提示。每次游戏绘制前清空，不保留原生指针、不改写地图或探索状态 |
| 副手绘制 | RVA `0x4471c0`，`ECX=PlayerHUD*`、`XMM3=scale`、栈参数 12 字节 | 仅绘制本机 HUD，保留 receiver、透明度与其他口袋内容；挑战使用完整布局和缩放 1 |
| 完整副手位置 | 调用点 RVA `0x5a73ef`；逻辑宽高 RVA `0x878dc4/0x878edc`，HUD 偏移 `+0x594c/+0x5950` | 使用 `(width-28+offsetX, height-18+offsetY)`，临时栈 Vector 不改写调用方数据 |
| 百宝袋绘制 | RVA `0x449510`，`ECX=PlayerHUD*`、栈 `Vector*`、`XMM2=scale`，被调方清理 4 字节 | 保留寄存器与 SSE；仅借用目标 receiver，本机位置不变，不写入材料或预览缓存 |
| HUD 终点 | 绘制标记 RVA `0x5a4eae`，`Game::GetChallengeParams` RVA `0x306940` | 仅在指定 HUD 查询点提供标量目标视图，不进入玩法或原生容器析构 |
| 挑战完成 | `Game::FinishChallenge`，RVA `0x304f20` | 在可靠结束后的安全边界调用；原版 `Game::Challenge` 为 0，不写入同编号原版挑战解锁 |
| 呈现预测输入 | `input::PresentationInputScope` 借用当前本机 `InputFrame`；桥接通过 Lua `EntityPlayer:GetMovementInput()`／`GetShootingInput()` 查询各身体 | 仅在客机呈现回调内覆盖本机控制器的移动、射击与分离键查询，包含托管输入；离开作用域恢复，不消费按键边沿、不改权威输入或角色对象 |
| 鼠标瞄准 | `Player.MouseAim` RVA `0x3b9f60`，`thiscall bool(Player*, Vector*, bool)`，被调方清理 8 字节；`Player.ShootingEntity` RVA `0x379320`，`thiscall Entity*(Player*)` | 采集只在同步调用期间将本机角色 `+0x1618` 借用为键盘 ID 0，调用原版坐标转换后恢复；不调用控制器分配、不持有实体。目标以射击实体（为空时为角色）的 `+0x33c/+0x340` 为锚点，原版输出为目标差乘 `0.2`。回放按连接槽位选择目标并使用当前射击实体计算差值，继续由原版处理武器；单人调用原入口。坐标校验和生命周期遵循[输入契约](https://github.com/BMingSY/isaac-lan/blob/main/docs/synchronization.md#输入与时间) |

百宝袋目标校验读取 PlayerHUD 绑定、HUD 的八个槽位、Player `+0x1618/+0x20a9`，并使用 `GetActiveItem` 确认持有。绘制只借用引用，不替换绑定、不持有角色或精灵。

## 控制台执行与输入

[session_backend.cpp](https://github.com/BMingSY/isaac-lan/blob/main/src/engine/versions/j460/session_backend.cpp) 提供具名 `executeConsole`，仅由运行层在已就绪的权威会话、有效连接槽和角色房间作用域内调用。`Console::RunCommand` RVA `0x28cdc0` 的 J460 ABI 为 `thiscall void(Console*, const NativeString*, bool silent, Player*)`；返回文字由同步 `Console.Print` 捕获，入口 RVA `0x2929e0`，ABI 为 `thiscall void(Console*, const NativeString*, unsigned color, unsigned fade)`。打印仍进入原版记录；捕获不跨命令保留游戏字符串引用。

命令字符串使用游戏自己的 assign／析构接口，遵循 MSVC 24 字节字符串布局，不能使用 MinGW 堆代替。结果立即复制为自有字符串，限制 16 KiB；嵌入层按 UTF-8 边界分段。`Game+console` 的状态字段 `+0` 仅在联机接管输入时清为关闭，离开联机恢复原版更新。原生入口纳入启动签名校验。

[chat_input.cpp](https://github.com/BMingSY/isaac-lan/blob/main/src/engine/versions/j460/chat_input.cpp) 接收本机窗口文字、剪贴板与 IME 消息，不向游戏投递输入文本。UTF-16／UTF-8 转换拒绝非法编码；IME 候选位置跟随编辑光标，失焦取消输入法组合并关闭输入。随机掷骰调用 `BCryptGenRandom` 并使用拒绝采样，不消耗游戏 RNG。编辑缓冲、手柄边沿和动作释放状态在所属组件清理，Lua 只接收普通值。

菜单地址、端口和种子通过同一适配器的 `beginField`／`endField` 使用独立编辑缓冲，无需创建原生 Chat 对象；地址上限 253 个 ASCII 字符，端口只收 5 位数字，种子只收 8 位大写字母或数字。编辑期间在原版窗口处理前消费键盘消息，确认／取消通过 `fieldKey` 取一次，文本通过 `fieldText` 借用到下一次编辑操作。菜单暂停键盘动作绑定查询，仅继续查询手柄确认／返回；退出字段后仍消费其已按住键的松开事件，打开前已按住的键则允许原版清理。字段切换、菜单退出与失焦清理编辑和输入法状态，不改变游戏按键配置。

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

`characters::completionPreview` 只读取调用方提供的个人 `Progress`，不写原生存档。J460 原版角色与替身的计数映射集中在 [completion_marks.h](https://github.com/BMingSY/isaac-lan/blob/main/src/engine/versions/j460/completion_marks.h)。每个计数只取低两位的单人记录，屏蔽官方联机记录；十二层按 `gfx/ui/completion_widget.anm2` 排列，含代表 Delirium 的纸张层。预览的低 24 位每两位保存一层，位 24 表示数据可用；解码拒绝额外位和层值 3。未收录的 Mod 角色返回不可用，仍可正常选角，不伪造未通关记录。

## 道具与效果

底座拾取适配位于 [item_effects.cpp](https://github.com/BMingSY/isaac-lan/blob/main/src/engine/versions/j460/item_effects.cpp)。`Player::QueueItem` RVA `0x35e050` 使用 `thiscall`，只在底座确认拾取的返回点 `0x2ebe11` 通知运行层，传递玩家栏位、实体种子、道具 ID、充能、Touched、VarData 与来源池。兼容组件接受时不再向原拾取者入队；其他调用点、饰品、开局和恢复沿用原生方法。通知期间不切换房间；结算在模拟作用域退出后、发布视图前完成。源对象和配置指针不进入 Lua，不由适配器释放。

`items_take_collectible(sprite, id)` 在当前角色作用域调用原生 `Player::DropCollectible`（RVA `0x390530`，`thiscall(Player*, int, Pickup*, bool)`），复制充能、VarData 和来源池，再由实体的原生 Remove 消除临时底座。`items_give_collectible(sprite, id, charge, first, data, pool)` 通过原生掉落保存被替换的主动，再用原生 AddCollectible 发放。入口只接受主机就绪视图中当前名单的玩家 Sprite 包装和有效配置；角色与掉落的分配、注销由游戏管理。底座字段 `+0x524/+0x52c/+0x530/+0x59c` 分别为充能、Touched、来源池和 VarData。入口、调用点和布局常量统一定义在版本后端并受签名校验。

`items_collectible_name(id)` 读取配置名称并解析本机 `Items` 翻译键，返回最多 1024 字节的文本；不暴露配置或字符串指针。上述能力不增加同步字段或网络消息，库存、药丸映射与实体沿用现有契约，扩展指纹包含后端与嵌入 Lua 的变更。

`items_active_charge(sprite, slot)` 返回当前主动的原生充能类型和有效容量，分别调用 `Player::GetActiveChargeType`（RVA `0x391530`）与 `GetActiveMaxCharge`（`0x391320`），均为 `thiscall(Player*, int)`、`RET 4`。`items_add_active_charge(sprite, slot, amount)` 调用 `AddActiveCharge`（`0x3915a0`，`thiscall(Player*, int amount, int slot, bool, bool, bool)`、`RET 20`），三个标志均为 false，返回实际增加量；容量、额外电池槽和充满演出由原生处理。接口沿用发放道具的玩家身份校验，仅接受 0–3 槽和 0–1024 的非负增量，不允许强制溢出或任意内存访问。

原生 `Player::TriggerRoomClear` 返回后通知运行层原调用玩家及清房的维度／房间编号；记录原生已经处理的玩家，实际补发在房间模拟退出后执行。通知只表示清房事件，不在后端解释规则，也不替其他房间调用完整的 `TriggerRoomClear`。客机继续抑制原生清房玩法，接受主机库存状态。

| 能力 | 边界与参考 |
| --- | --- |
| 错误道具定义与负编号库存 | 有序种子恢复、注册表和真实数量查询见[错误道具定义](https://github.com/BMingSY/isaac-lan/blob/main/docs/generated-item-definitions.md) |
| 全队恶魔／天使概率 | 原生查询 ABI、名单上下文与客机数值校验见[共享概率](https://github.com/BMingSY/isaac-lan/blob/main/docs/shared-deal-chances.md) |
| 共享道具生成查询 | 通过受限 PlayerManager 查询范围借用完整名单；达摩剑额外底座调用点 VA `0x6e0ade`，受伤与落剑仍查询实际持有者 |
| 小夜灯显示 | Room::Render 的 RVA `0x410dad` 查询按所在房间筛选；角色姿态携带 `Player+0x1ae4` 的有限角度，不改变减速判定 |
| 特殊房间描述符 | 列表编号允许特殊房间使用自己的负房间编号，普通房间使用非负下标；描述符仍通过原生查找取得 |
| 临时效果 | [temporary_effects.lua](https://github.com/BMingSY/isaac-lan/blob/main/src/bridge/sync/temporary_effects.lua) 通过原版 Lua API 采集道具、饰品及 Null 效果集合，按层数差值恢复并移除已过期效果；不重放使用动作 |
| 本机拾取预览 | `Pickup::UpdateGhosts` RVA `0x2e17c0`，`thiscall(Pickup*)`；只在本机名单内生成 `PICKUP_GHOST`。遍历 Room 的绘制实体数组（`+0x1258`），先冻结拾取物列表再调用；Entity `+0x170` 表示已注册，不能作为删除标志过滤。原生持有 LootList、ANM2 与实体引用，普通实体快照排除该效果；预览查询不推进掉落 RNG |
| 跨房持续激光 | `Player+0x1458` 是受注册的激光 `EntityPtr`。在来源房间内调用实体原生 Remove，再以 `EntityPtr::Assign` RVA `0x2b5b50`（ECX 引用、EDX 新实体）解除引用；不复制指针、不释放原生内存、不重置剩余时间 |
| 道具／饰品复活上下文 | `Player::ReviveFromCollectible` RVA `0x3a23a0` 为 `thiscall void(Player*, unsigned item, bool owned)`；`ReviveFromTrinket` RVA `0x3a3430` 为 `thiscall void(Player*, unsigned trinket, unsigned scratch)`。后者的第二个栈字未参与 J460 逻辑，但原生以 `RET 8` 清栈，必须原样透传，不能沿用旧版单参数声明。PlayerManager 在房间更新之外处理死亡时，按角色控制器借入所属房间与名单，再调用一次原入口；已有作用域及单人模式沿用原上下文，不重放复活效果。入口受版本签名校验，角色及效果实体仍由游戏拥有 |
| 蓝色房间初始化 | `Level::TryInitializeBlueRoom` RVA `0x34d4a0` 为 `thiscall bool(Game*, int source, int destination, int direction)`。仅在步行且同维度转场的角色房间中调用；资格、描述符、房门标记与出口由原生实现维护，成功时采用原生蓝色房间编号 `-16`，不自行创建或释放描述符 |
| 换层随行效果 | `Player+0x1f04` 是赎罪效果的注册 `EntityPtr`。兼容策略仅选择类型 `1000`、变体 `185` 且与该引用相同的实体；换层收拢名单时，从旧房间迁入原生离场房间，随后交由原生换层更新与清理。普通换房不保留该例外，不复制或重新绑定引用，不手动结算奖励 |

房间年龄使用 `Game+0x264f8` 的游戏帧减去 `Room+0x11f0` 的进入帧。后端为每个房间记录上次观察的游戏帧，房间进场屏障暂停期间仅将经过的帧数补入进入帧；初始化／接管房间时重设观察点，重复游戏帧不补偿。原生玩家更新仍负责首帧道具效果和充能，运行层不代替这些效果结算。
| 跨局共享奖励 | `Player::AddCollectible` RVA `0x35f0e0` 的具名调用点 `0x3be32f` 标识原生祝福奖励。只在新建联机局时记录至多两项 ID，原生初始化后向其他控制器各发放一次；不复制初始库存，不重放宿主奖励或修改个人射速 |
| 个人画面状态 | `Game::AddPixelation` RVA `0x353cc0`、`Player::UpdateWavyCap` RVA `0x1cb480`；画面状态按控制器保存。Game 的 `+0x26528/+0x2652c/+0x26530` 是泛光剩余时间／初始时间／强度，`+0x269e0/+0x269e4` 是像素化剩余／初始时间，`+0x67738/+0x6773c/+0x67740` 是扭曲当前／目标／步长；角色更新及嵌套的道具／药丸／卡牌调用借入同一所属状态，结束时回收并恢复全局标量；绘制只借入本机状态，角色动作外的世界泛光保留全局归属 |
| 规则文字 | `HUD::ShowFortuneText` RVA `0x5a3ac0` 借用 x86 MSVC 字符串链表，返回后不保留或释放调用方节点；接收端用本地字符串构造临时只读节点。`StringTable::Indexed` RVA `0x626d30` 根据原生选中的节名／索引翻译，不再次抽取随机提示 |

道具演出 pose 在状态、ID、延迟之后携带两个 `u32` 像素化计时和三个按 IEEE 754 位模式编码的 `f32` 扭曲标量，随后是泛光的两个 `u32` 计时与一个 `f32` 强度。接收端先校验完整记录：计时不得倒置，浮点必须有限且非负；重复快照只恢复状态，不重置计时。规则文字事件使用种类 5，受现有序号、楼层代次、接收者、事件数与长度限制。世界 schema 为 35、网络消息版本为 44；包含扩展 DLL 与嵌入 Lua 的指纹阻止旧实现接入，schema 同时拒绝旧快照。

本页描述实现契约，不代表对应玩法已经验收通过。兼容状态维护在[道具清单](https://github.com/BMingSY/isaac-lan/blob/main/docs/item-effect-compatibility.md)，原生验证方法见[开发与测试](https://github.com/BMingSY/isaac-lan/blob/main/docs/development-and-testing.md)。

## NPC 命中与受击绘制

[combat_feedback.cpp](https://github.com/BMingSY/isaac-lan/blob/main/src/engine/versions/j460/combat_feedback.cpp)仅在 J460 主线程及已建立的房间上下文运行。后端保留原生伤害判定和所有 Mod 回调，不在副本执行伤害。

| 能力 | 契约 |
| --- | --- |
| `combat_identity(sprite)` | 仅主机；接收活动实体的借用 Sprite，返回状态与伤害事件共用的递增身份。地址、InitSeed、索引用于检测对象替换；不拥有实体，不返回地址 |
| `combat_events(slot)` | 仅主机；slot 范围为联机玩家上限，按房间观看者掩码过滤。大端 u32 数量后每项为 `u32 serial,tick,epoch; i32 dimension,room; u32 source,target; u8 accepted,duration`，时长单位为 30 Hz tick，0–6。最多 512 项／90 tick |
| `combat_present()` / `combat_present(sprite)` | 无参数清空本机绘制选择；有参数仅客机，借用活动 NPC Sprite，在当前呈现帧选择原版受击样式。原生对象仍由游戏拥有 |
| `combat_reset()` | 会话重置清理身份、事件、序号和绘制选择；不分配／释放游戏对象 |

`NPC::TakeDamage` RVA `0x2d60a0` 为 thiscall，参数为 float、u64、EntityRef 指针和 int，返回 bool。EntityRef 的实体引用位于 `+0x24`；调用前取得来源／目标身份与房间，返回后记录最终接受结果。HP 仍由原生更新消费伤害队列。`Entity::SetColor` RVA `0x2b2fa0` 只有返回地址为 `0x2af895` 的原生伤害闪烁调用被接管，且仅限 LAN 主机的 NPC；其他颜色调用原样转发。入口／返回位置受启动签名校验。

`accepted` 保留原生接触返回值；演出确认等待原生更新结算。接触时只记录新增伤害队列项的索引与已取得的来源／目标身份，不保留实体或队列项的可解引用指针。队列位于 `Entity + 0x8`，每项 `0x38` 字节；嵌套伤害独立归属。原生伤害 `SetColor` 调用点的 ESI 指向当前队列项，只有实际调用发生才登记其演出时长。队列清空位置 `0x2af8c6`（EDI 为实体）统一发布一次确认：免疫、回调否决、禁止闪烁等没有产生原生演出的命中时长为零。未入队的接触直接确认；未结算观察有数量和过期限制，重置／世界切换清理。序号在发布时分配，避免嵌套或延迟结算被客机高水位跳过。入口与寄存器契约由启动签名校验覆盖；原生伤害队列、HP 和返回值均不修改。

房间 renderArray 内的实体由房间持有。绘制作用域保存 44 字节 Sprite.Color，临时使用原版两种伤害样式，离开作用域按 RAII 恢复，不向原生颜色队列插入条目。实体 InitSeed／索引不符及过期记录失效；客机每次呈现先清空上一帧选择，暂停和视图重置也清空。此能力不推进动画、不创建碰撞特效、不播放声音，不适用于任意原生地址或独立创建的 Sprite。
