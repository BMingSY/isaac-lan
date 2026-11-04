# 常见问题（FAQ）

## Q：安装或卸载报错怎么办？

A：脚本会输出 `Isaac LAN [错误类别]`、具体原因和 `Next step` 处理建议。先关闭游戏，再按类别处理：

| 错误类别 | 处理方法 |
| --- | --- |
| `GAME_PATH` | 在 Steam 中选择「管理 → 浏览本地文件」，使用包含 `isaac-ng.exe` 的游戏目录；Windows 文件选择框选择该文件。 |
| `PACKAGE_INVALID` | 将完整发布 ZIP 重新解压到一个新目录，不混用不同版本的文件。缺文件时检查安全软件的隔离记录。 |
| `GAME_INCOMPATIBLE` | 核对游戏为 Windows Repentance+ `1.9.7.17.J460`，必要时通过 Steam 验证文件；Linux／Steam Deck 使用 Proton 版。 |
| `CHECKER_FAILED` | 游戏检查程序未正常运行。确认安装包已完整解压，检查安全软件的拦截记录；仍失败时保留完整报错。 |
| `GAME_RUNNING`、`FILE_IN_USE` | 退出游戏以及占用报错文件的程序，等待进程退出后重试。 |
| `PERMISSION_DENIED` | 先关闭占用报错文件的程序，再检查目录写入权限和安全软件拦截。Windows 仅在目录权限确有要求时以管理员身份重试；Linux 使用 Steam 游戏库所属账户。 |
| `DISK_FULL`、`IO_ERROR` | 检查报错路径、游戏所在磁盘的剩余空间及读写状态，再重试。 |
| `FILE_CONFLICT` | 保留并备份报错 DLL，确认它属于哪个扩展。其他扩展用其自己的卸载方式处理；被改动的 Isaac LAN 文件需从对应安装备份恢复。 |
| `INSTALLATION_INVALID` | 从同一份安装备份恢复 `.isaac-lan-install` 和 `isaac-lan/installation.json`；不要删除整个 `isaac-lan` 目录来绕过检查。 |
| `ROLLBACK_FAILED` | 暂勿启动游戏。保留报错指向的 `.isaac-lan-transaction-*` 恢复目录，按其中 `recovery.json` 的 `path` 与 `backup` 对照恢复旧文件；`backup` 为 `null` 表示操作前该文件不存在。不能确认时保留目录并提供完整报错。 |

安装记录有效且现有 DLL 未被修改时，重新安装可以补回缺失 DLL，卸载也允许 DLL 已缺失。写入或删除中途失败会尝试恢复原文件；恢复失败时保留全部备份，并继续恢复其他文件。卸载保留会话数据和日志。

## Q：主客机进度不一致，能一起玩吗？

A：可以。局内路线和道具解锁以房主为准，选角和挑战资格按各自存档判断。

## Q：联机能解锁成就吗？

A：能保留本局新增的游戏内解锁，房主开局前已有的不会补给客机。扩展不主动补发 Steam 成就。

## Q：会覆盖个人进度或单人存档吗？

A：保留原有解锁，计数只合并本局变化；单人 Continue 与联机存档分开管理。

## Q：联机挑战会给原版挑战奖励吗？

A：不会。

## Q：能保存续玩吗？

A：可以，需原房主、原存档栏、原人数、原加入顺序和匹配的扩展构建。临时挑战不能续玩。

## Q：客机掉线能重连吗？

A：可以。房主会话仍在时，保留原来的 `player-id.txt` 重连，恢复原角色并回到房主当前房间。

## Q：能中途加新人或更换房主吗？

A：暂不支持。

## Q：能分开探索吗？

A：可以同层分房探索，换层时全队一起走。

## Q：Mod 必须一样吗？

A：内容 Mod 需各端一致；已适配的界面 Mod 可各自安装，见[兼容清单](https://github.com/BMingSY/isaac-lan/blob/main/docs/mod-compatibility.md)。

## Q：连不上怎么办？

A：全员安装同一份扩展并重启，核对房主地址、端口（默认 UDP 29506）和防火墙；跨网络还需配置端口映射或转发。
