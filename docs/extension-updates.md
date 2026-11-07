# 原生扩展更新

首次安装仍使用完整安装包。安装器把 `winmm.dll`、根目录主体 DLL 和归属记录写入游戏目录；加载器包含本次安装的版本号，作为自动更新的最低版本。后续正常启动时，加载器可采用 Steam 已下载的完整、兼容且版本更高的主体 DLL，无需再次执行安装器。

## 启动与来源

[`loader.cpp`](https://github.com/BMingSY/isaac-lan/blob/main/src/app/loader.cpp) 在系统加载锁释放后、游戏入口执行前装配[更新选择器](https://github.com/BMingSY/isaac-lan/blob/main/src/runtime/extension_update.cpp)和[原生加载组件](https://github.com/BMingSY/isaac-lan/blob/main/src/app/extension_loader.cpp)。该阶段不初始化 Steam、不执行工坊 Lua，也不等待下载。

标准 Steam 库布局中，游戏位于 `steamapps/common/<游戏目录>`，更新来源为同一库的 `steamapps/workshop/content/250900/3817760679/isaac-lan-update`。直接读取 Steam 原始下载目录，因此不依赖游戏稍后刷新 `mods` 副本。不扫描其他 Mod，不修改工坊内容。非标准安装位置没有工坊自动发现；已缓存的兼容版本仍可使用。显式指定本隔离实例的 `ISAAC_LAN_LAB_ROOT` 时，加载器只加载根目录主体 DLL，保持夹具与候选构建一致。

Steam 未下载或仍在下载的更新不保证在本次启动生效；本组件不提供下载器或运行时热替换。首次订阅、下载延迟和 Steam 离线时，继续从本地兼容缓存或安装版本启动。`winmm.dll` 自身以及不兼容的加载器 ABI 升级仍需关闭游戏后重新安装。

## 包契约

[发布准备工具](https://github.com/BMingSY/isaac-lan/blob/main/tools/workshop_release.py)保留完整 ZIP，并从已经校验的 ZIP 提取主体 DLL 到上述更新子目录。SHA-256、扩展版本、游戏版本来自 ZIP 的 `payload.json`，不另行构建主体。缺少 `loader_abi` 的旧安装包只提供手动安装，不生成自动更新载荷。

[契约常量](https://github.com/BMingSY/isaac-lan/blob/main/src/core/extension_package.h)同时供 C++ 消费者和 [Python 打包组件](https://github.com/BMingSY/isaac-lan/blob/main/tools/extension_package.py)使用。`manifest.txt` 为 ASCII，依次包含以下五行，每行以换行结束；读取支持 LF 和 CRLF，不接受附加行：

| 行 | 内容 |
| --- | --- |
| 1 | `IsaacLANUpdate/1` |
| 2 | `version=<主版本.次版本.补丁版本>`，三个无前导零的无符号 32 位整数 |
| 3 | `game_build=<游戏版本>` |
| 4 | `loader_abi=<加载器 ABI>` |
| 5 | `sha256=<主体 DLL 的 64 位小写十六进制 SHA-256>` |

清单不超过 1024 字节，主体不超过 64 MiB；当前 ABI 为 1。自动候选的 ABI 和游戏版本必须与加载器一致，扩展版本必须高于加载器的安装基线，版本按三个整数比较。加载后、启动前还核对 DLL 的 `unsigned __cdecl IsaacLanLoaderABI()` 导出返回值，并要求存在 `DWORD WINAPI IsaacLanBootstrap(void*)`，启动参数为 `nullptr`。主体 `DllMain` 不安装 Hook 或访问游戏对象，初始化统一留在启动入口，以便 ABI 不匹配时可以卸载候选并继续回退。校验用于完整性与契约检查；载荷来源沿用该工坊条目的信任边界，SHA-256 不构成发布者签名。

## 缓存与失败边界

更新选择器把主体复制到 `isaac-lan/versions/.staging-<事务标识>`，核对复制后的 SHA-256，并再次读取源清单确认一致；清单写入成功后，将整个目录重命名为 `<版本>-<SHA-256>`。游戏不会加载暂存目录，也不直接加载可能被 Steam 更新的源 DLL。普通失败只清理该事务创建的固定文件；崩溃残留的暂存目录被后续选择忽略。

候选按版本从高到低排列，源载荷在同版本下优先；缓存中的损坏清单、链接、错误哈希和加载失败候选被跳过，最后回退到根目录安装版本。根目录 DLL、安装归属记录、配置和存档不随自动更新改变。重复启动复用缓存；手动安装更高版本后，低于安装基线的旧缓存不会覆盖新安装。缓存保留以供回退，卸载后没有加载器与安装标记，缓存不会自行启用。

原生初始化开始前的复制、校验、ABI 或动态加载失败可以尝试下一候选。`IsaacLanBootstrap` 一旦开始执行，失败沿用现有关闭游戏的处理；不在可能已经安装 Hook 的进程中切换另一主体。这里的回退不表示能够自动恢复任意原生崩溃。

主体启动日志记录实际模块路径；联机扩展指纹也计算实际加载模块的字节，因此不同缓存版本继续受现有构建准入检查约束。工坊缺失或失败原因在加载器阶段写入 Windows 调试输出。
