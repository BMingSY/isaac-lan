# J835 原生接口参考

原版《忏悔》`1.7.9b.J835` 尚无可构建的完整联机后端。[J835 目录](https://github.com/BMingSY/isaac-lan/tree/main/src/engine/versions/j835) 提供版本／资源描述、存档编解码和角色目录组件，以及 Lua 初始化入口资料；房间、会话、输入和实体同步尚未接通。组件可单独参与离线测试，CMake 和版本生成器仍拒绝把它们链接为可安装后端。可构建完整后端为 [J460](https://github.com/BMingSY/isaac-lan/blob/main/docs/native-backend.md)。

目标游戏程序 SHA-256 为 `04469d0c3d3581936fcf85bea5f9f4f3a65b2ccf96b36310456c9626bac36dc6`，架构为 Windows x86。版本标记、PE 节区、Lua DLL 和资料目录以 [profile.json](https://github.com/BMingSY/isaac-lan/blob/main/src/engine/versions/j835/profile.json) 为准。两端须使用相同游戏和扩展构建，不能与忏悔＋混联。

`LuaEngine::Init` 为 `thiscall void(LuaEngine*, bool)`，入口和签名位于 [entrypoints.h](https://github.com/BMingSY/isaac-lan/blob/main/src/engine/versions/j835/entrypoints.h) 与 [signatures.inc](https://github.com/BMingSY/isaac-lan/blob/main/src/engine/versions/j835/signatures.inc)。初始化完成后的 Lua 状态指针位于 `LuaEngine + 0x18`，只可借用；状态的创建、重置和销毁仍由游戏持有。初始化可能在同一进程内重复发生，不能将先前状态的引用、注册表键或回调复用于新状态。该入口资料不授权其他布局读写，也不代表完整 ABI 验收。

Lua ABI 为 5.3，符号加载复用 [lua_api.h](https://github.com/BMingSY/isaac-lan/blob/main/src/engine/lua_api.h)。该游戏导入表没有 `SteamAPI_RestartAppIfNecessary`；隔离启动不能把该导入的存在当成必要条件。资料隔离仍须在游戏入口前完成，不能在 Lua 初始化后才更改存档位置。

## 存档与进度

[save.cpp](https://github.com/BMingSY/isaac-lan/blob/main/src/engine/versions/j835/save.cpp) 使用游戏的原生序列化格式，不能读取忏悔＋的存档。`Manager`、`Game` 和 `GameState` 都由游戏持有；后端只在同步调用期间借用对象。入口签名和重定位掩码与其他原生入口一起校验。

| 操作 | J835 ABI | 布局与限制 |
| --- | --- | --- |
| 采集 | `thiscall void(Game*, GameState*)`，RVA `0x2cc850` | 默认目标为 `Manager+0xf34`；包含玩家离房处理，调用方须配对恢复进房临时状态 |
| 清理 | `thiscall void(GameState*)`，RVA `0x520160` | 解码前清理已有原生内容；不替换对象本身 |
| 编码 | `thiscall bool(GameState*, Context*)`，RVA `0x521a00` | 临时流字段为 `GameState+0x1fac8`，输出上限 8 MiB |
| 解码 | `thiscall bool(GameState*, Context*)`，RVA `0x524320` | 仅一个栈参数，被调方清理 4 字节；J460 的额外布尔参数不适用 |

两版共用 [x86 内存流](https://github.com/BMingSY/isaac-lan/blob/main/src/engine/versions/common/save_stream.h)，`Context` 为 28 字节，原生读写回调返回元素个数。流与字节缓冲由扩展持有，不能交给游戏释放；越界寻址、短读、只读流写入和分配失败会使整个操作失败，流指针在返回和 C++ 异常退出时恢复。

原生解码失败处理可能请求删除存档文件。[文件名作用域](https://github.com/BMingSY/isaac-lan/blob/main/src/engine/versions/common/save_file_names.h) 在内存流解码期间临时清空四个本地／Steam 文件名槽，随后逐字节恢复原生字符串和其所有权。文件名偏移在 [layout.h](https://github.com/BMingSY/isaac-lan/blob/main/src/engine/versions/j835/layout.h) 中集中声明。此保护不提供 GameState 内容回滚：失败后会话必须中止恢复，不能把部分加载状态视为完成。

进度位于 `Manager+0x14`；成就数组从 `+0x38` 开始，共 638 字节，计数数组从 `+0x2b8` 开始，共 496 个 uint32。[进度复制组件](https://github.com/BMingSY/isaac-lan/blob/main/src/engine/versions/common/progress.h) 只读写这些元素，共同网络结构的剩余元素补零，不触及相邻收藏记录或按忏悔＋的数组长度访问原版对象。

## 角色目录与表现

[角色目录](https://github.com/BMingSY/isaac-lan/blob/main/src/engine/versions/j835/characters.cpp) 通过原生目录读取角色、里角色及 Mod 角色，复用两版共有的目录算法。原版选择条件入口为 RVA `0x4a1ea0`，`thiscall bool(record*, int)`；翻译入口为 RVA `0x56b880`，使用 `Manager+0x4a234` 的字符串表。选择条件在临时安装本机个人进度和菜单场景后求值，返回时恢复；伊甸继续游戏只临时豁免已经消耗的代币，不更改实际进度。目录只返回复制后的名称、资源路径和可选状态，不持有原生容器。完成标记使用共同的原版事件编号，替代身体映射到对应起始角色。

原版菜单与聊天使用游戏自带的 `font/cjk/lanapixel.fnt`，逻辑字号和缩放由版本描述声明。大厅面板使用两版共有的白色填充 Sprite，角色画像与完成标记沿用游戏资源。没有官方联机、原生表情轮盘或忏悔＋大厅美术时，不显示相关入口，也不加载对应资源。上述表现适配与原生联机后端的可用性独立。

候选入口可以参考 [REPENTOGON 1.0.12e](https://github.com/TeamREPENTOGON/REPENTOGON/tree/1.0.12e/libzhl/functions)，但参考特征码不是当前游戏的 ABI 保证。审计必须保留多重匹配并核对实际调用点、参数、返回值、对象布局与所有权；不把 J460 地址或字段偏移套入 J835。离线与实机边界见[开发与测试](https://github.com/BMingSY/isaac-lan/blob/main/docs/development-and-testing.md)。
