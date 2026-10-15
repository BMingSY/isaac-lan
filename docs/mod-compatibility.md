# 第三方 Mod 额外兼容记录

本表记录当前 `main` 内置的自动适配器、精确目标和已知边界。注册、主机动作与适配器开发契约见[第三方接入 API v1](https://github.com/BMingSY/isaac-lan/blob/main/docs/third-party-mod-integration.md)。实现统一位于 [`compat/mods/`](https://github.com/BMingSY/isaac-lan/tree/main/src/bridge/compat/mods)，不修改上游 Mod 源码。

## 安装与通用边界

| 使用方式 | 安装约定 |
| --- | --- |
| Stats+ 属性面板、EID 基础说明 | 需要显示的一端安装；房主不必安装相同界面 Mod |
| GoodTrip 地图界面 | 需要操作的一端安装；房主处理器随 LAN 提供，可独立关闭传送能力 |
| 添加道具、角色、实体、房间或资源的内容 Mod | 各端仍需一致的内容定义、资源和 ID 映射 |
| 主动接入第三方玩法动作 | 房主必须注册兼容业务版本的处理器并允许该动作；客机界面只提交意图 |

通用本机视图为界面提供自己的房间与角色，但不会清除 Mod 已有缓存，也不会自动复制 `GetData()`、配置、存档扩展或资源。全局换房／更新回调的本机作用域不等于为每个房间运行全部第三方玩法逻辑，见[Mod 回调与输入](https://github.com/BMingSY/isaac-lan/blob/main/docs/rooms-and-presentation.md#mod-回调与输入)。没有专项适配器的 Mod 不因此被判为不兼容，也不因此获得完整兼容保证。

自动安装需要实际启用的 `RegisterMod` 实例、匹配的注册名称、创意工坊 ID、元数据版本、源码指纹及运行时探测。目录存在、残留全局、同名或版本相同均不足以匹配。Mod 差异提示不会自动检测或阻止所有内容定义冲突。

## 当前支持配置

三种适配器的 `adapterVersion` 均为 `1`；下表是代码中的完整目标配置。`metadataVersion` 来自 `metadata.xml`，与 Lua 运行时自报版本可能不同，不能只按界面版本号判断。

| Mod／注册名称 | 适配器 ID | 创意工坊 ID | 元数据版本 | 额外运行时探测 |
| --- | --- | --- | --- | --- |
| Stats+／`stats-plus` | `isaac-lan.compat.stats-plus` | `2729900570` | `2.1.3` | 等待玩家服务、API、属性观察器、容器和生命周期模块；核对指定方法 |
| GoodTrip 原版／`goodtrip` | `isaac-lan.compat.goodtrip` | `1630477831` | `1.2.8` | `gt` 必须为目标实例，传送与地图生命周期入口齐全；安装时检查原版 `player` 缓存 |
| EID／`External Item Descriptions` | `isaac-lan.compat.eid` | `836319872` | `5.23` | `EID` 为目标实例；`ModVersion="5.24"`，`ModVersionCommit="980bb0b"`，显示入口齐全 |
| EID／`External Item Descriptions` | `isaac-lan.compat.eid` | `836319872` | `5.24` | `EID` 为目标实例；`ModVersion="5.25"`，`ModVersionCommit="d7aab88"`，显示入口齐全 |

每条配置还必须匹配以下 SHA-256：

| 配置 | `sourceHash` |
| --- | --- |
| Stats+ 2.1.3 | `f9bce56542b60f8f0291cf1fb6d85c059c87f841e1efa7b82ecef794e4a3bab2` |
| GoodTrip 原版 1.2.8 | `57a2525436aac726053e9f465667090a9b4a68e150c19285a51dc035a6397858` |
| EID 元数据 5.23 | `8f2614a6a4cd58d60345dd0a33072a0bc7822ecf06ad9106234a6a9b2380b3fc` |
| EID 元数据 5.24 | `705a61422ffc09c683d4250dedf2a569b6d76d4eee884dec70b705eedfa898f5` |

指纹算法与配置文件排除规则见 [API 的自动兼容注册](https://github.com/BMingSY/isaac-lan/blob/main/docs/third-party-mod-integration.md#自动兼容注册)。修改过的源码、新上游版本和 GoodTrip Fixed 等其他分支需要独立支持记录，当前不会强行安装。

## Stats+

实现：[`stats_plus.lua`](https://github.com/BMingSY/isaac-lan/blob/main/src/bridge/compat/mods/stats_plus.lua)。

| 问题／效果 | 适配行为 | 边界 |
| --- | --- | --- |
| 玩家服务缓存完整合作名单 | 服务来源改为本机角色，并过滤旧缓存中的远端玩家；对象、人数或序号变化时通过原版生命周期服务重建 | 本机序号从 0 开始，保留雅各与以扫等双角色布局，不改变权威角色名单 |
| 客机不重放 `MC_EVALUATE_CACHE` | 每次 `ViewUpdated` 使用原版属性观察器读取已同步的原生属性 | 不伪造道具使用或缓存事件；渲染、更新、初始化及相关缓存回调在本机视图运行，队友缓存回调不进入本机 Provider |
| 射速上限 Provider 会临时增删道具 | LAN 中返回 `UNKNOWN` 并隐藏该项 | 防止本机界面刷新触发玩法；单机沿用原 Provider |
| D8 历史倍率缺少权威使用历史 | LAN 中隐藏该项 | 不用默认历史冒充真实倍率；普通属性及可安全计算的派生倍率继续按本机角色显示 |

`StateReset`、本机角色变化以及原生包装对象变化均由适配器处理；使用 `GetPtrHash` 比较身份，避免每次新建 Lua 包装对象就重建服务。

## GoodTrip

实现分为本机入口 [`client.lua`](https://github.com/BMingSY/isaac-lan/blob/main/src/bridge/compat/mods/goodtrip/client.lua) 与主机规则 [`authority.lua`](https://github.com/BMingSY/isaac-lan/blob/main/src/bridge/compat/mods/goodtrip/authority.lua)。主机能力加载不依赖原 Mod 是否安装，也不等待联机会话开始。

| 问题／效果 | 适配行为 | 边界 |
| --- | --- | --- |
| 地图 UI 直接传送并产生副作用 | 在原传送函数执行前提交 `travel` v1 主机动作；等待最终到达结果 | 主机自己的操作也走相同队列；失败使用原界面的失败反馈，不在客机回退执行旧传送 |
| 目标与费用需由主机判定 | 读取实际请求角色和房间，检查源／目标清房、已访问、维度、隐藏地图、封闭挑战／小 Boss 房、追逐、Mom 限制和挑战房血量 | 不信任载荷中的玩家编号、费用或客户端房间快照；冷却为 45 tick |
| 诅咒房代价与免伤条件 | 按原版 GoodTrip 规则检查飞行、扁锉、以撒的心脏、牙和钉；初始迁移接受后只扣一次代价 | 死亡或路径中断返回单独结果；已经扣除的代价不因取消自动撤销。这些道具检查只属于 GoodTrip 路径规则 |
| 秘密房路径 | 从权威门与实际移动记录入口，必要时逐段迁移 | 缺少所需路径信息时拒绝 `secret_path_unknown`；固定目标不再次运行迷宫随机选房，也不全局移除诅咒 |
| 本机缓存、快捷重开与演出 | 换房／角色变化更新本机缓存；显示前仅在缓存失效时重新 `prep`；LAN 中关闭原快捷重开 | 不逐帧重建有效地图；使用 LAN 原生传送表现，不同步原界面动画配置 |
| 首份 LAN 视图前失败／退回单机 | 恢复原版玩家零缓存，继续原生 UI | 不让残留的空 LAN 缓存阻断普通单人游戏 |

适配入口不会为同一次点击再生成旧 `RoomRequest`；原生过门、其他 Mod 的通用房间请求与道具迁移入口仍由各自通道处理。

## EID（External Item Descriptions）

实现：[`eid.lua`](https://github.com/BMingSY/isaac-lan/blob/main/src/bridge/compat/mods/eid.lua)。

| 问题／效果 | 适配行为 | 边界 |
| --- | --- | --- |
| 基础说明读取合作名单与当前房间 | 原版显示路径在本机视图运行，`setPlayer()` 更新本机玩家、合作列表与控制器列表 | 保留原版输入、距离、可见性、说明注册和布局，不新增重复绘制回调；队友道具不混入基础合作列表 |
| 换房／重建后的旧描述目标 | 清除描述目标、说明缓存和指示器，在视图提交时重新选择本机角色 | 保留本机语言、字体与配置 |
| LAN 视图未提交时到达原生生命周期回调 | 延后实际发生的开局／换房／换层回调，同一回调合并为最新参数，待视图就绪执行一次 | 保留沙漏所需的原版初始化；不积压逐帧显示与更新回调 |
| 普通单人和继续游戏 | 未处于 LAN 会话时直接执行原逻辑 | 不等待不存在的 LAN 视图；退出 LAN 后恢复原生玩家选择 |

Flip 隐藏事实、动态 `EID_Description`、合成与随机预测没有新增权威数据通道，不能据此声称全部高级功能已完整兼容。静态说明仍需本机安装说明注册代码；内容 ID 一致性由各端的内容 Mod 安装保证。

## 状态、开关与卸载

可在自己的调试代码中查询状态；这不是新增游戏内菜单：

```lua
local api = rawget(_G, "IsaacLAN")
if api and api.API_VERSION == 1 then
    for _, entry in ipairs(api:GetCompatibilityStatus()) do
        Isaac.DebugString(entry.id .. ":" .. entry.state .. ":" .. (entry.reason or ""))
    end
end
```

`active` 表示身份匹配、运行时探测和安装完成，不等于全部功能已通过验收。GoodTrip 的 `authority=true` 表示独立处理器已经注册，可能与本机 UI 是否探测到无关。状态字段和错误返回见 [API 状态契约](https://github.com/BMingSY/isaac-lan/blob/main/docs/third-party-mod-integration.md#兼容状态与开关)。

`IsaacLAN:SetCompatibilityEnabled(id, false)` 持久关闭本机某个适配器，保存到游戏目录的 `integrations.ini`；也会移除其独立能力。主机仅想禁止传送并保留自己的 GoodTrip UI 时，调用 `IsaacLAN:SetActionEnabled("isaac-lan.compat.goodtrip", "travel", false)`，此动作开关只在当前 Lua 环境生效。

目标 Mod 主动 `RegisterMod` 接入 API 时，注册器让出该实例；停用或安装失败会执行已登记清理、撤回仍由本适配器持有的方法修改并注销句柄。回调包装保留原优先级、参数、顺序及返回值；重连不重复安装。主机独立能力与 UI 安装分别管理。

## 验证范围

| 类型 | 入口／证据 | 能说明的范围 |
| --- | --- | --- |
| 离线 API 与适配器 | [`bridge_api.lua`](https://github.com/BMingSY/isaac-lan/blob/main/tests/bridge_api.lua) | 身份与视图、事件、注册／清理、主动接入优先、Stats+／EID／GoodTrip 包装与版本不匹配 |
| 离线主机路线 | [`goodtrip_rules.lua`](https://github.com/BMingSY/isaac-lan/blob/main/tests/goodtrip_rules.lua) | 特殊房间规则、一次扣费、死亡取消、迷宫固定目标与秘密房分段到达 |
| 真实网络通道 | [`net_test.cpp`](https://github.com/BMingSY/isaac-lan/blob/main/tests/net_test.cpp) 的 `integrations` | 发送者绑定、可靠顺序、不合并请求、结果范围、限额与重连代次 |
| 双实例 Mod 缓存／界面 | [`state_mod_integrations.lua`](https://github.com/BMingSY/isaac-lan/blob/main/tests/state_mod_integrations.lua)、[`state_mod_ui.lua`](https://github.com/BMingSY/isaac-lan/blob/main/tests/state_mod_ui.lua) | 真实本机玩家缓存、双角色序号与 ID、原生地图输入、客机请求去重和到达 |

2026-10-08 的既有双实例验证使用 75 ms 单向附加延迟，覆盖仅客机安装三种 Mod、两端安装并用原生地图输入、两端均为雅各与以扫；双角色检查各自两人的缓存、显示序号和逻辑 ID，客机传送后主机仍留原房间。

后续 EID 5.25 支持、普通沙箱单人→联机→继续单人、Stats+ 本机缓存的实机结果见[已报问题回归](https://github.com/BMingSY/isaac-lan/blob/main/docs/history/issue-regressions.md)；EID 沙漏回调延后及 GoodTrip 缓存恢复见[支线与回退回归](https://github.com/BMingSY/isaac-lan/blob/main/docs/history/side-route-regressions.md)，分层后双端集成结果见[分层回归](https://github.com/BMingSY/isaac-lan/blob/main/docs/history/layer-refactor-validation.md)。保留各轮失败和未覆盖项，不把指纹记录或离线通过当作未知上游版本的实机证明。安装组合与执行命令见[开发与测试](https://github.com/BMingSY/isaac-lan/blob/main/docs/development-and-testing.md)。
