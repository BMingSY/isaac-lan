---
name: isaac-dual-test
description: "在 isaac-lan 仓库双开主客机供用户手动测试，按指定角色与延迟自动联机开局。用于双开、双端手测、带延迟启动，以及查看或关闭本工具的实例；不用于自动玩法验收。"
---

# 以撒双开手测

在仓库根目录使用 [run_manual_dual.py](https://github.com/BMingSY/isaac-lan/blob/main/tools/run_manual_dual.py)，不要临时重写启动脚本或使用自动玩法验收工具代替手动测试。

```bash
python3 tools/run_manual_dual.py --characters 以撒 阿撒泻勒 --latency-ms 80
```

- `--characters` 顺序为主机、客机。接受菜单中文名、英文枚举名及数字 PlayerType；不确定名称时运行 `--list-characters`。例如 `里以撒`、`tainted-isaac`、`PLAYER_ISAAC_B` 均可。
- `--latency-ms` 是增加的往返延迟，80 表示每方向 40 ms；实际 Ping 还含调度开销。用户若明确说单程延迟，乘二后传入。
- 沿用用户本次会话已给出的角色与延迟；没有指定时用双以撒、0 ms，不为默认参数反复询问。
- 默认使用已有 `host-001`／`client-001` 隔离目录及 `build-win32`。工具默认增量构建；环境不同才使用 `--host`、`--client`、`--build`。缺少隔离副本时按工具报错和[开发测试说明](https://github.com/BMingSY/isaac-lan/blob/main/docs/development-and-testing.md)准备，不能把正式安装目录当成隔离目录。

启动成功以双端进入游戏、实际角色匹配及工具报告交接完成为准。工具会启用音乐，零音量恢复至 20%，窗口左右排列；自动联机开局后撤下启动钩子，不合成移动、攻击或其他游戏输入。后台仅维持 UDP 中继和退出收尾。启动后向用户报告角色、增加的 RTT、实际 Ping 及运行记录目录，并把操作交给用户。

```bash
python3 tools/run_manual_dual.py --status
python3 tools/run_manual_dual.py --stop
```

状态与关闭默认针对最近一次成功启动；可加 `--session <运行记录目录>`。仅在用户要求关闭、重开或参数变化需要重新启动时关闭所属实例，不因为自己的回合结束就关闭手测窗口。已运行的实例不能直接覆盖；先查看状态，保留用户正在进行的测试。

关闭两窗口或执行 `--stop` 后，工具保存日志并恢复本次启动前的隔离配置、存档、数据和临时标记；本次手测进度不会覆盖原隔离存档。记录在 `test-runs/manual-dual/`。失败时读取该轮 `session.json`、`supervisor.log` 与双端日志，保留备份；不要删除存档、强行接管其他游戏进程或自动循环重启。
