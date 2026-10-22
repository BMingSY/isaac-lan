# Steam 创意工坊更新

更新现有 [Isaac LAN / 局域网联机](https://steamcommunity.com/sharedfiles/filedetails/?id=3817760679) 条目，使用 GitHub Release 的正式安装包和已确认文案。App ID 为 `250900`，条目 ID 为 `3817760679`；不为新版本创建新条目。

工具默认只更新内容和版本更新说明，保留标题、各语言介绍、封面、标签与可见性。显式传入 `--prepend-notes` 时，在默认语言和简体中文介绍前放置版本标题与已确认更新说明，以 `-----` 分隔原介绍；`--preview` 指定本次封面，同时更新内容中的 `preview.png`。原介绍中的群号、反馈入口等保留。

## 准备环境

- Windows Steam 已登录条目所有者账号，并已安装以撒；无需启动游戏，也无需再次执行游戏验收。
- GitHub Release 已发布，当前检出的发布说明对应目标标签。文案按 [AGENTS.md](https://github.com/BMingSY/isaac-lan/blob/main/AGENTS.md#发布文案约定) 审阅；已有授权且措辞不变时直接复用。
- Python 环境已安装 [工具依赖](https://github.com/BMingSY/isaac-lan/blob/main/tools/requirements-ci.txt)，`gh` 已登录；Windows x86 构建环境按[开发与测试](https://github.com/BMingSY/isaac-lan/blob/main/docs/development-and-testing.md) 配置。

构建发布工具，它不包含在玩家安装包中：

```sh
cmake --build build-win32 --target isaac_lan_workshop
```

以下命令在 WSL Bash 中执行。先设置三个变量：`ISAAC_GAME_DIR` 为游戏目录，`WORKSHOP_ASSETS` 为本次下载目录，`WORKSHOP_OUTPUT` 为本次准备目录。均使用 WSL 路径；准备目录应位于 Windows 磁盘，且尚不存在。工具也支持 Windows Python，此时传入 Windows 路径。

## 准备安装包与文案

```sh
tag="v$(cat VERSION)"
gh release download "$tag" --repo BMingSY/isaac-lan \
  --dir "$WORKSHOP_ASSETS" --pattern '*.zip' --pattern '*.sha256'

python tools/workshop_release.py prepare \
  --helper build-win32/isaac_lan_workshop.exe --game "$ISAAC_GAME_DIR" \
  --archive "$WORKSHOP_ASSETS/Isaac-LAN-$tag-windows-x86.zip" \
  --notes ".github/release-notes/$tag.md" \
  --tag "$tag" --output "$WORKSHOP_OUTPUT"
```

`prepare` 不发布。它校验安装包，查询现有条目并下载当前内容，保留原有 Lua 入口、预览图和安装说明，更新 `metadata.xml` 的版本号，只放入本次 ZIP 和校验文件。更新说明只转换标题格式为 Steam BBCode，不改变措辞。

需要将更新说明放到介绍最前面并更换封面时，在 `prepare` 命令中追加 `--prepend-notes --preview docs/assets/steam-workshop-cover.png`；只有用户明确要求时使用。准备结果额外包含各语言的完整介绍和封面哈希，发布前核对其与已确认文案、原介绍和指定图片一致。该操作在现有介绍前添加一次内容，不自动删除历史版本段落。

Steam 页面封面须小于 1 MB。原图超过限制时，制作同一图片的压缩副本，用 `--preview-upload` 指定；`--preview` 仍指定原图，保留在下载内容中。发布工具分别校验上传副本与内容原图。

检查输出中的 `reviewed-notes.md`、`steam-change-notes.txt` 和 `preparation.json`。文案只写玩家能感知的变化；没有新特性就不保留该分类，不列排查原因、内部同步机制或逐项调试细节。

## 发布并核对

获得本次发布授权、确认文案后执行：

```sh
python tools/workshop_release.py publish \
  --helper build-win32/isaac_lan_workshop.exe --game "$ISAAC_GAME_DIR" \
  --output "$WORKSHOP_OUTPUT"
```

发布前再次核对本地文件和文案哈希，以及远端条目是否变化。上传成功须取得 Steam 成功回执且无待接受协议；随后自动下载条目，逐文件校验内容，并核对默认语言和简体中文的标题、介绍及可见性。旧安装包不能残留。

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
