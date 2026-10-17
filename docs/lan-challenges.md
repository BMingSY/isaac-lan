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

## 规则与生命周期

切换规则清空全员准备状态；加入、选角、准备和启动分别校验本机存档资格及规则代次。普通选角使用原生菜单目录与可选判定，包含本机已加载的 Mod 角色。新开局所需的消耗型资格不重复限制已有角色恢复。

规则 ID／版本、原栏位与材料随检查点和实时视图恢复。R 键与沙漏保留会话规则，退出恢复受保护的单人 Continue。玩法层决定奖励与结束时机，运行层协调原生退出。

## 显示与扩展位置

终点使用原版 HUD 的 Destination 分支；百宝袋使用原版绘制，在本机右下角显示观察目标，隐藏队友小 HUD 的副手区域。本机其他卡牌／药丸正常显示。材料仍完整同步，显示限制不提供防作弊或数据保密。

| 职责 | 入口 |
| --- | --- |
| 编号、版本、资格与效果定义 | [compat/challenges/catalog.h](https://github.com/BMingSY/isaac-lan/blob/main/src/compat/challenges/catalog.h) |
| 规则描述符和大厅传输 | [core/run_rules.h](https://github.com/BMingSY/isaac-lan/blob/main/src/core/run_rules.h)、[net/](https://github.com/BMingSY/isaac-lan/tree/main/src/net) |
| 生命周期、重连与结束 | [bridge/runtime/challenges.lua](https://github.com/BMingSY/isaac-lan/blob/main/src/bridge/runtime/challenges.lua)、[runtime/session.cpp](https://github.com/BMingSY/isaac-lan/blob/main/src/runtime/session.cpp) |
| 终点与奖励规则 | [compat/routes/challenge_lamb.lua](https://github.com/BMingSY/isaac-lan/blob/main/src/bridge/compat/routes/challenge_lamb.lua) |
| 菜单与本机显示 | [presentation/menu.lua](https://github.com/BMingSY/isaac-lan/blob/main/src/bridge/presentation/menu.lua)、[J460 HUD 能力](https://github.com/BMingSY/isaac-lan/blob/main/docs/native-backend.md#hud-与本机输入) |

地图策略可通过 `maps[id]` 提供 `onLayoutReady(info, level)` 与 `canEnter(ctx)`。前者在权威布局准备后调用，后者在迁移入队前验证来源／目标和传送类型。1001 不配置地图策略；这些回调不提供房间构建或任意布局同步能力。

规则变更更新定义版本；启动与恢复均校验规则。专项入口为 [run_lan_challenges.py](https://github.com/BMingSY/isaac-lan/blob/main/tools/run_lan_challenges.py)，使用方法和执行范围见[开发与测试](https://github.com/BMingSY/isaac-lan/blob/main/docs/development-and-testing.md#按需专项)。
