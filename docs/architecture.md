# 架构与技术选择

## 整体结构

Isaac LAN 在游戏进程中加载原生 DLL，并嵌入 Lua 桥接代码。房主运行原版玩法逻辑，客机提交操作、接收状态并显示自己的房间。

```mermaid
flowchart LR
    CI[客机原生输入] --> CT[客机 Session]
    CT -->|输入和操作请求 · TCP| HT[房主 Session]
    HI[房主原生输入] --> HT
    HT --> HR[原生游戏与分房模拟]
    HR --> HS[Lua 状态采集]
    HS -->|按客机房间生成状态| HT
    HT -->|状态和可靠事件 · TCP| CT
    CT --> CR[客机状态应用]
    CR --> CP[移动预测与原生显示]
    HR --> HP[房主本机显示]
```

客机的状态包包含全队角色的主要状态、楼层地图和本机所在房间的实体、网格与表现。不同客机可以收到不同房间的视图。

## 状态同步

采用房主权威状态同步，避免各进程必须保持完整随机序列和执行顺序一致。客机应用房主状态，校验只检查数据格式、传输完整性和应用条件。

代价是状态处理与带宽开销。客机移动使用本机预测，伤害和道具效果仍等待房主结果。

## 原生集成

原生挂钩管理游戏更新、房间对象、输入、镜头和过场，Lua 桥接读取和应用实体状态。房间生成、战斗、道具效果、存档和多人 HUD 复用原版。

`winmm.dll` 自动加载 `isaac_lan_probe.dll`。桥接 Lua 在构建时嵌入 DLL。

## 网络传输

采用 IPv4 TCP、非阻塞套接字和 `TCP_NODELAY`，默认端口为 29506。利用有序交付处理状态分块、换层和检查点事务。

尚未开始发送的旧视图可由新视图替换；可靠事务保留顺序。已入队数据和 TCP 重传仍可能增加延迟。

## 模块边界

| 模块 | 职责 |
| --- | --- |
| [`loader.cpp`](../src/loader.cpp)、[`probe.cpp`](../src/probe.cpp) | 自动加载、启动校验、原生挂钩与 Lua API 绑定 |
| [`game_build.cpp`](../src/game_build.cpp) | 游戏版本、PE 布局和挂钩入口校验 |
| [`lan_session.cpp`](../src/lan_session.cpp)、[`net_protocol.h`](../src/net_protocol.h) | 连接、协议、消息队列、输入、状态和可靠事务 |
| [`runtime_net.cpp`](../src/runtime_net.cpp) | 将网络会话接到游戏更新、状态桥接、换层和存档生命周期 |
| [`bridge/state.lua`](../src/bridge/state.lua) | 状态字段、序列化、实体视图应用与移动预测 |
| [`engine_rooms.cpp`](../src/engine_rooms.cpp) | 原生房间上下文、分房更新、角色迁移与本机视图 |
| [`engine_input.cpp`](../src/engine_input.cpp) | 控制器归属、网络输入、按键边沿与本机 UI 输入 |
| [`engine_visuals.cpp`](../src/engine_visuals.cpp)、[`engine_audio.cpp`](../src/engine_audio.cpp)、[`engine_presentation.cpp`](../src/engine_presentation.cpp) | 原生精灵、音效、音乐及 Boss 播报的同步与归属 |
| [`engine_save.cpp`](../src/engine_save.cpp)、[`engine_rewind.cpp`](../src/engine_rewind.cpp) | 原生存档序列化和全队回退 |
| [`frontend.cpp`](../src/frontend.cpp)、[`bridge/menu.lua`](../src/bridge/menu.lua) | 官方／局域网入口、原生风格菜单、本机 HUD 和 Ping 显示 |

游戏对象、Lua 调用和网络轮询都在游戏主线程处理。

## 当前边界

- 引擎地址与布局针对 Windows 32 位忏悔＋ `v1.9.7.17.J460`。升级游戏需要重新核对入口和对象布局。
- 联机扩展指纹和协议版本必须一致；其他 Mod 的差异只做提示。
- 第三方 Mod 的内部 Lua 表和私有数据没有通用同步机制。玩法以房主为准，本机界面使用本机上下文。
- 房主不能迁移；整场联机续玩要求原人数、原加入顺序。运行中的客机重连使用保留的玩家标识。

协议细节见[网络与状态同步](synchronization.md)，房间和表现的边界见[分房模拟与本机显示](rooms-and-presentation.md)。
