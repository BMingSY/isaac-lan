# Isaac LAN

《以撒的结合：忏悔＋》局域网联机扩展，支持 2–4 人，适用于 Windows 版 **v1.9.7.17.J460**。

## 功能

- 共享楼层，分房探索与战斗，随时进入队友房间汇合。
- 允许加载其他 Mod，保留原版多人 UI 和官方联机入口。
- 小地图显示玩家位置，支持 Ping 显示和断线重连。

进度差异、成就解锁、存档续玩与连接排查见[常见问题（FAQ）](https://github.com/BMingSY/isaac-lan/blob/main/docs/faq.md)。

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

首次启动会生成扩展配置文件 `config.ini`，修改后重启游戏生效：

```ini
[logging]
level = INFO

[diagnostics]
performance = false
sample_interval_ms = 1000
```

`level` 支持 `DEBUG`、`INFO`、`WARN`、`ERROR`，默认不写 DEBUG 日志。需要排查卡顿时，可将 `performance` 改为 `true`；采样间隔支持 100–60000 毫秒。

日志随原版 `log.txt` 保存在当前游戏的数据目录。每次启动单独建目录，每局再按序号、种子和主客机分目录：启动及退出记录在 `startup.log`，局内记录在 `runtime.log`；开启性能统计后，同目录还有 `performance.jsonl`。历史日志一直保留，需要时可手动删除旧目录。升级和卸载会保留配置、联机存档及历史日志。

## 创建与加入

1. 房主设置端口，点击“创建房间”，把自己的 IPv4 地址或域名和端口告诉队友。
2. 队友填写房主 IP／域名和端口，点击“加入房间”。
3. 所有人选择角色并准备，由房主开始游戏。

使用 **TCP**，默认端口为 **29506**，可以在界面中修改。

## 重连

客机掉线后返回局域网大厅，重连后回到房主当前所在房间。

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
