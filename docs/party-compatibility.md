# 队伍兼容修复

对应 #41、#42、#43、#44、#47、#48、#49、#51、#54。当前传输协议为 29，世界视图 schema 为 16；两端必须使用相同 DLL。此文记录实现边界和当时的协议升级，当前版本契约见[网络与状态同步](https://github.com/BMingSY/isaac-lan/blob/main/docs/synchronization.md)，历次证据见[专项验收](https://github.com/BMingSY/isaac-lan/blob/main/docs/history/party-compatibility-validation.md)。

按效果查询当前兼容范围，见[角色兼容记录](https://github.com/BMingSY/isaac-lan/blob/main/docs/character-compatibility.md)、[道具与效果兼容记录](https://github.com/BMingSY/isaac-lan/blob/main/docs/item-effect-compatibility.md)和[第三方 Mod 兼容记录](https://github.com/BMingSY/isaac-lan/blob/main/docs/mod-compatibility.md)。本页保留原生机制与修复依据。

## 跟班池与实体回收

J460 EntityFactory::Create 的跟班分支在 RVA `0x2f00d7` 使用 64 槽循环池（掩码 `0x3f`、对象步长 `0xf48`），按 `_valid` 检查空槽；Game::Spawn 的默认参数允许池满时覆盖旧槽。原同步先生成新实体、最后才删除旧实体，池满时会覆盖仍被当前视图引用的跟班，随后补实体关系报 `Replica identity missing`，结束客机会话。

[`sync/entities.lua`](https://github.com/BMingSY/isaac-lan/blob/main/src/bridge/sync/entities.lua) 先按实际对象身份保留仍在视图里的实体，删除过期对象，再调用原版 `Room:Update()` 完成回收，之后创建替换对象和补关系。`Remove()` 尚未完成回收时仍占用原生槽，不能只调整 Lua 遍历顺序。跟班初始化可产生额外烟雾并挤占效果池；这一轮被原版回收的瞬时效果跳过补关系，下份权威视图仍需要时重建，其他实体的身份缺失仍报错。原版负责清理引用和释放槽位；同步层不扩容池、不设置原生有效位或接管所有权。离线夹具模拟 64 槽、延迟释放与新实体先到的顺序，并检查重复视图、多轮替换和效果池回收。

## 公共被动效果与店长

[`compat/items/team_effects.h`](https://github.com/BMingSY/isaac-lan/blob/main/src/compat/items/team_effects.h) 统一声明指南针、白地图、打折、蓝地图、黑蜡烛、补货、十字圣球的公共效果。后端只在原版 PlayerManager 的道具查找／数量查询中暂时借用完整队伍名单，退出查询即恢复房间名单；库存、个人属性与主动道具仍属于原持有者。新增公共效果只需扩展此名单，保留原版叠加公式。

原版商店布局生成会直接检查当前名单中的里店长，不能只修复 FindPlayerType 查询。第一层在远端玩家对象创建前生成，使用已确认的大厅角色选择升级商店 subtype；之后使用完整原生名单。RoomConfig::GetRandomRoom 保持原随机种子、12 个参数及返回对象所有权，普通商店 subtype 只加一次 100，限定已核对的商店生成调用点。商店定价的里店长查询同样限定原生调用点。

恶魔房交易通过 [`compat/characters/keeper.lua`](https://github.com/BMingSY/isaac-lan/blob/main/src/bridge/compat/characters/keeper.lua) 在权威拾取碰撞前按实际买家重新询问原版 Room 的基础价和折扣价。`pickup_price` 只接受存活拾取物和已列入房间的玩家精灵包装，临时借用买家名单计算价格，不创建或复制原生对象。表店长和里店长使用金币，其他角色使用血量；自定义固定价和免费道具不覆盖。本机价格显示使用本机玩家上下文。

## 里 Lost 的公共生成特性

角色公共效果统一放在 compat/characters/team_effects.h。里 Lost 的攻击性标签筛选、品质 0／1 的五分之一重抽和允许特殊卡时的十分之一神圣卡替换，都读取全队名单；原版生成算法、种子、标签与概率保持不变。卡牌生成的角色判断被原版内联为名单遍历，因而另在 GetCardEx 范围临时借用完整名单。主机生成后同步结果，分房不改变生效范围。具体反汇编地址、二进制哈希和复核方法见[原版生成证据](https://github.com/BMingSY/isaac-lan/blob/main/docs/tainted-lost-item-generation.md)。

## 死亡证明

原版进入死亡证明与拿取后的延迟返回均使用动画 20，返回调用的玩家参数为空，原来的逐角色适配无法解析该返回。[`compat/items/death_certificate.h`](https://github.com/BMingSY/isaac-lan/blob/main/src/compat/items/death_certificate.h) 根据动画与来源／目标维度选择整队传送；内部过门和卡牌仍逐人执行。传送卡只解析死亡证明维度内的目的地，缺少对应房间时回到原版入口 80，不能跳回普通层。任何玩家拿取后全队返回原版保存的来源房间。

首名角色沿用原生初始化落点；后续角色进入已加载房间时，复用已到达角色的位置，并同步放置其双角色身体与随行实体，避免沿用大房间坐标而落到地图外。落点只取自本次目标房间，不跨房间或楼层缓存。入口门定位和追逐型 Shadow 的原生进房行为保持原有处理。

J460 原版的死亡证明基座可触发多人奖励补发，拿取后又生成 Boss 池道具。本次落点修复保留该行为；原版代码依据和验证范围见[死亡证明落点追加验证](https://github.com/BMingSY/isaac-lan/blob/main/docs/history/party-compatibility-validation.md#死亡证明落点追加验证)。

客机从权威房间视图进入时没有执行 Game::EnterDeathCertificate，需要补齐原版的 5 个标量来源字段：当前／上一房间索引和维度、离开门。返回时以权威目的地修正来源，避免原版 ChangeRoom 使用未初始化的索引 0。沿用已有房间生命周期、原版返回索引与维度，不复制或释放物品池、房间或实体；到达后恢复原版动画导致的控制锁。

## 口袋槽与药丸

原版 GetPocketItem 使用 Player+0x17a0 的四个 `{ID, kind}` 标量记录。只同步卡牌／药丸 setter 和主动 ID 不能恢复口袋主动与切换顺序，导致原版多人 HUD 副手缺失。库存第 11 项添加 32 字节记录，在所有库存 setter 后恢复；`actor_pockets` 校验列入名单的玩家、记录长度、种类与主动槽 ID，写入限客机。主动对象、实体指针和获取行为仍由原有库存组件管理。

里该隐的合成袋还需要独立的私有状态，口袋槽 ID 不包含袋内材料。J460 原版拾取计数（RVA `0x3d54e2`）与 HUD 材料读取（RVA `0x44a1f6`）使用 Player+0x1f44 的 8 字节材料顺序；HUD 预览读取（RVA `0x443b06`）使用 Player+0x1f4c 的道具 ID。三处代码加入启动特征校验，现有原版 Lua API 没有完整读取／恢复这些字段的接口。

[`compat/items/crafting_bag.lua`](https://github.com/BMingSY/isaac-lan/blob/main/src/bridge/compat/items/crafting_bag.lua) 匹配四个主动槽中的合成袋，给每个角色元组追加第 8 项、固定 12 字节的材料与预览；同房和分房都采集所有玩家，库存 setter 后恢复，失去道具时清空旧显示状态，合作幽灵的隐藏库存保留原生所有权。`actor_crafting_bag` 只接受列入完整名单的玩家，完整验证载荷长度、材料种类、紧凑顺序和预览范围后才写入，写入限客机。数据变化时仅标记该玩家的原版 HUD 预览缓存，重复状态不重置缓存。拾取、合成、物品池来源缓存和道具获取仍由主机执行，不复制指针、主动对象或 Mod 私有表，不增加 Hook。角色元组变化使 schema 14 升为 15；协议仍为 26，扩展指纹随 DLL 更新。

联机延迟文字原先覆盖右侧口袋 HUD 的材料格，[`presentation/menu.lua`](https://github.com/BMingSY/isaac-lan/blob/main/src/bridge/presentation/menu.lua) 将它移到上方中间，保留原版副手布局。

原版 ItemPool 是 Game+0x1a740；GetPillEffect 读取 +0x7a4 的 15 个颜色效果，IdentifyPill／IsPillIdentified 屏蔽大药丸颜色位后读取 +0x7e0 的 15 个鉴定字节。现有 Lua API 没有完整恢复颜色分配和撤销鉴定的接口，因此 `pill_state` 提供固定 75 字节读写，全部验证后才写入，写入限客机。[`sync/pills.lua`](https://github.com/BMingSY/isaac-lan/blob/main/src/bridge/sync/pills.lua) 将其作为顶层第 20 项，在库存 setter 后恢复，重复状态与回退均可重放。

## 主机续关决定

仅针对 Game+0x26778 的原版跑圈提示，主机显示完整提示和选项，并使用主机物理菜单输入；客机不显示或处理这个提示，其他原版提示保留既有处理。主机这次提示关闭 +0x130 的 Steam 投票模式，否则原版提示／Game::Update 仍会等待内置联机票数；原版 Manager 提示还会选择原生多人输入配置，房间／显示输入作用域不足以保证主机菜单确认生效。原生按下边沿只保留一个渲染帧，提示却按联机模拟步执行，直接重读物理输入会在部分相位漏掉按键。适配使用已有采集链路缓存的主机第 0 槽输入边沿，修改原版选择／结果标量，再调用已校验的 VictoryPrompt::Hide（RVA 0x438190）播放原版退出动画；楼层处理仍通过原生 NextVictoryLap 和运行协调器。私有只读 victory_lap_prompt 返回活动、选择、结果、投票模式与可交互状态，用于验收实际的“是／否”路径。原版 Game::NextVictoryLap 会直接更新种子、圈数、玩家和楼层，不能只同步目标层数。

可靠楼层事务的原生重开标记改为受限种类：0 为普通换层，1 由 R Key 适配器处理，2 由 [`compat/routes/victory_lap.lua`](https://github.com/BMingSY/isaac-lan/blob/main/src/bridge/compat/routes/victory_lap.lua) 处理。网络层只传输并校验种类与事务边界，不访问角色、道具或游戏对象。协议升至 26。两端在同一楼层代次屏障内调用原版重开；原生调用延迟至房间作用域退出，并先恢复完整名单、清理旧房间，沿用原有重新接管流程。

## 域名与 Proton

IPv4 直接连接；域名允许 ASCII 字母、数字、点和连字符，长度最多 253，异步解析并尝试至多 16 个 IPv4 地址。任务只拥有结果对象和独立 Winsock 引用，退出、取消、重连不阻塞 DNS；旧任务不持有会话或游戏对象。菜单与命令入口均接受域名，重连保留原输入。

适配基准是 [Proton 11.0-2](https://github.com/ValveSoftware/Proton/releases/tag/proton-11.0-2)，对应 Wine 提交 `dc26e61847081a1b5cb0733dc30feba6ee575482`。其 winmm 导出仍缺少代理表中的 14 个名称；游戏直接导入的 timeBeginPeriod、timeEndPeriod、timeGetDevCaps 均存在。缺少的导出绑定至具名错误终止入口，避免未使用 API 导致启动失败或空指针跳转；实际存在的 API 保持系统转发。

同一版本的 [cabinet.spec](https://github.com/ValveSoftware/wine/blob/dc26e61847081a1b5cb0733dc30feba6ee575482/dlls/cabinet/cabinet.spec) 也缺少 Windows Compression API。协议 26 改为模式 2 的可移植 DEFLATE，使用静态编入的 [miniz 3.1.2](https://github.com/richgel999/miniz/tree/3.1.2)（MIT），保留无收益时的模式 0 原文。解压验证准确长度、输入消费、校验和与容量边界；Windows 与 Proton 发送同一格式。旧 XPRESS 读取只用于 Windows 历史诊断归档，不作为新会话依赖。源码与许可证随仓库／安装包分别纳入，未增加动态 DLL 依赖。

Linux 安装器只依赖 Python 3 标准库，复用 Windows 安装记录与归属标记，核验安装包哈希、x86 J460 PE、版本标记、区段及同一组原生入口签名。安装／升级／卸载使用同盘暂存、备份和失败回滚；拒绝外来或被修改的 DLL、链接文件和运行中的游戏，保留配置、存档和日志。安装包包含从版本后端生成的 `game-profile.json`，升级时同步校验器数据。

## 验证

测试命令见[开发与测试](https://github.com/BMingSY/isaac-lan/blob/main/docs/development-and-testing.md)，既有结果、失败轮次和未覆盖项见[专项验收记录](https://github.com/BMingSY/isaac-lan/blob/main/docs/history/party-compatibility-validation.md)。
