# 启动错误码

启动错误码由 [`startup_error.h`](https://github.com/BMingSY/isaac-lan/blob/main/src/core/startup_error.h) 统一定义，供主体、原生后端和加载器共用。编号是 `IsaacLanBootstrap` 的返回值及失败退出码，不是 Windows 系统错误码；已经分配的编号不重新解释，拆分原因使用新编号。`0` 表示成功。

加载器在失败时显示中文原因、对应操作和错误码。主体通过可选的 `const wchar_t* __cdecl IsaacLanBootstrapError()` 导出提供完整诊断，包含可用的失败路径、系统错误类别与编号、具体接口信息；它返回模块持有的 UTF-16 字符串，不跨 DLL 分配或释放内存，借用期限为下一次记录失败或模块卸载之前。加载器只在启动返回非零后调用，导出缺失、返回空指针或空文本时按错误码解释；未知编号保留数值并提示反馈，不推断为版本问题。

主体同时尝试写入 `startup_failure=` 错误日志和 Windows 调试输出。日志目录本身不可用时可能没有日志，弹窗仍可读取诊断。版本不兼容详情由同一弹窗显示，不再由主体另开弹窗。主体启动一旦开始，任何失败都关闭当前进程，不尝试切换到另一 DLL。

完整提示需要支持该导出的 `winmm.dll`。工坊自动更新只替换主体，已安装的加载器需通过完整安装包更新；旧加载器仍会显示原有通用提示和主体返回的编号。加载器 ABI 保持为 1，启动参数仍为 `nullptr`；更新及回退边界见[原生扩展更新](https://github.com/BMingSY/isaac-lan/blob/main/docs/extension-updates.md)。

## 目录与安装

| code | 名称 | 含义与排查范围 |
| --- | --- | --- |
| 10 | `LAB_ENVIRONMENT` | 隔离测试环境变量过长，缩短测试根目录 |
| 11 | `EXECUTABLE_PATH` | 游戏路径获取失败或与隔离配置不符 |
| 12 | `INSTALLATION_MARKER` | 缺少有效安装／隔离标记，核对安装目标或重新准备隔离目录 |
| 13 | `GAME_COMPATIBILITY` | 游戏文件或内存接口不兼容，查看具体校验详情 |
| 14 | `DIRECTORIES` | 兼容旧主体的目录／资料路径综合错误；仅凭此编号不能区分文档、日志、数据或隔离路径问题 |
| 28 | `DOCUMENTS_DIRECTORY` | Windows 文档目录定位失败，核对文档重定向位置及附带 HRESULT |
| 29 | `LOG_INITIALIZATION` | 日志目录创建或启动日志打开失败，核对弹窗中的路径、权限、磁盘空间、文件占用及拦截记录 |
| 30 | `DATA_DIRECTORY` | 游戏目录下的 `isaac-lan` 数据目录创建失败 |
| 31 | `LAB_PROFILE` | 隔离资料路径过长或包含换行符 |
| 100 | `EXTENSION_LOAD` | 所有候选均未能加载，查看最终安装 DLL 的路径和系统错误；旧加载器也用此码表示启动导出缺失 |
| 101 | `BOOTSTRAP_EXPORT` | 已加载的 DLL 缺少 `IsaacLanBootstrap`，核对加载器与主体来自同一安装包 |

启动前首先使用系统文档目录下的 `My Games/Binding of Isaac Repentance+/isaac-lan/logs`，隔离测试使用所属资料目录。创建启动目录及打开 `startup.log` 时保留具体失败路径和系统错误，失败的日志切换不关闭原有日志句柄；原版打开自定义 `log.txt` 后的重定向契约见[诊断与资源检查](https://github.com/BMingSY/isaac-lan/blob/main/docs/diagnostics-and-resource-testing.md)。

## 原生接口与其他失败

| code | 名称 | 初始化阶段 |
| --- | --- | --- |
| 15 | `IMPORT_BINDING` | 系统／日志导入接口，详情给出具体接口 |
| 16 | `ROOM_UPDATE` | 房间更新；兼容旧主体的挂接组件错误 |
| 17 | `HALF_UPDATE` | 游戏更新 |
| 18 | `SESSION` | 联机会话 |
| 19 | `WINDOW_FOCUS` | 窗口焦点 |
| 20 | `RENDERING` | 游戏渲染 |
| 21 | `ROOMS` | 房间同步 |
| 22 | `FRONTEND` | 菜单与脚本 |
| 23 | `COMBAT_FEEDBACK` | 战斗反馈；兼容旧主体的音效错误 |
| 24 | `PRESENTATION` | 本机显示；兼容旧主体的描边／透明度错误 |
| 25 | `REWIND` | 回溯 |
| 27 | `ITEMS` | 道具；兼容旧主体的生成道具错误 |
| 32 | `HOOK_LIBRARY` | 挂接组件，详情给出组件状态 |
| 33 | `AUDIO` | 音效 |
| 34 | `PLAYER_OUTLINES` | 玩家描边 |
| 35 | `PLAYER_OPACITY` | 玩家透明度 |
| 36 | `GENERATED_ITEMS` | 生成道具 |
| 37 | `STARTUP_EXCEPTION` | 启动过程中捕获的 C++ 异常，不表示已恢复原生崩溃 |
| 90 | `ENTRY_RESTORE` | 游戏入口恢复失败时的直接退出码；加载锁内不显示对话框 |
| 127 | `SYSTEM_EXPORT` | 系统 `winmm.dll` 缺少转发接口，核对 Windows／Proton 与接口名称或序号 |

接口失败只标识初始化阶段，不足以确认冲突的具体扩展。排查时保留错误截图、扩展版本和可用的启动日志；只对版本／接口类失败提示版本兼容性检查。
