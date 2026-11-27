# Isaac LAN

简体中文 · [English](https://github.com/BMingSY/isaac-lan/blob/main/docs/i18n/README.en.md)

《以撒的结合》的 2–4 人联机扩展。你可以邀请 Steam 好友、加入公开房间，或通过局域网地址直连。一次安装即可在 Windows 版 **忏悔 v1.7.9b.J835** 和 **忏悔＋ v1.9.7.20.J514** 中使用。[下载 Isaac LAN](https://github.com/BMingSY/isaac-lan/releases/latest)

## 功能

- 玩家可以在同一楼层分头探索和战斗，通过小地图找到队友并汇合。
- 联机时可以加载其他 Mod，使用原版多人界面。
- 显示网络延迟，支持断线重连。

## 安装与更新

关闭游戏，解压安装包。

### Windows

运行 `Install.cmd`，选择游戏目录中的 `isaac-ng.exe`。

### Linux／Steam Deck（Proton）

使用 Proton 11.0-2 或更高版本。在解压后的安装包目录中运行以下命令，将路径换成游戏安装目录。

```sh
python3 install.py --game-directory "/path/to/The Binding of Isaac Rebirth"
```

在 Steam 的游戏属性中填写启动选项。

```text
WINEDLLOVERRIDES="winmm=n,b" %command%
```

## 创建与加入

所有玩家需使用相同的游戏版本和 Isaac LAN 构建。从 Steam 启动游戏，选择存档栏，打开主菜单第三项「联机模式（Online）」。忏悔＋的扩展菜单使用中文，其中「官方联机」通往游戏自带的多人模式。进入 Isaac LAN 大厅后，全员选好角色并准备，由房主选择「开始游戏」。

### Steam 联机

- **邀请好友**　房主选择「Steam 联机 → 创建私人房间」，在大厅打开「Steam 房间 → 邀请 Steam 好友」。队友在 Steam 接受邀请即可加入。如果游戏因此启动，先选存档栏。
- **公开房间**　房主在「Steam 房间」把可见性切换为「公开」。队友从「Steam 联机 → 公开房间」选择房间。人数右侧是到房主的预估延迟，延迟低的排在前面，暂时无法估算的显示 `--ms`，排在最后。

### 局域网联机

打开「局域网联机」。房主确认端口（默认 UDP 29506），选择「创建房间」，把地址和端口发给队友。队友输入房主的 IPv4 地址、IPv6 地址或域名及端口，选择「加入房间」。忏悔在 Steam 联机不可用时会直接打开局域网页面。

### 断线与续玩

客机断线后会自动重连一次。进行中的对局只接受原玩家。

- **Steam 联机**　仍在原大厅的客机可在「Steam 联机」页选「重连游戏」。如果队友已离开房间或关掉游戏，房主可留在原局，按 `Shift+Tab` 打开 Steam 好友列表，对这名队友选择「邀请加入游戏」。队友用原 Steam 账号接受后，会恢复原角色并回到房主当前房间。
- **局域网联机**　队友使用原房主的地址和端口重连。

房主保存退出后，可以用原存档栏重新建房。原队伍按上次的顺序加入并准备后，由房主选择「继续上次联机」。临时挑战只支持在原局重连。

## 卸载

关闭游戏后运行卸载命令。配置、联机存档和日志会保留。

- **Windows**　运行 `Uninstall.cmd`，选择游戏目录中的 `isaac-ng.exe`。
- **Linux／Steam Deck**　在安装命令末尾加上 `--mode Uninstall` 并运行，再移除上文为扩展设置的 Steam 启动选项。

## 配置与日志

首次启动时，扩展会在游戏目录生成 `isaac-lan/config.ini`。已有配置会自动补齐缺项，保留原有设置。修改后重启游戏生效。

```ini
; Isaac LAN：修改后重启游戏生效。
[network]
; 客机输入发送频率：30 / 60，默认 60；各端可以不同。
; 30 减少输入流量，但可能多等一个渲染帧；主机模拟和本机显示频率不变。
input_hz = 60

[players]
; 其他玩家默认不透明度：0–100；0 完全透明，100 保留原本外观，仅影响本机画面。
others_opacity = 100
; 客机自己的移动预测：true 开启，false 只显示房主确认的位置。
movement_prediction = true

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
; 自定义背景支持 PNG、JPG/JPEG 和 BMP。可使用绝对路径或相对 config.ini 的路径。
; 例如 backgrounds/chat.png。留空使用纯色。图片按框大小缩放并保留透明区域。
background_image =
; 纯色背景、边框／分隔线与通用界面文字颜色：六位 RGB 十六进制，不加 #。
background_color = 231B18
border_color = 79604C
text_color = E8DFCB
```

## 技术文档

[架构与开发文档](https://github.com/BMingSY/isaac-lan/tree/main/docs)

[第三方 API](https://github.com/BMingSY/isaac-lan/blob/main/docs/third-party-mod-integration.md)

## 源码构建

需要 CMake、Ninja、32 位 MinGW-w64，以及 Dear ImGui v1.92.6、MinHook v1.3.4 的源码。

将 `ISAAC_IMGUI_SOURCE` 和 `ISAAC_MINHOOK_SOURCE` 设为对应依赖源码位置后执行：

```sh
for backend in repentance repentance_plus
do
  cmake -S . -B "build-$backend" -G Ninja \
    -DCMAKE_TOOLCHAIN_FILE=cmake/mingw-x86.cmake \
    -DCMAKE_BUILD_TYPE=Release -DISAAC_LAN_BACKEND="$backend" \
    -DIMGUI_SOURCE_DIR="$ISAAC_IMGUI_SOURCE" \
    -DMINHOOK_SOURCE_DIR="$ISAAC_MINHOOK_SOURCE"
  cmake --build "build-$backend" --target isaac_lan_probe isaac_lan_check
done
cmake --build build-repentance_plus --target isaac_lan_loader
python3 tools/build_package.py --build build-repentance --build build-repentance_plus --output dist/Isaac-LAN
```

## 问题与建议

在联机大厅或对局的聊天中输入 `/feedback 问题描述`。闪退后可重新启动游戏，进入联机大厅提交。提交成功后，游戏会显示反馈编号。上传失败时，游戏会显示本地反馈包的位置。

反馈包包含游戏和扩展版本、最近两次启动的联机日志、游戏的 `log.txt` 和扩展的 `config.ini`。有匹配的崩溃记录时，还会附上崩溃文本或异常摘要。日志上传到作者服务器，仅作者可见。路径中的 Windows 用户名会隐去。[反馈收集范围](https://github.com/BMingSY/isaac-lan/blob/main/docs/feedback.md)

如果 Steam 联机进不了大厅，或需要对照两端的连接记录，房主和客机可以分别在 Windows 上双击安装包解压目录里的 `Collect-Steam-Logs.cmd`。它会在各自的「下载」目录生成 `Isaac-LAN-Steam-Logs-*.zip`。把两份 ZIP 发给作者时，请注明哪份来自房主、哪份来自客机，以及问题发生的大致时间。

在 GitHub 报告问题时，请写明游戏版本、你是房主还是客机、复现步骤和使用的 Mod，并附上已有的反馈编号或相关日志。[提交 Issue](https://github.com/BMingSY/isaac-lan/issues)

## 贡献与许可

参与开发请参阅[贡献指南](https://github.com/BMingSY/isaac-lan/blob/main/CONTRIBUTING.md)。

禁止售卖本 Mod 或其修改版。详见[使用许可](https://github.com/BMingSY/isaac-lan/blob/main/LICENSE)。
