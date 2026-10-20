# Isaac LAN

《以撒的结合：忏悔＋》局域网联机扩展，支持 2–4 人，适用于 Windows 版 **v1.9.7.17.J460**。

## 功能

- 共享楼层，分房探索与战斗，随时进入队友房间汇合。
- 允许加载其他 Mod，保留原版多人 UI 和官方联机入口。
- 小地图显示玩家位置，支持 Ping 显示和断线重连。

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
; 联机协议：udp / tcp；同一局所有玩家必须一致。
transport = udp
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

[chat]
; 聊天背景不透明度：0–100，0 完全透明，100 不透明。
background_opacity = 70
; 自定义背景：PNG、JPG/JPEG、BMP；相对 config.ini 的路径或绝对路径。
; 留空使用纯色；按框大小缩放，保留透明区域，原图不修改。
background_image =
; 纯色背景、边框／分隔线与通用界面文字颜色：六位 RGB 十六进制，不加 #。
background_color = 231B18
border_color = 79604C
text_color = E8DFCB
```

## 创建与加入

1. 房主设置端口，点击“创建房间”，把自己的 IPv4 地址或域名和端口告诉队友。
2. 队友填写房主 IP／域名和端口，点击“加入房间”。
3. 所有人选择角色并准备，由房主开始游戏。

默认使用 **UDP**，端口为 **29506**，可以在界面中修改。

## 聊天与掷骰

联机时按 `~` 打开聊天，`/help` 查看命令。聊天和掷骰结果默认全队共享；末尾加 `--room` 只给当前同房、同维度的玩家，输出带 `【房间】` 标记。

| 输入 | 效果 |
| --- | --- |
| `/d6`、`/2d6` | 投掷一颗／两颗六面骰，显示明细与总和 |
| `/1d6+2d3`、`/2d6+3` | 混合骰子或加减常数，支持运算符两侧的空格 |
| `/d100b`、`/d100p` | 百分骰附带一颗奖励／惩罚骰；共用个位、额外掷十位，分别取低／高值 |
| `/d100b2`、`/d100p2` | 百分骰附带两颗奖励／惩罚骰，显示全部候选结果 |
| `/2d6 --room`、`这间有宝箱 --room` | 仅当前房间共享本次掷骰／聊天 |

`/MdN` 的 M 默认 1，N 为 1～999；一次表达式最多 20 颗基础骰、20 项，加减常数为 0～9999。奖惩骰仅用于 D100，数量为 1～2；`/2d100b` 对两颗百分骰分别使用奖励骰，再将结果相加。大小写均可；单骰示例为 `2P 掷骰：D6 = 4`，多骰示例为 `2P 掷骰：2D6 = [3 + 5] = 8`。

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
