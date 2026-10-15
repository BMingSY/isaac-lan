# 角色效果额外兼容记录

本表按当前 `main` 的实现记录原版角色在分房联机中需要的额外处理，适用于 J460 后端。角色未单列时仍使用通用角色、库存、实体与表现同步；单列也不表示该角色所有道具组合均已验收。道具带来的效果见[道具与效果记录](https://github.com/BMingSY/isaac-lan/blob/main/docs/item-effect-compatibility.md)，第三方角色的接入边界见[第三方 Mod 记录](https://github.com/BMingSY/isaac-lan/blob/main/docs/mod-compatibility.md)。

## 公共生成与个人交易

公共特性通过原版查询临时读取完整队伍名单，使分房后的生成规则一致；角色库存、个人属性和主动道具仍归本人。策略位于 [`characters/team_effects.h`](https://github.com/BMingSY/isaac-lan/blob/main/src/compat/characters/team_effects.h)，原生查询上下文位于 [`rooms.cpp`](https://github.com/BMingSY/isaac-lan/blob/main/src/engine/versions/j460/rooms.cpp)。

| 角色／效果 | 额外处理 | 生效范围与边界 |
| --- | --- | --- |
| 里店长：商店布局与定价 | 商店生成和指定定价查询读取全队里店长；第一层远端对象尚未创建时读取已确认的大厅角色选择 | 普通商店 subtype 只升级一次；仅作用于已限定的原版商店调用点，不把队友都变成里店长 |
| 店长、里店长：恶魔房购买 | 在权威拾取碰撞前，以实际买家名单调用原版价格计算；本机显示也按本机买家计算 | 店长使用金币，其他角色使用血量；只处理启用自动定价的恶魔房道具，不覆盖免费或自定义固定价。Lua 入口为 [`keeper.lua`](https://github.com/BMingSY/isaac-lan/blob/main/src/bridge/compat/characters/keeper.lua) |
| 里游魂：道具生成 | 原版攻击性标签过滤、品质 0／1 道具的五分之一重抽读取完整队伍 | 主机生成并同步结果，分房后继续影响公共生成；不重写物品池公式、种子或个人库存 |
| 里游魂：神圣卡生成 | 原版允许特殊卡时的十分之一神圣卡替换读取完整队伍 | 补齐原版 `GetCardEx` 内联名单查询；不强制每张卡都变成神圣卡。反汇编依据见[生成特性参考](https://github.com/BMingSY/isaac-lan/blob/main/docs/tainted-lost-item-generation.md) |

## 身体替换、双角色与随行实体

| 角色／效果 | 额外处理 | 清理与边界 |
| --- | --- | --- |
| 里拉撒路：Flip 切换生／死身体 | [`lazarus.lua`](https://github.com/BMingSY/isaac-lan/blob/main/src/bridge/compat/characters/lazarus.lua) 解析权威形态，后端以原版替换入口切换既有身体 | 不用 `ChangePlayerType` 在旧身体上另造备份；核对控制器及期望类型，替换后重绑对象，删除旧实体身份对应的移动与库存缓存 |
| 里拉撒路＋长子权：双身体入列与交换 | 客机依据权威名单，将原版已有备份身体登记为双角色；原生交换使用完整名单中的全局索引 | 不额外分配备份身体；房间作用域退出时把交换结果合回完整名单，避免跨房索引错位。能力与所有权维护在 [`rooms.cpp`](https://github.com/BMingSY/isaac-lan/blob/main/src/engine/versions/j460/rooms.cpp) |
| 里雅各：暗以扫跨房跟随 | 迁移时从敌人列表中识别暗以扫，通过玩家引用、父体／生成者关系确定归属；目标新房完成初始化后再插入 NPC | 房间存档丢失原生归属引用时，仅在源房恰有一名可确定的里雅各且暗以扫无其他归属时重绑；多人归属不明确时不猜测 |
| 雅各与以扫、遗骸与灵魂等同控制器角色 | 房间迁移、名单恢复与本机视图保留同一参与者的关联身体；视图分别提供逻辑角色 ID | 属于通用多身体支持，不逐项改写角色能力；本机界面必须遍历 `GetLocalPlayers()`，不能假设只有一人。身份契约见[公开 API](https://github.com/BMingSY/isaac-lan/blob/main/docs/third-party-mod-integration.md#本机视图与身份) |

## 角色私有资源与变身

| 角色／效果 | 额外处理 | 生效范围与边界 |
| --- | --- | --- |
| 里 ???：便便法术队列 | [`blue_baby.lua`](https://github.com/BMingSY/isaac-lan/blob/main/src/bridge/compat/characters/blue_baby.lua) 采集便便法力和 6 个法术的顺序，由受限原生能力恢复绝对值 | 不调用 `UsePoopSpell`，不重复消耗或生成法术；仅该角色且非合作幽灵时采集 |
| 里该隐／任意合成袋持有者 | 独立同步袋内 8 个材料与权威预览道具，在库存后恢复原版 HUD 数据 | 匹配四个主动槽中的合成袋，不限定角色；失去道具时清理旧显示，幽灵隐藏库存由原版持有。详情见[合成袋记录](https://github.com/BMingSY/isaac-lan/blob/main/docs/item-effect-compatibility.md#库存口袋槽与药丸) |
| 伯大尼／里伯大尼等角色的灵魂充能、鲜血充能 | [`inventory.lua`](https://github.com/BMingSY/isaac-lan/blob/main/src/bridge/sync/inventory.lua) 通用库存保存并恢复这两类资源 | 不为角色重放主动道具使用；资源同步不表示第三方角色的任意私有计数都可恢复 |
| 白火临时游魂形态 | 通用库存单独同步 `ID_LOST_CURSE` 空效果层数，主机仍执行原版触碰与清房恢复 | 与合作幽灵分开；客机按权威结果增加／移除该空效果，不重复触碰白火。应用在 [`inventory.lua`](https://github.com/BMingSY/isaac-lan/blob/main/src/bridge/sync/inventory.lua) |
| 死亡后的合作幽灵与复活 | 客机通过原版幽灵转换／复活入口恢复身体；跨房 Boss 复活查询包括其他房间的在线幽灵，普通队伍转场携带幽灵 | 转换在角色所属房间内执行；隐藏库存不通过普通道具增删重建，金币／炸弹／钥匙仍恢复公共值。道具复活另见[相关记录](https://github.com/BMingSY/isaac-lan/blob/main/docs/item-effect-compatibility.md#复活随行与本机演出) |

## 角色目录与第三方角色

大厅目录读取原版菜单配置、肖像和可选择性，原版角色按各端个人解锁／资源判断。伊甸续玩恢复已存在身体时，目录中的解锁判断允许已消耗的令牌，不为新开局凭空补充令牌。第三方角色沿用原版 Mod 角色轮的父子／里角色配对，不另造角色黑名单。实现见 [`characters.cpp`](https://github.com/BMingSY/isaac-lan/blob/main/src/engine/versions/j460/characters.cpp)。

目录中能选择某个 Mod 角色，只说明已读取原生定义；其 Lua 私有状态、特殊回调和内容 ID 仍遵循[第三方接入边界](https://github.com/BMingSY/isaac-lan/blob/main/docs/mod-compatibility.md#安装与通用边界)，不能据此判断该角色玩法已完整兼容。

## 回归入口与证据

| 范围 | 离线回归 | 实机夹具／既有记录 |
| --- | --- | --- |
| 店长、公共生成特性 | [`keeper.lua`](https://github.com/BMingSY/isaac-lan/blob/main/tests/keeper.lua)、[`core_test.cpp`](https://github.com/BMingSY/isaac-lan/blob/main/tests/core_test.cpp) 的队伍规则 | [`state_party_compat.lua`](https://github.com/BMingSY/isaac-lan/blob/main/tests/state_party_compat.lua)、[`state_item_generation.lua`](https://github.com/BMingSY/isaac-lan/blob/main/tests/state_item_generation.lua)、[队伍专项记录](https://github.com/BMingSY/isaac-lan/blob/main/docs/history/party-compatibility-validation.md) |
| 里拉撒路、长子权与分房多身体 | [`actor_forms.lua`](https://github.com/BMingSY/isaac-lan/blob/main/tests/actor_forms.lua)、[`core_test.cpp`](https://github.com/BMingSY/isaac-lan/blob/main/tests/core_test.cpp) 的身体置换规则 | [`state_lazarus_mines.lua`](https://github.com/BMingSY/isaac-lan/blob/main/tests/state_lazarus_mines.lua)、[`state_characters.lua`](https://github.com/BMingSY/isaac-lan/blob/main/tests/state_characters.lua)、[已报问题回归](https://github.com/BMingSY/isaac-lan/blob/main/docs/history/issue-regressions.md) |
| 角色资源、白火与幽灵 | [`poop.lua`](https://github.com/BMingSY/isaac-lan/blob/main/tests/poop.lua)、[`shared_resources.lua`](https://github.com/BMingSY/isaac-lan/blob/main/tests/shared_resources.lua)、[`replica_pipeline.lua`](https://github.com/BMingSY/isaac-lan/blob/main/tests/replica_pipeline.lua) | [`state_white_fire.lua`](https://github.com/BMingSY/isaac-lan/blob/main/tests/state_white_fire.lua)、[`state_ghost.lua`](https://github.com/BMingSY/isaac-lan/blob/main/tests/state_ghost.lua)、[已报问题回归](https://github.com/BMingSY/isaac-lan/blob/main/docs/history/issue-regressions.md) |
| 原版／Mod 角色目录 | [`test_character_catalog_runner.py`](https://github.com/BMingSY/isaac-lan/blob/main/tests/test_character_catalog_runner.py)（测试运行器） | [`character_catalog_test.cpp`](https://github.com/BMingSY/isaac-lan/blob/main/tests/character_catalog_test.cpp)、[`state_character_catalog.lua`](https://github.com/BMingSY/isaac-lan/blob/main/tests/state_character_catalog.lua) |

夹具存在不等于所有角色组合已通过；执行命令与集中验收约定见[开发与测试](https://github.com/BMingSY/isaac-lan/blob/main/docs/development-and-testing.md)，具体通过、失败及未覆盖项以各轮记录为准。
