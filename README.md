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

## 配置与日志

首次启动会在游戏目录生成 `isaac-lan/config.ini`，修改后重启游戏生效：

```ini
[logging]
level = INFO

[diagnostics]
performance = false
sample_interval_ms = 1000
```

`level` 支持 `DEBUG`、`INFO`、`WARN`、`ERROR`，默认不写 DEBUG 日志。需要排查卡顿时，可将 `performance` 改为 `true`；采样间隔支持 100–60000 毫秒。

日志位于原版 `log.txt` 同级目录下的 `isaac-lan/logs/`，通常在 `文档/My Games/Binding of Isaac Repentance+/`。每次启动单独建目录，每局再按序号、种子和主客机分目录：启动及退出记录在 `startup.log`，局内记录在 `runtime.log`；开启性能统计后，同目录还有 `performance.jsonl`。历史日志一直保留，需要时可手动删除旧目录。升级和卸载会保留配置、联机存档及历史日志。

## 创建与加入

1. 房主设置端口，点击“创建房间”，把自己的局域网 IPv4 地址和端口告诉队友。
2. 队友填写房主 IP 和端口，点击“加入房间”。
3. 所有人选择角色并准备，由房主开始游戏。

使用 **TCP**，默认端口为 **29506**，可以在界面中修改。

## 重连

客机掉线后返回局域网大厅，重连后回到房主当前所在房间。

## 卸载

关闭游戏，运行 `Uninstall.cmd`，选择同一个 `isaac-ng.exe`。卸载会保留联机存档。

## 技术文档

[架构与开发文档](https://github.com/BMingSY/isaac-lan/tree/main/docs)


## 源码构建

需要 CMake、Ninja、32 位 MinGW-w64，以及 Dear ImGui v1.92.6、MinHook v1.3.4 的源码。

```sh
cmake -S . -B build-win32 -G Ninja \
  -DCMAKE_TOOLCHAIN_FILE=cmake/mingw-x86.cmake \
  -DCMAKE_BUILD_TYPE=Release \
  -DIMGUI_SOURCE_DIR=/path/to/imgui \
  -DMINHOOK_SOURCE_DIR=/path/to/minhook
cmake --build build-win32
python3 tools/build_package.py --build build-win32 --output dist/Isaac-LAN-J460
```

## 问题与建议

请提交到 [Issues](https://github.com/BMingSY/isaac-lan/issues)，写明游戏版本、主客机、复现步骤和使用的其他 Mod；遇到联机异常时可以附上 `isaac-lan/logs/` 中对应启动的完整目录。
