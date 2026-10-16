# LAN 人机托管

LANBOT 通过正常输入接管本机玩家的移动与射击，便于“人机主机＋人工客机”测试。主客机均可使用，无需额外 Mod、Agent 或 API Key。

## 启用

启动游戏前，在当前存档目录的 `options.ini` 设置 `EnableDebugConsole=1`。Windows 默认位置为 `%USERPROFILE%\Documents\My Games\Binding of Isaac Repentance+\options.ini`；隔离或自定义存档使用各自目录。扩展不会自动改配置。同机双实例需要后台继续运行时，设置 `PauseOnFocusLost=0`。

进入 LAN 游戏，打开原生控制台（通常为 `~`／反引号键），输入 `lanbot on`，关闭控制台后开始托管。默认 `run + balanced`，只影响本机所属玩家。

## 命令

| 命令 | 行为 |
| --- | --- |
| `lanbot on` | 开启或继续托管；重复开启不会叠加控制器 |
| `lanbot mode run` | 收集免费资源、探索当前层正常可达分支，再寻找普通出口 |
| `lanbot mode explore` | 探索当前层，完成后等待，不自动换层 |
| `lanbot mode hold` | 当前房间战斗与恢复，清房后留守 |
| `lanbot style aggressive` | 更积极争取输出位置 |
| `lanbot style balanced` | 平衡危险、距离与进度 |
| `lanbot style cautious` | 增加危险裕量，偏好较远的有效输出位置 |
| `lanbot pause`／`resume` | 释放按键供人工操作／恢复托管，保留配置 |
| `lanbot off` | 清除任务并交还人工，保留本次会话配置 |
| `lanbot next` | `run`／`explore` 沿正常路线前往已知出口，跳过本次队友等待；`hold` 拒绝 |
| `lanbot status` | 查看任务、等待原因、阶段和决策统计 |
| `lanbot help` 或 `lanbot` | 帮助 |

模式和风格可预先设置，不会自行启动。`on`／`resume` 要求 LAN 已开局；关闭状态须先 `on`。普通换层默认等存活队友进入出口房间，`next` 不生成出口，也不绕过原版限制。

`pause` 只暂停人机，不暂停全队，已发生或已发出的操作无法撤回。退出、断线或新一局关闭托管并恢复默认配置；重连后需重新开启。

## 支持范围

| 场景 | 行为与限制 |
| --- | --- |
| 输入 | 接管移动和射击；地图、暂停、控制台、炸弹、主动道具及卡牌仍由真人操作 |
| 普通路线 | 正常走门、免费资源／道具、每间 Boss 房至多一份奖励；已有主动道具时不反复交换，不自动购物或处理特殊结局解谜 |
| 贪婪模式 | 启动波次前等队友，战斗时避开停止按钮，Boss 波后补给、收集道具房并换层；跳过可选恶魔奖励波 |
| 贪婪商店 | 为缺钥匙／缺血预留预算，再按收益购买被动或跟班；按队友装备分配道具，不自动买主动、未知或负代价商品 |
| 地形 | 射击清除挡路大便与普通／红火，处理普通压力按钮和可确认安全窗口的交替尖刺；避开危险地面、蓝／紫火，复杂障碍交还人工 |
| 战斗 | 寻路、短时避险、普通射击及部分蓄力武器策略；双角色共享原有输入，不支持独立走位 |

打开界面、换房／重建、死亡或视图未就绪时清理旧输入。客机观察超过 250 ms 未更新会等待 `stale_view`；决策异常转为暂停。常见等待原因为 `wait_for_party`、`exploration_complete`、`resource_missing`、`route_blocked`、`wait_for_trap` 和 `needs_manual`。

`status` 的 `frames` 为决策次数，`hits` 为有效观察间的血量下降次数，`blocked` 为受阻次数，`max_ms` 为观察与决策峰值。2 ms 是设计目标，尚不是实时保证。`run` 表达推进目标，不保证任意种子、角色或武器都能通关。

实现与失效约束见[设计](https://github.com/BMingSY/isaac-lan/blob/main/docs/lanbot-design.md)。
