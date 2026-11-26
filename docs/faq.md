# 常见问题（FAQ）

## Q：安装或卸载报错怎么办？

A：脚本会输出 `Isaac LAN [错误类别]`、具体原因和 `Next step` 处理建议。按错误类别处理：

| 错误类别 | 处理方法 |
| --- | --- |
| `GAME_PATH` | Windows 下安装和卸载都选择 `isaac-ng.exe`。检测到 Steam 中的以撒后，脚本会打开对应目录并预填文件名。也可以手动浏览。若游戏程序已移走，卸载时可在原目录直接点「打开」。 |
| `PACKAGE_INVALID` | 将完整发布 ZIP 重新解压到一个新目录，不混用不同版本的文件。缺文件时检查安全软件的隔离记录。 |
| `GAME_INCOMPATIBLE` | 核对 Windows 游戏版本为忏悔 `1.7.9b.J835` 或忏悔＋ `1.9.7.20.J514`。必要时通过 Steam 验证游戏文件。Linux／Steam Deck 使用 Proton 版。 |
| `CHECKER_FAILED` | 游戏检查程序未正常运行。确认安装包已完整解压，检查安全软件的拦截记录；仍失败时保留完整报错。 |
| `GAME_RUNNING`、`FILE_IN_USE` | 退出游戏以及占用报错文件的程序，等待进程退出后重试。 |
| `FILE_EXISTS` | Windows 在替换被占用的文件时也可能返回「文件已存在」。先关闭占用程序后重试；仍失败时保留完整报错，不要手动删除目标文件来绕过检查。 |
| `PERMISSION_DENIED` | 先关闭占用报错文件的程序，再检查目录写入权限和安全软件拦截。Windows 仅在目录权限确有要求时以管理员身份重试；Linux 使用 Steam 游戏库所属账户。 |
| `DISK_FULL`、`IO_ERROR` | 检查报错路径、游戏所在磁盘的剩余空间及读写状态，再重试。 |
| `FILE_CONFLICT` | 检查报错路径。若另一扩展占用共享的 `winmm.dll`，先用该扩展自己的方式处理，再安装 Isaac LAN。 |
| `INSTALLATION_INVALID` | 检查报错路径是否为普通文件或目录。如果标记和记录都已损坏，从同一安装备份恢复其中一份有效记录后重试。 |
| `ROLLBACK_FAILED` | 暂勿启动游戏。保留报错指向的 `.isaac-lan-transaction-*` 恢复目录，按其中 `recovery.json` 的 `path` 与 `backup` 对照恢复旧文件；`backup` 为 `null` 表示操作前该文件不存在。不能确认时保留目录并提供完整报错。 |

重新运行安装可以认领与包内完全相同的手动安装、补回缺失的 DLL，也能用有效标记或记录修复另一项。已是当前版本可直接退出。有改动的 Isaac LAN 专用文件在修复前备份到输出所列的 `.isaac-lan-transaction-*` 目录。

卸载优先按游戏目录的安装记录清理。记录缺失时，用包内的 SHA-256 清单识别手动复制的 DLL。即使缺少安装包里的 DLL 和检查程序，或已从游戏目录移走 `isaac-ng.exe`，也能卸载。卸载会跳过已删除的文件，列出并保留无法确认归属的文件，保留会话数据和日志。重复运行可正常结束。安装或卸载写入失败时会逐个恢复旧文件，恢复失败时保留全部备份。

## Q：Windows 上装好了 Isaac LAN，游戏里却找不到局域网联机入口怎么办？

A：退出游戏，在 Steam 库中右键《以撒的结合》，选择「管理 → 浏览本地文件」。

1. 找到 `isaac-ng.exe`，查看同一目录下有没有 `winmm.dll`。如果缺少，重新运行安装包里的 `Install.cmd`，选择这里的 `isaac-ng.exe`。
2. 如果 `winmm.dll` 已经在游戏目录，右键 `isaac-ng.exe`，打开「属性 → 兼容性」，尝试勾选 **「禁用全屏优化」** 并点击「应用」。[微软全屏优化设置说明](https://devblogs.microsoft.com/directx/demystifying-full-screen-optimizations/)

从 Steam 库重新启动游戏并选择存档。忏悔打开「联机模式（Online）」即可，忏悔＋还需在里面选择「局域网联机」。

如果仍找不到入口，让游戏停在主菜单，在开始菜单中打开 **Windows PowerShell (x86)**，粘贴下面的命令查看游戏加载的 DLL 路径。[微软 PowerShell 命令说明](https://learn.microsoft.com/zh-cn/powershell/module/microsoft.powershell.management/get-process?view=powershell-5.1)

```powershell
Get-Process isaac-ng -Module |
    Where-Object { $_.ModuleName -in 'winmm.dll', 'isaac_lan_probe.dll' } |
    Select-Object -ExpandProperty FileName
```

正常时会列出两份 `winmm.dll`，一份在游戏目录，一份在 Windows 系统目录，还会列出 `isaac_lan_probe.dll`。如果只列出系统目录下的 `winmm.dll`，说明这次启动跳过了 Isaac LAN 加载器。反馈时可附上命令输出。

## Q：切换忏悔和忏悔＋需要重装吗？

A：通用安装包一次装好两版。在 Steam 启用或禁用忏悔＋，等下载完成后重启游戏，加载器会根据当前游戏自动选择对应的联机扩展。

如果 Steam 更新游戏后启动时提示 `code 13`，请核对该游戏补丁是否已有联机适配。已通过完整安装包启用跨补丁更新的玩家，等待 Steam 下载本 Mod 的适配更新后重启游戏即可。使用旧加载器或通过安装包手动接收更新的玩家，可在关闭游戏后用对应的新版完整安装包覆盖安装。

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

A：全员选择相同的游戏版本，安装相同版本的联机扩展并重启，核对房主地址、端口（默认 UDP 29506）和防火墙；跨网络还需配置端口映射或转发。
