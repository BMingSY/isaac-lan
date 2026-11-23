# 参与贡献 · Contributing to Isaac LAN

[English](https://github.com/BMingSY/isaac-lan/blob/main/CONTRIBUTING.md#english)

## 报告问题或提出建议

可以用中文或英文提交 Issue。先搜索已有讨论，同一问题可以直接补充在原帖。报告联机故障时，写明游戏和扩展版本、房主或客机、启用的 Mod，以及怎样触发问题。已通过游戏内 `/feedback` 提交的，附上反馈编号即可。公开日志请只贴相关片段，隐去 IP、用户名和本机路径。[提交 Issue](https://github.com/BMingSY/isaac-lan/issues/new/choose)

## 提交 Pull Request

1. 从 `main` 建分支，每个 PR 集中处理一个问题。先按改动职责找到对应模块。[代码结构与修改约定](https://github.com/BMingSY/isaac-lan/blob/main/AGENTS.md)
2. 安装开发依赖后运行 `python3 tools/format.py --check`。修改 PowerShell 时也运行 `./tools/format_powershell.ps1 -Check`。选择能覆盖改动的离线用例；日常离线测试入口是 `python3 tools/test.py --profile fast`。涉及原生行为或画面的改动，再验证受影响的游戏场景。[开发与测试](https://github.com/BMingSY/isaac-lan/blob/main/docs/development-and-testing.md)
3. 标题使用与改动匹配的前缀，如 `fix:`、`feat:` 或 `docs:`。正文说明原先的问题、改动效果、实际运行的检查和结果。有关联 Issue 时附上链接。若某个场景尚未验证，请写明。

修改 README 中的安装命令、菜单路径或配置示例时，请同步中英文两份说明。

提交的原创贡献按 PolyForm Noncommercial 1.0.0 授权。你可以为非商业目的使用、修改和分享项目原创代码。再分发时请附上协议正文或协议网址，以及项目的 `Required Notice:` 声明。商业销售或纳入商业产品需另行取得权利人授权。[项目许可证](https://github.com/BMingSY/isaac-lan/blob/main/LICENSE)

引入第三方材料时，请标明来源并保留其版权和许可声明。第三方组件沿用各自的许可，游戏本体和游戏素材的权利属于各自的权利人。[第三方许可](https://github.com/BMingSY/isaac-lan/tree/main/third_party)

## English

Issues and pull requests are welcome in English or Chinese. Search existing issues first. For a bug, include the game and extension versions, your host or guest role, enabled mods and steps to reproduce. If you used `/feedback` in game, the feedback ID is enough to reference those logs. For public reports, share only relevant excerpts and redact IP addresses, usernames and local paths. [Open an issue](https://github.com/BMingSY/isaac-lan/issues/new/choose)

1. Branch from `main` and keep each PR focused on one problem. Follow the existing module boundaries. [Repository guidelines (Chinese)](https://github.com/BMingSY/isaac-lan/blob/main/AGENTS.md)
2. With the development dependencies installed, run `python3 tools/format.py --check`. For PowerShell changes, also run `./tools/format_powershell.ps1 -Check`. Choose offline checks that exercise your change. The standard offline suite is `python3 tools/test.py --profile fast`. For native behavior or visual changes, verify the affected scenario in game. [Development and testing (Chinese)](https://github.com/BMingSY/isaac-lan/blob/main/docs/development-and-testing.md)
3. Use a title prefix such as `fix:`, `feat:` or `docs:`. Describe the original problem, the change and what you verified. Link any related issue and mention relevant scenarios you could not test.

When editing installation commands, menu paths or configuration examples in a README, update both language versions.

You license your original contributions under PolyForm Noncommercial 1.0.0. You can use, modify and share the project's original code for noncommercial purposes. If you distribute a copy, include the license text or its URL and the project's `Required Notice:` line. Commercial sales or inclusion in a commercial product require separate permission from the rights holders. [Project license](https://github.com/BMingSY/isaac-lan/blob/main/LICENSE)

Identify the source of third-party material and retain its copyright and license notices. Third-party components retain their own licenses. The game and its assets belong to their respective rights holders. [Third-party licenses](https://github.com/BMingSY/isaac-lan/tree/main/third_party)
