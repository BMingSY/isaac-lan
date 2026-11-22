# 原版错误道具挑战环境

[联机挑战45](https://github.com/BMingSY/isaac-lan/blob/main/docs/lan-challenges.md#当前规则1006-挑战45)使用 J511 原生 DELETE THIS 的房间外观和路线判断。挑战目录与运行层持有规则身份，后端只接收布尔启用回调；不修改普通单人挑战或联机选角。

## J511 接口与校验

适用游戏 SHA-256：`024ed7300fbed8b65afa1fdd1e36f20b446ede65dcdda0c8375d0423aa9f078d`。

入口与签名分别注册在 [entrypoints.h](https://github.com/BMingSY/isaac-lan/blob/main/src/engine/versions/j511/entrypoints.h) 和 [signatures.inc](https://github.com/BMingSY/isaac-lan/blob/main/src/engine/versions/j511/signatures.inc)，仅对通过版本及指令校验的映像安装。[generated_challenge.cpp](https://github.com/BMingSY/isaac-lan/blob/main/src/engine/versions/j511/generated_challenge.cpp)在以下五处原生 `Game.Challenge == 45` 比较中选择相等分支，后续随机选择仍使用原生逻辑和楼层种子：

| 能力 | RVA | 游戏指针寄存器 |
| --- | --- | --- |
| 网格样式 | `0x31abb7` | EDX |
| 岩石样式 | `0x321529` | EDX |
| 背景类型 | `0x3f3518` | EDI |
| 背景样式 | `0x3f999f` | EDX |
| 房间配置外观 | `0x5a7d1a` | EDI |

比较长度为 7 字节，续接点为比较之后。包装保留通用寄存器、XMM0–7 和非算术标志；启用时仅替换比较结果对应的算术标志，关闭时保持原生比较。回调不分配或持有游戏对象。

## 路线查询与生命周期

`GeneratedChallengeRewardScope` 在原生清房奖励和结局宝箱查询期间暂借原生挑战45，避免普通存档的路线解锁限制改变挑战终点。宝箱查询 RVA `0x3006d0` 使用 x86 stdcall，接收一个布尔参数并返回整数结局编号；包装原样转发参数和结果。

作用域从当前游戏对象借用 `Game + 0x26584` 的挑战字段，退出时恢复原值，支持嵌套与异常展开。不拥有或释放游戏对象；恢复前重新确认全局游戏对象仍对应原字段地址。作用域外保留联机会话的原生挑战值零，角色、临时会话存档保护及完成事件仍由联机运行层管理。

错误道具生成和随机效果的权威执行边界见[生成定义与库存](https://github.com/BMingSY/isaac-lan/blob/main/docs/generated-item-definitions.md)。测试操作统一见[开发与测试](https://github.com/BMingSY/isaac-lan/blob/main/docs/development-and-testing.md#开发专项入口)。
