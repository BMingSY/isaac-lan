# Isaac LAN

《以撒的结合：忏悔＋》局域网联机扩展，支持 2–4 人，适用于 Windows 版 **v1.9.7.17.J460**。

## 功能

- 共享楼层，分房探索与战斗，随时进入队友房间汇合。
- 允许加载其他 Mod，保留原版多人 UI 和官方联机入口。
- 小地图显示玩家位置，支持 Ping 显示和断线重连。
- 队伍文字聊天、角色头顶气泡和独立表情；主客机均可使用原版控制台命令。

## 安装

1. 解压完整安装包，运行 `Install.cmd`。
2. 保持游戏是关闭状态，选择游戏目录中的 `isaac-ng.exe`。
3. 从 Steam 正常启动游戏，选择存档栏，进入 **Online／在线联机 → 局域网联机**。

所有玩家需要使用相同游戏版本和同一份联机扩展。

### Linux／Steam Deck（Proton）

需要 Windows 版 J460、Proton 11.0-2 及以上。

将 `ISAAC_GAME_DIRECTORY` 设为游戏安装位置后执行：

```sh
python3 install.py --game-directory "$ISAAC_GAME_DIRECTORY"
```

Steam 启动选项设为：

```text
WINEDLLOVERRIDES="winmm=n,b" %command%
```

升级时从新安装包重新运行安装命令。卸载使用同一命令加 `--mode Uninstall`，并删除上述启动选项；配置、联机存档和历史日志会保留。

## 配置与日志

首次启动会在游戏目录生成 `isaac-lan/config.ini`：

```ini
; Isaac LAN：修改后重启游戏生效。
[network]
; 客机输入发送频率：30 / 60，默认 60；各端可以不同。
; 30 减少输入流量，但可能多等一个渲染帧；主机模拟和本机显示频率不变。
input_hz = 60

[logging]
; 日志与原版 log.txt 位于同一游戏数据目录，按启动和局次分目录保存。
; startup.log 记录启动和退出，runtime.log 记录局内事件。
; 历史日志可手动清理。
; 日志等级：DEBUG / INFO / WARN / ERROR，默认 INFO。
level = INFO

[diagnostics]
; 性能统计：true / false，默认 false；排查卡顿时可开启。
; 开启后在同一日志目录生成 performance.jsonl。
performance = false
; 性能统计采样间隔（毫秒）：100–60000，默认 1000。
sample_interval_ms = 1000
```

## 创建与加入

1. 房主设置端口，点击“创建房间”，把自己的 IPv4 地址或域名和端口告诉队友。
2. 队友填写房主 IP／域名和端口，点击“加入房间”。
3. 所有人选择角色并准备，由房主开始游戏。

使用 **TCP**，默认端口为 **29506**，可以在界面中修改。

## 重连

客机掉线后返回局域网大厅，重连后回到房主当前所在房间。

## 聊天与命令

联机大厅和游戏中按 **`~` 所在的键**打开／收起聊天框，Enter 发送，Esc 收起并保留草稿。聊天每条最多 60 字，所有队友都能收到，同房角色头顶显示气泡。↑／↓ 调出输入历史，Page Up／Page Down 查看记录，Tab 补全聊天命令；支持中文输入与复制粘贴。

| 输入 | 效果 |
| --- | --- |
| 普通文字 | 发送给队友并显示气泡 |
| `/e 内容` 或 `/echo 内容` | 仅在自己的记录中输出，不显示气泡 |
| `/d20` | 掷出 1～20 的随机整数，全队可见并显示气泡；`N` 可取 1～1,000,000,000 |
| `/console 原版命令` 或 `/c 原版命令` | 原样执行原版命令，例如 `/c giveitem c1`、`/console stage 2`；返回文字默认只给执行者 |

命令输入最多 2048 个 UTF-8 字节。涉及角色和房间的原版命令在输入者的角色／房间上下文执行。联机期间 `~` 使用此输入框，离开联机后恢复原版控制台。

手柄 **L3** 打开／收起文字输入，A 发送、B 收起；文字内容仍用键盘输入。表情独立于聊天：**左 Alt／R3** 打开原版轮盘，沿用原版选择、翻页与确认操作，发送后显示原版角色表情气泡。表情不写入文字记录，不支持自定义导入。

聊天框背景默认半透明，可在 `isaac-lan/config.ini` 修改后重启；各端独立设置，文字气泡使用半透明的原版素材：

```ini
[chat]
; 0 完全透明，100 不透明。
background_opacity = 70
; 六位 RGB 十六进制，不加 #。
background_color = 231B18
border_color = 79604C
text_color = E8DFCB
```

## 卸载

关闭游戏，运行 `Uninstall.cmd`，选择同一个 `isaac-ng.exe`。卸载会保留联机存档。

## 技术文档

[架构与开发文档](https://github.com/BMingSY/isaac-lan/tree/main/docs)

[第三方 API](https://github.com/BMingSY/isaac-lan/blob/main/docs/third-party-mod-integration.md)

## 源码构建

需要 CMake、Ninja、32 位 MinGW-w64，以及 Dear ImGui v1.92.6、MinHook v1.3.4 的源码。

将 `ISAAC_IMGUI_SOURCE` 和 `ISAAC_MINHOOK_SOURCE` 设为对应依赖源码位置后执行：

```sh
cmake -S . -B build-win32 -G Ninja \
  -DCMAKE_TOOLCHAIN_FILE=cmake/mingw-x86.cmake \
  -DCMAKE_BUILD_TYPE=Release \
  -DIMGUI_SOURCE_DIR="$ISAAC_IMGUI_SOURCE" \
  -DMINHOOK_SOURCE_DIR="$ISAAC_MINHOOK_SOURCE"
cmake --build build-win32
python3 tools/build_package.py --build build-win32 --output dist/Isaac-LAN-J460
```

## 问题与建议

请提交到 [Issues](https://github.com/BMingSY/isaac-lan/issues)，写明游戏版本、主客机、复现步骤和使用的其他 Mod；遇到联机异常时可以附上对应启动的完整日志归档。
