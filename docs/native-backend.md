# J460 原生能力参考

本文记录 Lua API 无法表达的原生能力、调用边界与所有权，供修改版本后端时查阅。适用 Repentance+ `1.9.7.17.J460`，游戏 SHA-256 为 `7122ac28779925b24e23e2416f231322b1470388bd25e2c08665ad8d53b3ea4f`。

入口与签名以 [entrypoints.h](https://github.com/BMingSY/isaac-lan/blob/main/src/engine/versions/j460/entrypoints.h)、[signatures.inc](https://github.com/BMingSY/isaac-lan/blob/main/src/engine/versions/j460/signatures.inc) 为准，布局由版本后端持有。这里的地址不能用于其他游戏版本；桥接和兼容组件仅使用具名能力，不读取任意内存。

## 实体引用与房间数据

| 能力与实现 | 原生边界 | 校验与所有权 |
| --- | --- | --- |
| [持有炸弹](https://github.com/BMingSY/isaac-lan/blob/main/src/engine/versions/j460/held_bombs.h) `boss_held_bombs` | Lua API 不暴露 NPC `+0xbf0` 的持有容器；Hornfel 为两槽，Horny Boys 为三槽 | 读取本机实体索引，由兼容组件转换为同步 ID；客机写入校验 Boss、炸弹类型和槽数，使用游戏 resize 与 `EntityPtr.Assign`，容器仍由游戏析构 |
| [矿车引用](https://github.com/BMingSY/isaac-lan/blob/main/src/engine/versions/j460/entity_links.h) `entity_minecart` | 乘坐者 Entity `+0x3d4` 的反向引用不由矿车 `Child` 表达 | 仅接受矿车 Sprite／空值，使用原生引用注册与撤销；不调用会生成新矿车的玩法方法 |
| [轨道布局](https://github.com/BMingSY/isaac-lan/blob/main/src/engine/versions/j460/rails.h) `room_rails` | `Room:GetGridEntity` 不包含 RailManager；房间 `+0x746c` 为 448 字节数组 | 客机整体验证长度、值、尺寸与所有者后写入；空轨道也恢复，Sprite 仍由房间持有 |
| 客机实体回收 | `Remove()` 不保证立即释放池槽位；J460 跟班池为 64 槽 | 在房间作用域内通过原生更新完成回收，更新前须启用客机 AI 拦截；不扩容原生池，不手工释放对象 |
| 玩家清房回调 | `Player::TriggerRoomClear`，RVA `0x3a8fd0`，`thiscall void(Player*)`；Lua 没有阻止原生清房效果的前置回调 | 联机客机房间启用期间跳过玩法触发，角色状态由权威快照恢复；主机、单人及原生加载保留原调用，不分配或替换角色对象 |
| 口袋槽、合成袋、药丸状态 | 原生载荷分别为 32、12、75 字节 | 在库存恢复后应用，完整校验载荷与玩家归属；写入限客机，主动对象与物品池仍由原版管理 |

实体链接在对象恢复完成后应用。原生能力只处理引用与布局，Boss 匹配和状态选择由 [compat/bosses/](https://github.com/BMingSY/isaac-lan/tree/main/src/bridge/compat/bosses) 负责。

`rooms_with_player` 可以切换到客机的远端角色存储壳；该对象不保证网格尺寸、门或房间描述符已经初始化。房间内容只能在主机权威房间或客机当前可见房间查询，可见性须同时比较房间编号和 dimension。远端角色的库存、属性与位置仍可采集，不能将存储壳视为完整房间。

## 转场与暂停

Lua `SetStage` 不能提供原生过场中延迟选层所需的来源房间；普通 `Game::StartRoomTransition` 同时选路并启动转场，不能直接作为客机结果回放接口。

| 能力 | 入口与调用约定 | 约束 |
| --- | --- | --- |
| 换层来源上下文 | `Level::SetNextStage`，RVA `0x3467c0`，`thiscall void(Level*)` | 调用期间临时替换 `Level+0x18304` 来源索引，范围 `[-20, 168]`；返回恢复，事务完成／取消时失效，不切换房间对象 |
| 已决定的房间转场 | `RoomTransition.Start`，RVA `0x42ee40`，receiver 为 `Game+0x1b83c`，五个栈参数、被调方清理 20 字节 | 回放 index、direction、animation、player、dimension，保留原版尾部完成标志；不重新选择路线 |
| 暂停菜单 | `pauseMenuShow`、`pauseMenuHide`、`pauseMenuControls`、`optionsSave` | 菜单操作独立于整段 `Game::Controls`，临时使用本机显示名单，返回恢复，不接管菜单或角色所有权 |
| 原生菜单提示清理 | `input::resetMenuPrompts`，RVA `0x239b0`，`thiscall void(Manager+0x4a950, false)` | 联网启动销毁菜单后调用一次，被调方清理 4 字节，不影响随后暂停菜单提示 |

回退使用者源房只在完整权威房间、无借用作用域时激活；不激活客机远端存储壳，不跨清理持有 Room Scope。来源和回放参数由运行事务维护，选路与对象分配／释放由原版负责。

联机拦截 `Manager::SaveGame` 的文件写入时仍执行 `Game::CaptureState`。采集包含原生玩家离房清理，调用方随后恢复进房临时效果；两者必须配对。捕获结果只保存在原生 GameState 中，单人存档由会话备份保护，联机退出写入独立会话存档。个人进度合并完成后，`session::persistProgress` 按原生顺序调用 `Progress::SaveCloud`（RVA `0x528ee0`）和 `Progress::SaveFile`（RVA `0x5294f0`），两者均为 `thiscall void(Manager+0x14)`，由原生打开并关闭流；不能直接调用需要已打开流的 `Serialize`。该接口只保存当前存档槽的进度，不分配角色或写入局内存档。

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
| 本机拾取预览 | `Pickup::UpdateGhosts` RVA `0x2e17c0`，`thiscall(Pickup*)`；只在本机名单内生成 `PICKUP_GHOST`。遍历 Room 的绘制实体数组（`+0x1258`），先冻结拾取物列表再调用；Entity `+0x170` 表示已注册，不能作为删除标志过滤。原生持有 LootList、ANM2 与实体引用，普通实体快照排除该效果；预览查询不推进掉落 RNG |
| 跨房持续激光 | `Player+0x1458` 是受注册的激光 `EntityPtr`。在来源房间内调用实体原生 Remove，再以 `EntityPtr::Assign` RVA `0x2b5b50`（ECX 引用、EDX 新实体）解除引用；不复制指针、不释放原生内存、不重置剩余时间 |
| 跨局共享奖励 | `Player::AddCollectible` RVA `0x35f0e0` 的具名调用点 `0x3be32f` 标识原生祝福奖励。只在新建联机局时记录至多两项 ID，原生初始化后向其他控制器各发放一次；不复制初始库存，不重放宿主奖励或修改个人射速 |
| 个人画面状态 | `Game::AddPixelation` RVA `0x353cc0`、`Player::UpdateWavyCap` RVA `0x1cb480`；画面状态按控制器保存。Game 的 `+0x269e0/+0x269e4` 是像素化剩余／初始时间，`+0x67738/+0x6773c/+0x67740` 是扭曲当前／目标／步长；绘制时借入本机状态并完整恢复全局标量 |
| 规则文字 | `HUD::ShowFortuneText` RVA `0x5a3ac0` 借用 x86 MSVC 字符串链表，返回后不保留或释放调用方节点；接收端用本地字符串构造临时只读节点。`StringTable::Indexed` RVA `0x626d30` 根据原生选中的节名／索引翻译，不再次抽取随机提示 |

世界 schema 24 的道具演出 pose 在状态、ID、延迟之后携带两个 `u32` 像素化计时和三个按 IEEE 754 位模式编码的 `f32` 扭曲标量。接收端先校验完整记录：计时不得倒置，浮点必须有限且非负；重复快照只恢复状态，不重置计时。规则文字事件使用种类 5，受现有序号、楼层代次、接收者、事件数与长度限制。网络消息版本仍为 30；包含扩展 DLL 与嵌入 Lua 的指纹阻止旧实现接入，schema 同时拒绝旧快照。

本页描述实现契约，不代表对应玩法已经验收通过。兼容状态维护在[道具清单](https://github.com/BMingSY/isaac-lan/blob/main/docs/item-effect-compatibility.md)，原生验证方法见[开发与测试](https://github.com/BMingSY/isaac-lan/blob/main/docs/development-and-testing.md)。
