# 错误道具定义与库存

错误道具的负编号只在当前进程的动态注册表中有效。同步底座编号和普通背包不足以在客机重建效果，同步契约使用有序生成种子，在房间、实体和背包恢复之前重建定义。双方须使用相同游戏版本和扩展构建，不能用种子表实现跨版本混联。

## 原生边界

[共享定义组件](https://github.com/BMingSY/isaac-lan/blob/main/src/engine/versions/common/generated_items.cpp) 通过版本绑定访问注册表与库存，不分配或复制原生配置、字符串、效果列表和纹理。这些对象及其保存／继续生命周期均由游戏持有。

| 字段或入口 | J511 | J835 |
| --- | --- | --- |
| 注册表指针向量 | `Game+0x67758` | `Game+0x283c20` |
| 生成函数 RVA | `0x5f49a0` | `0x532980` |
| 原生恢复的 CALL 位置 RVA | `0x5f802b` | `0x535cbb` |
| 玩家数量树头指针／大小 | `+0x1fcc/+0x1fd0` | `+0x1ec4/+0x1ec8` |
| 版本绑定 | [J511](https://github.com/BMingSY/isaac-lan/blob/main/src/engine/versions/j511/generated_items.cpp) | [J835](https://github.com/BMingSY/isaac-lan/blob/main/src/engine/versions/j835/generated_items.cpp) |

生成函数均为 `thiscall int(registry*, uint32 seed, uint32 flags)`，清理八字节栈参数。原生注册表最多 1024 项，编号为 `~index`，即 `-1…-1024`。条目 `+0` 指向 ItemConfig，`+8` 保存规范化种子，ItemConfig `+4` 保存编号。原生恢复调用按序传入规范化种子与 `flags=0`。程序身份和适用范围见 [J511](https://github.com/BMingSY/isaac-lan/blob/main/docs/native-backend.md)／[J835](https://github.com/BMingSY/isaac-lan/blob/main/docs/native-backend-j835.md) 后端参考。

`generated_items()` 采集、`generated_items(bytes)` 恢复定义。载荷最多 4096 字节，先检查长度、非零种子和已有前缀，再依次调用原生生成器追加缺少的后缀；重复快照不重复生成，冲突、倒退或生成失败终止会话。失败不提供原生对象回滚，不自行清空或释放已经存在的定义。

客机房间初始化可能自行抽取道具，生成拦截暂用普通道具编号，随后由权威快照覆盖；原生存档恢复的精确返回点保留。Hook 安装失败只撤销本组件创建的 Hook 并清除旁路，可重试；重复安装不替换原始调用入口。

`HasCollectible` 的负编号分支读取玩家的原生数量树。节点左／父／右指针为 `+0/+4/+8`，空节点标志为 `+0xd`，编号／数量为 `+0x10/+0x14`。`generated_item_count(sprite, id)` 仅接受当前原生名单中的玩家精灵，验证包装、负编号、向量边界与对齐、树大小、节点与遍历上限，读取真实数量；不分配、修改或释放树节点。J511 `GetCollectibleNum` 对负编号返回零，因此不能替代该查询。

随机效果派发入口接收负道具编号、玩家、事件编号、关联实体、位置和速度六个借用参数。单人和房主执行效果，客机接收权威结果。

## 同步与生命周期

客机先恢复定义，再恢复引用该定义的底座和库存。游戏以无符号 32 位数提供底座的 `SubType`。如果新底座被 TMTRAINER 替换成占位道具，兼容组件将编号还原为负数，调用 `EntityPickup:Morph` 绑定本机生成的图像，保留价格和种子并跳过道具修饰。随后应用房主的底座状态和动画。同一底座收到后续快照时复用已绑定的图像。原生存档负责保存和继续游戏时的定义恢复。

Lua 的道具池接口不能按原生注册表顺序恢复指定定义，现有静态库存枚举也不包含负编号。特殊定义适配位于 [glitched.lua](https://github.com/BMingSY/isaac-lan/blob/main/src/bridge/compat/items/glitched.lua)，通用库存通过注入的额外编号列表采集和应用；背包仍通过原生 AddCollectible／RemoveCollectible 应用差量，避免重复快照反复添加被动效果。

错误技的共享效果与验证状态见[道具清单](https://github.com/BMingSY/isaac-lan/blob/main/docs/item-effect-compatibility.md)。其他道具的原生接口见[后端参考](https://github.com/BMingSY/isaac-lan/blob/main/docs/native-backend.md#道具与效果)，专项入口见[开发与测试](https://github.com/BMingSY/isaac-lan/blob/main/docs/development-and-testing.md#开发专项入口)。
