# 联机挑战

联机挑战由房主在大厅选择，通过运行规则约束角色、难度、终点和效果。网络传输规则描述符，玩法由挑战兼容组件执行，界面复用原版 HUD。

## 当前规则：1001 恶魔形态

| 项目 | 行为 |
| --- | --- |
| 资格 | 全员自己的存档均解锁底片和里该隐；共享主机进度不参与资格判定 |
| 开局 | 普通难度、里该隐、2–4 人 |
| 百宝袋 | 固定栏位形成 P1 → P2 → … → P1 观察环；显示下一位的材料与原生预览，实际材料和操作仍属于自己 |
| 身份变化 | 死亡、掉线和重连不重排观察环；目标缺失、幽灵或没有袋子时隐藏显示 |
| 路线与终点 | 沿原版路线取得底片并前往暗室；羔羊清场后以原版奖杯替代结局宝箱 |
| 完成 | 在线、存活且非幽灵的角色领取奖杯，房主发布一次可靠结束，全队返回菜单，不写入原版挑战解锁 |
| 保存 | 临时会话，不保存整场续玩，不覆盖已有普通联机存档；原客机可通过当前层检查点重连 |

非终点的终局宝箱、原生结局和跑圈入口受规则限制。羔羊清场后移除会绕开终点的虚空入口、楼层地洞和天堂光柱，保留普通房门；奖杯领取是唯一通关方式。死亡与主动退出仍可结束会话。

## 当前规则：1002 运气游戏

| 项目 | 行为 |
| --- | --- |
| 开局 | 普通难度、2–4 人；不限定角色，沿用各自存档的普通选角资格 |
| 开局饰品 | 每人永久吞下一枚“禁令”（No!），不占饰品栏，保留原有开局饰品；按原版规则阻止主动道具生成 |
| 拾取 | 原版确认非主动道具的底座拾取后，全队在线、存活且非幽灵的玩家各掷一次 D100；点数加当前幸运值，最高者获得道具 |
| 同分 | 在并列玩家中随机决定顺序；同一次换层的最高者与最低者不同 |
| 换层 | 每次向更深楼层推进时掷骰，最低者随机交出一件持有道具给最高者；开局、同层重置与回退不触发，最低者没有道具时不转移 |
| 道具范围 | 主动道具正常拾取，不掷骰、不发分配消息；被动道具及重复副本参与拾取分配。换层按实际持有副本抽取（含携带主动），角色口袋主动不参与；赠送保留主动充能和道具内部数据，不重复发放首次拾取资源 |
| 清房 | 每次实际清房奖励额外生成一颗免费的幸运上升药丸，独立于原版奖励和二选一组 |
| 终点 | 妈腿所在 Boss 房清场后生成奖杯，移除楼层出口；领取奖杯结束全队挑战 |
| 聊天 | 仅公布拾取者、各玩家原版 `/d100` 输出、带幸运补正的得主；换层公布掷骰与赠送结果 |

开局饰品由兼容组件在主机就绪和客机首个已提交视图中初始化；已有吞下状态的检查点不会重复添加，不依赖重新执行道具掷骰。

拾取与换层分配复用 [loot_roll.lua](https://github.com/BMingSY/isaac-lan/blob/main/src/bridge/compat/rules/loot_roll.lua) 的玩家分组、D100 排序与原生发放能力。挑战向它提供运气修正；普通[道具掷骰房间规则](https://github.com/BMingSY/isaac-lan/blob/main/docs/room-rules.md#道具掷骰分配) 不提供修正。挑战自己的拾取范围优先，两者同时开启只结算一次。

原版负责拾取资格、购买代价、二选一与底座替换；确认进入道具队列后才分配。因此开局物品、控制台发放、合成、重掷与状态恢复不触发拾取掷骰。角色原生将底座拆成材料等行为仍保留。接收者已有主动时，原生掉落保留其原道具；赠送不触发第二次掷骰。

## 当前规则：1003 吃鸡

| 项目 | 行为 |
| --- | --- |
| 开局 | 普通难度、2–4 人、以撒；移除开局自带 D6，后续获得的主动道具正常保留；房间规则固定为队友伤害，其他可选规则关闭，主客机均不能修改 |
| 地图 | 首轮固定普通路线第一层，后续轮次从第 1–5 层随机抽取，各轮保留普通层变种；在 13×13 网格内按原生红房间规则展开可生成的位置，保留普通探索资源；玩家随机分配不同角落，出生房清除敌人和障碍，保留拾取物与房门。出生分配和 Boss 定点传送不受迷宫诅咒改变目的地，普通探索保留原生诅咒规则 |
| 资源房 | 计入原生已有的同类房间，目标补齐 16 个宝箱房、8 个商店、4 个书房、4 个拱廊；优先保障出生点附近可达的宝箱房，并在第一圈内保留至少一半配额，其余按区域分散。预留出生房、Boss 房、初始房和最终决战房；模板或可用位置不足时保留原生连接，只在兼容位置补充 |
| 房间入口 | 宝箱房和商店免钥匙进门，商品按原生价格收费；清怪前仍遵守战斗封门，缩圈后按逃离规则开门 |
| 生存 | 90、180、240 秒时，安全区从全图依次缩为 9×9、5×5、一个房间；每次位置随机且完全位于上一安全区内，最终房间从实际存在的普通 1×1 房间中抽取，排除 Boss 房；缩圈后允许逃离未清怪房间。圈外持续受伤，五分钟后最终房间也逐渐增加环境伤害；Boss 战另计时间 |
| 死亡 | 本挑战移除复活机，正常道具复活保留，等待复活结算后判断幸存者；最终死亡者本轮淘汰，Boss 清场不复活队友；重连保留淘汰状态 |
| 胜场 | 确认唯一幸存者后立即结束生存阶段并进入 Boss 流程，无需等满五分钟；首次击败普通 Boss 记一胜并进入赛点，再次吃鸡后直接挑战妈腿，击败后由胜者领取挑战奖杯结束 |
| Boss 入口 | 平时禁止进入 Boss 房；幸存者脚下出现传送门，约一秒过场后自动进入本轮普通 Boss 房或预留的原生妈腿房；到达后正常拾取临时教条，包含原生拾取效果，下一轮假换层时移除临时副本，原有副本保留 |
| 奖励与推进 | Boss 结算底座使用混沌的原生跨道具池抽取，至少一个底座品质不低于 3，额外底座不保证品质；该抽取只作用于 Boss 结算，探索房间使用各自道具池。普通 Boss 胜者可领取或跳过奖励，只有胜者可以进入下一轮出口；站在出口生成位置时须离开后重新进入 |
| 下一轮 | 假换层重新随机地图；保留道具、属性和资源，淘汰者复活，全员补满当前红心容器，已有魂心／黑心保留且不额外补发。全灭或 Boss 战失败时无人得分，保留之前胜场并继续 |
| 显示 | 血条上方使用图形胜场进度和赛点奖杯；各自探索地图独立；原生地图 HUD 上以实线标出当前安全区、虚线预告下一圈、淡红色标出圈外，并在地图下沿显示距下一次缩圈的进度条。提示随原生小地图／展开地图的裁剪、位置和透明度变化，生存结束后隐藏 |

玩法组件为 [battle_royale.lua](https://github.com/BMingSY/isaac-lan/blob/main/src/bridge/compat/challenges/battle_royale.lua)，可离线运行的胜场、缩圈与配额规则为 [battle_royale_rules.lua](https://github.com/BMingSY/isaac-lan/blob/main/src/bridge/compat/challenges/battle_royale_rules.lua)。[地图组件](https://github.com/BMingSY/isaac-lan/blob/main/src/bridge/compat/challenges/battle_royale_map.lua)通过原生红房间规则展开地图，预留原生妈腿房并确定随机缩圈，再由[资源分布组件](https://github.com/BMingSY/isaac-lan/blob/main/src/bridge/compat/challenges/battle_royale_resources.lua)补齐兼容模板和出生资源路径；普通胜场排除 XL 地图中的妈腿房。[奖励组件](https://github.com/BMingSY/isaac-lan/blob/main/src/bridge/compat/challenges/battle_royale_rewards.lua)仅在结算抽取作用域中借用混沌，正常返回或异常时均移除临时副本，原有混沌保留。Boss、出口和整轮推进由房主裁决。个人地图保留各自探索及原生揭图效果，不提供数据保密或防作弊保证。

## 规则与生命周期

切换规则清空全员准备状态；加入、选角、准备和启动分别校验本机存档资格及规则代次。普通选角使用原生菜单目录与可选判定，包含本机已加载的 Mod 角色。新开局所需的消耗型资格不重复限制已有角色恢复。

挑战均为临时会话，不保存整场续玩，不覆盖普通联机存档。规则 ID／版本、原栏位与材料随检查点和实时视图恢复。R 键与沙漏保留会话规则，退出恢复受保护的单人 Continue。玩法层决定奖励与结束时机，运行层协调原生退出。

## 显示与扩展位置

终点使用原版 HUD 的 Destination 分支；百宝袋使用原版绘制，在本机右下角显示观察目标，隐藏队友小 HUD 的副手区域。本机其他卡牌／药丸正常显示。材料仍完整同步，显示限制不提供防作弊或数据保密。

| 职责 | 入口 |
| --- | --- |
| 编号、版本、资格与效果定义 | [compat/challenges/catalog.h](https://github.com/BMingSY/isaac-lan/blob/main/src/compat/challenges/catalog.h) |
| 规则描述符和大厅传输 | [core/run_rules.h](https://github.com/BMingSY/isaac-lan/blob/main/src/core/run_rules.h)、[net/](https://github.com/BMingSY/isaac-lan/tree/main/src/net) |
| 生命周期、重连与结束 | [bridge/runtime/challenges.lua](https://github.com/BMingSY/isaac-lan/blob/main/src/bridge/runtime/challenges.lua)、[runtime/session.cpp](https://github.com/BMingSY/isaac-lan/blob/main/src/runtime/session.cpp) |
| 终点与奖励规则 | [compat/routes/challenge_goal.lua](https://github.com/BMingSY/isaac-lan/blob/main/src/bridge/compat/routes/challenge_goal.lua) |
| 运气游戏规则 | [compat/challenges/luck_game.lua](https://github.com/BMingSY/isaac-lan/blob/main/src/bridge/compat/challenges/luck_game.lua) |
| 菜单与本机显示 | [presentation/menu.lua](https://github.com/BMingSY/isaac-lan/blob/main/src/bridge/presentation/menu.lua)、[J460 HUD 能力](https://github.com/BMingSY/isaac-lan/blob/main/docs/native-backend.md#hud-与本机输入) |

地图策略可通过 `maps[id]` 提供 `onLayoutReady(info, level)` 与 `canEnter(ctx)`。前者在权威布局准备后调用，后者在迁移入队前验证来源／目标和传送类型。1001 和 1002 不配置地图策略，1003 通过这些回调展开红房间并限制 Boss 入口。回调只协调游戏 API，新增房间沿用既有布局同步。

有动态进度的挑战通过世界字段 `challenge` 传输规则编号、规则版本和组件载荷，重连恢复后再绘制图形 HUD。1003 的规则版本为 3，载荷包含轮次、阶段、已用生存帧、胜者、四个栏位的胜场、存活掩码、四个安全区的左上角网格索引和可选传送门位置。整轮缩圈位置只由房主抽取，按 13、9、5、1 的边长验证边界与逐级包含关系；字段位置由可移植规则模块定义，玩法状态由挑战组件统一清理。[个人地图组件](https://github.com/BMingSY/isaac-lan/blob/main/src/bridge/sync/map_visibility.lua)按玩家投影显示／探索字段，不改变权威房间的清场、掉落或布局。

规则变更更新定义版本；启动与恢复均校验规则。恶魔形态专项入口为 [run_lan_challenges.py](https://github.com/BMingSY/isaac-lan/blob/main/tools/run_lan_challenges.py)，运气游戏专项入口为 [run_luck_game.py](https://github.com/BMingSY/isaac-lan/blob/main/tools/run_luck_game.py)。使用方法和执行范围见[开发与测试](https://github.com/BMingSY/isaac-lan/blob/main/docs/development-and-testing.md#开发专项入口)。
