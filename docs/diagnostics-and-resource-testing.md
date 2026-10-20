# 诊断与资源检查

配置解析与有界统计在 [`core/`](https://github.com/BMingSY/isaac-lan/tree/main/src/core)，文件读写在 [`app/configuration.*`](https://github.com/BMingSY/isaac-lan/tree/main/src/app)，运行测量在 [`diagnostics/`](https://github.com/BMingSY/isaac-lan/tree/main/src/diagnostics)，Lua 阶段计时在 [`bridge/diagnostics/`](https://github.com/BMingSY/isaac-lan/tree/main/src/bridge/diagnostics)。诊断选项只控制记录，不控制玩法、状态字段或背压。

## 配置与日志

扩展配置文件 `config.ini` 在首次启动时生成，已有配置保留原文和值，只补齐缺失项及说明注释，修改后需重启。默认 INFO、关闭性能统计、采样间隔 1000 ms。

- UTF-8，可带 BOM／CRLF；支持空行和 `;`／`#` 开头的注释，不支持行尾注释。
- 键和值区分大小写，重复键取第一次；未知键和非法值写启动日志，非法项回退默认值，文件超过 64 KiB 则整份回退。
- `[logging] level = DEBUG` 开启明细；`[diagnostics] performance = true` 开启性能窗口。安装器不覆盖用户配置。

日志随原版 `log.txt` 归档，按启动和局次区分。`startup.log` 记录启动与退出，`runtime.log` 记录局内事件，开启性能统计后另有 `performance.jsonl`。

每局用新序号，同种子继续也不覆盖；退出后写回启动日志。记录含毫秒时间、时区、等级和 PID，消息换行转义。切换目录关闭旧句柄，错误立即刷新，路径确定前的缓存最多 256 KiB。没有自动轮转或总量限制，可手动清理旧目录。

## 性能口径

| 数据 | 含义 |
| --- | --- |
| 进程资源 | 本局时间／窗口时长、CPU 占单核比例、私有内存、工作集、句柄；读取失败为 `null` |
| 阶段耗时 | 渲染间隔，采集／应用、编码／解码、库存、实体、网格、精灵、压缩／解压；应用另分位置、角色、地图、房间和提交阶段 |
| 对象与队列 | Lua 堆、实体／网格／地图规模、连接、队列／状态容量、退休会话 |
| `cached_world_bytes` | 完整视图历史的分配容量 |
| `world_in_flight_bytes`／`world_in_flight_states` | 发送窗口中的未确认载荷／视图数；不含记录超时后仍在重传的 UDP 恢复包 |
| `world_delivery_window`／`world_oldest_unapplied_ms` | 有在途视图的连接窗口总和／最旧未确认视图的年龄 |
| `input_coalesced` | 当前连接合并的未发送输入数量；不包含已交给传输协议的输入 |
| `world_snapshots_total`／`world_delta_snapshots_total` | 当前会话累计视图数／增量数 |
| `world_raw_bytes_total`／`world_wire_bytes_total`／`world_full_wire_bytes_total` | 原始字节／已发布压缩载荷／同批完整压缩对照量 |

载荷计数包含实际发送的低频依赖以及大视图校验片和片头；不含 TCP／UDP／ENet 封装、重传、frp 或可靠存档流量；实际链路用量以中继记录为准。`compress` 已包含 `delta.encode`，二者不能相加。DEBUG 的 `state_transfer` 提供 `raw`、`wire`、`full_wire`、`delta`、`base`。

网络压缩／解压计时由工作线程产生，通过有界队列交回主线程；队列已满时丢弃诊断样本，不阻塞传输。`checkpoint_capture` 区分主线程原生采集与存档封装耗时；`checkpoint_pack` 记录原始／压缩字节数与后台耗时；`checkpoint_received` 记录后台还原耗时及从启动头到还原完成的时间。这些数据不包含后续原生 Continue 和首份实时视图应用，不能当成完整重连耗时。

`input.present` 测量本机采样到首次绘制回调完成，`input.ack` 测量采样到包含对应确认号的权威视图应用完成；两者都使用本机单调时钟，不包含操作系统送达前的硬件输入时间，也不证明某个射击效果实际触发。`view.age` 是时钟映射估算的采集到应用年龄，不能替代同机日志的实测视图年龄。`prediction.corrections` 记录重放后的纠偏次数，`sum_millipixels`／`max_millipixels` 以千分之一坐标单位记录总量／最大值；`prediction.bucket1`～`bucket5` 分别统计 ≤1、(1,4]、(4,16]、(16,64]、>64 的纠偏幅度。计数包含零偏差，按会话清理，不写入游戏界面。

均值与最大值使用窗口收到的全部样本；p50／p95／p99 使用最近 512 个样本，成本名及计数器各最多 64 个并按窗口清理。Lua 堆为只读采样，不强制游戏 GC；关闭统计时直接调用原函数。

将 `ISAAC_RUN_OUTPUT` 和 `ISAAC_PERFORMANCE_SUMMARY` 设为本轮记录与汇总输出后执行：

```sh
python3 tools/check_performance.py "$ISAAC_RUN_OUTPUT" --output "$ISAAC_PERFORMANCE_SUMMARY"
```

汇总按调用次数加权平均，列出最慢窗口百分位，不把窗口百分位当全局百分位。定位卡顿应同时看渲染间隔、应用成本、网络队列和对象规模；跨层资源加载造成的内存增长不能直接判为泄漏。堆调试、并发负载和录像会干扰性能，需分开对照。

## 带宽测量

TCP 的 [`tools/delayed_relay.py`](https://github.com/BMingSY/isaac-lan/blob/main/tools/delayed_relay.py) 对所有客机下行共享预算，上行有独立共享预算，默认不限速；375000 字节／秒对应十进制 3 Mbps。`--relay-control` 接受 JSON 中的 `downstream_bytes_per_second`、`upstream_bytes_per_second`、`delay_ms`、`jitter_ms`、`stall_every_ms` 与 `stall_ms`，配置先完整校验再应用。抖动和停传保持字节顺序，不删除 TCP 流内容，也不代表真实 IP 丢包。UDP 使用 [`tools/datagram_relay.py`](https://github.com/BMingSY/isaac-lan/blob/main/tools/datagram_relay.py)，另支持真实报文丢失、复制和重排。`run_network_engine.py --record-relay` 按所选协议保存 TCP 字节流或带时间戳的 UDP 报文；逐秒中继记录包含双向转发字节数与实际配置。弱网功能与状态年龄验收见[开发测试说明](https://github.com/BMingSY/isaac-lan/blob/main/docs/development-and-testing.md)。

`isaac_lan_replay_world` 使用生产解码器还原状态，再比较同批、同更新率的 `wire` 与 `full_wire`，无需启动游戏。它支持旧字节补丁和 Zstd prefix 记录；`full_wire` 始终是当前 Zstd 完整帧对照，CSV 的 `full_codec` 标明算法，不能将旧记录的比值解释为同算法的增量收益。[`tools/analyze_delirium_performance.py`](https://github.com/BMingSY/isaac-lan/blob/main/tools/analyze_delirium_performance.py) 汇总载荷、应用频率和帧间隔；状态滞后需要 `tick_ms`／`utc_ms` 时钟校准，战斗成本排除加载窗口。

## 编解码基准

[`benchmark_state_codec.py`](https://github.com/BMingSY/isaac-lan/blob/main/tools/benchmark_state_codec.py) 在无需游戏的 Linux Lua 5.3 中比较生产 C++ 绑定与 Lua 参考实现。使用独立 Release 构建，避免 sanitizer 和调试构建干扰计时：

```sh
cmake -S . -B build-codec -DISAAC_LAN_BUILD_ENGINE=OFF -DCMAKE_BUILD_TYPE=Release
cmake --build build-codec --target isaac_lan_state_codec_runner
python tools/benchmark_state_codec.py --runner build-codec/isaac_lan_state_codec_runner \
  --iterations 100 --output "$ISAAC_CODEC_REPORT"
```

默认输入是模拟库存和实体字段的合成状态，先核对字节一致，再测编码、解码和同房三客机片段复用；不能据此推定游戏帧率。`--snapshot` 可输入一份已还原的完整二进制视图。输出保存逐项 CPU 时间、样本数、均值／P95、速度比、执行器哈希和 JSON／JUnit；缺少一端测量、输入规模不一致或执行失败不能计为完成。报告通过表示对照执行完整，不表示实机性能已通过。

[`benchmark_compression.py`](https://github.com/BMingSY/isaac-lan/blob/main/tools/benchmark_compression.py)比较真实快照的 miniz、LZ4、Zstd 完整帧，以及完整发送路径的 miniz 字节补丁和 Zstd prefix。构建时将 `ISAAC_LAN_LZ4_SOURCE_DIR` 指向上游 LZ4 1.10.0 的 `lib` 目录，生成 `isaac_lan_compression_benchmark`；LZ4 只用于基准，不链接到游戏 DLL。

```sh
python tools/benchmark_compression.py --runner "$ISAAC_COMPRESSION_RUNNER" \
  --pair "$ISAAC_BASE_SNAPSHOT" "$ISAAC_NEXT_SNAPSHOT" \
  --iterations 100 --output "$ISAAC_COMPRESSION_REPORT"
```

每组输入是已确认基线与下一份完整字节。一个 `--pair` 测同视图，多次提供（最多三组）测不同视图；分别执行 2／3／4 人所需的发送端压缩和各接收端解压，解压计时是各客机之和。每次还原必须逐字节相同，报告保留输入与执行器哈希、实际大小、均值／P95／P99、上下文内存及 JSON／JUnit。计时包括 prefix 索引和完整帧候选，不含网络、Lua 和游戏绘制；在目标 Windows x86 Release 构建中单独执行，不能与实机性能轮次并发。

## 按需性能与资源回归

日常命令见[开发与测试](https://github.com/BMingSY/isaac-lan/blob/main/docs/development-and-testing.md)。CI 覆盖 sanitizer、Lua 实体反复创建／删除与弱引用释放、慢消费者下的有界传输，以及重复分局后的日志句柄清理；不据此推定游戏或未执行 Hook 的资源行为。

性能与压力测试不属于默认发版范围。需要定位相关问题时，单独使用一组隔离主客机，选择对应负载；道具压力套件在启动前和关闭后检查机器上是否还有游戏进程，有其他运行实例时不能计为有效性能轮次。测量期间也不得启动其他游戏或 CPU 密集任务。例如长流程资源检查可运行：

```sh
python3 tools/run_special_routes.py \
  --host "$ISAAC_HOST_LAB" \
  --client "$ISAAC_CLIENT_LAB" \
  --case campaign --performance --output "$ISAAC_RUN_OUTPUT"
```

`engine_test.py run item-audit -- --mode stress ...` 默认开启性能统计、关闭堆观察与录像；原生异常专项可加 `--heap-check`，画面可加 `--record`，两者的测量需与纯性能轮次区分。其他道具审计模式仍保留堆观察。`stress:idle-baseline`、`stress:idle-inventory-100/300/500` 和 `stress:idle-copies-1000` 禁止自动攻击，要求双端至少 100 个渲染样本且 P95 不超过 33.33 ms；原有未带 `idle-` 的场景仍包含短暂攻击，必须分别解释。

`--no-phase-profile` 将本轮隔离配置的详细诊断显式关闭，用于对照默认生产设置；夹具自身仍逐帧记录渲染间隔，并记录每次采集、应用耗时和字节数，验收预算不变。大量实体下，逐实体／精灵的详细计时会干扰结果，基线与候选必须使用同一诊断设置。

较慢的基线可用 `--case-timeout` 延长单用例看门狗，以完成相同目标 tick 的对照；它不改变道具负载、采样起点或帧耗时预算。原超时轮次必须保留。

`--verify-codec` 在每个场景的双端各核对一次真实视图的新旧编码，并保存原始快照及下一 tick 的快照；同时将泪弹、跟班和效果实体的原生批量字段与游戏 Lua API 对照，客机还检查写入结果与非法数组无写入。压力场景在第 150 tick 的统计窗口前执行；`codec_verified`／`entity_fields_verified` 是独立证据，不替代场景完成与退出结果。

`campaign` 使用固定路线、Boss 房定位、保护和伤害加速，原版战斗、拾取、出口、换层及羔羊结局仍实际执行；不代表随机无辅助通关。默认不录画面，按需 `--record`。隔离资料逐文件备份／恢复，进程非零退出仍判整轮失败。

前置解锁由 [`tools/progress_fixture.py`](https://github.com/BMingSY/isaac-lan/blob/main/tools/progress_fixture.py) 在启动前写入隔离存档，核对 J460 文件头、区段和校验算法，以临时文件原子替换；必须已有原版基线；角色菜单初始化后禁止修改内存解锁表。

## 原生异常与堆检查

Boss、转场与退出验收的异常采集与性能压测分别安排。`--heap-check` 用独立的 `isaac_lan_heap_watch.exe` 观察已标记目录和已校验路径的进程。异常上下文复制到实验共享区，转储完成后继续原异常链；最多前三次异常、每次最多等 30 秒，无观察器时不等待。正常关闭预留 45 秒，超时终止必须判失败。

完整转储先写 Windows 临时目录，再复制到产物的转储归档；复制失败保留临时文件并报错，不打入安装包。观察器不改 IFEO／注册表、不附加调试器；fail-fast 或更早启动错误不保证捕获，仍检查退出结果。Windows CI 用合成进程验证转储链路，不启动游戏，也不把“未观察到异常”当作已排除所有堆损坏。
