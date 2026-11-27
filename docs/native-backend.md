# 忏悔＋原生能力参考

本文记录原生能力、调用边界与所有权，供修改版本后端时查阅。适用 Repentance+ `1.9.7.20.J514`，游戏 SHA-256 为 `c8337b957b7805aee1eac0c49cc7a8ea7ba2e195c7f84a0ab41051406df9426a`。

入口与签名以 [entrypoints.h](https://github.com/BMingSY/isaac-lan/blob/main/src/engine/versions/repentance_plus/entrypoints.h)、[signatures.inc](https://github.com/BMingSY/isaac-lan/blob/main/src/engine/versions/repentance_plus/signatures.inc) 为准，布局由版本后端持有。这里的地址不能用于其他游戏版本；桥接和兼容组件仅使用具名能力，不读取任意内存。

版本元数据以 [profile.json](https://github.com/BMingSY/isaac-lan/blob/main/src/engine/versions/repentance_plus/profile.json) 为唯一来源。PE 节区、版本标记与签名在配置阶段生成；运行时仍在安装游戏 Hook 前校验磁盘版本与内存入口。布局、原函数的调用约定和对象所有权不通过版本描述对上层开放。[room_hooks.h](https://github.com/BMingSY/isaac-lan/blob/main/src/engine/versions/common/room_hooks.h) 仅供后端传递借用的原生房间／玩家与原函数。

后端能力 `native_emotes` 表示可使用原版轮盘和表情接口。应用装配只在能力存在时安装与绑定这些接口；文字聊天可在缺少表情接口时使用普通气泡绘制。核心房间、会话和存档能力仍是启动所必需的，不支持时不能以空实现进入联机。

## 更新入口与诊断实验

正式更新、半帧更新和渲染入口使用[共享更新组件](https://github.com/BMingSY/isaac-lan/blob/main/src/engine/versions/common/bootstrap.cpp)。忏悔＋ [绑定](https://github.com/BMingSY/isaac-lan/blob/main/src/engine/versions/repentance_plus/bootstrap.cpp) 分别提供 `0x40b030`、`0x304230`、`0x3028a0`；房间与渲染方法使用 ECX 接收对象，半帧方法无参数。更新组安装失败只撤销自身 Hook，渲染安装独立重试；仅成功的半帧推进才通知运行层完成。

[双房间探针](https://github.com/BMingSY/isaac-lan/blob/main/src/engine/versions/repentance_plus/room_probe.cpp) 持有诊断实验的后台房间与计数，保留原生分配／构造／析构／删除和名单借用边界。正式房间调度优先，只有未接管且显式创建实验房间时才执行探针。探针的前台名单临时裁剪和后台房间作用域均在返回及 C++ 异常时恢复；它只用于两个普通玩家、无转场的内部夹具，不是生产房间调度能力。

## Steam 大厅成员变化

《忏悔+》和 Mod 共用 Steam 回调。游戏收到大厅成员变化后，先将 Steam 大厅 ID 解析为原版大厅引用。J514 的成员处理入口采用 x86 stdcall，依次接收借用的大厅引用、成员 ID 指针和变化类型。引用中的 `+0x4` 是原版大厅对象。此字段为空时，后端直接返回。有对象时，三个参数原样交回游戏，仍由游戏检查当前大厅。引用的释放由调用方负责。该入口与会话 Hook 一起校验和安装。[J514 会话绑定](https://github.com/BMingSY/isaac-lan/blob/main/src/engine/versions/repentance_plus/session_backend.cpp)

## 实体字段批量读写

[`entity_fields_plan(type, template)`](https://github.com/BMingSY/isaac-lan/blob/main/src/engine/versions/common/entity_fields.cpp)将 Lua 同步组件提供的嵌套字段名数组编译为 userdata。仅支持泪弹、跟班、掉落物和效果实体的具名属性白名单；`false` 为由 Lua 填充的占位，其他实体类型返回 `false`。模板最多 128 个节点、三层深度，不接受地址或偏移。计划只持有字段描述符，不持有游戏对象；线上的字段顺序仍由 Lua schema 决定。

`entity_fields_capture(entity:GetSprite(), plan, memo?)`返回同形数组。可选 `memo` 必须由调用方创建为空表并独占维护；接口按实时读取的原生浮点位模式共享向量和颜色叶数组，保留浮点类型及零的符号，最多缓存 256 个数组，满后仍正常采集。调用方不得修改缓存条目或返回的共享叶数组。根数组及字段容器始终新建，占位始终为 `false`；不提供 `memo` 时数组独立。`entity_fields_apply(sprite, plan, value)`只允许客机调用；一次遍历校验数组形状以及可写字段的类型、有限数值与整数范围，跳过由其他组件处理的占位字段，将普通值保存在固定大小的栈缓冲后，再按模板顺序写入。两者要求活动实体的借用 Sprite 与计划类型相符；版本后端不跨调用保存 Sprite、实体或数组引用。对象分配、回收和实体身份仍由原有生命周期管理。

`entity_fields_encode(sprite, plan)` 将数值计划直接编码为与 `state_encode` 相同的数组字节，不生成中间 Lua 表；`entity_fields_apply` 也接受这种字节串。此路径仅支持上述四类实体的数值字段，最多 4864 字节，使用固定栈缓冲；解码按计划核对每个数组、数值范围和结束位置，完整校验后才写入该计划的字段。身份、位置、速度及引用仍单独供 Lua 同步组件使用。编码占位只能为 `false`，不接受精灵名称字段或任意内存数据。

`sprite_fields_plan(template)`／`sprite_fields_capture(sprite, plan, memo?)`／`sprite_fields_apply(sprite, plan, value)`使用同一模板边界和只读叶数组复用规则处理精灵字段。支持文件名、动画名、帧、翻转、旋转、缩放、偏移及七个颜色通道；字符串与动画字段只读，动画切换、加载和完整层状态继续使用原有接口。接受借用或 Lua 自有 Sprite，不能将实体计划用于精灵。主动画帧按原版取 floor，叠加帧截断；无动画返回空名称与 `-1`。颜色写入与七参数 Lua `Color` 一致，完整 colorize 状态随后由 `sprite_state` 恢复。

字段计划、校验及编解码由两版后端共用。忏悔＋属性布局集中在 [`layout.h`](https://github.com/BMingSY/isaac-lan/blob/main/src/engine/versions/repentance_plus/layout.h)，属性与读写策略在 [`entity_fields.h`](https://github.com/BMingSY/isaac-lan/blob/main/src/engine/versions/common/entity_fields.h)。`Size` 使用下述尺寸恢复能力；`Color` 构造 44 字节临时颜色值并调用原 setter（cdecl，RVA `0x47ba60`），保留其虚方法及精灵颜色处理，不保留该临时指针；`CollisionDamage` 使用实体虚表 `+0x40`；泪弹 `Height`／`Scale` 调用原 thiscall setter（RVA `0x27cca0`／`0x27ce00`），保留游戏副作用。掉落物 `Price` 调用原 thiscall setter（RVA `0x2e8890`），保留商店显示和特殊价格行为；`ShopItemId` 按原 Lua setter 限制在 -2 至 7。`SortingLayer`（`Entity+0x35c`）和 `RenderZOffset`（`+0x354`）按原 Lua 属性读写有符号 32 位整数，与 `DepthOffset`（`+0x358`）共同参与原生排序，不改变实体所属列表。其余白名单字段采用相同的属性存储，身份、帧计数和实体标志只读；标志、引用、外观与兼容规则仍通过所属适配器应用。入口受版本签名校验，不能用于其他游戏版本。

`entity_size(entity:GetSprite(), radius)` 仅供客机恢复活动实体的有限数值尺寸，接受借用 Sprite，不接受 Lua 自有 Sprite、地址或偏移。Lua 普通字段恢复与上述批量字段共用 [`entity_size.h`](https://github.com/BMingSY/isaac-lan/blob/main/src/engine/versions/repentance_plus/entity_size.h)。实体的 XML 配置指针 `+0x330` 非空时，沿用原 Lua setter（cdecl，RVA `0x47ba90`）。配置为空时，读取本机 `SizeMulti`（`+0x374` 的两个 float）及碰撞点向量（`+0x178` 的 begin／end／capacity，每点 8 字节），校验有限乘数、非默认哨兵和向量边界后，把现有形状及实际点数显式传给原生 `Entity::SetSize`（thiscall，RVA `0x2b3240`；参数为 float、两个 float 组成的值类型和 int）。碰撞点由游戏重建，向量内存仍由游戏管理；适配器不借用其他实体配置，不直接复制、分配或释放 MSVC 向量，也不跨调用保存任何原生引用。线上的尺寸字段保持原有布局。

`entity_npc_boss(npc:GetSprite(), boolean)` 仅供客机恢复活动 NPC 的 Boss 分类。忏悔＋ `EntityNPC::IsBoss`读取 NPC `+0xc3d` 的独立布尔值；它与 `GetBossID()` 返回的类型标识不同。接口只接受活动实体的借用 Sprite 与布尔值，并通过游戏的 MSVC RTTI 转换确认 NPC 身份；内容类型编号不用于限制 NPC。非 NPC、失效实体、Lua 自有 Sprite 和主机写入均拒绝，不接收地址、不保留引用，不运行 NPC AI。同步组件将 `IsBoss()` 与六个 scratch／目标坐标 float32 一起编码为 25 字节；完整校验后应用，原生血条仍按这些实体及血量计算。

[`entity_cast::npc`](https://github.com/BMingSY/isaac-lan/blob/main/src/engine/versions/repentance_plus/entity_cast.h) 与命中反馈共用 NPC 身份判定。它调用游戏的 `__RTDynamicCast` 导入跳板（RVA `0x711811`，`cdecl`，五个栈参数），以 `Entity`／`Entity_NPC` 类型描述符（RVA `0x8862d0`／`0x8863a0`）执行非引用转换，返回借用的 NPC 或空值。描述符名称与跳板指令在启动时校验，调用期间不分配游戏对象、不改变所有权。调用者保证实体仍归当前同步或绘制作用域所有；Lua 恢复与本机命中反馈选择另外检查活动状态。

## 诅咒迷雾的随从归属

[迷雾适配](https://github.com/BMingSY/isaac-lan/blob/main/src/engine/versions/repentance_plus/cursed_mist.cpp)仅在联机主机的原生道具禁用／恢复调用期间借用当前角色身份。忏悔＋ `Player::DisableCollectibles`（RVA `0x3e1000`）和 `EnableCollectibles`（`0x3e13a0`）均为无栈参数的 `thiscall`；递归处理子角色、异常退出后恢复外层身份，不跨房间或帧缓存角色指针。

`EntityList::FindByType`（RVA `0x1c3f0`）为 `thiscall`，六个栈参数依次为结果缓冲、类型、变体、子类型、使用缓存、排除友好实体，被调方清理 24 字节并返回结果地址。适配只处理返回点 `0x3e115e`／`0x3e16c6` 的无缓存随从查询，查询种类由[矿坑路线策略](https://github.com/BMingSY/isaac-lan/blob/main/src/compat/routes/mines.h)限定。结果描述符的借用标记、数据指针、容量、数量位于 `+0/+4/+8/+12`；校验数量不超过容量及 65536 后，按 `Familiar.Player`（`+0x410`）稳定筛选当前角色的结果。只改查询结果中的地址顺序与数量，不改房间实体列表、结果容量或借用标记。存储载荷、生成、移除和内存回收仍由原生完成；单人、客机及其他查询原样执行。入口与调用返回点均纳入启动签名校验。

## 实体引用与房间数据

[实体姿态组件](https://github.com/BMingSY/isaac-lan/blob/main/src/engine/versions/common/entity_pose.cpp)通过 [忏悔＋绑定](https://github.com/BMingSY/isaac-lan/blob/main/src/engine/versions/repentance_plus/entity_pose.cpp)提供 `actor_pose` 和 `entity_shadow`，仅接受实体的 8 字节借用 Sprite，写入限客机。角色服装姿态按路径与同名出现顺序映射到本机索引，未知路径使用基础层回退。[映射规则](https://github.com/BMingSY/isaac-lan/blob/main/src/core/occurrence_mapping.h)只接收普通字符串视图；版本后端在单次调用内借用原生名称，不跨调用缓存服装地址。Lua 表现层缓存名称与索引映射，每次应用仍重新取得 Sprite 列表并核对本机名称；增删服装后再次取得列表，渲染前恢复权威姿态。权威服装映射仅随不可变视图复用，视图不再被引用时释放。

`room_layout` 的房间元数据和 `map_pickups` 的地图掉落物由 [room_metadata.h](https://github.com/BMingSY/isaac-lan/blob/main/src/engine/versions/common/room_metadata.h) 校验、复用。布局载荷包含维度、房间／网格／列表索引、占用格子、配置标量、门与种子；校验维度、索引、格子、尺寸、形状与载荷结束位置后才替换缓存。相同字节复用解析值，每次调用仍恢复原生描述符及格子登记。配置缓冲由后端持有，描述符只借用其稳定地址；开始楼层、重启或回退时清除解析缓存，保留原生清理仍可能引用的配置存储。

主机房间占格索引逐次比较对应维度的 169 个原生格子值，变化时重建，仅缓存复制值。地图掉落物每房最多 4096 项，每项仅接受原生类型 5／6 的六个元数据字段；相同已校验字节复用本机地图缓存向量。该向量只在地图缓存调用期间借给描述符，随后恢复原有保存向量，楼层与会话清理时释放。缓存不延后读取主机字段，不改变同步格式或原生对象所有权。

[精灵状态组件](https://github.com/BMingSY/isaac-lan/blob/main/src/engine/versions/common/sprite_state.cpp)通过 [忏悔＋绑定](https://github.com/BMingSY/isaac-lan/blob/main/src/engine/versions/repentance_plus/sprite_state.cpp)实现 `sprite_state(sprite)`，返回精灵状态的字节串。客机调用 `sprite_state(sprite, bytes)` 恢复状态，返回需要替换的贴图层数组，贴图相同时返回 `true`。客机使用本地替代动画时调用 `sprite_state(sprite, bytes, true)`，校验完整载荷后只恢复精灵颜色和播放速度，图层、阴影层与动画游标由本地 ANM2 管理。

`sprite_has_shadow_layer(sprite)` 读取当前精灵的阴影层 ID，按 ID 核对本机图层表，并返回布尔值。借用和 Lua 自有 Sprite 均可查询。

`sprite_graphics_loaded(sprite[, layerID])` 读取游戏加载后的图像状态。无图层参数时，Sprite 须含有图层，所有路径非空的图层均须有图像。指定图层时按 ID 在最多 64 层中查找，返回该层是否有图像。忏悔＋图层的图像指针位于 `+0x98`。接口接受借用或 Lua 自有的 Sprite，只检查指针是否为空，资源的装卸和所有权归游戏。

精灵载荷以格式号 `2` 开头，主动画与叠加动画各保存存在标记、浮点帧、播放标记、当前／历史事件位图、图层与挂点层的 ID／帧索引。可移植契约见 [animation_pose.h](https://github.com/BMingSY/isaac-lan/blob/main/src/core/animation_pose.h)：最多 64 个图层、256 个挂点层，帧索引为 `-1` 或小于 65535 的整数；拒绝重复 ID、非法标记与非有限帧。忏悔＋的动画状态 `+0x8/+0xc` 分别引用图层／挂点帧数组，动画数据 `+0x20/+0x24` 为挂点描述数组与数量，每项 16 字节，帧数位于项内 `+0xc`。事件位图位于动画状态 `+0x18/+0x1c`。所有数组由游戏持有，恢复只按本机 ID 与帧数边界写入；空层允许游戏自身使用的初始游标 `0` 和重置游标 `-1`，不将游标用作数组下标。不分配或替换原生数组。动画名未变化时直接恢复这些完整状态，名称变化仍调用游戏动画切换接口。

恢复前先解码并校验完整载荷、两组本机动画数组和贴图路径，截断、尾部字节、非有限数、非法布尔值及重复图层 ID 均在写入前拒绝。动画缺失时通过原生 `AnimationState::Reset`（RVA `0x9ae0`，thiscall 接收空动画参数，清栈 4 字节）释放该状态持有的帧数组；扩展不自行释放或替换数组。忏悔＋图层步长为 `0xa0`，五个混合参数位于 `+0x78..+0x88`，标志为 `+0x8c`，裁剪偏移为 `+0x90/+0x94`。纹理路径、资源指针、过滤参数和 Sprite 自引用保持游戏所有权；[忏悔绑定](https://github.com/BMingSY/isaac-lan/blob/main/docs/native-backend-repentance.md#精灵状态)使用不同图层步长与字段。

`sprite_animation_length(sprite)` 只读取当前主动画数据 `+0x30` 的总帧数，限制 `0..65535`，无动画返回 0。接受实体借用或 Lua 自有 Sprite，不分配资源、不推进实体；本地步行动画按该长度和原生 30 Hz 节拍保留小数帧。

`actor_pose` 的五个武器槽来自 `Player+0x13e0`。每个现有槽读取原生虚表第 6 项 `GetMaxCharge`（thiscall，浮点返回）和 `Weapon+0x34` 修正标志；蓄力上限必须有限，允许原生道具组合返回负值，只有正上限参与本地蓄力预测。写入只针对客机已存在且类型匹配的武器，不创建武器、不执行攻击；上限作为只读显示元数据，修正标志与蓄力一并恢复。武器记录格式见[状态同步](https://github.com/BMingSY/isaac-lan/blob/main/docs/synchronization.md#完整视图与实体身份)。

角色姿态完整解码并完成服装映射后才提交字段，拒绝截断、尾部字节、非法标记、非有限武器／角度值及越界图层 ID。服装向量位于 `Player+0x1220/+0x1224`，步长 `0x130`，最多 4096 项；十五项图层映射从 `+0x122c` 开始，步长 `0x10`。绘制标志 `+0x139c/+0x139e`、闪烁计时 `+0x1338`、受击计时 `+0x13c0` 和小夜灯角度 `+0x1ae4` 只恢复标量。武器不创建、不释放，缺失或类型不同的槽保留本机对象。

`entity_shadow` 的四个 float32 字段为 `Entity+0x15c/+0x160/+0x164/+0x350`，分别为阴影大小、XY 偏移和实体高度；固定 16 字节，完整验证后应用。该能力适用于其他实体类型，不只玩家。角色和阴影组件不安装 Hook、不推进 AI、不跨调用缓存对象；[原版布局](https://github.com/BMingSY/isaac-lan/blob/main/docs/native-backend-repentance.md#角色姿态与实体阴影)由对应绑定提供。

`familiar_body(sprite[, layers])` 限定跟班的原生身体组件，校验 `Familiar+0xee0` 虚表 RVA `0x788c2c`。读取返回四个大端有符号图层 ID 和五个借用 Sprite；Sprite 位于组件 `+0x4`，间距 `0x114`，图层位于 `+0x568`。写入仅允许客机，完整校验载荷、图层为 `-1` 或对应 Sprite 的有效图层后提交。Lua 道具适配复用普通 Sprite 编解码，先恢复使用道具时缓存的外观，再恢复绘制图层；不借用当前玩家外观，不执行跟班 AI，不分配或转移原生组件所有权。

`pickup_flip_visual(entitySprite[, visible])` 只接受道具底座的借用 Sprite。读取返回生命逆转阴影的显示标记和借用 Sprite；写入只允许客机设置布尔标记。忏悔＋底座 `+0x5d0` 内嵌阴影 Sprite，`+0x6dd` 是原生绘制使用的标记，构造与绘制位置受启动签名校验。兼容组件使用已有 Sprite 编解码先恢复外观，再设置可见性；空底座仍可显示另一面的道具。接口不复制底座保存状态、不执行翻转或拾取、不改变 Sprite 的原生所有权，借用对象不能跨实体回收保存。

`familiar_tether(sprite)` 限定跟班实体借用 Sprite，检查 `Familiar+0xee0` 的 `UmbilicalBabyData` 虚表 RVA `0x782034`。返回最多 256 个 XYZ 点和绳索借用 Sprite，无此组件返回 `false`。组件 `+0x8/+0xc/+0x10/+0x14` 为原生 deque 的映射、容量、首项和数量，Sprite 位于 `+0x18`；非零映射容量限定为不超过 4096 的二次幂，数量不能超过容量，非空映射及各点不能为空，所有坐标必须有限。空且未分配的 deque 返回零点快照。

`familiar_tether_render(entitySprite, ropeSprite, bytes)` 仅允许客机绘制，完整校验点载荷后调用忏悔＋ RVA `0x39470` 的原生绳索绘制方法，ABI 为 thiscall，接收零偏移向量指针和分段值 0，清栈 8 字节。零点或单点不调用绘制。只在调用期间借用已有跟班及借用／Lua 自有绳索 Sprite，构造栈上只读 deque 视图并临时替换组件指针，正常返回及 C++ 异常时恢复。不构造／析构原生组件、不转移 Sprite 所有权、不执行跟班 AI 或武器更新。入口字节受启动签名校验。

这些能力由[实体视图组件](https://github.com/BMingSY/isaac-lan/blob/main/src/engine/versions/common/entity_visuals.cpp)共享校验、编码和借用边界，版本绑定提供布局与入口；[原版布局](https://github.com/BMingSY/isaac-lan/blob/main/docs/native-backend-repentance.md#跟班组件与实体绘制准备)独立核对。`entity_prepare(sprite)` 仅在权威端为 Needle 调用 `0x155e70`，thiscall 接收实体、无栈参数，准备后台房间中不会进入本机渲染的身体图层；其他实体直接成功，不执行 NPC AI。实体身份只接受 8 字节借用包装，不接受独立 Sprite。

Lua 绘制组件按权威实体 ID 维护实际绳索记录，以 `EntityPtr` 解析跟班和拥有者；绘制只访问这些记录。权威绳索消失、引用失效、换房、换层和会话重置移除记录，不跨视图保留借用 Sprite。

| 能力与实现 | 原生边界 | 校验与所有权 |
| --- | --- | --- |
| [持有炸弹](https://github.com/BMingSY/isaac-lan/blob/main/src/engine/versions/common/held_bombs.h) `boss_held_bombs` | Lua API 不暴露 NPC `+0xbf0` 的持有容器；Hornfel 为两槽，Horny Boys 为三槽 | 读取本机实体索引，由兼容组件转换为同步 ID；客机写入校验 Boss、炸弹类型和槽数，使用游戏 resize 与 `EntityPtr.Assign`，容器仍由游戏析构 |
| [矿车引用](https://github.com/BMingSY/isaac-lan/blob/main/src/engine/versions/common/entity_links.h) `entity_minecart` | 乘坐者 Entity `+0x3d4` 的反向引用不由矿车 `Child` 表达 | 仅接受矿车 Sprite／空值，使用原生引用注册与撤销；不调用会生成新矿车的玩法方法 |
| [角色持有引用](https://github.com/BMingSY/isaac-lan/blob/main/src/engine/versions/common/entity_links.h) `actor_held_entity` | Player `+0x1414` 的 `EntityPtr` 供原生抱起渲染使用，独立于 `Parent`／`Child`；赋值位置 RVA `0x3dafa6` 受签名校验 | 读取返回本机实体索引，无对象时为 `-1`；同步组件转换为稳定 ID。写入仅限客机，接受角色和目标的借用 Sprite 或 `false`，拒绝非角色持有者和自引用；使用原生 `EntityPtr.Assign` 注册、替换和清空，目标释放时由游戏撤销引用，不调用拾取／投掷玩法 |
| [轨道布局](https://github.com/BMingSY/isaac-lan/blob/main/src/engine/versions/common/rails.h) `room_rails` | `Room:GetGridEntity` 不包含 RailManager；房间 `+0x7484` 为 448 字节数组 | 客机整体验证长度、值、尺寸与所有者后写入；空轨道也恢复，Sprite 仍由房间持有 |
| 客机实体回收 | `Remove()` 不保证立即释放池槽位；忏悔＋跟班池为 64 槽 | 在房间作用域内通过原生更新完成回收，更新前须启用客机 AI 拦截；不扩容原生池，不手工释放对象 |
| TNT 更新 | `GridEntityTNT::Update`，RVA `0x3264f0`，无栈参数的 `thiscall`；入口受启动签名校验 | 客机跳过原生倒计时、动画选择和爆炸，状态、碰撞与完整姿态由主机恢复；主机及单人保留原调用。对象分配、释放和渲染仍由游戏持有，不读写私有倒计时 |
| 跟班蓄力显示 | `Familiar+0xdcc` 为对象自有的蓄力 Sprite；`Sprite.Update` 的 RVA 为 `0xa3d0`，无栈参数的 `thiscall` | 客机拦截跟班更新时只推进该显示动画，充能值仍使用同步的 `FireCooldown`；不执行跟班 AI、发射或伤害，不复制 Sprite，生命周期由游戏管理 |
| 玩家清房回调 | `Player::TriggerRoomClear`，RVA `0x3b1d60`，`thiscall void(Player*)`；Lua 没有阻止原生清房效果的前置回调 | 联机客机房间启用期间跳过玩法触发，角色状态由权威快照恢复；主机、单人及原生加载保留原调用，不分配或替换角色对象 |
| 口袋槽、合成袋、药丸状态 | 原生载荷分别为 32、12、75 字节 | 在库存恢复后应用，完整校验载荷与玩家归属；写入限客机，主动对象与物品池仍由原版管理 |

[网格状态组件](https://github.com/BMingSY/isaac-lan/blob/main/src/engine/versions/common/grid_state.cpp)通过 [忏悔＋绑定](https://github.com/BMingSY/isaac-lan/blob/main/src/engine/versions/repentance_plus/grid_state.cpp)访问当前 `Game+0x18300` 的房间。`grid_variant` 只改原生变种字段；`grid_remove(index)` 调用立即删除入口 `0x427440`，避免队列中的旧删除操作影响后续替代物。该入口使用 thiscall，栈参数为索引、0、false，由被调方清理 12 字节；网格分配与析构由游戏管理。

`door_slot(-1)` 清空房间 `+0x724` 的八个借用门指针，保留 `+0x24` 网格表中的所有权。`door_slot(slot, index, sprite)` 验证门类型、网格索引及当前房间持有该对象后，恢复槽指针和 `+0x744` 的索引。缺少第三参数时调用 `Room::MakeDoor`（RVA `0x3f6df0`，thiscall 接收槽号、清栈 4 字节）；失败恢复先前目标索引。写入仅限客机，槽号限 0–7、网格索引限 0–447；组件每次查询当前房间，不缓存旧 Game 或房间。

`door_sprite` 仅为门返回附加 Sprite 的 8 字节借用包装，沿用输入的 metatable。忏悔＋的普通／附加 Sprite 为网格 `+0x40/+0x27c`；不复制动画、不创建或析构原生 Sprite。轨道使用房间 `+0x7480` 的所有者检查和 `+0x7484` 的 448 字节网格，完整校验长度、值域和房间尺寸后恢复。[原版绑定](https://github.com/BMingSY/isaac-lan/blob/main/docs/native-backend-repentance.md#网格门与轨道)使用不同的附加 Sprite 和轨道偏移。

[原生引用组件](https://github.com/BMingSY/isaac-lan/blob/main/src/engine/versions/common/references.cpp)通过 [忏悔＋绑定](https://github.com/BMingSY/isaac-lan/blob/main/src/engine/versions/repentance_plus/references.cpp)提供上表的矿车、抱起物和持有炸弹接口。实体链接在对象恢复完成后应用。原生能力只处理引用与布局，Boss 匹配和状态选择由 [compat/bosses/](https://github.com/BMingSY/isaac-lan/tree/main/src/bridge/compat/bosses) 负责。

引用赋值统一调用 `EntityPtr::Assign`，ECX 为引用槽、EDX 为目标实体，无栈参数；替换和清空维护原生观察者集合。重复值不重新登记，读取只返回本机实体索引，不暴露指针。持有炸弹容器为空时，即使快照为空也通过原生 resize（RVA `0x4ff90`，thiscall 接收槽数，清栈 4 字节）初始化渲染所需槽位。所有目标类型在分配或赋值前校验；扩展不接管容器分配器或实体生命周期。原生 resize 只用于空容器的扩张，不用它收缩或销毁含引用的容器。[原版绑定](https://github.com/BMingSY/isaac-lan/blob/main/docs/native-backend-repentance.md#原生实体引用)提供自身字段与入口。

`actor_forgotten_form(playerSprite, desiredType)` 仅供客机在该玩家的房间作用域内恢复骸骨／灵魂形态，接受当前名单中玩家的借用 Sprite，目标类型限定为 16／17。后端检查 `Player+0x1d98` 的隐藏身体及两者互补类型，拒绝合作幽灵和无效配对；相同目标不再次切换。调用 `Player::SwapForgottenForm`（RVA `0x3d4de0`，`thiscall bool(Player*, bool force, bool quiet)`、`RET 8`），两个标志均为 true，以跳过输入冷却和切换演出。原生交换当前／隐藏身体状态并维护骨架引用，两份分配和所有权均留给游戏；随后同步组件分别恢复两种形态的生命。接口不接受地址、不分配或替换角色，入口受启动签名校验。

角色换房时，后端从原房间的持久、普通、更新及效果列表中收集随行对象并按地址去重。附着效果由[道具转场策略](https://github.com/BMingSY/isaac-lan/blob/main/src/compat/items/room_transitions.h)按类型、变体、子类型和归属决定；归属沿忏悔＋ `Entity.Parent`（`+0x3bc`）最多追溯八级，跟班归属使用 `Familiar.Player`（`+0x410`）。仅对泪弹读取 `EntityTear+0x430` 的标志高 64 位，位 127 标识鲁多维科可控泪弹。泪弹缺少父实体时从生成者确认归属。迁移先记录原生持久列表成员身份，再移除源列表引用并调用原生添加入口。普通添加未恢复的持久成员通过既有 `AddPersistent`（RVA `0x1c970`）登记，避免重复添加；该列表位于 Room 实体容器 `+0x30`，布局归入 [layout.h](https://github.com/BMingSY/isaac-lan/blob/main/src/engine/versions/repentance_plus/layout.h)。成员身份在目的房间初始化和跟班入房回调前恢复，适用于换房、跨层聚合和离线角色停放。对象仍由游戏持有和销毁，不复制效果、不重放道具使用；没有对应持有者的效果及房间独立效果不随角色迁移。

迁移的原生离房回调完成后、随行实体迁出前，主机在源房间作用域内通知 `_IsaacLanRoomLeaving()`；回调只借用当前房间，不保留对象。蓝钥匙兼容组件在这里消费源房间各门目标的 `FLAG_BLUE_REDIRECT`，保留其他标记。

原生放置完成后，主机在仅含本次抵达身体的目的房间作用域内通知 `_IsaacLanRoomEntered(door)`。无门到达（`door < 0`）由[落点组件](https://github.com/BMingSY/isaac-lan/blob/main/src/bridge/runtime/room_placement.lua)检查房间边界、碰撞范围和飞行能力，只把无效位置移到最近的安全网格；有效位置和常驻玩家保持原状。地窖等横版房间由路线兼容策略保留原生落点。常规门口位置仍由原生入口处理，客机接受主机最终位置。

客机房间请求先核对楼层、维度和实际源房间。对于同维度的非传送请求，主机读取目标描述符 `roomDescriptor::doors`，将邻接格解析为原生 `SafeGridIndex`；只有一个入口指向源房间时才采用该门的落点。源端出口同样唯一时，后端在源房间及所属身体作用域内执行既有步行转场解析，特殊过道等原生重定向先于迁移与标记消费；客机报告的邻接房间不直接决定最终目的地。多个入口、非邻接房间、地图外目的地、跨维度或传送请求不推断入口。描述符仅在查找期间借用，不缓存原生指针或改变房间所有权。

妈手抓取的原生转场调用点为 RVA `0x13afb2`，以空玩家参数请求起始房间的淡入淡出，调用字节受启动签名校验。后端识别该调用上下文，交由[抓取转场策略](https://github.com/BMingSY/isaac-lan/blob/main/src/compat/enemies/room_transitions.h)验证目的地和参数，只排队源房间内已连接的参与者及其受控身体。安全边界完成迁移后按原生 `RoomTransition::ChangeRoom` 的排除标志恢复可见性并提供到达保护；目的地已加载或就是当前房间时同样完成恢复。恢复请求随会话清理，不改变其他房间的玩家状态。

Boss 演出事件使用独立序号和楼层／维度／房间身份。权威端在房间屏障有效期间持续向尚未完成的观看者发送事件，完成确认按观看者清除；离房、断开和屏障超时结束等待。客机在本机视图匹配后播放并记录序号，房间尚未就绪时保留重试机会。载荷沿用八个大端 `u32` 字段，起始 tick 仅记录事件时间，不作为早于屏障的独立过期条件；无需重建房间或重新连接。

`rooms_with_player` 可以切换到客机的远端角色存储壳。壳对象在构造前清零，借用所属楼层描述符并设置房间类型、编号、维度及含边框的网格尺寸，供库存恢复和属性重算查询；尺寸来自配置 `+0x46/+0x47`，写入 Room `+0xc/+0x10` 时各加二，计算规则受启动签名校验。同步地图同时携带有人占用的地图外特殊房间布局，在恢复角色位置前安装描述符。壳不加载真实网格、门、敌人或背景，也不执行入房逻辑；本机进入时才按权威布局完成原生初始化，并强制建立背景资源，不能沿用空壳的绘制缓存。完整房间内容只能在主机权威房间或客机当前可见房间查询，可见性须同时比较房间编号和 dimension；壳只提供安全的空网格上下文，不能用于预测远端玩法。

`rooms_teleport(slot, index, dimension)` 在房主更新安全边界请求传送一个已连接参与者，参数范围为槽位 0–3、房间索引 -20–168、维度 0–2。目标必须具有有效原生房间描述符；入口返回布尔值表示请求是否被接受，不表示已经到达。目标按已确定的房间处理，跳过混乱诅咒选路；迁移、受控身体、随行对象、进入效果和到达动画复用现有房间事务，不增加布局或对象所有权。排队时不启动离开动画，取消不会留下传送中的角色状态。上层负责目标选择、到达确认和失效清理，取消使用 `api_cancel_move`，不对旧楼层执行取消。该内部能力不属于第三方稳定 API。

两版的合作复活接口都调用版本绑定的 `replicaRevivePlayerGhost`，只借用目标所属房间内该玩家及其身体的名单。幽灵标志取自两版布局中的玩家字段 [忏悔](https://github.com/BMingSY/isaac-lan/blob/main/src/engine/versions/repentance/layout.h) 和 [忏悔＋](https://github.com/BMingSY/isaac-lan/blob/main/src/engine/versions/repentance_plus/layout.h)。身体和背包由游戏管理。接口接受 0–3 的玩家席位，调用时须位于主机房间系统的最外层。

- `rooms_revive_player(slot)` 用于挑战回合，目标为合作幽灵且挑战允许 `round_revive` 时复活，返回是否成功。复活时机、回血和资源保留由挑战组件决定。
- `rooms_coop_revive(slot)` 用于联机控制台，按 `coop_revive` 挑战规则处理在线合作幽灵。返回 `revived`、`alive`、`offline`、`forbidden` 或 `unavailable`，复活后再次读取目标的幽灵标志确认结果。

`actor_lazarus_unpair(index)` 仅供客机恢复长子权里拉撒路的幽灵状态。角色兼容组件根据权威幽灵状态请求挂起第二具身体；后端要求房间系统启用、没有借用作用域，索引指向完整名单内的主人，双向配对身体位于其后、同房、同控制器，分别属于里拉撒路的两种形态，且双方没有隐藏备份。校验失败不写入。后端按忏悔＋原生降级路径把双方的 `player::lazarusBackup`（`+0x1e6c`）设为彼此，用原生 EntityPtr 赋值清除公开配对引用，将备份设为未注册／不活动、玩家索引为 `-1`，再调用 `PlayerManager::RemoveExistingPlayer`（RVA `0x5d1b20`，`thiscall void(manager, player)`）移出名单。该入口只移除名单元素，不能传入不在名单中的身体；启动时校验其签名。备份仍由原生玩家对象持有，不销毁或分配角色；既有幽灵／复活入口遍历隐藏备份，`actor_form` 在权威重新列出身体时恢复公开配对和名单。房间作用域负责位置记录，后续实体同步负责跟班状态；接口不接收地址，不调用客机伤害或玩家更新逻辑。

完整名单借用使用 [`room_roster.h`](https://github.com/BMingSY/isaac-lan/blob/main/src/engine/versions/common/room_roster.h) 的 `TeamRoster`，只复制原生玩家向量的 begin／end／capacity 描述符，不复制角色或持有其分配。借用期间，[`ScopeStack::TeamBinding`](https://github.com/BMingSY/isaac-lan/blob/main/src/runtime/room_scope.h) 将完整名单来源指向当前原生向量；重复查询不重新装入保存的描述符，原生扩容、增删和重排均保留。嵌套房间作用域暂借其保存的最新描述符；正常返回及异常退栈先交回更新后的名单，再恢复父作用域。绑定必须按栈顺序销毁，不跨会话、楼层清理或异步调用持有。既有原生入口与启动签名校验保持适用，角色和向量分配／释放仍由后端与 PlayerManager 管理。

角色构造期间调用共享资源广播时，新身体可能尚未登记到房间位置表。此时后端先从已登记参与者用既有 `Player::CopyResourcesTo` 复制本次共享掩码内的资源，再借入完整名单执行原生广播，避免将构造初始值写回队伍。已登记身体、个人资源位及未启用房间系统时沿用各自原生路径；不保存跨帧资源副本、不补发拾取物，也不改变身体分配或资源所有权。

`room_special_template(index, type, variant, seed)` 为主机未访问、未实例化、没有覆盖配置的主维度房间选择原生特殊房间模板。既有 `roomConfigRandomRoom` Hook 记录当前游戏所属的配置对象；接口限定特殊房间库、精确类型和原房间形状。`variant` 非负时指定精确变种，`-1` 时从普通模式模板中随机选择。既有连接的门掩码参与筛选，结果必须包含所有连接门位；选择不消耗房间权重，失败不替换原配置。描述符仅借用游戏配置指针，字符串、生成列表与房间对象仍由游戏持有；布局字段归入 [layout.h](https://github.com/BMingSY/isaac-lan/blob/main/src/engine/versions/repentance_plus/layout.h) 的 `roomDescriptor`／`roomConfig`。接口不传递地址、不构造或释放原生配置，不允许替换已加载房间；具体模板与调用时机由挑战地图策略决定。

`room_connections(index)` 在主机房间系统启用且没有借用作用域时读取主维度房间的实际门连接。索引限定为 0–168，返回八个门位的目标 `SafeGridIndex`；无门、地图外入口或缺失目标返回 `-1`，无效源房间返回 `false`。接口只返回普通整数，不加载房间或改变连接；上层可据此检查资源房的可达路径。

原生整队复活、死亡结算、楼层跳转和共享清房奖励在既有 Hook 内询问挑战的具名事件许可。Lua 错误使请求失败；单人及没有对应策略的挑战沿用原版行为。逐角色的道具复活不经过整队复活许可。`map_refresh()` 在房间系统启用期间仅刷新原生小地图显示缓存。个人地图在本机绘制前暂借显示／探索字段，绘制后恢复；既有玩家更新 Hook 以所属栏位暂借地图显示、四种揭图标志和全图可见状态，将原生拾取、卡牌／道具使用与受伤效果产生的探索变化交回所属玩家。玩家更新期间不替换权威访问次数，避免改变普通房间的玩法判定；原生对象与房间保存数据的所有权不变。

`actor_companions` 在空闲客机恢复亲子角色名单。每项为 `id:u32, index:u8, parent:u8, controller:u8, kind:u16, variant:u16, babySkin:i16`，均使用大端；开头为项目数 `u8`，上限 60。父项必须先于子项，控制器必须相同，ID 与索引不得重复。`babySkin` 由 Lua `GetBabySkin()` 采集，限定 `-1..71`，在父角色库存恢复前写入忏悔＋ `Player+0x1aec`；布局由 `GetBabySkin`（RVA `0x2e27d0`）签名校验。原生库存缓存通过变体和婴儿身份识别已有伴随角色。角色仍由原生玩家管理器分配、注销，不以本机地址作为线上身份。

房间转移请求可以携带目标房间中的落点，与入口门槽分开保存；明确的入口门槽优先。已解析的传送加入有人占用的房间且没有指定落点时，使用目标房间内已有玩家的坐标；不沿用来源房间坐标。门槽在原生目的地解析之后、目标房间初始化之前恢复，门布局与角色落点使用同一入口；迷宫重定向保留原生选择的最终方向。落点随单次请求消费，楼层和会话清理同时丢弃请求。后端读取忏悔＋ Player `+0x20a9` 的联机幽灵标记、连接状态、房间键和坐标，将普通值交给[幽灵随队策略](https://github.com/BMingSY/isaac-lan/blob/main/src/compat/characters/ghost.h)；返回的队友坐标通过既有到达路径写入，不改变对象分配、释放或门的目的地。

进入已有房间或重新接入停放的角色时，后端清空该角色 `Player+0x1b1c/+0x1b20` 的原生转场吸附目标。原生完整入房会将这个向量归零；角色更新对非零目标持续执行位置靠拢。写入仅针对已在迁移名单中的角色，在入房效果之前或重连落点设置时执行一次，不逐帧覆盖，也不改变速度、控制器或对象所有权。布局由 RVA `0x3afc00` 的原生清理指令签名校验。

进入已有房间的跟班在落点设置后调用 `Familiar.ResetRoomState`（RVA `0x232550`）。这复用原生房间入场对跟随历史、速度及临时状态的处理；仅主机对迁移名单中的跟班调用，不触及留在目标房间中的跟班，也不改变原生分配与回收的所有权。入口签名在启动时校验。

## 房间描述符与地图缓存

[房间数据组件](https://github.com/BMingSY/isaac-lan/blob/main/src/engine/versions/common/room_data.cpp)复用[忏悔＋布局绑定](https://github.com/BMingSY/isaac-lan/blob/main/src/engine/versions/repentance_plus/room_data.cpp)，由房间调度注入启用、空闲和可写房间状态。`room_layout([index, dimension])` 采集当前或指定描述符；`room_layout(bytes)` 仅客机恢复。载荷依次为四个大端 int32（维度、规范索引、网格索引、列表索引）、单字节格子数量及格子编号、十个配置 uint32、宽高字节、门掩码、八个门目标和四个种子。大房间按单元映射输出规范索引；不传递名称、生成对象、容器或地址。

忏悔＋描述符数组为 `Game+0x14`、步长 `0xb8`，三个维度共 507 项；格子映射为 `+0x17adc`，已登记数量为 `+0x182cc`。原生查询 `0x348580` 使用 thiscall 接收索引、维度并清栈 8 字节。普通房间写入已构造的数组项，再登记对应格子；特殊房间限定 `-20..-1` 并使用原生查询，不写缺失房间的共享占位对象。完整载荷、维度、索引、单元覆盖、形状及尺寸先校验再提交。

描述符的配置／覆盖配置为 `+0x10/+0x14`，门掩码／门为 `+0x18/+0x1c`，种子为 `+0x58` 的四字。配置为 `0x5c` 字节，仅恢复 `0/4/8/0xc/0x10/0x2c/0x38/0x3c/0x48/0x4c` 的标量和 `+0x46/+0x47` 的宽高；名称保持空内联字符串，无初始生成列表。组件按房间键持有稳定存储，跨原生楼层清理保持地址有效，同键快照只复制标量；配置不进入原生析构。

`map_pickups(index, dimension)` 捕获保存实体中的拾取物和槽机，`map_pickups(bytes)` 仅客机接收，返回成功及内容是否变化。载荷为维度和索引两字，加至多 4096 组六个 uint32；字段取自记录 `+0/+4/+8/+0x14/+0x28/+0x2c`。忏悔＋保存向量在描述符 `+0x74`、记录步长 `0x78`，原版使用不同步长。接收不修改游戏保存向量；只在小地图缓存期间借用零初始化的记录，其余字段为空。嵌套缓存、同描述符别名及异常按逆序恢复原向量，正在借用的存储保持到作用域结束，换层清理只失效接收缓存。

`room_backdrop(id)` 在客机当前已加载的房间内切换原生背景。忏悔＋使用 `Room+0x1bc8` 的 Backdrop，类型在对象 `+0x150`。编号须在 0 至 62 内，变化时调用 `Backdrop::Init(id, true)` 加载图形，房间继续持有原生绘制资源。

`room_floor_sprite(sample)` 借用当前已加载房间的地面 Sprite（Backdrop `+0x3c`），沿用 `GetSprite()` 的非持有包装。调用方在本次房间作用域内读写动画与帧。存储壳和未加载图形的房间返回 false。

`room_ambush_wave()` 在 Boss Rush 作用域读取当前波和总波数；客机以 `(进行标记, 当前波, 总波数)` 恢复这些标量。进行标记为 0 或 1，当前波在 0 和总波数之间。原生 HUD 与封门判断共用当前房间的标记。客机跳过该房的原生启动和推进，待刷波次队列、随机数和奖励由主机持有。忏悔＋的 Ambush 位于 `Game+0x265d8`，总波数、进行标记及当前波分别在对象 `+0x18/+0x20/+0x24`。

`room_water_current(x, y)` 只为已初始化的客机当前房间写入 `Room+0x7478/+0x747c`，拒绝存储壳、非有限坐标及长度大于单位向量的值。`state_clock(frame)` 恢复客机 `Game+0x26508` 的 uint32 帧钟；销毁后的 Game 不访问。`map_refresh()` 仅在启用时调用 `0x5a2cd0`（thiscall、无参数）刷新 `Game+0x25ef4/+0x26054`，并维护 `+0x22ed4/+0x22edc` 的显示状态，不执行可见性玩法。布局与缓存的[原版绑定](https://github.com/BMingSY/isaac-lan/blob/main/docs/native-backend-repentance.md#房间描述符与地图缓存)独立核对。

## 角色附属状态

[共享角色状态组件](https://github.com/BMingSY/isaac-lan/blob/main/src/engine/versions/common/actor_state.cpp)由房间后端注入本次调用的本地／完整队伍名单，使用[忏悔＋绑定](https://github.com/BMingSY/isaac-lan/blob/main/src/engine/versions/repentance_plus/actor_state.cpp)访问现有角色。`actor_sprites(index, sprite)` 返回三个附属 Sprite、七个蓄力条及服装 Sprite，顺序固定；只接受当前名单对应的 8 字节借用包装，服装向量完整验证容量、步长和 4096 项上限后才创建借用包装。忏悔＋三个附属 Sprite 为 `+0x41c/+0xff8/+0xee4`，蓄力条从 `+0x758` 开始、步长 `0x114`，服装从 `+0x1220` 的向量取得、步长 `0x130`；不复制资源或转移析构责任。

`actor_pockets(sprite[, bytes])` 以固定 32 字节传递四组大端 `id:u32, kind:u32`，来自 `Player+0x17a0`；种类为 0～2，种类 2 仅接受槽 ID 3、4。`actor_crafting_bag(sprite[, bytes])` 传递八个材料字节和大端预览 ID，共 12 字节，分别来自 `+0x1f44/+0x1f4c`。两者要求完整队伍中的玩家，写入仅限客机；先验证整份载荷再提交，不执行拾取或创建主动道具。

百宝袋内容变化时，通过 `Game::GetHUD`（RVA `0x18de0`、thiscall、无参数）取得现有 HUD，仅对绑定该角色的八个 PlayerHUD 槽设置 `+0x6ad` 刷新位，槽步长 `0x6dc`；重复快照保留缓存和动画。`actor_poop(sprite, bytes)` 仅为完整名单中的客机里蓝人恢复 10 字节资源快照，四字节大端 mana 和六个队列字节写入 `+0x1f54/+0x1f58`，不改未来随机队列。各接口不跨调用保留玩家、HUD 或 Sprite；[原版布局](https://github.com/BMingSY/isaac-lan/blob/main/docs/native-backend-repentance.md#角色附属状态)独立提供偏移。

黑暗以扫的本体（类型 866、变体 0）可绑定到所属玩家，出场地洞（同类型、变体 1）由生成它的房间管理。本体随角色迁移时，主机调用 `NPC.NewRoom`（RVA `0x2de770`，`thiscall void(NPC*)`），让原版按两间房的坐标换算追赶位置。新房间中在原生初始化及 NPC 迁移之后调用；加入已有房间时同样调用一次。调用期间暂借 `Game+0x18308/+0x18310` 的来源房间与维度，返回后恢复；实体保持原有身份和引用，不重新生成，也不放到玩家落点。客机从权威快照恢复 NPC，不执行该角色的原生入房玩法。妈妈的影子加入已有房间时复用同一原生入口和来源上下文。入口受启动签名校验，对象分配与回收仍由游戏管理。

犯罪模式启用且房间就绪时，`crime_view()` 采集原版 HUD 的通缉和持枪数据，`crime_view(bytes)` 仅在客机恢复。大端载荷以全队的通缉值（float32，0～6）和星标闪烁计时（int32，−10～56）开头，分别来自 `Game+0x26644` 的 `+0x4/+0x47c`。随后按完整角色名单逐人记录控制器、武器掩码、当前枪（各一字节，`0xff` 表示空手）和四种弹药（各两字节）。接收端核对整份载荷、名单顺序和取值后，再写入各角色的 `+0x2f10/+0x2f14/+0x2f08`。转房时，原生房间后端以 `Player+0x2f18` 的持枪引用识别随行实体，引用本身由游戏管理。[忏悔＋犯罪模式状态](https://github.com/BMingSY/isaac-lan/blob/main/src/engine/versions/repentance_plus/crime_view.cpp)

忏悔＋后端校验犯罪模式死亡演出的原生入口（J514 RVA `0x28980`，thiscall，仅接收游戏持有的模式对象）。联机挑战中，角色转成合作幽灵前，后端临时切回完整在线名单，调用原版存活人数查询。仍有其他活人时跳过这次演出，否则将模式对象交还原版处理。计时、全灭确认和结算由游戏管理。

## 玩家轮廓

[`outlines::withPlayers(connected, render)`](https://github.com/BMingSY/isaac-lan/blob/main/src/engine/player_outlines.h) 仅在本机房间绘制期间借用 LAN 在线槽位掩码，退出或异常时恢复外层掩码；不缓存角色地址，不增加同步字段。至少两名玩家在线且 `Player+0x161c` 属于有效槽位时，使用表现层的固定配色。挑战要求隐藏玩家时传入空掩码。单人、退出会话及不属于在线槽位的实体继续原版路径。

忏悔＋后端在 `Player::Render` 的三个轮廓资格分支接入原生绘制：普通身体 Gate／Draw RVA 为 `0x394e41`／`0x394e9f`，特殊精灵为 `0x394bb1`／`0x394c0b`，幽灵／宝宝为 `0x39502c`／`0x39507c`。各边界的 `EBX` 是当前角色，`[EBP+0xc]` 是主绘制标记，前两个分支还保留 `[EBP-0x6d]` 的原生全息分身限制。跳转适配保存通用寄存器、标志与全部 XMM 寄存器，只替换 Steam 名单资格判断；身体、头部、装扮的四方向偏移绘制和颜色栈清理由原版完成。所有边界及续接入口均纳入启动签名校验。

`PlayerManager` 的颜色转换入口 RVA `0x31190` 使用 thiscall，接收借用的 `ColorMod*` 输出与 `Player*`，返回同一输出指针并弹出 8 字节参数。只在上述三个原生描边调用点改写输出的 44 字节临时 `ColorMod`（RGBA 乘数、四个 colorize 值、RGB 偏移），不写角色或装扮颜色。其他 HUD／效果调用保留原函数；不修改官方联机状态、原生玩家颜色分配、用户配色选项、对象所有权或存档。绘制作用域及配色由[共享组件](https://github.com/BMingSY/isaac-lan/blob/main/src/engine/versions/common/player_outlines.cpp)维护；这些布局与入口仅用于忏悔＋，[原版边界](https://github.com/BMingSY/isaac-lan/blob/main/docs/native-backend-repentance.md#玩家轮廓)使用自己的颜色调用与幽灵绘制。

## 玩家不透明度

百分比校验与绘制名单由[共享组件](https://github.com/BMingSY/isaac-lan/blob/main/src/engine/versions/common/player_opacity.cpp)管理，版本后端提供玩家布局和原生绘制边界。

[`player_opacity::withPlayers(players, connected, render)`](https://github.com/BMingSY/isaac-lan/blob/main/src/engine/player_opacity.h) 在本机房间绘制作用域内，将有效 LAN 槽位的角色及角色精灵映射到本机倍率。只借用角色的基础 Sprite（`+0x48`）、额外 Sprite（`+0x41c`）、辅助 Sprite（`+0xee4`、`+0xff8`）及装扮向量（`+0x1220`，步长 `0x130`，上限 4096）；拒绝倒序、未对齐和越界向量。七个充能条及其他实体精灵不在该精灵名单内；泪弹与激光通过原版弹幕绘制边界查询角色归属。嵌套绘制、正常退出和异常退栈均恢复外层映射；不跨绘制缓存游戏地址，不分配或释放游戏对象。

忏悔＋的 Sprite 图层绘制在 RVA `0xa5e1` 完成原始颜色、图层颜色与颜色栈覆盖的选择，此时 `[EBP-0xf4]` 是所属 Sprite，`[EBP-0x40]` 是栈上的最终 `ColorMod` 副本。受启动签名校验的边界保存通用寄存器、标志、x87、MXCSR 及全部 XMM 寄存器，仅将该副本的 Alpha（`ColorMod+0xc`）乘以所属倍率。原生描边和全息颜色也经过此处，每次角色图层绘制只乘一次；角色实体、精灵、图层及全局颜色栈均保持原值，后续水面／房间着色继续由游戏完成。

泪弹 `Render` 在 RVA `0x28006c` 已由原生转换得到 `EDX=Player*`，并保存原始精灵颜色。仅当该指针属于本次有效 LAN 名单时，将泪弹 `ESI` 的精灵 Alpha（`+0x48+0xa8+0xc`）乘以所属倍率，接回 `0x2800e1` 的原生绘制；原版在 `MC_POST_TEAR_RENDER` 之前恢复颜色。激光 `Render`（`0x58fcd7`）和 `RenderShadowLayer`（`0x594035`）使用原生解析的 `EAX=Player*`，分别设置栈上倍率 `[EBP-0x1a0]` 与 `[EBP-0x124]`，接回 `0x58fcff`／`0x594074`，由游戏处理光束、环和地面层的着色。三个入口及接续地址均有启动签名校验，保存通用寄存器、标志、x87、MXCSR 与全部 XMM 寄存器。不解引用名单外的归属指针；未归属、已断开或绘制作用域外的调用保持原版路径。100% 同样绕过原版 Steam 偏好，避免与 LAN 倍率重复应用；不修改官方联机选项、攻击的模拟状态或对象所有权。

内部 Lua 能力 `player_opacity()` 读取启动配置的其他玩家默认百分比；`player_opacity(p1, p2, p3, p4)` 原子更新四个本机百分比，只接受四个 0～100 的 Lua 整数，失败返回 `false` 且保留全部旧值。玩家选择、默认值与会话清理由表现组件负责；接口不接受原生指针，也不更改联网状态。

## 激光路径呈现

[`laser_path(sprite)`](https://github.com/BMingSY/isaac-lan/blob/main/src/engine/versions/common/laser_state.cpp) 读取活动激光的采样状态、起点／终点、形状／缩放、采样数量与两组路径坐标。要求实体借用 Sprite，回溯所属对象后核对激光类型；不接受自有 Sprite 或其他实体类型，不跨调用保留指针。

`laser_path(sprite, bytes[, dx, dy])` 仅允许客机写入。可选偏移必须同时提供，只平移世界坐标，不修改形状、缩放或采样数量；调用方按已接受视图的路径重新计算平移，公开 `EndPoint` 属性由桥接层同步设置。

纯数据接口 `laser_project(bytes, playerBeam)` 返回传输字节和是否可细化，`laser_expand(bytes)` 将其恢复为 `laser_path` 的输入。采用紧凑表示时两者依次返回路径头的精确终点 X、Y 和起点 X、Y。公开 `EndPoint` 和实体坐标与对应点逐位相等时可引用它，独立坐标随实时视图完整传输。两者只处理受限的路径值。逐点误差、归属以及细节接收契约见[世界状态同步](https://github.com/BMingSY/isaac-lan/blob/main/docs/synchronization.md)。

忏悔＋的采样状态位于实体 `+0x45d`，允许 `0`、`1` 与原生未初始化值 `255`；起点／终点位于 `+0x468` 至 `+0x474`，形状值为 `+0x478`、缩放为 `+0x4e0`，采样数量为 `+0x47c`，两个游戏自有向量位于 `+0x480`／`+0x48c`。采样数量及每个路径向量各限制 2048 个点，所有浮点数及平移结果必须有限；完整解析、边界和偏移校验完成后才写入。两组原生向量的长度、容量和分配头也须有效；扩容先为两组准备存储，全部成功后才提交向量和标量，失败释放临时存储并保留旧状态。分配／释放入口分别为 `0x628dd0/0x71000c`，使用 cdecl、参数为字节数／指针和字节数。容量达到 4096 字节时额外申请 `0x23` 字节，返回 32 字节对齐位置并在前四字节保存原分配指针；释放还原原指针及完整字节数，保持原生向量析构约定。清空路径保留可复用容量，所有权和最终析构仍由游戏管理；[原版绑定](https://github.com/BMingSY/isaac-lan/blob/main/docs/native-backend-repentance.md#激光路径)提供独立布局与分配器，可移植校验见 [laser_state.h](https://github.com/BMingSY/isaac-lan/blob/main/src/core/laser_state.h)。

## 房间音乐

[`music_state()`](https://github.com/BMingSY/isaac-lan/blob/main/src/engine/versions/repentance_plus/audio.cpp) 返回当前房间的 13 字节音乐请求：`mode:u8`、`id:u32`、`parameter:f32`、`queued:u32`，均为大端，浮点按 IEEE 754 位模式编码。模式为无请求、Play 或 Crossfade，排队 ID 为零表示无后续曲目。写入仅限客机；拒绝未知模式、超出有符号整数范围的曲目 ID、非有限参数和长度不匹配，完整校验后替换请求。不传递流、资源或游戏对象指针。

[共享声音组件](https://github.com/BMingSY/isaac-lan/blob/main/src/engine/versions/common/audio.cpp) 接收各版本的原生入口与布局绑定。忏悔＋音乐管理器位于 `Manager+0x2a104`，当前／排队 ID 分别为 `+0x30c/+0x310`；播放音量来自 `Manager+0x2a60c` 设置对象的 `+0x18`，不属于音乐对象本身。布局常量归入版本后端。房间作用域借入该房间的两个虚拟 ID；房主在采集和作用域退出前保存原生直接写入的排队 ID，再恢复外层或实际播放 ID。未知房间以空 ID 选择曲目，不借用其他房间的缓存。实际流仍由游戏管理，不复制、释放或在后台房间播放。

忏悔＋的房间环境音更新入口为 RVA `0x408a00`，签名为 `thiscall void(Room*)`。其内部通过 RVA `0x543b90`（`thiscall void(SFXManager*, int id, float volume, float pitch)`）设置循环声的目标音量和音高。两处入口都在启动时核对签名。后端按实际 Room 对象确定听者，只有本机所在房间可以操作实际声道。水流底声由各端从当前房间产生。其余房间循环声以房主模拟所得的音量与音高为准。

`sound_events(slot, dimension, index[, warningId])` 的首个返回值为最近 30 个逻辑帧的播放事件。可选的 `warningId` 由表现层传入，与该编号匹配的单次音按原生发声时的楼层、维度与房间筛选。卸载房间后这些预警失效。其余事件按发声时的听者筛选。第二个返回值只包含指定听者所在房间的活动循环，每条是大端的 `id:u32, volume:f32, pitch:f32`。原生停止阈值为音量不高于 0.01。新一轮房间更新替换整组状态，房间卸载、楼层切换和会话重置清除旧值。客机复用已有的活动循环列表，首次起播、参数变化原位调整、消失即停声。显式播放保留原有事件语义。

客机只由已提交的权威请求选择房间音乐；原生房间初始化不能覆盖该请求。物理队列在作用域外自然完成，既不修改权威缓存，也不把重复快照视为新请求。进入另一房间时直接选择其排队曲目（若有）；同房的新请求保留原生过渡。

## 转场与暂停

[共享房间调度](https://github.com/BMingSY/isaac-lan/blob/main/src/engine/versions/common/rooms.cpp)从[版本绑定](https://github.com/BMingSY/isaac-lan/blob/main/src/engine/versions/repentance_plus/rooms.cpp)取得入口、布局、标量上下文和画面缓冲区位置。玩家管理器对象与玩家向量分别绑定，调用原生管理方法时不得以向量头代替接收对象。房间构造、析构、分配器和画面引用计数均沿用原生入口；作用域交换完整缓冲区引用对，不复制原生容器。特殊房间的下界随版本绑定校验。Lua 换层闭包及 Dogma 过场的 ABI 由版本适配器负责，公共调度不依赖具体版本的头文件。

忏悔＋的 `Game:StartStageTransition(sameStage, animation[, player])` Lua 闭包经适配入口调用与 `MoveToRandomRoom` 相同的三参数绑定（RVA `0x4c2870`），替换原入口 `0x4c27f0`；两个原生入口均校验签名。省略玩家时使用公共 Lua ABI 将第四个栈参数补为 `nil`；原生绑定仍从原闭包的 userdata upvalue 读取目标方法，沿用 Game／EntityPlayer 类型检查，将 `nil` 玩家转为空指针。底层 `Game::StartStageTransition`（RVA `0x304a60`）为 `thiscall void(Game*, bool, int, EntityPlayer*)`，清理 12 字节栈参数。游戏原生调用、房间来源选择与联机换层屏障继续使用该三参数契约；适配只保留进程内函数入口，不缓存 Lua 状态、闭包或玩家指针，Lua 重载后仍通过同一入口。

内部 C++ 能力 [`actorDepartureAnimation(player)`](https://github.com/BMingSY/isaac-lan/blob/main/src/engine/versions/common/visuals.cpp) 只读换层触发玩家正在播放的额外动作。调用方必须在安全更新边界持有有效玩家，且在房间拆卸前调用；入口校验非空与实体类型。忏悔＋的有效标记位于 `Player+0x139c`，动作名来自实体主 Sprite 的当前动画数据 `+0`，使用原生 MSVC 字符串布局；长度不得超过容量或协议的 64 字节上限。无有效额外动作或动画数据时返回空字符串。返回值拥有独立副本，不保留玩家或动画数据指针，不写游戏状态；动作匹配和回放由桥接表现层负责。

Lua `SetStage` 不能提供原生过场中延迟选层所需的来源房间；普通 `Game::StartRoomTransition` 同时选路并启动转场，不能直接作为客机结果回放接口。

[`presentation_events`](https://github.com/BMingSY/isaac-lan/blob/main/src/engine/versions/repentance_plus/presentation.cpp) 保持每条八个 `u32` 的 Boss 出场载荷，按楼层、类型、维度和房间匹配后调用原生 `StartBossIntro`。加入已加载房间只订阅其未完成事件，沿用序号和 Boss ID；主机加入时在到达作用域内启动本机原生画面，客机通过权威视图接收。原始观看者决定动画时长。客机确认看到了该事件后，已接受视图中移除事件会截断剩余动画。房主持续暂停这个房间的战斗，直到仍在房间的观看者逐个确认本机画面已结束。投票通过也沿用同一结束确认。重复状态按房间与序号去重；等待和已参与名单由 [IntroBarrier](https://github.com/BMingSY/isaac-lan/blob/main/src/core/intro_barrier.h) 管理，完成／超时后不接受新订阅，退出清理名单。载荷字段和协议号不变，不同 DLL 由扩展指纹拒绝连接。

[`finishBossIntro`](https://github.com/BMingSY/isaac-lan/blob/main/src/engine/versions/repentance_plus/boss_intro.h) 只完成忏悔＋的 Boss versus 状态，不暴露 Lua 写内存接口。游戏的 `RoomTransition` 位于 `Game+0x1b83c`，模式／已用帧／持续帧在 `+0/+4/+8`，出场 Sprite 在 `+0x38`，Boss 标记在 `+0x238`。仅当标记有效且模式为 2 或 3 时操作：模式 2 清除 Sprite 主动画的播放位，再调用原生 `RoomTransition::Update`（RVA `0x43a2b0`）完成音乐和演出收尾；模式 3 将已用帧推进到持续帧，再调用原生完成控制恢复。最多调用两次，不直接改写模式、不重新初始化房间，不分配或保留原生对象；其他转场完全不写入。主机在本机房间名单作用域内执行，客机在已提交视图的本机作用域内执行。

[`animation_skip`](https://github.com/BMingSY/isaac-lan/blob/main/src/engine/versions/repentance_plus/animation_skip.cpp) 只提供当前动画、观看名单和按事件完成的具名能力；同意收集由[运行组件](https://github.com/BMingSY/isaac-lan/blob/main/src/bridge/runtime/animation_skip.lua)负责。Boss 跳过沿用 `finishBossIntro` 和逐观看者控制恢复。换层梦境位于 `Manager+0x21770`，仅在场景 5、对象活动且属于联机运行时处理；`Manager+0x21d58` 标记的 Home 个人梦境由本机直接确认。`NightmareScene::Show`（RVA `0x536f40`，`thiscall void(Scene*, bool)`）清空上一次许可；`Update`（RVA `0x535780`，`thiscall void(Scene*)`）在受限输入作用域内读取投票许可作为 `ACTION_MENUCONFIRM`，仍由原生更新完成 Sprite、音效和场景退出。`Render`（RVA `0x535ba0`，`thiscall void(Scene*)`）在原生梦境绘制后接入联机 HUD，供同意进度显示。入口均通过签名校验，接口校验运行、楼层代次和事件身份，不写场景编号，不绕过原版不可跳过的阶段，不分配或保留原生对象。正常单人游戏与结局保留原生行为。

镜子过门调用 `Game::StartRoomTransition` 时，目标已从 `ROOM_MIRROR_IDX` 解析为实际描述符索引和维度；识别依据是 `RoomTransitionAnim.FADE_MIRROR`（18）。[镜像路线策略](https://github.com/BMingSY/isaac-lan/blob/main/src/compat/routes/mirror.h)仅对有效门槽位保留原门作为目标入口；屏幕反射不改变世界空间的门槽位。普通过门继续按相邻描述符选择入口。

[`room_routing`](https://github.com/BMingSY/isaac-lan/blob/main/src/engine/versions/common/room_routing.h) 在 `Level::ChangeRoom` 的 RVA `0x347e9c` 同步提供最终房间索引、维度、入口及原生改送标志（当前原生栈帧 `EBP+0xb`）。改送标志也覆盖同一大房间的不同子格，不能仅通过标准房间索引是否改变推断。此处原生混乱诅咒的临时容器已析构，目的房间尚未初始化。调用方先选择或创建真实目标、迁移进入者并切换房间作用域；返回 `true` 继续原生初始化，返回 `false` 经 RVA `0x3481ca` 的原生公共尾部返回，再由联机运行组件执行已加载房间的进入效果。两版共用回调与安装实现，具体入口、字段和栈帧偏移由版本绑定提供。拦截保存通用寄存器、标志、SSE／x87 状态及控制字；公共尾部恢复原生 SEH 栈并清理两个栈参数。回调只在当前主线程调用中借用，错误在原生栈退出后重新抛出，不跨原生帧展开 C++ 异常。

已确定目的地的回放在 RVA `0x347858` 跳过混乱诅咒分支至 `0x347cee`，不改写诅咒位、不消耗该分支的随机数，覆盖普通诅咒与特殊种子的附加诅咒。抑制状态按调用栈恢复；单人及正常主机选路保持原生执行。活动诅咒按原生基础位、种子位及附加／移除种子效果合并。`Level::SwapRooms`（RVA `0x351140`，`thiscall bool(Level*, int, int)`）仅在原生混乱诅咒调用点检查活动房间保护，其他调用保留原行为；是否允许交换由[路线兼容策略](https://github.com/BMingSY/isaac-lan/blob/main/src/compat/routes/curses.h)决定。入口、返回点和分支均通过启动签名校验。安装先创建全部 Hook，再启用；失败只撤销本组件创建的 Hook 并清除旁路，可重新安装。

| 能力 | 入口与调用约定 | 约束 |
| --- | --- | --- |
| 换层来源上下文 | `Level::SetNextStage`，RVA `0x34e6a0`，`thiscall void(Level*)` | 调用期间临时替换 `Level+0x18304` 来源索引，范围 `[-20, 168]`；返回恢复，事务完成／取消时失效，不切换房间对象 |
| 已决定的房间转场 | `RoomTransition.Start`，RVA `0x437880`，receiver 为 `Game+0x1b83c`，五个栈参数、被调方清理 20 字节 | 回放 index、direction、animation、player、dimension，保留原版尾部完成标志；不重新选择路线 |
| 沙漏检查点路线标记 | `Game+0x26558` 的 64 位 `GameStateFlag`，由既有原生 Store 写入 GameState | 按[路线策略](https://github.com/BMingSY/isaac-lan/blob/main/src/compat/routes/hourglass.h)临时投影标记，仅限同步保存调用；返回时恢复实时标记。不改变存档布局、协议或对象所有权 |
| 暂停菜单 | `pauseMenuShow`、`pauseMenuHide`、`pauseMenuControls`、`optionsSave` | 菜单操作独立于整段 `Game::Controls`，临时使用本机显示名单，返回恢复，不接管菜单或角色所有权 |
| 原生菜单提示清理 | `input::resetMenuPrompts`，RVA `0x24750`，`thiscall void(Manager+0x4ac20, false)` | 联网启动销毁菜单后调用一次，被调方清理 4 字节，不影响随后暂停菜单提示 |
| 原生结束回放 | `Game::End`，RVA `0x300120`，`thiscall void(Game*, int id)` | `1` 为死亡结算，`2～14` 为结局；房主原生确认后发送可靠结束事件，客机在安全更新边界调用原入口。本机名单只在调用期间借用，不复制结算 Sprite、角色或原生容器；单人保留原调用 |
| 返回联机菜单 | `menu_context::returnToMain`，仅由待处理的联机返回请求调用 | 等待 `Manager+0x8` 为菜单场景、`+0x10` 为有效存档栏 `1～3` 且菜单对象存在；将 `MenuManager+0x40` 从标题／存档／主菜单页 `1～3` 设为主菜单 `3`，再显示联机界面。结局场景和其他菜单页不写入，不分配或释放原生菜单对象 |
| 更新提示与退出 | `update_continue()`、`update_exit()` | 仅在待更新提示占用首次开局前主菜单时接受；继续操作清除本进程提示，退出操作向所属窗口发送 `WM_CLOSE`，返回是否成功提交请求。保留正常退出清理，不启动其他进程、不替换已加载 DLL。`input::menuHeld` 只查询本机原生动作值，用于打开／关闭提示后的松键屏障；不写原生菜单或输入对象 |

忏悔＋暂停根页从上到下为继续、选项、物品和退出，打开时光标位于继续。联机在本机房间视图内读取光标，并把继续和退出交由会话协调。

客机在副本 `Game::Update` 调用期间使用 `pause_menu::FocusPauseScope`，暂时关闭原生失焦自动暂停，结束或异常退栈时恢复原值。选项位于 `Manager+0x2a60c` 的配置对象内 `+0x69`；`Game.Update.focusPauseOption`（RVA `0x3024e0`）校验实际读取该字节的指令及条件分支。暂停状态仍由联机权威决定，本机菜单操作、选项保存、主机及单人更新不进入该作用域；不持久修改用户配置，不分配原生对象。

`session_backend` 在原版 `Game::Controls` 返回后检查 `Game+0x265cc` 的重开淡出动作：`5` 为结算确认，`6` 为长按重开。只有运行层接收联机请求时才清除该动作、`+0x265c0` 的淡出透明度和 `+0x265d4` 的按住帧数；其他转场及单人调用原样保留。不会调用或复制带原生容器的 `Manager::RestartGame` 参数。

`input::restartHeld` 通过既有原生动作查询读取本机 `ACTION_RESTART=18`，不使用网络模拟输入；XInput 手柄同时按住双肩键和双摇杆时识别为重开组合。组合包含聊天／表情快捷键时，界面关闭其临时输入状态，以重开组合操作为先。运行层负责按住时长和松开后才可重复提交的规则，不改写角色控制器身份。

回退使用者源房只在完整权威房间、无借用作用域时激活；不激活客机远端存储壳，不跨清理持有 Room Scope。来源和回放参数由运行事务维护，选路与对象分配／释放由原版负责。[共享检查点组件](https://github.com/BMingSY/isaac-lan/blob/main/src/engine/versions/common/rewind.cpp) 通过 [忏悔＋绑定](https://github.com/BMingSY/isaac-lan/blob/main/src/engine/versions/repentance_plus/rewind.cpp) 执行采集、恢复与原生选择；Home 只发布换层事务，客机仅回放主机实际选择，只有动画 12 恢复旧玩家位置。

忏悔＋采集入口为 `0x30cf10`，`stdcall void(int door)`，清栈 4 字节。两个缓冲区从 `Game+0x26e8c` 开始，步长 `0x20788`，选择编号为 `+0x67d9c`；有效位为缓冲区 `+0`，GameState 为 `+4`，门／帧／523 项计数分别为 `+0x1ff54/+0x1ff58/+0x1ff5c`。使用者计数为 `Player+0x1da8/+0x1dac`。客机下层回放完成后，绑定按原生包装函数的条件清除 `Game+0x265d0`，并清除 `+0x67e34`；这些字段不适用于忏悔。原生对象仍由游戏持有，检查点只保存序列化字节和普通位置。载荷完整校验后才恢复，失败不回滚已加载的 GameState；Hook 冲突保留外部 Hook，失败清理自己的旁路后可重试。

联机拦截 `Manager::SaveGame` 的文件写入时仍执行 `Game::CaptureState`。采集包含原生玩家离房清理，调用方随后恢复进房临时效果；两者必须配对。捕获结果只保存在原生 GameState 中，单人存档由会话备份保护，联机退出写入独立会话存档。个人进度合并完成后，`session::persistProgress` 按原生顺序调用 `Progress::SaveCloud`（RVA `0x53e380`）和 `Progress::SaveFile`（RVA `0x53e9a0`），两者均为 `thiscall void(Manager+0x14)`，由原生打开并关闭流；不能直接调用需要已打开流的 `Serialize`。该接口只保存当前存档槽的进度，不分配角色或写入局内存档。

存档编解码共用后端的 [x86 内存流](https://github.com/BMingSY/isaac-lan/blob/main/src/engine/versions/common/save_stream.h)，忏悔＋默认状态为 `Manager+0xfcc`，临时流字段为 `GameState+0x1ff4c`。读取入口 `0x5e4280` 为 `thiscall bool(GameState*, Context*, bool)`，联机传入 `false`；此参数不能套用于忏悔。解码期间[临时清空四个存档文件名槽](https://github.com/BMingSY/isaac-lan/blob/main/src/engine/versions/common/save_file_names.h)，阻止原生读档错误清理使用单人文件路径；返回时恢复原生字符串与流指针。输出限制为 8 MiB，短读、越界和写入只读流均使操作失败；部分 GameState 内容不回滚。

`RecordCharacterCompletion`（RVA `0x5716f0`）为 `stdcall void(event, character, difficulty)`，返回时清理 12 字节。观察器保留原生调用与资格判定，只向运行层提供本次通关的计数 ID、普通／困难位及成就 ID；重复通关仍产生通知。事件限定为 0–14、角色为 0–40、难度为 0–3，只读恢复期间不产生奖励。原生描述符表位于 RVA `0x85e420`，每名角色 18 项，每项两个 32 位 ID；HUD 映射及位计数分类见 [completion_marks.h](https://github.com/BMingSY/isaac-lan/blob/main/src/engine/versions/repentance_plus/completion_marks.h)。回调不暴露原生地址，不改变描述符或对象所有权。

`commitProgress` 只用于退出时提交已合并的个人进度：恢复个人计数和原有成就，使用 `Progress::TryUnlock`（RVA `0x53eeb0`，`thiscall bool(id)`）提交本局解锁，再以 `Progress::IncreaseEventCounter`（RVA `0x53efd0`，`thiscall void(id, delta)`）的零增量检查累计条件。提交期间借用可写位并在返回时恢复；运行层须先结束共享进度合并，避免原生同步保存再次合并。该能力不写入局内 Continue 或分配游戏对象。

客机恢复与原生更新使用 `ProgressReadOnlyScope`，按栈保存并恢复 `Manager+0x14` 进度对象的 `+1` 只读位。忏悔＋收藏记录更新与成就尝试（RVA `0x53eeb0`）均先检查此位；复制权威成就／计数不通过这些方法，因此不被拦截。作用域结束恢复原值，不改变主机进度、会话合并或退出持久化。

## 入场演出与本机视图

[共享演出组件](https://github.com/BMingSY/isaac-lan/blob/main/src/engine/versions/common/presentation.cpp) 通过 [忏悔＋绑定](https://github.com/BMingSY/isaac-lan/blob/main/src/engine/versions/repentance_plus/presentation.cpp) 处理原生入场和本机视图。`StartBossIntro` RVA `0x437c10` 以 ECX 接收 `Game+0x1b83c` 的转场对象，两个栈参数是 Boss ID，清栈 8 字节。`Update` 为 `0x43a2b0`，无栈参数；模式 2／3 对应入场与退出，`+0x238` 是完整 Boss ID，不能按 bool 读取。

本机回放将转场 `+0x14/+0x18` 设置为当前房间／维度，`Game+0x1bb74` 指向当前名单首位角色；该版本由游戏在角色移除时清空此引用。事件保留既有 32 字节网络字节序、房间／楼层身份、序号去重和 90 帧有效期，队列上限 32 条。背景房间不占用主机画面；等待确认只暂停所属房间，断线或超时释放等待。原生推进在房间模拟前执行一次，模拟期间的临时模式在正常或异常退出时恢复，不覆盖更新后的转场或已释放的 Game。

客机完成确认后，主机在事件原房间借用对应角色名单，调用 `PlayerManager::SetControlsEnabled` RVA `0x5d69f0`：thiscall receiver 为 `Game+0x1baa8`，栈参数 true，清栈 4 字节。结束状态及 `Game+0x26628 >= 2` 的原生保护阻止恢复。房间 Boss 缓存为 `+0x1bb0/+0x1bb4`，敌人数为 `+0x12c8/+0x12cc`；特殊房间检查沿用原生描述符。

小夜灯只筛选 `Room::Render` 在 `0x4194bd` 发起的道具查询，不改其他调用者或道具。玩家 HUD 桥接使用 `Game+0x1da04` 和下方的坐标能力，小地图桥接发布前端实际绘制视图。两个演出 Hook 成组创建，失败只撤销本组件 Hook；其他演出子组件分别管理安装边界，启动装配在任一失败时中止。[忏悔参考](https://github.com/BMingSY/isaac-lan/blob/main/docs/native-backend-repentance.md#入场演出与本机视图) 说明其不同的角色引用、标记和对象布局。

## 道具演出事件与对象

[共享道具演出组件](https://github.com/BMingSY/isaac-lan/blob/main/src/engine/versions/common/item_presentation.cpp) 通过[版本绑定](https://github.com/BMingSY/isaac-lan/blob/main/src/engine/versions/common/item_presentation_bindings.h) 访问大书、HUD 文字与屏幕效果。忏悔＋ [绑定](https://github.com/BMingSY/isaac-lan/blob/main/src/engine/versions/repentance_plus/item_presentation.cpp) 使用以下布局；[忏悔的布局和不同文字 ABI](https://github.com/BMingSY/isaac-lan/blob/main/docs/native-backend-repentance.md#道具演出与屏幕状态) 独立声明。

忏悔＋全局大书位于 `Game+0x1c034`，对象大小 `0x12b8`；48 个配置从 `+0x11c` 开始、步长 `0x58`，普通／Mega Mush Sprite 为 `+8/+0x11a4`，延迟为 `+0x119c`。扩展按版本分配对齐存储，依次调用两个 ANM2 构造和全部配置构造，再调用原生 Load；加载失败中止会话并立即析构该对象，不显示半初始化动画。字符串、动画资源及玩家引用由原生构造／析构管理，扩展只释放自身存储。Mega Mush 将全局动画交换到所属玩家对象，双方的 `ANM2+0x30/+0x50` 自引用分别重绑到自身，避免共享所有权。

主机每个控制器持有独立大书，在所属房间推进并按本机栏位绘制。Home 睡眠使用全局对象并等待全队集合；终局动画继续执行原生标记。客机普通大书只应用姿态，不在原生 Update 中再次产生治疗、音效或路线副作用。重置和配置重载析构全部独立对象；屏幕作用域在正常及 C++ 异常返回时恢复借用标量，Game 失效时不写回旧对象。重置清除动作归属、事件、翻译来源和去重状态，可仅保留像素化计时。

`HUD::ShowItemText` 使用玩家和 ItemConfig 两个栈参数；接收端通过原生配置查询解析 ID，不能把 EntityConfig 当作 ItemConfig。忏悔＋ `ShowItemTextCustomUTF8` 为 `thiscall void(HUD*, Player*, const char*, const char*)`，清栈 12 字节，使用原生固定的粘附文字样式。文字和规则提示只在所属玩家 HUD 播放；翻译按本机 StringTable 解析捕获的节名／键，不保留字符串指针或重新抽取随机提示。规则提示借用 x86 MSVC 循环链表，节点 32 字节、字符串位于 `+8`，接收端的临时节点在原生调用返回后释放。

事件批次先完整解析再执行，最多 24 条，最长 90 个接受帧；每条前缀依次为 `u32 serial/tick/epoch`、`u8 slot/role/kind`，使用网络字节序。种类 1 为大书 ID、延迟和是否绑定玩家，种类 2 为道具 ID／类型，种类 3 为两段文字，种类 4 在文字后携带两组翻译来源，种类 5 为规则提示及索引来源。种类 6 使用种类 4 的字段并追加一个样式字节：位 0 为粘附动画，位 1 为诅咒显示；仅忏悔接收，忏悔＋拒绝该种类。每段文字最多 1024 字节，每个来源字段最多 128 字节，批次最多 65535 字节；接收者、身体角色、代次、年龄和序号共同限制回放。种类 1–5 的编码保持一致。

`item_presentation_pose` 为 `u8 state/id`、`u32 delay` 及 32 字节屏幕标量；状态最多 2，ID 必须小于本版配置数，延迟最多 900。屏幕标量依次为像素化两个计时、扭曲当前／目标／步长、泛光两个计时与强度，整数为 u32，浮点按 IEEE 754 位模式编码；计时有序，浮点有限且非负。`home_scene_pose` 为 `u8 state/id`、`u32 sleepSerial`、`u8 dreamHome`、`i32 dreamIndex`；完整校验后写入显示状态，不调用 Show／Update，也不重新启动已经结束的主机梦境。Sprite 接口只接受八字节借用 userdata 并沿用其元表，不返回原生地址给 Lua。

本组件的 14 个 Hook 成组创建和启用，冲突只清理本组件所建 Hook 与跳板，保留外部 Hook；重复安装被拒绝。Home 更新门控及拾取预览各自管理安装，启动装配在任一组件失败时中止。世界 schema 与网络消息版本以 [world_schema.lua](https://github.com/BMingSY/isaac-lan/blob/main/src/bridge/sync/world_schema.lua)、[protocol.h](https://github.com/BMingSY/isaac-lan/blob/main/src/net/protocol.h) 为准；现有 Lua 字段仍承载不透明事件字符串，扩展 DLL 指纹阻止不同实现混联，不能据此进行跨版本转换。

## Home 场景推进

`BossOverlay::Update` RVA `0x21fd0` 是 thiscall 无栈参数方法。[更新绑定](https://github.com/BMingSY/isaac-lan/blob/main/src/engine/versions/repentance_plus/scene_update.cpp) 交给[共享门控](https://github.com/BMingSY/isaac-lan/blob/main/src/engine/versions/common/scene_update.cpp)：普通客机在结束状态前不执行原生路线标记，主机和结束状态调用原函数；姿态仍由道具演出同步提供。组件不写入或持有原生对象，Hook 失败只清理自身资源，保留外部 Hook，重复安装被拒绝。[忏悔](https://github.com/BMingSY/isaac-lan/blob/main/docs/native-backend-repentance.md#home-场景推进) 使用游戏更新函数内的指令边界，不能沿用该方法 ABI。

## 胜利圈提示

[胜利圈组件](https://github.com/BMingSY/isaac-lan/blob/main/src/engine/versions/common/victory_prompt.cpp) 通过 [忏悔＋绑定](https://github.com/BMingSY/isaac-lan/blob/main/src/engine/versions/repentance_plus/victory_prompt.cpp) 访问 `Game+0x26c18`。Controls、Render、Hide 分别为 RVA `0x440970/0x440610/0x440b20`，均为 thiscall，无栈参数。动画 `+0x34`、播放位 `+0x44`、选择 `+0x128`、结果 `+0x12c` 和投票位 `+0x130` 只在该对象上使用；动画、字符串和字体仍由游戏持有。

普通联机只显示主机提示，主机使用已锁存菜单按键沿，并关闭原生 Steam 投票等待；客机不消费提示输入。Idle 动画阶段才可确认，原生结果 1 接受、2 拒绝，然后调用 Hide。联机挑战在各端等到 Idle 后拒绝；其他提示和单人会话保留原函数。`victory_lap_prompt` 返回打开、选择、结果、投票和 Idle 五个普通值，每次从当前 Game 读取，空 Game 返回关闭状态。两个 Hook 成组安装，失败撤销本组件 Hook 和借用指针，保留外部 Hook 并允许重试。[原版绑定](https://github.com/BMingSY/isaac-lan/blob/main/docs/native-backend-repentance.md#胜利圈提示) 使用自己的字段，不访问 Steam 投票状态。

## 楼层生成

联机开局在新建的 0x5c 字节 `Seeds` 上设置房主的普通地图种子。启用犯罪模式时，[忏悔＋会话绑定](https://github.com/BMingSY/isaac-lan/blob/main/src/engine/versions/repentance_plus/session_backend.cpp)在交给 `Manager::StartNewGame` 之前调用原生 `Seeds::AddSeedEffect(80)`。该入口 RVA 为 `0x2f67d0`，使用 `thiscall` 并校验入口签名。游戏负责分配效果集合节点并消费按值传入的开局对象。此能力只用于本次开局，忏悔后端不提供该入口。

[floor_generation.h](https://github.com/BMingSY/isaac-lan/blob/main/src/engine/floor_generation.h) 接受运行层提供的同步布尔查询，仅选择原版超大层生成分支。忏悔＋的房间数量判断位于 RVA `0x34895f`，布局判断位于 RVA `0x34940f`；两处均为对 `Game+0x26594` 原生挑战编号的七字节比较指令。入口与后续条件跳转受启动签名校验。

后端在原比较后的条件跳转处接入；查询为 true 时，仅将其算术标志改为相等比较的结果，再执行原版分支。通用寄存器、栈、SSE、x87 与 MXCSR 均恢复，不写 `Game.Challenge`、诅咒、种子、布局或原生容器。房间数量抽样、随机数推进、布局与房间对象分配仍由原版负责。查询适用于首层、换层与重新生成；无活动挑战时保留原生行为。玩法匹配由上层挑战目录负责。两个 Hook 成组安装，失败只回滚本次创建的 Hook；相同图像和回调可以复用已安装组件，供外层会话装配失败后重试。[原版绑定](https://github.com/BMingSY/isaac-lan/blob/main/docs/native-backend-repentance.md#楼层生成)使用独立的比较位置。

原版挑战的清房奖励、结局宝箱查询及 DELETE THIS 的房间外观由 [generated_challenge.h](https://github.com/BMingSY/isaac-lan/blob/main/src/engine/generated_challenge.h) 能力提供；调用范围、ABI、签名和借用字段的生命周期见[原版挑战的清房奖励与房间外观](https://github.com/BMingSY/isaac-lan/blob/main/docs/generated-challenge.md)。

## HUD 与本机输入

[共享前端](https://github.com/BMingSY/isaac-lan/blob/main/src/engine/versions/common/frontend.cpp)负责窗口消息、Lua 生命周期和菜单装配，[版本绑定](https://github.com/BMingSY/isaac-lan/blob/main/src/engine/versions/repentance_plus/frontend.cpp)声明游戏入口及布局。忏悔＋的 Online 选择项仍打开模式选择，再由用户选择官方联机或局域网；忏悔使用[独立菜单入口](https://github.com/BMingSY/isaac-lan/blob/main/docs/native-backend-repentance.md#主菜单入口)。标题、选档和其他原生页面不接收局域网输入。

[小地图组件](https://github.com/BMingSY/isaac-lan/blob/main/src/engine/versions/common/minimap.cpp)在房间绘制前借用本机视角刷新缓存，绘制时只观察纹理四边形并发布普通投影值。忏悔＋的地图为 `Game+0x25edc`，两配置为 `+0x18/+0x178`；纹理虚表 `+0x10` 接收源、目标和透明参数并清栈 12 字节，宽高为纹理 `+0x10/+0x14`，alpha 为目标第 12 个 float。纹理 ABI 由[忏悔＋适配](https://github.com/BMingSY/isaac-lan/blob/main/src/engine/versions/repentance_plus/minimap.cpp)持有，不用于[忏悔绘制](https://github.com/BMingSY/isaac-lan/blob/main/docs/native-backend-repentance.md#小地图绘制)。地图切换只失效缓存归属，不复制或释放原生纹理。

队伍 HUD 的玩家绑定、StatHUD 和历史栏筛选由[共享 HUD 组件](https://github.com/BMingSY/isaac-lan/blob/main/src/engine/versions/common/frontend_hud.cpp)执行，[忏悔＋绑定](https://github.com/BMingSY/isaac-lan/blob/main/src/engine/versions/repentance_plus/frontend_hud.cpp)声明入口与布局。八个 PlayerHUD 仅在绑定变化时调用原生 Reset、写入借用玩家和刷新标记，并重新计算历史栏；更新和绘制借用房间视角，单人沿用原生行为。组件不复制或持有心容器、道具和 Sprite 资源。忏悔＋的步长为 `0x6dc`、刷新标记 `+0x6ac`、历史栏 `HUD+0x5c54`；[忏悔参考](https://github.com/BMingSY/isaac-lan/blob/main/docs/native-backend-repentance.md#玩家-hud-绑定)声明其不同布局。

物理采集、虚拟 XInput、权威输入分发、按键沿消费和退出恢复位于[共享输入组件](https://github.com/BMingSY/isaac-lan/blob/main/src/engine/versions/common/input.cpp)。[忏悔＋输入绑定](https://github.com/BMingSY/isaac-lan/blob/main/src/engine/versions/repentance_plus/input.cpp) 提供原生查询／鼠标入口、布局、动作映射与菜单提示重置。查询通过输入管理器虚表 `+0x74` 安装，失败撤销本组件创建的 Hook；鼠标旁路保留原生 thiscall 参数。采集按 `Manager+0x4ae8c` 的渲染帧编号去重；重复采集消费按键沿但保留按住值，不更改网络字段与编码顺序。

`input_ready()` 根据同一份受锁保护的设备 ID 快照，检查虚拟设备是否已启用、输入查询是否已安装及 ID 1–4 是否全部存在。[公共设备组件](https://github.com/BMingSY/isaac-lan/blob/main/src/engine/versions/common/input_devices.cpp) 串行化原生扫描 `0x68da90` 与轮询 `0x68de40` 的完整事务，允许同线程回调重入。虚拟手柄接入和断开时，组件在设备锁内各执行一次原生扫描，即使关闭 `ControllerHotplug` 也能更新设备列表。断开清理继续受同一把锁保护。忏悔＋输入管理器 RVA `0x880068` 的列表首尾为 `+8/+12`，元素八字节，设备 ID 位于 `+12`。输入采集与表情轮盘共用逻辑槽到物理设备的映射。逻辑键盘槽 0 查询原生设备 ID −2，联机期间把四个手柄（含原生编号 0）分配到 1–4；组件不修改元素中的原生所有权字段。退出只恢复仍存在且编号未被独立更改的设备，设备对象仍由游戏分配和释放。运行协调器在就绪后请求开局；角色槽位绑定仍由 `input_assign` 与角色生命周期组件负责。

`players_spawn` 和 `input_assign` 通过[共享玩家组件](https://github.com/BMingSY/isaac-lan/blob/main/src/engine/versions/common/player_input.cpp) 使用 [忏悔＋绑定](https://github.com/BMingSY/isaac-lan/blob/main/src/engine/versions/repentance_plus/player_input.cpp)。忏悔＋ `PlayerManager` 与其玩家向量起点均为 `Game+0x1baa8`；创建 `0x5d1830` 接收管理器和角色类型，分配 `0x3aee10` 接收角色、控制器和伴生传播标志，初始化 `0x3c52c0` 接收角色，均为 thiscall。初始化和开局奖励后重新读取向量，为新增身体设置控制器与当前／上一位置，然后由 `0x18de0` 取得 HUD 并调用 `0x5bfde0` 分配显示槽位。已有角色保持原样；对象和向量由游戏持有，部分原生创建失败不提供回滚。

`input::finishUpdate` 在每个联机半帧开始前清除已消费的按键边沿。主机同时比较远端输入所属房间与 `rooms::captureLocations()` 返回的位置；完整更新后刚换房或缺少房间上下文的远端角色只保留过渡允许的持有值，收到目的地输入后恢复移动。该检查只读取位置快照并过滤已接受输入，不写角色、房间或原生容器；客机和主机本地槽位不受此过滤。

联机显式返回菜单时，`menu_context::returnToMain` 只在原生已重建菜单、已选存档栏且处于标题／选档／主菜单页时选择主菜单。不构造菜单对象，也不接管其他页面或未选存档的启动流程。

Lua API 不提供每个 PlayerHUD 的实际屏幕坐标，也不能独立选择百宝袋的材料来源和绘制位置。玩家坐标的对象借用、可见性和有限正视口检查由[共享组件](https://github.com/BMingSY/isaac-lan/blob/main/src/engine/versions/common/player_hud.h) 负责，各版本提供布局和位置。[player_hud.h](https://github.com/BMingSY/isaac-lan/blob/main/src/engine/versions/repentance_plus/player_hud.h)、[crafting_hud.cpp](https://github.com/BMingSY/isaac-lan/blob/main/src/engine/versions/repentance_plus/crafting_hud.cpp) 与 [challenge_hud.cpp](https://github.com/BMingSY/isaac-lan/blob/main/src/engine/versions/repentance_plus/challenge_hud.cpp) 提供受限能力。

| 能力 | 布局／入口 | 约束 |
| --- | --- | --- |
| `presentation_player_huds` | 四个主 PlayerHUD，步长 `0x6dc`，调用原生布局与位置函数 | 在本机视图内返回控制器、布局和坐标；过滤隐藏、空槽、无效值和屏幕外坐标，不持有原生对象 |
| `presentation_minimap` | 复用 `Minimap::Render` 内的纹理绘制观察，读取 `layout::mapConfig` 的纹理、格距和锚点及绘制 quad | 返回本帧实际绘制的小／大地图视图：网格原点中心、横纵格距、屏幕裁剪矩形、透明度和维度，均为普通值。只接受有限数值、正尺寸和轴对齐绘制；不绘制时返回空表；`_IsaacLanMinimapRender` 在本机原生地图绘制后调用，上层可使用当帧坐标追加提示。每次游戏绘制前清空，不保留原生指针、不改写地图或探索状态 |
| `api_with_hud_players` | 在本机房间的完整临时玩家名单中运行内部采集函数，结束或报错时恢复外层名单 | SDK 仅复制已登记且在线身体的身份与血量，不保留房间或玩家引用 |
| 心格、主动栏、饰品 | `PlayerHUD::RenderHearts` RVA `0x44c9e0`、`RenderActiveItem` RVA `0x44de60`，均为 thiscall、清栈 24 字节。饰品 `RenderTrinket` RVA `0x44fa90` 清栈 20 字节 | 联机本机视图按绑定身体筛选隐藏或自绘。向 Lua 传递当帧锚点、缩放，以及主动或饰品的槽号。紧凑双子的副行锚点下移 34。隐藏时用屏幕外坐标调用原生方法，保留返回的尺寸向量供后续栏位排版。主动栏传入原生透明度，饰品使用 1 |
| 副手绘制 | RVA `0x44fc60`，`ECX=PlayerHUD*`、`XMM3=scale`、栈参数 12 字节 | 仅绘制本机 HUD，保留 receiver、透明度与其他口袋内容；挑战使用完整布局和缩放 1。口袋栏自绘使用布局调整后的锚点、缩放和原生透明度 |
| 完整副手位置 | 调用点 RVA `0x5beb41`；逻辑宽高 RVA `0x89ee7c/0x89f0d0`，HUD 偏移 `+0x594c/+0x5950` | 使用 `(width-28+offsetX, height-18+offsetY)`，临时栈 Vector 不改写调用方数据 |
| 百宝袋绘制 | RVA `0x451fd0`，`ECX=PlayerHUD*`、栈 `Vector*`、`XMM2=scale`，被调方清理 4 字节 | 保留寄存器与 SSE；仅借用目标 receiver，本机位置不变，不写入材料或预览缓存 |
| HUD 终点 | 绘制标记 RVA `0x5bc53c`，参数读取边界 `0x5bcb60` | 原生查询照常执行，仅在 HUD 内替换 EAX 中的借用结果；标量视图不进入玩法或原生容器析构 |
| 挑战完成 | `Game::FinishChallenge`，RVA `0x30be70` | 在可靠结束后的安全边界调用；原版 `Game::Challenge` 为 0，不写入同编号原版挑战解锁 |
| 呈现预测输入 | `input::PresentationInputScope` 借用当前本机 `InputFrame`；桥接通过 Lua `EntityPlayer:GetMovementInput()`／`GetShootingInput()` 查询各身体 | 仅在客机呈现回调内覆盖本机控制器的移动、射击与分离键查询，包含托管输入；离开作用域恢复，不消费按键边沿、不改权威输入或角色对象 |
| 鼠标瞄准 | `Player.MouseAim` RVA `0x3c2b30`，`thiscall bool(Player*, Vector*, bool)`，被调方清理 8 字节；`Player.ShootingEntity` RVA `0x381780`，`thiscall Entity*(Player*)` | 采集只在同步调用期间将本机角色 `+0x161c` 借用为原生键盘 ID −2，调用原版坐标转换后恢复；不调用控制器分配、不持有实体。目标以射击实体（为空时为角色）的 `+0x33c/+0x340` 为锚点，原版输出为目标差乘 `0.2`。回放按连接槽位选择目标并使用当前射击实体计算差值，继续由原版处理武器；单人调用原入口。坐标校验和生命周期遵循[输入契约](https://github.com/BMingSY/isaac-lan/blob/main/docs/synchronization.md#输入与时间) |

挑战目标的[共享组件](https://github.com/BMingSY/isaac-lan/blob/main/src/engine/versions/common/challenge_hud.cpp) 仅在 HUD 内的两个指令边界介入。忏悔＋的目标存在位是 CL，无解锁标志是栈帧 `EBP-0xa2`；参数读取前的 EAX 指向 164 字节借用视图，只有终点 `+0x40` 与路线类型 `+0x80` 非零，其余字段清零。它不替换 `Game::GetChallengeParams` 本身，不写入 Game、每日挑战或原生参数对象。离开联机挑战后原样传递原生寄存器和参数；边界保存整数寄存器、标志位、SSE、x87 与控制字。两处 Hook 成组安装，失败只撤销本组件创建的 Hook，重复安装被拒绝。[忏悔绑定](https://github.com/BMingSY/isaac-lan/blob/main/docs/native-backend-repentance.md#挑战目标-hud) 使用自己的内联读取点和旧版路线标志。

百宝袋的[共享组件](https://github.com/BMingSY/isaac-lan/blob/main/src/engine/versions/common/crafting_hud.cpp) 使用[忏悔＋绑定](https://github.com/BMingSY/isaac-lan/blob/main/src/engine/versions/repentance_plus/crafting_hud.cpp) 校验 PlayerHUD 绑定、HUD 的八个槽位、Player `+0x161c/+0x20a9`，并通过 `GetActiveItem` 查询四个主动槽。目标为固定的下一联机栏位；无已提交视图、目标为幽灵或已失去百宝袋时隐藏材料，仍保留有效本机副手的卡牌／药丸与图标。普通会话原样调用原生入口。绘制只借用引用，不替换绑定、不持有角色或精灵。副手与材料两个 Hook 成组安装，失败清理本组件的 Hook 和函数／视口指针，保留外部 Hook；重复安装被拒绝。

## 控制台执行与输入

[共享会话后端](https://github.com/BMingSY/isaac-lan/blob/main/src/engine/versions/common/session_backend.cpp) 使用 [忏悔＋绑定](https://github.com/BMingSY/isaac-lan/blob/main/src/engine/versions/repentance_plus/session_backend.cpp) 提供具名 `executeConsole`，仅由运行层在已就绪的权威会话、有效连接槽和角色房间作用域内调用。`Console::RunCommand` RVA `0x293870` 的忏悔＋ ABI 为 `thiscall void(Console*, const NativeString*, bool silent, Player*)`；返回文字由同步 `Console.Print` 捕获，入口 RVA `0x2994e0`，ABI 为 `thiscall void(Console*, const NativeString*, unsigned color, unsigned fade)`。打印仍进入原版记录；捕获不跨命令保留游戏字符串引用。

命令字符串使用游戏自己的 assign／析构接口，遵循 MSVC 24 字节字符串布局，不能使用 MinGW 堆代替。结果立即复制为自有字符串，限制 16 KiB；嵌入层按 UTF-8 边界分段。`Game+console` 的状态字段 `+0` 仅在联机接管输入时清为关闭，离开联机恢复原版更新。原生入口纳入启动签名校验。

[chat_input.cpp](https://github.com/BMingSY/isaac-lan/blob/main/src/presentation/chat_input.cpp) 接收本机窗口文字、剪贴板与 IME 消息，不向游戏投递输入文本。UTF-16／UTF-8 转换拒绝非法编码；IME 候选位置跟随编辑光标，失焦取消输入法组合并关闭输入。随机掷骰调用 `BCryptGenRandom` 并使用拒绝采样，不消耗游戏 RNG。编辑缓冲、手柄边沿和动作释放状态在所属组件清理，Lua 只接收普通值。

菜单地址、端口和种子通过同一适配器的 `beginField`／`endField` 使用独立编辑缓冲，无需创建原生 Chat 对象；地址上限 253 个 ASCII 字符，端口只收 5 位数字，种子只收 8 位大写字母或数字。编辑期间在原版窗口处理前消费键盘消息，确认／取消通过 `fieldKey` 取一次，文本通过 `fieldText` 借用到下一次编辑操作。菜单暂停键盘动作绑定查询，仅继续查询手柄确认／返回；退出字段后仍消费其已按住键的松开事件，打开前已按住的键则允许原版清理。字段切换、菜单退出与失焦清理编辑和输入法状态，不改变游戏按键配置。

聊天输入适配的 `chat_ui_pointer(width, height)` 只在所属窗口处于前台且输入打开时返回鼠标位置和左键状态，客户区坐标换算为逻辑画面坐标；其他状态返回无效位置与松开状态。编辑期间左键事件由界面接管，客户区使用系统箭头光标；拖动范围、HUD 避让和位置状态属于 Lua 表现层。

`chat_ui_copy(text)` 仅在联机输入已启用、打开且所属窗口处于前台时写入 Windows 剪贴板，返回成功与否。文本限制为 2048 字节并校验 UTF-8，拒绝空文本、非法编码和控制字符；换行及制表符保留。消息复制与编辑器复制／剪切共用 `CF_UNICODETEXT` 写入路径：成功后内存交由 Windows 持有，失败时释放自有分配；消息复制不更改编辑器、网络状态或日志。

## 原版表情轮盘与气泡

[emotes.cpp](https://github.com/BMingSY/isaac-lan/blob/main/src/engine/versions/repentance_plus/emotes.cpp) 复用游戏已构造的轮盘 `Game+0x25118`，不分配、复制或析构其 Sprite、环形几何和候选容器。原版 `EmoteWheel.Update` RVA `0x4dbd90` 为 `thiscall void(Wheel*)`，原版绘制由 `Game.Render` 调用；选择、分页、开合动画保留原有行为。

轮盘的本机参与者查询 RVA `0x51b4a0` 只在调用原版更新的作用域内提供控制器视图：临时普通缓冲仅在 `+0x378` 指向只读控制器记录，设备 ID 在 `+0xc`。键盘使用 −2，手柄使用分配后的 1～4，原版据此选择方向键或摇杆。作用域结束即失效，既不加入官方在线名单，也不启动 Steam 连接。原版待发送字段 `Manager+0x4d04c` 在调用后读取并恢复，选中 ID 交给独立通信消息；官方模式下所有查询保留原调用。

角色的原版 Emote 组件位于 `Player+0x26f0`，`Show` RVA `0x348c0` 为 `thiscall void(Emote*, int id, unsigned duration)`。桥接值 1～59 对应原生 ID 0～58，仅在已就绪、已连接的角色房间作用域内设置；相同表情重复发送重新开始计时。原版玩家更新与绘制管理动画和气泡寿命，所有原生对象仍由游戏拥有。离开界面关闭轮盘标量状态，不修改其原生容器。

原版轮盘的 D6／D20 选项分别为原生 ID 18／19，确认时由轮盘生成一次结果，待发送值分别为 22～27／28～47。通信转发这个结果编号，两端的原版 Emote 更新负责播放 `D6Roll`／`D20Roll`，再切换到对应的结果帧；接收端不重新掷骰。

客机的副本角色跳过权威玩法更新时，仍按原版角色更新节拍调用 `Emote.Update` RVA `0x34550`（`thiscall void(Emote*)`）。该调用仅推进已存在组件的动画、结果帧和寿命，不分配对象或执行角色玩法；主机沿用原版完整更新，避免重复推进。入口纳入忏悔＋签名校验。

## 角色目录与个人资格

原版 Lua API 不提供完整角色菜单目录和可选判定。[characters::catalogue](https://github.com/BMingSY/isaac-lan/blob/main/src/engine/characters.h) 复制原生名称、画像与资格数据，Lua 不接收原生指针。

- 原版两页菜单表 RVA `0x744b50`，每条 `0x18`、每页 18 条；画像页表 RVA `0x744eb0`。随机占位行按位置排除；两页相同位置给出表／里配对。
- Manager 的 PlayerConfig 向量首尾指针位于 `+0x2a948/+0x2a94c`，每条记录占 `0x148` 字节。启动时校验 RVA `0x3637e4` 处读取这两个字段的指令。角色目录按原生 Mod 菜单规则排除 `hidden +0x128` 和子配置，里页使用 `+0x124` 的配对角色。
- `MenuCharacter::Available` RVA `0x55c5d0` 使用菜单记录作 receiver，栈参数为 0，被调方清理 4 字节。查询期间借入本机 642 个成就字节、523 个计数和 frontend scene；禁止在该作用域内执行 Lua、回调、存档或分配，返回前完整恢复。续玩只临时豁免已消耗的伊甸令牌。
- 校验配置范围、数量、ID、字符串长度和配对索引；入口和 Mod 枚举锚 RVA `0x55eb6e` 受签名校验。字符串立即复制，原生 MSVC 字符串由游戏销毁。

`net_characters()` 的目录条目用 `tainted` 标明分组，`counterpart` 为另一组对应的目录角色 ID；没有有效配对时省略。配对可尚未解锁，选角必须另查返回的可选 ID 列表。联机菜单只在当前组内循环和随机。`net_choose_random(group, ready)` 以个人可选 ID 和目录分组生成候选集合；`net_poll()` 返回的 `random0..3` 标识大厅的随机选择，角色卡显示问号并隐藏通关标记。运行层仅在主机发起新局时抽取最终 ID，准备／取消准备不触发抽取，启动参数只携带最终角色。表／里切换复用忏悔＋单人选角的 `ACTION_MENURB`（25，键盘 E／手柄右肩键），原生输入查询沿用现有菜单作用域，选角行右侧固定位置绘制原版 `gfx/ui/main menu/pageswapwidget.anm2` 的按键与切换符号层，省略底纸；角色名在预留宽度内显示。

`characters::completionPreview` 只读取调用方提供的个人 `Progress`，不写原生存档。忏悔＋原版角色与替身的计数映射集中在 [completion_marks.h](https://github.com/BMingSY/isaac-lan/blob/main/src/engine/versions/repentance_plus/completion_marks.h)。每个计数只取低两位的单人记录，屏蔽官方联机记录；十二层按 `gfx/ui/completion_widget.anm2` 排列，含代表 Delirium 的纸张层。预览的低 24 位每两位保存一层，位 24 表示数据可用；解码拒绝额外位和层值 3。未收录的 Mod 角色返回不可用，仍可正常选角，不伪造未通关记录。

## 道具与效果

`actor_inventory_order(sprite[, bytes])` 读取或恢复当前名单中玩家的 16 个库存槽顺序，每槽为大端 `i32` 道具 ID，0 表示空槽；玩法适配只用于里以撒。写入只允许客机，在完整解析并校验重复项数量后，把 ID 映射到本机已有历史索引，再一次提交槽位并置该角色 `PlayerHUD+0x6ac` 的库存刷新字节；顺序不变时不触及缓存。历史容器、道具效果、纹理和 HUD 缓存仍归原生代码所有，不复制主机索引、不分配历史条目。忏悔＋的槽数组位于 `Player+0x1e00`，历史向量位于 `+0x1dec`，历史条目步长 `0x1c`、饰品标记 `+0x4`、道具 ID `+0x8`；读取检查向量长度、65536 条上限和每个索引，布局受原生 HUD 读取指令签名校验。实现见 [inventory_order.h](https://github.com/BMingSY/isaac-lan/blob/main/src/engine/versions/repentance_plus/inventory_order.h)。

`actor_smelted_trinkets(sprite[, bytes])` 读取当前名单中玩家的已吞饰品；写入只允许客机，返回 0 表示未变、1 表示已变，失败返回 `false` 并终止当前恢复。载荷为大端 `u16` 条目数，后接严格递增的 `{u16 id, u16 normal, u16 golden}`；编号范围为 1～32767 且必须存在于本机容器，数量各为 0～32767，每项至少有一种数量非零。忏悔＋的 `Player+0x1748` 为游戏持有的配置大小向量，每项两个 `i16` 计数，普通／金色偏移分别为 0／2；原生倍率读取指令签名验证该布局。恢复在完整解析、校验向量范围和全部条目后原位写计数，清零省略项，不调整向量大小、不转移所有权、不触发使用道具、拾取奖励或历史条目。调用方在数量变化后刷新属性。实现见 [smelted_trinkets.h](https://github.com/BMingSY/isaac-lan/blob/main/src/engine/versions/common/smelted_trinkets.h)。

`items_active_data(sprite[, bytes])` 接受当前原生名单中玩家的借用 Sprite，读取或恢复四个主动槽的 `{id:i32, data:i32}` 大端记录，并在末尾携带一个打包盒非空标志（0／1），共 33 字节。写入只允许客机；完整解析后核对四个 ID 与已恢复的库存一致、空槽状态为 0，并通过[道具状态校验](https://github.com/BMingSY/isaac-lan/blob/main/src/compat/items/active_data.h)后才提交。D 无限高 16 位为十种骰子的索引，低 16 位保留充能状态。原生描述符位于 `Player+0x1580`，槽间隔 `0x20`，状态在槽内 `+0x1c`；布局由 RVA `0x39a199` 的原生写入指令校验。

状态变化只清空该玩家对应槽的原生 HUD 图标键。PlayerHUD 数组起于 `Game+0x1da04`，共 8 项、每项 `0x6dc`，首字段为借用玩家指针；四个主动图标缓存起于 `+0x190`，间隔 `0x1c`。根、步长、清空操作和槽间隔受原生指令签名校验。重复状态不触及缓存；图片加载、释放和绘制继续由原生 HUD 负责，不借用队友图标，也不执行主动道具玩法。实现见 [active_items.h](https://github.com/BMingSY/isaac-lan/blob/main/src/engine/versions/repentance_plus/active_items.h)。

打包盒内容由 `Player+0x1d7c/+0x1d80` 的原生向量边界只读判空。客机标志按玩家地址和实体种子保存，在演出状态重置时清理；不写该向量或主动槽内部状态。`PlayerHUD::RenderActiveItem` 的 RVA `0x44e392` 分支仅选择原生满盒／空盒裁剪路径，保存通用寄存器、标志和 XMM0–7，图片所有权不变。向量读取与分支受签名校验。实现见 [moving_box.cpp](https://github.com/BMingSY/isaac-lan/blob/main/src/engine/versions/repentance_plus/moving_box.cpp)。

死亡证明的原生拾取倒计时位于 `Game+0x6945c`，返回房间和维度位于 `+0x18900/+0x18904`。RVA `0x302662` 是倒计时完成后的返回边界：主机视口已离开道具区而仍有在线玩家留在其中时，仅为这次原生转场借入该玩家的房间作用域。转场沿用 `thiscall(Game*, int room, int direction, int animation, Player*, int dimension)` 和原生来源字段；没有道具区玩家时只消费已完成的倒计时。单人、客机和视口仍在道具区时走原分支。适配保存通用寄存器、标志、x87、XMM0–7 和 MXCSR，错误不跨原生帧展开；不改回溯存档或对象所有权。返回作用域与失败清理由[共享组件](https://github.com/BMingSY/isaac-lan/blob/main/src/engine/versions/common/death_certificate_return.cpp)管理，[忏悔＋绑定](https://github.com/BMingSY/isaac-lan/blob/main/src/engine/versions/repentance_plus/death_certificate_return.cpp)只提供布局和原生转场调用。

底座拾取、发放、充能及复活作用域使用[共享道具组件](https://github.com/BMingSY/isaac-lan/blob/main/src/engine/versions/common/item_effects.cpp)，原生入口与布局由 [忏悔＋绑定](https://github.com/BMingSY/isaac-lan/blob/main/src/engine/versions/repentance_plus/item_effects.cpp) 提供。`Player::QueueItem` RVA `0x366240` 使用 `thiscall`，只在底座确认拾取的返回点 `0x2f24d1` 通知运行层，传递玩家栏位、实体种子、道具 ID、充能、Touched、VarData 与来源池。兼容组件接受时不再向原拾取者入队；其他调用点、饰品、开局和恢复沿用原生方法。通知期间不切换房间；结算在模拟作用域退出后、发布视图前完成。源对象和配置指针不进入 Lua，不由适配器释放。

忏悔＋发放接口保留六个栈参数，入队接口保留五个栈参数，均包含来源道具池；原生充能类型继续使用 `0x39a1b0` 的角色方法。安装先创建发放、入队及两种复活的完整 Hook 组再启用，失败只撤销已创建的 Hook，允许重试。开局记录失败时清除部分奖励，避免后续会话继续使用。

`items_take_collectible(sprite, id)` 在当前角色作用域调用原生 `Player::DropCollectible`（RVA `0x399150`，`thiscall(Player*, int, Pickup*, bool)`），复制充能、VarData 和来源池，再由实体的原生 Remove 消除临时底座。`items_give_collectible(sprite, id, charge, first, data, pool)` 通过原生掉落保存被替换的主动，再用原生 AddCollectible 发放。入口只接受主机就绪视图中当前名单的玩家 Sprite 包装和有效配置；角色与掉落的分配、注销由游戏管理。底座字段 `+0x524/+0x52c/+0x530/+0x59c` 分别为充能、Touched、来源池和 VarData。入口、调用点和布局常量统一定义在版本后端并受签名校验。

`items_collectible_name(id)` 读取配置名称并解析本机 `Items` 翻译键，返回最多 1024 字节的文本；不暴露配置或字符串指针。上述能力不增加同步字段或网络消息，库存、药丸映射与实体沿用现有契约，扩展指纹包含后端与嵌入 Lua 的变更。

`items_active_charge(sprite, slot)` 返回当前主动的原生充能类型和有效容量，分别调用 `Player::GetActiveChargeType`（RVA `0x39a1b0`）与 `GetActiveMaxCharge`（`0x399fa0`），均为 `thiscall(Player*, int)`、`RET 4`。`items_add_active_charge(sprite, slot, amount)` 调用 `AddActiveCharge`（`0x39a220`，`thiscall(Player*, int amount, int slot, bool, bool, bool)`、`RET 20`），三个标志均为 false，返回实际增加量；容量、额外电池槽和充满演出由原生处理。两端都能在就绪视图中查询已连接身体的有效容量和类型。发放充能仅限权威端。接口仅接受 0–3 槽和 0–1024 的非负增量，不允许强制溢出或任意内存访问。

原生 `Player::TriggerRoomClear` 返回后通知运行层原调用玩家及清房的维度／房间编号；记录原生已经处理的玩家，实际补发在房间模拟退出后执行。通知只表示清房事件，不在后端解释规则，也不替其他房间调用完整的 `TriggerRoomClear`。客机继续抑制原生清房玩法，接受主机库存状态。

| 能力 | 边界与参考 |
| --- | --- |
| 错误道具定义与负编号库存 | 有序种子恢复、注册表和真实数量查询见[错误道具定义](https://github.com/BMingSY/isaac-lan/blob/main/docs/generated-item-definitions.md) |
| 全队恶魔／天使概率 | 原生查询 ABI、名单上下文与客机数值校验见[共享概率](https://github.com/BMingSY/isaac-lan/blob/main/docs/shared-deal-chances.md) |
| 共享道具生成查询 | 通过受限 PlayerManager 查询范围借用完整名单；达摩剑的额外底座查询使用完整名单，受伤与落剑仍查询实际持有者 |
| 小夜灯显示 | Room::Render 的 RVA `0x4194bd` 查询按所在房间筛选；角色姿态携带 `Player+0x1ae4` 的有限角度，不改变减速判定 |
| 特殊房间描述符 | 列表编号允许特殊房间使用自己的负房间编号，普通房间使用非负下标；描述符仍通过原生查找取得 |
| 临时效果 | [temporary_effects.lua](https://github.com/BMingSY/isaac-lan/blob/main/src/bridge/sync/temporary_effects.lua) 通过原版 Lua API 采集道具、饰品及 Null 效果集合，按层数差值恢复并移除已过期效果；不重放使用动作 |
| 本机拾取预览 | `Pickup::UpdateGhosts` RVA `0x2e7a60`，`thiscall(Pickup*)`；只在本机名单内生成 `PICKUP_GHOST`。遍历 Room 的绘制实体数组（`+0x1258`），先冻结拾取物列表再调用；Entity `+0x170` 表示已注册，不能作为删除标志过滤。原生持有 LootList、ANM2 与实体引用，普通实体快照排除该效果；预览查询不推进掉落 RNG |
| 跨房持续激光 | `Player+0x1458` 是受注册的激光 `EntityPtr`。在来源房间内调用实体原生 Remove，再以 `EntityPtr::Assign` RVA `0x2bc9f0`（ECX 引用、EDX 新实体）解除引用；不复制指针、不释放原生内存、不重置剩余时间 |
| 道具／饰品复活上下文 | `Player::ReviveFromCollectible` RVA `0x3ab080` 为 `thiscall void(Player*, unsigned item, bool owned)`；`ReviveFromTrinket` RVA `0x3ac0d0` 为 `thiscall void(Player*, unsigned trinket, unsigned scratch)`。后者的第二个栈字未参与忏悔＋逻辑，但原生以 `RET 8` 清栈，必须原样透传，不能沿用旧版单参数声明。PlayerManager 在房间更新之外处理死亡时，按角色控制器借入所属房间与名单，再调用一次原入口；已有作用域及单人模式沿用原上下文，不重放复活效果。道具／饰品读取上一房间的两个转场调用点为 `0x3ab6e7/0x3ac448`。主机按个人席位记录上一次进入前的房间与维度，换层清理记录。原地复活沿用原生行为。入口受版本签名校验，角色及效果实体仍由游戏拥有 |
| 蓝色房间初始化 | `Level::TryInitializeBlueRoom` RVA `0x3554d0` 为 `thiscall bool(Game*, int source, int destination, int direction)`。仅在步行且同维度转场的角色房间中调用；资格、描述符、房门标记与出口由原生实现维护，成功时采用原生蓝色房间编号 `-16`，不自行创建或释放描述符 |
| 换层随行效果 | `Player+0x1f04` 是赎罪效果的注册 `EntityPtr`。兼容策略仅选择类型 `1000`、变体 `185` 且与该引用相同的实体；换层收拢名单时，从旧房间迁入原生离场房间，随后交由原生换层更新与清理。普通换房不保留该例外，不复制或重新绑定引用，不手动结算奖励 |

房间年龄使用 `Game+0x26508` 的游戏帧减去 `Room+0x11f0` 的进入帧。后端为每个房间记录上次观察的游戏帧，房间进场屏障暂停期间仅将经过的帧数补入进入帧；初始化／接管房间时重设观察点，重复游戏帧不补偿。原生玩家更新仍负责首帧道具效果和充能，运行层不代替这些效果结算。
| 跨局共享奖励 | `Player::AddCollectible` RVA `0x367330` 的具名调用点 `0x3c6e0c` 标识原生祝福奖励。只在新建联机局时记录至多两项 ID，原生初始化后向其他控制器各发放一次；不复制初始库存，不重放宿主奖励或修改个人射速 |
| 个人画面状态 | `Game::AddPixelation` RVA `0x35bd80`、`Player::UpdateWavyCap` RVA `0x1d1360`；画面状态按控制器保存。Game 的 `+0x26538/+0x2653c/+0x26540` 是泛光剩余时间／初始时间／强度，`+0x26e80/+0x26e84` 是像素化剩余／初始时间，`+0x67e28/+0x67e2c/+0x67e30` 是扭曲当前／目标／步长；角色更新及嵌套的道具／药丸／卡牌调用借入同一所属状态，结束时回收并恢复全局标量；绘制只借入本机状态，角色动作外的世界泛光保留全局归属 |
| 规则文字 | `HUD::ShowFortuneText` RVA `0x5bb180` 借用 x86 MSVC 字符串链表，返回后不保留或释放调用方节点；接收端用本地字符串构造临时只读节点。`StringTable::Indexed` RVA `0x640c80` 根据原生选中的节名／索引翻译，不再次抽取随机提示 |

道具事件、pose 字段、范围校验与资源所有权见[道具演出事件与对象](https://github.com/BMingSY/isaac-lan/blob/main/docs/native-backend.md#道具演出事件与对象)。屏幕计时的重复快照只恢复状态，不重新开始计时。

本页描述实现契约，不代表对应玩法已经验收通过。兼容状态维护在[道具清单](https://github.com/BMingSY/isaac-lan/blob/main/docs/item-effect-compatibility.md)，原生验证方法见[开发与测试](https://github.com/BMingSY/isaac-lan/blob/main/docs/development-and-testing.md)。

## NPC 命中与受击绘制

[共享命中组件](https://github.com/BMingSY/isaac-lan/blob/main/src/engine/versions/common/combat_feedback.cpp) 通过 [忏悔＋绑定](https://github.com/BMingSY/isaac-lan/blob/main/src/engine/versions/repentance_plus/combat_feedback.cpp) 使用下述原生边界；[忏悔绑定](https://github.com/BMingSY/isaac-lan/blob/main/src/engine/versions/repentance/combat_feedback.cpp) 提供自己的入口和字段。观察仅在主线程及已建立的权威房间上下文运行，保留原生伤害判定和所有 Mod 回调，不在副本重放伤害。

| 能力 | 契约 |
| --- | --- |
| `combat_identity(sprite)` | 仅主机；接收活动实体的借用 Sprite，返回状态与伤害事件共用的递增身份。地址、InitSeed、索引用于检测对象替换；不拥有实体，不返回地址 |
| `combat_events(slot)` | 仅主机；slot 范围为联机玩家上限，按房间观看者掩码过滤。大端 u32 数量后每项为 `u32 serial,tick,epoch; i32 dimension,room; u32 source,target; u8 accepted,duration`，时长单位为 30 Hz tick，0–6。最多 512 项／90 tick |
| `combat_present()` / `combat_present(sprite)` | 无参数清空本机绘制选择；有参数仅客机，借用活动 NPC Sprite，在当前呈现帧选择原版受击样式。原生对象仍由游戏拥有 |
| `combat_reset()` | 会话重置清理身份、事件、序号和绘制选择；不分配／释放游戏对象 |

`NPC::TakeDamage` RVA `0x2dda70` 为 thiscall，参数为 float、u64、EntityRef 指针和 int，返回 bool。EntityRef 的实体引用位于 `+0x24`；调用前取得来源／目标身份与房间，返回后记录最终接受结果。HP 仍由原生更新消费伤害队列。`Entity::SetColor` RVA `0x2b9ea0` 只有返回地址为 `0x2b67a2` 的原生伤害闪烁调用被接管，且仅限 LAN 主机的 NPC；其他颜色调用原样转发。入口／返回位置受启动签名校验。

`accepted` 保留原生接触返回值；演出确认等待原生更新结算。接触时只记录新增伤害队列项的索引与已取得的来源／目标身份，不保留实体或队列项的可解引用指针。队列位于 `Entity + 0x8`，每项 `0x38` 字节；嵌套伤害独立归属。原生伤害 `SetColor` 调用点的 ESI 指向当前队列项，只有实际调用发生才登记其演出时长。队列清空位置 `0x2b67d3`（EDI 为实体）统一发布一次确认：免疫、回调否决、禁止闪烁等没有产生原生演出的命中时长为零。未入队的接触直接确认；未结算观察有数量和过期限制，重置／世界切换清理。序号在发布时分配，避免嵌套或延迟结算被客机高水位跳过。入口与寄存器契约由启动签名校验覆盖；原生伤害队列、HP 和返回值均不修改。

房间 renderArray 内的实体由房间持有。绘制作用域保存 44 字节 Sprite.Color，临时使用原版两种伤害样式，离开作用域按 RAII 恢复，不向原生颜色队列插入条目。实体 InitSeed／索引不符及过期记录失效；客机每次呈现先清空上一帧选择，暂停和视图重置也清空。此能力不推进动画、不创建碰撞特效、不播放声音，不适用于任意原生地址或独立创建的 Sprite。

三个 Hook 全部创建后才启用，安装失败只撤销本组件已创建的 Hook 并清空旁路，允许重试；重复安装不会覆盖正在使用的原函数。无 Game 时原生伤害仍透传，但不产生缺少房间归属的事件；无 Room 或渲染数组时仍执行原绘制回调。
