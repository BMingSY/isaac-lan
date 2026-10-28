# 原版前端离线检查（2026-10-28）

候选 `fe273c90b8f151dcce03932de28308ee2eba177b` 的 J460 DLL、两版菜单及小地图夹具通过；HUD 组件候选为 `b88d0945eec84d1406a6d35e50ddcc9550dc9d56`。J835 尚无完整房间调度和启动装配，不能安装为完整联机后端。按用户要求未启动游戏，无进程重启或资料恢复；原版真实鼠标／手柄、菜单画面、纹理与多房间 HUD 未验证。

只读核对目标 `1.7.9b.J835`，SHA-256 为 `04469d0c3d3581936fcf85bea5f9f4f3a65b2ccf96b36310456c9626bac36dc6`。证据组 `decompiled-j835-frontend`、`-r2`、`-r3`、`-r4`、`-texture` 包含 HUD 缓存、主菜单页与输入边界、地图缓存及纹理构造；额外指令核对 `0x55f990` 的六参数绘制、原生虚表和宽高查询。`frontend-all-signatures.json` 中 150 项登记签名与样本字节和重定位掩码一致。

| 检查 | 结果与证据标识 |
| --- | --- |
| Windows x86 Release | J460 DLL、HUD、菜单和地图夹具构建通过；原版前端版本绑定参加独立夹具链接 |
| HUD | J835 在 `frontend-hud-native-r1.log` 通过，J460 在 `frontend-hud-native-r2.log` 通过；覆盖本机／双子／子实体筛选、缓存所有权、重排、断线、异常和五 Hook 回滚 |
| 小地图 | `minimap-native-r2.log` 两版通过：缓存先 Flush 再切目标、房间／拾取物作用域、像素与归一化坐标、颜色与调用栈、嵌套／异常、重连／Game 替换、Hook 冲突及非有限坐标 |
| 原生菜单 | `frontend-native-r1.log` 三项通过：两版及原有 J460 入口，覆盖页与存档资格、确认动作、独立入口、输入阻塞、返回和逐字节清理边界 |
| Lua 菜单 | `frontend-lua-r2.log` 两项通过：模式选择、原版直接进入／返回、入口点击范围、不可用页面及可见界面不重复打开 |
| 结构／格式 | 分层与版本资料 32 项通过；402 个 C++、370 个 Lua、125 个 Python、9 个 CMake 文件格式通过 |

HUD 首轮 J460 失败源于新夹具把活动字节设在 `+0x176`，修正为现有绑定的 `+0x172` 后通过；生产布局未改，原始失败保留。小地图首轮编译的夹具参数类型不符合已有 ABI 调用助手，修正为 initializer_list 并使用 `eax` 返回值字段后构建通过，日志 `minimap-build-r1.log` 保留。Lua 初次筛选未选中测试，`frontend-lua-r1.log` 不计为通过，使用正确测试名后另开 r2。

| 冻结产物 | SHA-256 |
| --- | --- |
| `isaac_lan_probe.dll` | `34d7796962cf8b938817087303c7d0a20cb68f706d650c6f71e8c3064280109d` |
| `isaac_lan_minimap_j460_test.exe` | `cfee22f62fb90b7f9e42c976383c4cb5ceeb163a5801b25f3e36eb5efd87aa24` |
| `isaac_lan_minimap_j835_test.exe` | `67ff93decff2e5391609b2194c76284491aa4d5109e86f0d007dd4c3fc20077e` |
| `isaac_lan_frontend_menu_j460_test.exe` | `2f9bc0f23b11081d654bc44c6785b12f4101e6e2041e46cc6d340cdc4f8dcc8c` |
| `isaac_lan_frontend_menu_j835_test.exe` | `3476b2cded839ffe0127ca56e454a43e75394e75010eed8e26427a65cf7ca8a0` |
| `isaac_lan_frontend_menu_test.exe` | `2f9bc0f23b11081d654bc44c6785b12f4101e6e2041e46cc6d340cdc4f8dcc8c` |

HUD 冻结清单为 `frontend-hud-artifacts/manifest.json`，本轮清单为 `frontend-artifacts/manifest.json`。原始证据与产物均留在忽略的测试目录。范围外保留 J460 真实键盘菜单丢失端口数字的已知未验证问题；原版完整联机、Boss 和路线验收未执行，模拟原生函数不代表真实绘制通过。
