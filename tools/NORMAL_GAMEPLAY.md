# 正常操作双客户端回归

在 WSL 中运行，使用已经由 `prepare_lab.py` 创建的两个独立副本
`D:\isaac-lan-lab\host-001` 和 `client-001`。两边必须带 `.isaac-lan-lab`
标记；已有游戏进程时拒绝重新使用这些目录。正式游戏的存档和 Mod 不会改动。

```sh
python3 tools/manual_gameplay.py run \
  --output artifacts/gameplay-新编号 \
  --ffmpeg /path/to/ffmpeg
```

增加 `--latency-ms 75` 可在同一流程中给 TCP 的两个方向各加入
75 ms 延迟；客机通过原版输入框改填隔离代理端口 `29507`，房主仍监听
`29506`。代理只在脚本的完整 `run` 期间运行，退出后关闭。
这代表模拟约 150 ms RTT，不能替代实际 frp 测试。

每轮必须使用新的输出目录。流程固定为种子 `LBCD 0G4M`、普通难度、
两名阿撒泻勒、额外 Mod 关闭、直接连接 `127.0.0.1:29506`。
工具从标题、存档和 Online 菜单进入局域网菜单，输入 IP、选择角色、
准备并开始。随后正常走门、捡道具、用愚者卡、射击清房、分房探索、
打 Boss、验证全队获得两份奖励、暂停与恢复、走进下一层，再检查客机第一次过门。
客机在下一层的大房间进门后继续正常射击，核对镜头稳定后角色仍在可见区域。
原版允许一名玩家连续取走两份奖励，测试按全队道具增加数量判断。
战斗助手只使用方向和射击按钮；角色死亡、走门失败、回调报错等会记录为失败。
同时过门先使用双方方向输入，再按实际位置完成尚未到达者的移动；原生过场动画消耗按键时长时，不把仍在门口等待视为已经过门。

这里没有调用换房、生成道具、回血、击杀敌人或修改网络帧的测试接口。
观察器只读取状态，输入经正常的原生手柄处理和网络发送路径执行。
固定路线的战斗仍受游戏情况影响；失败时查看记录，不能把失败结果当作通过。

输出自动保存：

- `tested-probe.dll`、`observer.lua`、`controller.py`：冻结本轮实际使用的 DLL、观察器和操作脚本。
- `actions.jsonl`：操作时间、按钮、持续时间和里程碑状态。
- `*-host.png`、`*-client.png` 及同名 JSON：两端实际画面与各自房间状态。
- `host-frames/`、`client-frames/`：连续渲染画面和 `frames.csv` 时间索引。
- `*-game-before-close.log`、`*-probe-before-close.log`：关闭任何一端前冻结的双方日志。
- `*-probe-this-run.log`：仅本次启动的原生日志，避免把隔离目录以前的错误当作本轮错误。
- `report.json`：流程结果、错误和验证范围；画面仍需检查。
- `*-final-observer.json`：关闭任意客户端之前冻结的双方最终状态，避免退出房主后只读到客机大厅。
- `*-recording.mkv`：指定 `--ffmpeg` 后，关闭两端再自动归档的无损连续录像。
- `*-filmstrip.png` 和同名 JSON：队友过门时本端画面的连续图表、帧号和时间。
- `visual-candidates.json`：本端房间保持不变时，异常黑帧的自动筛查结果。
- `*-floor-hud.jsonl` 和 `floor-hud-result.json`：从换层前到原生动画结束持续读取多人 HUD 归属，要求本机栏位保持相同玩家，避免只检查到达下一层后的结果。

画面直接在隔离进程的 `SwapBuffers` 前读取，再由后台线程编码，
可以记录被另一窗口遮挡的客户端。录制只在带标记的隔离副本且存在
`visual-capture.test` 时开启。完整游玩默认约 10 fps，并记录丢帧数；定向闪屏用例可设置 16 ms 采样间隔，实际间隔和丢帧写入时间索引。
它适合查角色、镜头、阴影和持续闪屏，不能证明不存在只持续一个渲染帧的闪屏。
本机直连也不能替代 frp 延迟测试。
黑帧筛查是提示，不能代替看画面，也不把正常换房的淡出算作队友过门闪屏。
必须对照 `large-room-clear`、`shop-separated`、`client-door-1` 的房主画面：
客机进出小商店时，房主大房间里不应出现小房间的墙面阴影边框。
另需检查 `second-floor` 和 `second-floor-arrival-settled`：两端沿用原版
多人血量、卡牌与主动栏，各自镜头和属性归属本机玩家。
没有指定 `--ffmpeg` 时保留连续 PNG；可在关闭后分别运行
`archive_gameplay.py` 和 `review_gameplay.py`，二者都接受 `--ffmpeg`。

关闭本轮后，可用 `archive_gameplay.py 本轮目录 --ffmpeg /path/to/ffmpeg`
将连续 PNG 转为无损 RGB 视频，并验证帧数与第一帧像素。关键截图、
状态和时间索引会保留，完整连续画面保存到 `*-recording.mkv`，避免每轮堆积大量 PNG。

需要根据画面调整路线时，使用同一个输出目录分步操作：

```sh
python3 tools/manual_gameplay.py launch --output /绝对路径/本轮
python3 tools/manual_gameplay.py boot --output /绝对路径/本轮
python3 tools/manual_gameplay.py pad client --buttons r+b --frames 30 --output /绝对路径/本轮
python3 tools/manual_gameplay.py door host --slot 1 --output /绝对路径/本轮
python3 tools/manual_gameplay.py fight --output /绝对路径/本轮
python3 tools/manual_gameplay.py state --output /绝对路径/本轮
python3 tools/manual_gameplay.py capture --name 检查点 --output /绝对路径/本轮
python3 tools/manual_gameplay.py close --output /绝对路径/本轮
```

方向 `u/d/l/r`，射击 `a/b/x/y` 分别为下/右/左/上，`rb` 用卡，
`start` 暂停／恢复；组合按钮用 `+` 连接。连续画面始终自动保存，
走门和战斗完成也会自动保存双方里程碑截图。

完整固定回归可一次运行：

```sh
python3 tools/validate_replica.py \
  --output artifacts/回归-新编号 \
  --latency-ms 75 --ffmpeg /path/to/ffmpeg
```

默认先运行 `gameplay`：一对客户端只从菜单连接并开局一次，在同一场游戏里依次完成
移动预测、白火变化与原生清房恢复、条件性进门保护、主动按键／电插头、项圈／九命猫复活、硫磺火蓄力条、
分房 Boss 播报、发光沙漏的主客机及跨层回退、恶魔房门、再爽／5 点骰子房／R 键，
最后检查镜子房方向和大房间镜头。项目之间清理夹具状态，保留同一场联机和游戏进程；
网络帧编号继续递增，不重开游戏。日志核对每端只有一次开局和每项检查的完成记录。
仅在定向用例已完成、等待下一项时保护闲置角色；下一项恢复正常伤害冷却，并检查没有遗留死亡／幽灵角色。普通操作的一层流程没有这项保护。
骰子房夹具准备原版 5 点地板，让角色踩上去，由原版碰撞逻辑触发重置。
白火先使用未探索的战斗房；清理房间时处理原版敌人死亡后产生的子怪，返回前移除测试白火，避免门口重复触碰。
`gameplay-suite.lua` 和同名 JSON 冻结原始用例、相对时间、源码哈希和检查点。
仅运行这些连续项目可以增加 `--cases gameplay`；已有单项名称仍可用于定位失败。

保存续玩、意外掉线及加载期间换层会改变连接生命周期，保留独立运行。
安装加载与 HUD 归属、首次 Boss 奖励与复活、房主闪屏录制也各自保留明确的准备条件。
最后再跑普通菜单和手柄输入完成的一层流程；定向夹具不代替正常游玩测试。
`check_mirror_camera.py` 检查每次渲染的
角色位移和镜头偏移；原生动画、角色身体和蓄力条仍要查看录制画面。
每轮固定同一 DLL 哈希，保存各项日志和总结果；画面仍需按上述要求检查。
连续回归自动把关键画面保存到 `gameplay/checkpoints/`，索引包含实际帧号和网络时间。
连续用例同时记录主客机画面；指定 `--ffmpeg` 时，两端退出后自动归档为无损 `host-recording.mkv`、`client-recording.mkv`，保留检查点和
`frames.csv`；否则保留全部 PNG。再爽、骰子房和 R 键核对两端楼层及保留的道具、
血量和资源；日志或录制不足会使测试失败。

增加 `--goodtrip /已安装的/goodtrip目录` 会把该 Mod 原样复制到两个隔离客户端，额外检查同时操作时的地图输入／选择光标隔离、本机房间缓存及房主执行客机传送；正式安装目录不改动。这个定向夹具先准备两个已访问的清理房间，然后用原生手柄地图／射击方向输入选择目标，不直接替换 Good Trip 的传送函数。

定向闪屏测试使用 `run_network_engine.py --native-record-view 0 --frame-ms 16` 保存实际后缓冲画面；`check_peer_flash.py 结果目录 --ffmpeg /path/to/ffmpeg` 只检查房主未换房的游戏帧，输出亮度异常候选、采样间隔及丢帧数。它能复现原生后台房间加载导致的一帧全黑，但仍不能证明采样间隙没有更短的视觉问题。
