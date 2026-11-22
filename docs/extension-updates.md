# 原生扩展更新

首次使用通用安装包，在游戏根目录安装共享加载器 `winmm.dll`，在 `isaac-lan/backends/repentance/` 和 `isaac-lan/backends/repentance_plus/` 分别安装 `isaac_lan_probe.dll`。安装记录 `isaac-lan/installation.json` 保存所安装后端、完整游戏版本和各文件的相对路径与 SHA-256。加载器按正在运行的游戏镜像选择主体。安装时已知的游戏构建可使用对应的安装主体或工坊更新。后续游戏补丁通过工坊清单识别，每个候选都需匹配完整游戏构建号和版本标记位置。

## 启动与来源

[`loader.cpp`](https://github.com/BMingSY/isaac-lan/blob/main/src/app/loader.cpp) 在系统加载锁释放后、游戏入口执行前装配[更新选择器](https://github.com/BMingSY/isaac-lan/blob/main/src/runtime/extension_update.cpp)和[原生加载组件](https://github.com/BMingSY/isaac-lan/blob/main/src/app/extension_loader.cpp)。该阶段不初始化 Steam、不执行工坊 Lua，也不等待下载。

标准 Steam 库布局中，游戏位于 `steamapps/common/<游戏目录>`，更新来源为同一库的 `steamapps/workshop/content/250900/3817760679/isaac-lan-update`。直接读取 Steam 原始下载目录，因此不依赖游戏稍后刷新 `mods` 副本。不扫描其他 Mod，不修改工坊内容。非标准安装位置没有工坊自动发现；已缓存的兼容版本仍可使用。显式指定本隔离实例的 `ISAAC_LAN_LAB_ROOT` 时，加载器直接使用本次游戏对应的安装主体，保持夹具与候选构建一致。

对加载器安装后才适配的游戏补丁，Steam 下载对应更新后，下次启动即可加载，离线重启可使用已校验的同构建缓存。首次订阅或下载延迟时，安装时已知的游戏构建可从安装主体启动。游戏镜像缺少唯一匹配、下载不完整且无匹配缓存时，启动以游戏兼容性错误结束。加载器接口发生不兼容变化时，需要覆盖安装新版加载器。只能读取安装时构建表的旧加载器也需要覆盖安装一次以启用跨游戏补丁更新。

选完存档后，首次开局前的主菜单通过[后台检查组件](https://github.com/BMingSY/isaac-lan/blob/main/src/runtime/update_notice.cpp)每两秒补查本地更新，复用同一选择器、兼容校验与版本缓存。比较基准为当前运行主体编译时的版本，安装目录中的基础 DLL 不会触发提示；检查不加载候选 DLL、不联网、不阻塞菜单。完整且版本更高的兼容包就绪后，[游戏内弹窗](https://github.com/BMingSY/isaac-lan/blob/main/src/bridge/presentation/update_notice.lua)默认选择“退出游戏”，提示玩家退出后自行重新启动。支持键盘、手柄和鼠标，打开及关闭时等待菜单按键释放；返回键等同“继续”。选择“继续”、进入联机界面／会话或开始游戏后，本进程不再检查或提示，Lua 重建也不会重置该状态。隔离测试默认不检查真实工坊更新。

## 包契约

[发布准备工具](https://github.com/BMingSY/isaac-lan/blob/main/tools/workshop_release.py)保留完整 ZIP，并从已经校验的 ZIP 提取两个游戏版本各自的主体 DLL 和清单。工坊目录 `isaac-lan-update/` 下的 `repentance/` 和 `repentance_plus/` 分别对应忏悔和忏悔＋。加载器优先读取对应目录，并校验清单中的完整游戏构建号。遇到旧工坊包时，加载器依次查找完整构建号子目录和根目录。打包工具仅为能识别该构建的旧加载器在原位置保留同一份 DLL 和清单。SHA-256、扩展版本和游戏版本来自各后端的 `payload.json`，不另行构建主体。缺少 `loader_abi` 的旧安装包只提供手动安装，不生成自动更新载荷。

[契约常量](https://github.com/BMingSY/isaac-lan/blob/main/src/core/extension_package.h)供加载器与[打包组件](https://github.com/BMingSY/isaac-lan/blob/main/tools/extension_package.py)共用。工坊的两个游戏目录各有一个主体 DLL 和两份 ASCII 清单。默认读取 `manifest-v2.txt`，与旧加载器共用的 `manifest.txt` 用于已知构建。每行以换行结束，支持 LF 和 CRLF。

| 行 | 内容 |
| --- | --- |
| 1 | `manifest-v2.txt` 使用 `IsaacLANUpdate/2`，`manifest.txt` 使用 `IsaacLANUpdate/1` |
| 2 | `version=<主版本.次版本.补丁版本>`，三个无前导零的无符号 32 位整数 |
| 3 | `game_build=<游戏版本>` |
| 4 | `loader_abi=<加载器 ABI>` |
| 5 | `sha256=<主体 DLL 的 64 位小写十六进制 SHA-256>` |
| 6（仅格式 2） | `backend=<repentance 或 repentance_plus>`，与工坊来源目录一致 |
| 7（仅格式 2） | `version_rva=<十进制相对虚拟地址>`，指向游戏镜像中的完整版本标记 |

清单不超过 1024 字节，主体不超过 64 MiB；当前 ABI 为 1。自动候选的 ABI 必须与加载器一致，游戏构建必须与运行中的游戏匹配，扩展版本必须高于加载器的安装基线，版本按三个整数比较。加载后、启动前还核对 DLL 的 `unsigned __cdecl IsaacLanLoaderABI()` 导出返回值，并要求存在 `DWORD WINAPI IsaacLanBootstrap(void*)`，启动参数为 `nullptr`。主体 `DllMain` 不安装 Hook 或访问游戏对象，初始化统一留在启动入口，以便 ABI 不匹配时可以卸载候选并继续回退。校验用于完整性与契约检查；载荷来源沿用该工坊条目的信任边界，SHA-256 不构成发布者签名。

打包时从已校验的 ZIP 读取各后端的 `game-profile.json`，核对该文件的 SHA-256、后端、游戏构建号及标记边界。对安装时未知的游戏，加载器只在两个固定工坊目录和私有缓存中检查格式 2 清单，按给定位置匹配完整构建号及其分隔符。多个完整候选若匹配不同的构建身份，加载器拒绝启动。主体初始化时另行校验游戏节区与原生入口签名。

## 缓存与失败边界

更新选择器把主体复制到 `isaac-lan/versions/.staging-<事务标识>`，核对复制后的 SHA-256，并再次读取源清单确认一致；清单写入成功后，将整个目录重命名为 `<版本>-<SHA-256>-v2`（格式 2）或 `<版本>-<SHA-256>`（格式 1）。缓存内的 `manifest.txt` 保存实际核验过的清单，供离线启动使用。游戏不会加载暂存目录，也不直接加载可能被 Steam 更新的源 DLL。普通失败只清理该事务创建的固定文件；崩溃残留的暂存目录被后续选择忽略。

候选按版本从高到低排列，源载荷在同版本下优先；缓存中的损坏清单、链接、错误哈希和加载失败候选被跳过，安装时已识别的游戏构建还可回退到本构建的安装主体。安装目录中的 DLL、安装归属记录、配置和存档不随自动更新改变。重复启动复用缓存；手动安装更高版本后，低于安装基线的旧缓存不会覆盖新安装。缓存保留以供回退，卸载后没有加载器与安装标记，缓存不会自行启用。

原生初始化开始前的复制、校验、ABI 或动态加载失败可以尝试下一候选。`IsaacLanBootstrap` 一旦开始执行，失败沿用现有关闭游戏的处理；不在可能已经安装 Hook 的进程中切换另一主体。这里的回退不表示能够自动恢复任意原生崩溃。

失败提示由加载器统一显示，优先读取主体的可选 `IsaacLanBootstrapError` 导出，否则根据返回码解释。该导出不改变 ABI 1 的启动参数和候选准入要求，完整字符串及错误码契约见[启动错误码](https://github.com/BMingSY/isaac-lan/blob/main/docs/startup-errors.md)。旧加载器的通用提示需通过完整安装包更新，不能仅靠工坊主体更新替换。

主体启动日志记录实际模块路径；联机扩展指纹也计算实际加载模块的字节，因此不同缓存版本继续受现有构建准入检查约束。工坊缺失或失败原因在加载器阶段写入 Windows 调试输出。
