# 道具与效果额外兼容记录

本表按当前 `main` 的实现记录原版道具、饰品、卡牌、药丸和诅咒的额外处理，适用于 J460 后端。普通拾取、使用、伤害和随机结果仍由主机运行原版逻辑，客机恢复库存与世界结果。没有单独规则的道具沿用通用同步；本表不代表原版全部组合已验收。

角色固有效果见[角色记录](https://github.com/BMingSY/isaac-lan/blob/main/docs/character-compatibility.md)，第三方道具定义和私有状态见[Mod 接入边界](https://github.com/BMingSY/isaac-lan/blob/main/docs/mod-compatibility.md#安装与通用边界)。

## 公共被动效果

以下是 [`items/team_effects.h`](https://github.com/BMingSY/isaac-lan/blob/main/src/compat/items/team_effects.h) 的完整名单。原版 `PlayerManager` 查找持有者／统计数量时短暂借用完整队伍名单，因此玩家分房后仍能参与公共效果。保留原版叠加、品质筛选与生成算法，不把道具复制给其他玩家。

| 道具 | 原版 ID | 额外处理 |
| --- | --- | --- |
| 指南针（The Compass） | 21 | 公共地图查询可见其他房间持有者 |
| 藏宝图（Treasure Map） | 54 | 公共地图查询可见其他房间持有者 |
| 打折（Steam Sale） | 64 | 原版商店折扣查询计入完整队伍，保留原版叠加公式 |
| 蓝地图（Blue Map） | 246 | 公共地图查询可见其他房间持有者 |
| 黑蜡烛（Black Candle） | 260 | 原版公共查询计入全队；权威采集时另外检查全部角色库存并清除楼层诅咒，补齐异房持有者的消咒效果 |
| 补货（Restock） | 376 | 原版公共补货查询可见其他房间持有者 |
| 十字圣球（Sacred Orb） | 691 | 原版公共物品生成查询可见其他房间持有者 |

原生上下文实现见 [`rooms.cpp`](https://github.com/BMingSY/isaac-lan/blob/main/src/engine/versions/j460/rooms.cpp)，黑蜡烛补充策略见 [`black_candle.lua`](https://github.com/BMingSY/isaac-lan/blob/main/src/bridge/compat/items/black_candle.lua)。地图最终显示标志来自主机；客机不在库存应用后自行重算覆盖它。

## 公共资源与开门概率

| 效果 | 额外处理 | 边界与实现 |
| --- | --- | --- |
| 深口袋（Deep Pockets） | 增减金币时用全队名单判断原版金币上限；拾取、购买和放炸弹触发的原生资源广播覆盖异房队友及暂存角色 | 金币／炸弹／钥匙维持原版合作共享；沙漏充能等其他广播位仍留在原房间范围。见 [`rooms.cpp`](https://github.com/BMingSY/isaac-lan/blob/main/src/engine/versions/j460/rooms.cpp) 的 `addCoins`、`syncResources` |
| 恶魔／天使房概率相关道具、饰品与历史 | 原版概率查询、房间类型初始化和清房开门读取全队名单；客机接收总概率与条件天使概率 | 覆盖原版查询识别的五芒星、羊头、圣体、钥匙碎片、忏悔书、美德之书等修正；保留原版重复叠加／去重与优先级，不逐项重写公式 |
| 房间内的临时保证开门效果 | 对已加载权威房间查询原版总概率，取其最大值，使异房效果也能作用于整队 | 不重复累加同一份库存、楼层惩罚或临时效果，不延长房间效果寿命 |

概率同步在库存 setter 之后恢复，避免客机因道具恢复副作用、受击历史或所在房间重算出另一套 HUD 百分比。星象房不属于这套概率适配。详细契约、原生入口和验证记录见[共享恶魔／天使房概率](https://github.com/BMingSY/isaac-lan/blob/main/docs/shared-deal-chances.md)。

## 库存、口袋槽与药丸

| 效果 | 额外处理 | 清理与边界 |
| --- | --- | --- |
| 主动、卡牌、药丸和饰品槽位 | 通用库存恢复四个主动槽、两个饰品槽、卡牌和药丸；另恢复四条有序口袋记录，保留口袋主动和切换次序 | 口袋记录在其他库存 setter 后恢复；主动对象仍由原版创建和持有。见 [`inventory.lua`](https://github.com/BMingSY/isaac-lan/blob/main/src/bridge/sync/inventory.lua) 与 [口袋槽实现说明](https://github.com/BMingSY/isaac-lan/blob/main/docs/party-compatibility.md#口袋槽与药丸) |
| 合成袋（Bag of Crafting） | [`crafting_bag.lua`](https://github.com/BMingSY/isaac-lan/blob/main/src/bridge/compat/items/crafting_bag.lua) 为持有者独立采集 8 个材料与预览 ID；在库存后恢复，并按变化标记原版 HUD 缓存 | 四个主动槽均检查，同房／分房一致；失去道具时清空旧显示，重复状态不反复重置 HUD；合作幽灵隐藏库存由原版管理 |
| 联机挑战 1001 的合成袋显示 | 固定席位观察环只显示下一位玩家的材料与原生预览，保留自己的卡牌、药丸和其他口袋物品 | 仅挑战表现规则；材料、旋转和合成仍属于操作者，缺席／幽灵／无袋时隐藏，不回退看自己。见[联机挑战](https://github.com/BMingSY/isaac-lan/blob/main/docs/lan-challenges.md) |
| 药丸颜色到效果的分配、鉴定状态 | [`pills.lua`](https://github.com/BMingSY/isaac-lan/blob/main/src/bridge/sync/pills.lua) 保存 15 种基础颜色的效果与鉴定标志，共 75 字节；在所有角色库存之后恢复 | 支持撤销鉴定与重放回退；大药丸颜色位沿用原版基础颜色映射。`pill_state` 先整体校验、仅客机可写 |
| 药丸／卡牌的实际使用效果 | 主机执行原版使用链路，客机应用结果及独立的本机提示／动画 | 不在客机重复 `UsePill`、`UseCard`；药丸颜色同步不等于为每种药丸重写效果，也不复制第三方自定义药丸的私有 Lua 表 |

合成袋的拾取、合成、配方预览和物品池来源由主机决定，客机恢复权威预览；不自行用本机 RNG 预测结果。固定字段和原生验证边界见[队伍兼容](https://github.com/BMingSY/isaac-lan/blob/main/docs/party-compatibility.md#口袋槽与药丸)。

## 楼层诅咒与临时形态

| 效果 | 额外处理 | 生效范围与边界 |
| --- | --- | --- |
| 楼层诅咒掩码 | [`curses.lua`](https://github.com/BMingSY/isaac-lan/blob/main/src/bridge/sync/curses.lua) 采集同一份权威掩码，客机在库存之后按差量增加／移除，再更新地图 | 诅咒属于全层，不为每名玩家分别保存；回退／换层后以新代次状态为准，避免黑蜡烛的本地 setter 副作用覆盖主机结果 |
| 迷宫诅咒（Curse of the Maze） | 主机保留原版随机选房；客机进入已由主机选定的目的地时暂时屏蔽迷宫位，完成后恢复 | 仅暂存／恢复迷宫位，保留进房时其他诅咒位的改变；支持嵌套与异常退出。策略见 [`routes/curses.h`](https://github.com/BMingSY/isaac-lan/blob/main/src/compat/routes/curses.h) |
| 黑蜡烛消咒 | 全队库存中任一角色持有时，权威采集清除当前楼层诅咒，再同步结果 | 见[公共被动名单](#公共被动效果)；不在客机自行决定消咒 |
| 白火临时游魂效果 | 单独同步 `ID_LOST_CURSE` 的层数，并按权威状态移除 | 属于角色空效果，不与楼层诅咒或合作幽灵混为一项；见[角色记录](https://github.com/BMingSY/isaac-lan/blob/main/docs/character-compatibility.md#角色私有资源与变身) |

## 传送、重开与回退

| 道具／效果 | 额外处理 | 生效范围与边界 |
| --- | --- | --- |
| 死亡证明（Death Certificate） | 原版进入和拾取后返回的动画 20 触发整队迁移；客机补齐原版来源房间标量以便返回 | 任一玩家拿取后全队返回原版来源房间；该维度内普通过门仍逐人执行。策略见 [`death_certificate.h`](https://github.com/BMingSY/isaac-lan/blob/main/src/compat/items/death_certificate.h) |
| 死亡证明内使用传送卡／传送效果 | 目的地只在维度 2 内解析；目标不存在时回到原版入口 80 | 不把普通层同索引房间当作目标；动画 3／11／16 的普通传送保持逐人迁移 |
| 发光沙漏（Glowing Hour Glass） | 每个控制器记录上次进房时全队的原生检查点；房主在使用者实际源房间决定回退／Home／其他原版结果，通过可靠楼层事务交付 | 仅原版动画 12 的实际回退恢复检查点与全队位置；推进世界代次、拒绝旧视图。首访出生房无检查点、Home 优先级、贪婪 I AM ERROR 落点均保留原版选择，详见[全队回退](https://github.com/BMingSY/isaac-lan/blob/main/docs/session-lifecycle.md#全队回退) |
| R Key | [`r_key.lua`](https://github.com/BMingSY/isaac-lan/blob/main/src/bridge/compat/items/r_key.lua) 在可靠换层屏障内调用原版重开，两端先清理旧房间再重新接管 | 使用受限重开种类 1；网络只传输事务，不判断道具规则 |
| 遗忘我（Forget Me Now）、五点骰子房 | 原版重新生成当前层的请求进入共同楼层事务，使全队使用同一新楼层 | 属于通用同层重建路径，不在客机额外使用道具；保留原版重生成后的库存、资源与种子结果。见 [`transitions.lua`](https://github.com/BMingSY/isaac-lan/blob/main/src/bridge/runtime/transitions.lua) |
| 其他道具／卡牌传送、传送门 | 普通过门与原生传送进入逐参与者迁移队列，离开房间作用域后处理；传送演出按角色执行 | 传送门不等待会被原版覆盖的 `TeleportUp` 动画，避免迁移卡住；特殊全队路线仍遵循自己的生命周期策略，见[过门与汇合](https://github.com/BMingSY/isaac-lan/blob/main/docs/rooms-and-presentation.md#过门与汇合) |

## 复活、随行与本机演出

| 效果 | 额外处理 | 边界与实现 |
| --- | --- | --- |
| 死猫、嗝屁猫的项圈、安卡、1up! 的原生复活转场 | 识别原版动画 5–10，在逐人迁移完成时恢复角色可见性，避免绕过全局过场后身体一直隐藏；同房原地复活也处理 | 复活判定、概率、库存消耗仍由原版决定；夹具直接覆盖项圈和死猫，不能据此宣称其他所有复活组合已验收。见 [`rooms.cpp`](https://github.com/BMingSY/isaac-lan/blob/main/src/engine/versions/j460/rooms.cpp) |
| 跟班和附属刀具 | 迁移保留实际所有者与原生随行顺序；副本先删除过期实体并完成原版回收，再创建替换实体 | 避免原版 64 槽跟班循环池覆盖仍被引用的对象，不扩容池或接管所有权；见[跟班池说明](https://github.com/BMingSY/isaac-lan/blob/main/docs/party-compatibility.md#跟班池与实体回收) |
| 道具、卡牌、药丸的拾取／使用文字与书类演出 | 只发给触发者的控制器；同步有序事件与完整 ItemOverlay 图层、贴图、状态、延时 | 客机去重并过滤旧代次，不调用会治疗、换房或播音的原生玩法更新；演出由 [`presentation/items.lua`](https://github.com/BMingSY/isaac-lan/blob/main/src/bridge/presentation/items.lua) 与版本后端管理 |
| Mega Mush 与同时使用道具的演出 | 房主为每个控制器持有独立原生 ItemOverlay，按权威更新推进 | 避免演出全局暂停导致另一玩家漏掉道具输入，保留 Mega Mush 动画结束后的原版显形；不改道具战斗效果。详见[表现归属](https://github.com/BMingSY/isaac-lan/blob/main/docs/rooms-and-presentation.md#表现也需要归属) |
| 长子权对里拉撒路的身体管理 | 修复原生双身体入列、全局索引替换及副本身份清理 | 具体规则归角色模块，见[里拉撒路记录](https://github.com/BMingSY/isaac-lan/blob/main/docs/character-compatibility.md#身体替换双角色与随行实体)；不表示为所有角色重写了长子权效果 |

## 回归入口与证据

| 范围 | 离线回归 | 实机夹具／既有记录 |
| --- | --- | --- |
| 公共道具、资源、概率 | [`core_test.cpp`](https://github.com/BMingSY/isaac-lan/blob/main/tests/core_test.cpp)、[`shared_resources.lua`](https://github.com/BMingSY/isaac-lan/blob/main/tests/shared_resources.lua)、[`shared_deals.lua`](https://github.com/BMingSY/isaac-lan/blob/main/tests/shared_deals.lua) | [`state_party_compat.lua`](https://github.com/BMingSY/isaac-lan/blob/main/tests/state_party_compat.lua)、[共享概率记录](https://github.com/BMingSY/isaac-lan/blob/main/docs/history/shared-deal-chances-validation.md)、[共享状态记录](https://github.com/BMingSY/isaac-lan/blob/main/docs/history/shared-state-bugfix-validation.md) |
| 口袋、合成袋、药丸与诅咒 | [`pocket_inventory.lua`](https://github.com/BMingSY/isaac-lan/blob/main/tests/pocket_inventory.lua)、[`crafting_bag.lua`](https://github.com/BMingSY/isaac-lan/blob/main/tests/crafting_bag.lua)、[`pills.lua`](https://github.com/BMingSY/isaac-lan/blob/main/tests/pills.lua)、[`shared_curses.lua`](https://github.com/BMingSY/isaac-lan/blob/main/tests/shared_curses.lua) | [`state_crafting_bag.lua`](https://github.com/BMingSY/isaac-lan/blob/main/tests/state_crafting_bag.lua)、[`state_shared_curses.lua`](https://github.com/BMingSY/isaac-lan/blob/main/tests/state_shared_curses.lua)、[队伍专项记录](https://github.com/BMingSY/isaac-lan/blob/main/docs/history/party-compatibility-validation.md) |
| 重开、回退、特殊传送 | [`floor.lua`](https://github.com/BMingSY/isaac-lan/blob/main/tests/floor.lua)、[`core_test.cpp`](https://github.com/BMingSY/isaac-lan/blob/main/tests/core_test.cpp) 的死亡证明／回退规则 | [`state_floor_items.lua`](https://github.com/BMingSY/isaac-lan/blob/main/tests/state_floor_items.lua)、[`state_hourglass.lua`](https://github.com/BMingSY/isaac-lan/blob/main/tests/state_hourglass.lua)、[沙漏首层记录](https://github.com/BMingSY/isaac-lan/blob/main/docs/lan-hourglass-start-room-issue.md) |
| 复活与演出归属 | [`presentation.lua`](https://github.com/BMingSY/isaac-lan/blob/main/tests/presentation.lua)（事件／表现辅助契约） | [`state_item_revive.lua`](https://github.com/BMingSY/isaac-lan/blob/main/tests/state_item_revive.lua)、[`state_item_presentation.lua`](https://github.com/BMingSY/isaac-lan/blob/main/tests/state_item_presentation.lua)、[`state_guest_presentation_audio.lua`](https://github.com/BMingSY/isaac-lan/blob/main/tests/state_guest_presentation_audio.lua)、[已报问题回归](https://github.com/BMingSY/isaac-lan/blob/main/docs/history/issue-regressions.md) |

夹具与历史证据分别列出；新增道具、跨层／回退组合或原生机制仍需按[开发与测试](https://github.com/BMingSY/isaac-lan/blob/main/docs/development-and-testing.md)集中验收，不能把文档整理算作新的实机通过记录。
