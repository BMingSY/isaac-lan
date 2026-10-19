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

原版负责拾取资格、购买代价、二选一与底座替换；确认进入道具队列后才分配。因此开局物品、控制台发放、合成、重掷与状态恢复不触发拾取掷骰。角色原生将底座拆成材料等行为仍保留。接收者已有主动时，原生掉落保留其原道具；赠送不触发第二次掷骰。

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

地图策略可通过 `maps[id]` 提供 `onLayoutReady(info, level)` 与 `canEnter(ctx)`。前者在权威布局准备后调用，后者在迁移入队前验证来源／目标和传送类型。1001 和 1002 不配置地图策略；这些回调不提供房间构建或任意布局同步能力。

规则变更更新定义版本；启动与恢复均校验规则。恶魔形态专项入口为 [run_lan_challenges.py](https://github.com/BMingSY/isaac-lan/blob/main/tools/run_lan_challenges.py)，运气游戏专项入口为 [run_luck_game.py](https://github.com/BMingSY/isaac-lan/blob/main/tools/run_luck_game.py)。使用方法和执行范围见[开发与测试](https://github.com/BMingSY/isaac-lan/blob/main/docs/development-and-testing.md#开发专项入口)。
