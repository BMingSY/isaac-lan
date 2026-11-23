# 原版挑战的清房奖励与房间外观

[联机挑战目录](https://github.com/BMingSY/isaac-lan/blob/main/src/compat/challenges/catalog.h)分别指定房间外观和清房奖励使用的原版挑战。挑战45与「幺幺幺九」借用 DELETE THIS 通往宝箱层的路线，只有挑战45启用错乱房间外观。「捕风捉影」进入暗室前借用 I RULE! 的路线，抵达暗室后由羔羊掉落结局宝箱并转换为联机奖杯。开局、选角和奖杯完成仍由联机会话处理。

## 忏悔＋接口与校验

适用游戏 SHA-256：`024ed7300fbed8b65afa1fdd1e36f20b446ede65dcdda0c8375d0423aa9f078d`。

入口与签名分别注册在 [entrypoints.h](https://github.com/BMingSY/isaac-lan/blob/main/src/engine/versions/repentance_plus/entrypoints.h) 和 [signatures.inc](https://github.com/BMingSY/isaac-lan/blob/main/src/engine/versions/repentance_plus/signatures.inc)，仅对通过版本及指令校验的映像安装。[generated_challenge.cpp](https://github.com/BMingSY/isaac-lan/blob/main/src/engine/versions/repentance_plus/generated_challenge.cpp)在以下五处原生 `Game.Challenge == 45` 比较中选择相等分支，后续随机选择仍使用原生逻辑和楼层种子：

| 能力 | RVA | 游戏指针寄存器 |
| --- | --- | --- |
| 网格样式 | `0x31abb7` | EDX |
| 岩石样式 | `0x321529` | EDX |
| 背景类型 | `0x3f3518` | EDI |
| 背景样式 | `0x3f999f` | EDX |
| 房间配置外观 | `0x5a7d1a` | EDI |

比较长度为 7 字节，续接点为比较之后。包装保留通用寄存器、XMM0–7 和非算术标志；启用时仅替换比较结果对应的算术标志，关闭时保持原生比较。回调不分配或持有游戏对象。

## 路线查询与生命周期

`ChallengeRewardScope` 在原生清房奖励和结局宝箱查询期间暂借目录指定的挑战编号，使楼层出口和结局宝箱遵循该挑战的路线。编号为零时沿用游戏当前值。宝箱查询 RVA `0x3006d0` 使用 x86 stdcall，接收一个布尔参数并返回整数结局编号；包装原样转发参数和结果。

作用域从当前游戏对象借用 `Game + 0x26584` 的挑战字段，退出时恢复原值，支持嵌套与异常展开。不拥有或释放游戏对象；恢复前重新确认全局游戏对象仍对应原字段地址。作用域外保留联机会话的原生挑战值零，角色、临时会话存档保护及完成事件仍由联机运行层管理。

错误道具生成和随机效果的权威执行边界见[生成定义与库存](https://github.com/BMingSY/isaac-lan/blob/main/docs/generated-item-definitions.md)。测试操作统一见[开发与测试](https://github.com/BMingSY/isaac-lan/blob/main/docs/development-and-testing.md#开发专项入口)。
