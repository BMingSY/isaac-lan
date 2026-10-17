# 全队共享恶魔房／天使房概率

恶魔房和天使房的概率属于整队。房主使用全队的原版道具、饰品、受击、交易和楼层历史计算；客机使用房主的计算结果。玩家分处不同房间时也适用。增加和降低都影响同一份概率，多个玩家的 HUD 百分比不会直接相加。

保留原版的叠加和优先级：例如多个五芒星可以增加原版允许的额外概率，重复羊头和相同钥匙碎片不会凭空叠加；圣体、忏悔书、美德之书及楼层天使修正仍按原版判定。房间类型已经被原版确定后，不重新抽签或改写已有房间。星象房概率不属于该共享机制。

## 模块与同步契约

- [`src/bridge/sync/deals.lua`](https://github.com/BMingSY/isaac-lan/blob/main/src/bridge/sync/deals.lua) 采集、校验和应用整队概率；[`app/world.lua`](https://github.com/BMingSY/isaac-lan/blob/main/src/bridge/app/world.lua) 仅装配组件。顶层第 19 项为 `deals = { total, angel }`。`total` 是原版总开门概率，可超过 1；`angel` 是原版条件天使房概率，范围 0–1。通常显示的恶魔／天使概率分别为 `min(total, 1) * (1 - angel)`、`min(total, 1) * angel`；原版仍处理不允许开门的楼层和双重性显示。
- [`src/compat/items/deal_chances.h`](https://github.com/BMingSY/isaac-lan/blob/main/src/compat/items/deal_chances.h) 接收各原版查询的普通浮点数，合并跨房间效果；同一份全队库存与楼层惩罚不会因查询多个房间而被重复累加。
- 客机在库存应用后保存该结果。原版 HUD 的两个概率查询读取同一份已应用结果，客机不因本地受击记录或道具恢复副作用自行重算。楼层屏障、新局和原生楼层清理清空缓存；旧代次状态不能应用到新楼层。
- 只同步两个浮点数，不逐个同步概率道具或复制道具给房主。协议、schema 和指纹要求统一见[同步契约](https://github.com/BMingSY/isaac-lan/blob/main/docs/synchronization.md#校验与失败边界)。

## 必要的原生能力

现有 Lua API 不能让实际恶魔／天使房生成临时读取分房后的完整玩家名单，也不能覆盖原版 Found HUD 使用的内部条件天使概率。因此在 J460 后端提供具名 `deal_chances()` 查询／应用与 `deal_chances_reset()` 清理能力，原版查询在限定的上下文中执行，公式与战斗模拟名单仍由原版管理。

适用 J460，游戏标识见[后端参考](https://github.com/BMingSY/isaac-lan/blob/main/docs/native-backend.md)。原生入口如下：

| 入口 | RVA | 用途与 ABI |
| --- | --- | --- |
| `Room::GetDevilRoomChance` | `0x3f92b0` | Lua 公开查询、HUD 和实际开门共用；`thiscall`，x87 返回 |
| 原版条件天使概率查询 | `0x3f96f0` | HUD 与房间类型初始化共用；无参数，XMM0 返回 |
| `Level::InitializeDevilAngelRoom` | `0x3499a0` | 决定实际生成类型；`thiscall(bool, bool)` |
| `Room::TrySpawnDevilRoomDoor` | `0x3f83b0` | 原版清房开门及公开 API；`thiscall(bool, bool)` |

四个入口均受启动签名校验。条件天使查询的 SSE 返回约定由后端桥接，普通 C++／Lua 浮点接口使用正常 ABI，返回边界须正确转换 x87 与 XMM0。

具名查询、HUD 和实际生成使用同一原生计算入口。未启用联机会话时保持单人规则。

概率查询和房间类型初始化短暂借用现有 `TeamScope` 的完整名单，退出后恢复原来房内名单；不移动角色，不运行额外实体更新，不分配或释放原生对象。实际开门只在房主执行。

原版额外的 Boss 房红心受击惩罚依赖当前房间。查询时，如果已加载本层原版指定的最终 Boss 房，短暂借用其 Room 指针、房间索引和维度，随后恢复，确保玩家走出 Boss 房不会隐藏该惩罚。只读取既有房间，不加载 Boss 房、不消耗生成 RNG、不改写受击记录。其余受击、交易、乞丐和捐款等楼层状态沿用房主已有的全局原版状态。

原版部分临时保证开门效果保存在 Room 中。用相同的全队／Boss 惩罚上下文查询已有房间对象，取原版已经计算的最大总概率，从而让异房保证效果也对整队生效；不把同一效果相加，不复制效果，不延长原版对象生命周期。该处理仅适用于原版总概率查询已经识别的房间效果。

API 仅允许客机写有限、非负且可表示为 float 的总概率和 0–1 的条件天使概率，先整体校验后更新一对值，不允许房主接收客机概率。缓存只保存数值，不保存原生指针。规则依据以实际 J460 调用链为准；[Room Lua API 文档](https://wofsauge.github.io/IsaacDocs/rep/Room.html#getdevilroomchance) 用于核对公开查询的含义，旧 Repentance 的示例公式不直接移植到 Repentance+。
