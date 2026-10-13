# 暂停菜单验证（2026-10-14）

修复前，房主的 Game::Controls 消费了客机的菜单输入，客机只在暂停状态切换时重放 Controls。结果是客机不能操作自己的光标，还会改变房主的 Options。这与羔羊跑圈的 Yes／No 返回值错误是两处独立问题。

修复复用原版暂停菜单，通过本机输入与视图操作光标、Items 和 Options；共享暂停、恢复、离队与保存退出保持现有会话命令。原生调用和所有权说明见[会话文档](https://github.com/BMingSY/isaac-lan/blob/main/docs/session-lifecycle.md#暂停与退出)，实现见[暂停菜单后端](https://github.com/BMingSY/isaac-lan/blob/main/src/engine/versions/j460/pause_menu.cpp)与[会话调度](https://github.com/BMingSY/isaac-lan/blob/main/src/runtime/session.cpp)。未增加网络字段；协议仍为 28、WorldState schema 15，扩展指纹包含实际 DLL 内容。

## 离线检查

- Windows x86 构建与 J460 原生入口签名校验通过。
- 74 项 C++／Lua 回归、28 项网络测试和四套原生 ABI 测试通过。
- [暂停菜单 ABI 测试](https://github.com/BMingSY/isaac-lan/blob/main/tests/pause_menu_test.cpp)共 12 组：真实 thiscall 接收者、Show／Controls／Hide、Options 保存顺序、菜单索引借入与恢复、无效角色列表、同帧方向后确认、恢复／退出拦截、嵌套输入作用域、普通设置、玩法输入和暂停输入过滤。Options 保存覆盖重复关闭、Root／Items 不保存及空 Manager 边界。
- C++、CMake、Lua、Python 格式与脚本语法检查通过；Windows CI 增加暂停菜单 ABI 执行。

## 集中实机验收

`2026-10-14-01` 使用另外一对空闲隔离实例，用户正在操作的手测窗口未改动。主机 PID 9652、客机 PID 33608，分别只启动一次；开局、离队、重连、存退和续局全部复用这对进程，耗时 77.73 秒。

原生版本为 Repentance+ `1.9.7.17.J460`，最终 DLL SHA-256 为 `2bdb58b1a0057d0c21fd52f0862a72da8461adc491d9e5dc64dd1ec27ae8f598`。主机使用以撒，客机使用抹大拉；夹具为两人分别设置悲伤洋葱／内眼和共享 20 金币，以核对玩家身份与存档。客机资格仅在启动前临时解锁成就 1，结束后恢复原始资料。

| 检查 | 结果 |
| --- | --- |
| 客机真实窗口 Escape 打开暂停 | 通过；两端暂停，发起者为 P2 |
| 客机上移并打开 My Stuff | 通过；客机 page 3、controller 2，房主保持 root、selection 2、controller 1 |
| 客机本人的 Items 画面 | 通过；录制客机第 29 帧显示抹大拉头像与美味的心；对应主机第 54 帧仍停留 Resume Game |
| 客机打开 Options 并修改 Music | 通过；客机音量从 0 变为 0.1，主机始终为 0.2；返回菜单后设置保留 |
| 客机确认 Resume Game | 通过；双方恢复，原生关闭动画完成后 page 0 |
| 8 次单帧 Start 按键 | 通过；两端各记录 8 个暂停／恢复边沿，无丢失或重复 |
| 客机确认 Exit Game | 通过；仅客机返回大厅，主机仍暂停，恢复权限转给主机 |
| 主机恢复，客机重新加入 | 通过；恢复原 P2 栏位、角色与独立道具 |
| 主机确认 Exit Game 后普通 Resume | 通过；全队返回大厅并续局，角色、两人的独立道具和 20 金币保留 |
| 进程、堆与资料清理 | 通过；两端退出码 0、heap watcher 0、转储 0，profile、Mod 数据与联机存档恢复哈希一致 |

双端录制画面已检查，结果保存在本轮 `report.json`、`result.json`、`log.txt` 和 `frames.csv`。测试入口为[暂停验收 runner](https://github.com/BMingSY/isaac-lan/blob/main/tools/run_pause_menu.py)，操作夹具为[原生 GUI 场景](https://github.com/BMingSY/isaac-lan/blob/main/tests/state_pause_menu.lua)，只读菜单状态用于断言，未直接写菜单页或光标。

“队友恢复时另一端仍在 Options”的保存顺序已由离线 ABI 覆盖，本轮实机在本机 Back 后恢复，未单独覆盖该时序。三／四人暂停菜单与其他原生版本未在本轮实测。
