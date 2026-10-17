# 错误道具定义与库存

错误道具的负编号只在当前进程的动态注册表中有效。同步底座编号和普通背包不足以在客机重建效果，同步契约使用有序生成种子，在房间、实体和背包恢复之前重建定义。

## J460 原生边界

适用游戏 SHA-256：`7122ac28779925b24e23e2416f231322b1470388bd25e2c08665ad8d53b3ea4f`。

- `Game + 0x67758` 是生成定义的指针向量，最多 1024 项；编号为 `~index`，即 `-1…-1024`。条目 `+0` 指向 ItemConfig，`+8` 保存规范化种子；ItemConfig `+4` 保存编号。
- 生成函数 RVA `0x5dcc70` 为 x86 thiscall，参数为注册表、种子和标志；原生存档恢复在 RVA `0x5e036b` 调用它，以规范化种子和 `flags=0` 重建定义。
- [`generated_items.cpp`](https://github.com/BMingSY/isaac-lan/blob/main/src/engine/versions/j460/generated_items.cpp) 通过 `generated_items()` 采集和 `generated_items(bytes)` 恢复定义。载荷最多 4096 字节；先检查长度、种子和已有前缀，再依次调用原生生成器。重复快照不重复生成，冲突快照终止会话。
- 客机房间初始化可能自行抽取道具，生成拦截暂用普通道具编号，随后由权威快照覆盖；原生存档恢复调用保留。定义、字符串、效果列表和纹理均由游戏创建和释放，不跨进程复制指针，不自行清理原生注册表。
- Lua 的道具池接口不能按原生注册表顺序恢复指定定义，现有静态库存枚举也不包含负编号。特殊定义适配位于 [`compat/items/glitched.lua`](https://github.com/BMingSY/isaac-lan/blob/main/src/bridge/compat/items/glitched.lua)，通用库存通过注入的额外编号列表采集和应用。
- J460 `GetCollectibleNum` 在 VA `0x770cb3` 对所有负编号直接返回 0。`HasCollectible` 的负编号分支则读取 `Player + 0x1fcc` 的原生数量树（大小位于 `+0x1fd0`，节点编号／数量位于 `+0x10/+0x14`）。`generated_item_count(sprite, id)` 仅接受当前原生名单中的玩家精灵，验证负编号、树大小、节点与遍历上限，读取真实数量；不分配、修改或释放树节点。背包仍通过原生 `AddCollectible/RemoveCollectible` 应用差量，避免重复快照反复添加被动效果。

## 同步与生命周期

定义恢复必须先于引用负编号的实体和库存恢复。底座生成规则由道具兼容策略决定，恢复只重建相同定义和数量，不重新触发拾取或使用效果。原生存档拥有生成定义的保存／继续生命周期。

错误技的共享效果与验证状态见[道具清单](https://github.com/BMingSY/isaac-lan/blob/main/docs/item-effect-compatibility.md)。其他道具的原生接口见[后端参考](https://github.com/BMingSY/isaac-lan/blob/main/docs/native-backend.md#道具与效果)，专项入口见[开发与测试](https://github.com/BMingSY/isaac-lan/blob/main/docs/development-and-testing.md#按需专项)。
