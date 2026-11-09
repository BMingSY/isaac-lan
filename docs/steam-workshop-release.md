# Steam 创意工坊更新

更新现有 [Isaac LAN / 局域网联机](https://steamcommunity.com/sharedfiles/filedetails/?id=3817760679) 条目，使用 GitHub 自动发版 CI 生成的正式安装包和已确认文案。App ID 为 `250900`，条目 ID 为 `3817760679`；不为新版本创建新条目。每次发版同时更新 Mod 版本、更新记录，以及默认语言和简体中文介绍顶部的当前版本内容，完整流程见仓库 skill [isaac-lan-release](https://github.com/BMingSY/isaac-lan/blob/main/.agents/skills/isaac-lan-release/SKILL.md)。

工具不带介绍参数时只更新内容和更新记录；仓库发版流程必须传入介绍参数，不能使用该默认模式漏掉顶部版本说明。常规更新用 `--replace-notes-version` 替换顶部旧版本内容；仅在原介绍没有版本前缀时用 `--prepend-notes` 首次建立版本标题与说明，以 `-----` 分隔原介绍。分隔线后的项目介绍、群号和反馈入口保留，不累积旧版本段落。

更新本地化介绍时，同次提交发布前快照中非空的该语言标题；快照标题为空时不写入标题。标题、封面、标签与可见性沿用现值；用户要求更换封面时，`--preview` 指定本次封面，同时更新内容中的 `preview.png`。

## 准备环境

- Windows Steam 已登录条目所有者账号，并已安装以撒；无需启动游戏，也无需再次执行游戏验收。
- GitHub 标签对应的 [Build and release](https://github.com/BMingSY/isaac-lan/blob/main/.github/workflows/release.yml) 全部必需任务已通过，GitHub Release 与附件已发布，当前检出的发布说明对应目标标签。文案按 [AGENTS.md](https://github.com/BMingSY/isaac-lan/blob/main/AGENTS.md#发布文案约定) 审阅；已有授权且措辞不变时直接复用。
- Python 环境已安装 [工具依赖](https://github.com/BMingSY/isaac-lan/blob/main/tools/requirements-ci.txt)，`gh` 已登录；Windows x86 构建环境按[开发与测试](https://github.com/BMingSY/isaac-lan/blob/main/docs/development-and-testing.md) 配置。

构建发布工具，它不包含在玩家安装包中：

```sh
cmake --build build-win32 --target isaac_lan_workshop
```

以下命令在 WSL Bash 中执行。先设置 `ISAAC_GAME_DIR` 为游戏目录、`WORKSHOP_ASSETS` 为本次下载目录、`WORKSHOP_OUTPUT` 为本次准备目录；均使用 WSL 路径，准备目录应位于 Windows 磁盘且尚不存在。查询远端默认语言与简体中文介绍，将两者顶部实际旧版本记为 `WORKSHOP_NOTES_VERSION`；它可能落后于上次 Release，不能直接取上次发布标签。工具也支持 Windows Python，此时传入 Windows 路径。

## 准备安装包与文案

```sh
tag="v$(cat VERSION)"
gh release download "$tag" --repo BMingSY/isaac-lan \
  --dir "$WORKSHOP_ASSETS" --pattern '*.zip' --pattern '*.sha256'

python tools/workshop_release.py prepare \
  --helper build-win32/isaac_lan_workshop.exe --game "$ISAAC_GAME_DIR" \
  --archive "$WORKSHOP_ASSETS/Isaac-LAN-$tag-windows-x86.zip" \
  --notes ".github/release-notes/$tag.md" \
  --tag "$tag" --output "$WORKSHOP_OUTPUT" \
  --replace-notes-version "$WORKSHOP_NOTES_VERSION"
```

`prepare` 不发布。它校验安装包，查询现有条目并下载当前内容，保留原有 Lua 入口、预览图和安装说明，更新 `metadata.xml` 的版本号，只保留本次 ZIP 和校验文件。安装包声明加载器 ABI 时，同时从该 ZIP 提取主体 DLL 和清单到 `isaac-lan-update`，供已安装加载器采用；不重新编译，也不从上次工坊副本复用主体，契约见[原生扩展更新](https://github.com/BMingSY/isaac-lan/blob/main/docs/extension-updates.md)。更新说明只转换标题格式为 Steam BBCode，不改变措辞。

两种语言的原介绍均没有版本前缀时，将示例中的 `--replace-notes-version` 参数改为 `--prepend-notes`，首次建立顶部版本内容。该操作不会删除旧版本段落，不能在已有版本前缀时反复使用。

常规发版使用 `--replace-notes-version`，版本号必须与现有段落一致，不能同时传入 `--prepend-notes`。工具检查两种语言的介绍均以该版本标题开头，并具有 `-----` 分隔的项目介绍；只替换分隔线前的版本说明。任一语言的版本或结构不匹配时停止准备，核查并准备修正后的完整文本，不以 prepend 堆叠内容或发布部分修改。

用户明确要求更换封面时，在 `prepare` 命令中追加 `--preview docs/assets/steam-workshop-cover.png`。准备结果包含两种语言的完整介绍；指定封面时还包含其哈希，发布前核对与已确认文案、原介绍和指定图片一致。

Steam 页面封面须小于 1 MB。原图超过限制时，制作同一图片的压缩副本，用 `--preview-upload` 指定；`--preview` 仍指定原图，保留在下载内容中。发布工具分别校验上传副本与内容原图。

检查输出中的 `reviewed-notes.md`、`steam-change-notes.txt`、两份 `description-*.txt` 和 `preparation.json`，以及内容中的 `metadata.xml`、自动更新清单和主体哈希；它们的目标版本须与正式包一致。两种语言顶部都应只保留当前版本内容。文案只写玩家能感知的变化；没有新特性就不保留该分类，不列排查原因、内部同步机制或逐项调试细节。

## 发布并核对

获得本次发布授权、确认文案后执行：

```sh
python tools/workshop_release.py publish \
  --helper build-win32/isaac_lan_workshop.exe --game "$ISAAC_GAME_DIR" \
  --output "$WORKSHOP_OUTPUT"
```

发布前再次核对本地文件和文案哈希，以及远端条目是否变化。两种语言均须取得 Steam 成功回执且无待接受协议；随后自动下载条目，逐文件校验内容，核对 Mod 版本和自动更新主体，并确认两种语言介绍顶部均为目标版本及本次文案，标题及可见性符合预期。旧安装包不能残留。

介绍按语言分别提交：第一次同时提交内容、更新记录与可选封面，后续语言只提交介绍，不重复更新记录。每个语言保留独立回执；任一提交失败或未返回成功时，整次发布不能计为完成。指定封面时，从 Steam 返回的预览地址下载并核对图片哈希。

保留整个输出目录中的准备清单、上传回执和 `verify-*/verification.json`。最后查看创意工坊页面与更新记录，确认标题仍为 **Isaac LAN / 局域网联机**、说明采用已确认文案。仅有“已提交”日志不能视为发布完成。

## 中断或失败

仅重新核对已发布内容，不再上传：

```sh
python tools/workshop_release.py verify \
  --helper build-win32/isaac_lan_workshop.exe --game "$ISAAC_GAME_DIR" \
  --output "$WORKSHOP_OUTPUT"
```

- 上传超时或进程退出后，保留 `upload-started.json`，先执行 `verify` 并查看远端更新记录；不得直接重发。确认未成功提交后，再用新目录准备并重试。
- 多语言部分完成时，保留各语言成功回执，核对远端已完成与未完成的字段；不得重新上传已完成的内容或再次追加同一版介绍。
- Steam 要求接受协议时，由账号所有者处理；包、文案或远端条目发生变化时，重新准备，文案发生变化须重新审阅。
- 网页限流时可用 Steam API 和下载哈希核对内容，但需区分这些结果与网页更新记录的核对。简体中文标题为空可能只是没有单独设置该语言标题，按发布前快照保留，不自动改名。

实现入口：[Python 发布工具](https://github.com/BMingSY/isaac-lan/blob/main/tools/workshop_release.py)、[Steam API 工具](https://github.com/BMingSY/isaac-lan/blob/main/tools/workshop.cpp)。接口依据 [Steamworks UGC 文档](https://partner.steamgames.com/doc/api/ISteamUGC)：提交后等待结果回调，下载完成后再读取安装目录。开发回归使用模拟 Steam 接口；检查工具时可以查询／下载现有条目，不应为测试重复发布。
