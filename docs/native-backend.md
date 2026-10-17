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

精灵载荷以格式号 `2` 开头，主动画与叠加动画各保存存在标记、浮点帧、播放标记、当前／历史事件位图、图层与挂点层的 ID／帧索引。可移植契约见 [animation_pose.h](https://github.com/BMingSY/isaac-lan/blob/main/src/core/animation_pose.h)：最多 64 个图层、256 个挂点层，帧索引为 `-1` 或小于 65535 的整数；拒绝重复 ID、非法标记与非有限帧。J460 的动画状态 `+0x8/+0xc` 分别引用图层／挂点帧数组，动画数据 `+0x20/+0x24` 为挂点描述数组与数量，每项 16 字节，帧数位于项内 `+0xc`。事件位图位于动画状态 `+0x18/+0x1c`。所有数组由游戏持有，恢复只按本机 ID 与帧数边界写入，不分配或替换原生数组。动画名未变化时直接恢复这些完整状态，名称变化仍调用游戏动画切换接口。

| 能力与实现 | 原生边界 | 校验与所有权 |
| --- | --- | --- |
| [持有炸弹](https://github.com/BMingSY/isaac-lan/blob/main/src/engine/versions/j460/held_bombs.h) `boss_held_bombs` | Lua API 不暴露 NPC `+0xbf0` 的持有容器；Hornfel 为两槽，Horny Boys 为三槽 | 读取本机实体索引，由兼容组件转换为同步 ID；客机写入校验 Boss、炸弹类型和槽数，使用游戏 resize 与 `EntityPtr.Assign`，容器仍由游戏析构 |
| [矿车引用](https://github.com/BMingSY/isaac-lan/blob/main/src/engine/versions/j460/entity_links.h) `entity_minecart` | 乘坐者 Entity `+0x3d4` 的反向引用不由矿车 `Child` 表达 | 仅接受矿车 Sprite／空值，使用原生引用注册与撤销；不调用会生成新矿车的玩法方法 |
| [轨道布局](https://github.com/BMingSY/isaac-lan/blob/main/src/engine/versions/j460/rails.h) `room_rails` | `Room:GetGridEntity` 不包含 RailManager；房间 `+0x746c` 为 448 字节数组 | 客机整体验证长度、值、尺寸与所有者后写入；空轨道也恢复，Sprite 仍由房间持有 |
| 客机实体回收 | `Remove()` 不保证立即释放池槽位；J460 跟班池为 64 槽 | 在房间作用域内通过原生更新完成回收，更新前须启用客机 AI 拦截；不扩容原生池，不手工释放对象 |
| 玩家清房回调 | `Player::TriggerRoomClear`，RVA `0x3a8fd0`，`thiscall void(Player*)`；Lua 没有阻止原生清房效果的前置回调 | 联机客机房间启用期间跳过玩法触发，角色状态由权威快照恢复；主机、单人及原生加载保留原调用，不分配或替换角色对象 |
| 口袋槽、合成袋、药丸状态 | 原生载荷分别为 32、12、75 字节 | 在库存恢复后应用，完整校验载荷与玩家归属；写入限客机，主动对象与物品池仍由原版管理 |

实体链接在对象恢复完成后应用。原生能力只处理引用与布局，Boss 匹配和状态选择由 [compat/bosses/](https://github.com/BMingSY/isaac-lan/tree/main/src/bridge/compat/bosses) 负责。

## 转场与暂停

Lua `SetStage` 不能提供原生过场中延迟选层所需的来源房间；普通 `Game::StartRoomTransition` 同时选路并启动转场，不能直接作为客机结果回放接口。

| 能力 | 入口与调用约定 | 约束 |
| --- | --- | --- |
| 换层来源上下文 | `Level::SetNextStage`，RVA `0x3467c0`，`thiscall void(Level*)` | 调用期间临时替换 `Level+0x18304` 来源索引，范围 `[-20, 168]`；返回恢复，事务完成／取消时失效，不切换房间对象 |
| 已决定的房间转场 | `RoomTransition.Start`，RVA `0x42ee40`，receiver 为 `Game+0x1b83c`，五个栈参数、被调方清理 20 字节 | 回放 index、direction、animation、player、dimension，保留原版尾部完成标志；不重新选择路线 |
| 暂停菜单 | `pauseMenuShow`、`pauseMenuHide`、`pauseMenuControls`、`optionsSave` | 菜单操作独立于整段 `Game::Controls`，临时使用本机显示名单，返回恢复，不接管菜单或角色所有权 |
| 原生菜单提示清理 | `input::resetMenuPrompts`，RVA `0x239b0`，`thiscall void(Manager+0x4a950, false)` | 联网启动销毁菜单后调用一次，被调方清理 4 字节，不影响随后暂停菜单提示 |

回退使用者源房只在完整权威房间、无借用作用域时激活；不激活客机远端存储壳，不跨清理持有 Room Scope。来源和回放参数由运行事务维护，选路与对象分配／释放由原版负责。

联机拦截 `Manager::SaveGame` 的文件写入时仍执行 `Game::CaptureState`。采集包含原生玩家离房清理，调用方随后恢复进房临时效果；两者必须配对。捕获结果只保存在原生 GameState 中，单人存档由会话备份保护，联机退出写入独立会话存档。

## HUD 与本机输入

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
