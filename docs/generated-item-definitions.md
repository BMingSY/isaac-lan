# 错误道具定义与房间效果

错误道具的负编号只在当前进程的动态注册表中有效。同步底座编号和普通背包不足以在客机重建效果，因此 schema 20 增加有序生成种子，并在房间、实体和背包恢复之前应用。

## J460 原生边界

适用游戏 SHA-256：`7122ac28779925b24e23e2416f231322b1470388bd25e2c08665ad8d53b3ea4f`。

- `Game + 0x67758` 是生成定义的指针向量，最多 1024 项；编号为 `~index`，即 `-1…-1024`。条目 `+0` 指向 ItemConfig，`+8` 保存规范化种子；ItemConfig `+4` 保存编号。
- 生成函数 RVA `0x5dcc70` 为 x86 thiscall，参数为注册表、种子和标志；原生存档恢复在 RVA `0x5e036b` 调用它，以规范化种子和 `flags=0` 重建定义。
- [`generated_items.cpp`](https://github.com/BMingSY/isaac-lan/blob/main/src/engine/versions/j460/generated_items.cpp) 通过 `generated_items()` 采集和 `generated_items(bytes)` 恢复定义。载荷最多 4096 字节；先检查长度、种子和已有前缀，再依次调用原生生成器。重复快照不重复生成，冲突快照终止会话。
- 客机房间初始化可能自行抽取道具，生成拦截暂用普通道具编号，随后由权威快照覆盖；原生存档恢复调用保留。定义、字符串、效果列表和纹理均由游戏创建和释放，不跨进程复制指针，不自行清理原生注册表。
- Lua 的道具池接口不能按原生注册表顺序恢复指定定义，现有静态库存枚举也不包含负编号。特殊定义适配位于 [`compat/items/glitched.lua`](https://github.com/BMingSY/isaac-lan/blob/main/src/bridge/compat/items/glitched.lua)，通用库存通过注入的额外编号列表采集和应用。
- J460 `GetCollectibleNum` 在 VA `0x770cb3` 对所有负编号直接返回 0。`HasCollectible` 的负编号分支则读取 `Player + 0x1fcc` 的原生数量树（大小位于 `+0x1fd0`，节点编号／数量位于 `+0x10/+0x14`）。`generated_item_count(sprite, id)` 仅接受当前原生名单中的玩家精灵，验证负编号、树大小、节点与遍历上限，读取真实数量；不分配、修改或释放树节点。背包仍通过原生 `AddCollectible/RemoveCollectible` 应用差量，避免重复快照反复添加被动效果。

## 共享与显示

错误技 721 和已激活的达摩剑 656 复用现有 PlayerManager 查询范围，在全队各房间生效。原版达摩剑额外底座查询位于 VA `0x6e0ade`；个人受伤和落剑逻辑继续使用原持有者。未使用的主动道具 577 不提供共享奖励。

小夜灯缺少跨房间渲染筛选和客机光束角度更新。后端只在 Room::Render 的 RVA `0x410dad` 查询点过滤异房持有者；其他 `HasCollectible` 查询仍调用原版。光束角度 `Player + 0x1ae4` 随角色姿态同步，并检查其浮点值有限。没有改变照明的减速等玩法判定。

创世纪的特殊房间描述符可使用 `ListIndex=-12`。布局校验允许特殊房间的列表编号等于其房间编号；普通房间仍限制为非负数组下标，描述符仍由原生查找接口获取。

离线验证覆盖生成器 x86 调用、种子顺序、重复／冲突／损坏快照、负编号道具归属与移除，以及特殊布局编号边界。集中实机入口为 [`run_item_issues.py`](https://github.com/BMingSY/isaac-lan/blob/main/tools/run_item_issues.py)；原生随机效果的全部组合不可能由有限样本穷举，具体种子、结果及失败轮次保留在本次验证记录中。
