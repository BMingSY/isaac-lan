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
| 阶段耗时 | 渲染间隔，采集／应用、编码／解码、库存、实体、网格、精灵、压缩／解压 |
| 对象与队列 | Lua 堆、实体／网格／地图规模、连接、队列／状态容量、退休会话 |
| `cached_world_bytes` | 完整视图历史的分配容量 |
| `world_in_flight_bytes`／`world_in_flight_states` | 未确认载荷／视图数 |
| `world_snapshots_total`／`world_delta_snapshots_total` | 当前会话累计视图数／增量数 |
| `world_raw_bytes_total`／`world_wire_bytes_total`／`world_full_wire_bytes_total` | 原始字节／实际载荷／同批完整压缩对照量 |

载荷不含 TCP、frp 或可靠存档流量。`compress` 已包含 `delta.encode`，二者不能相加。DEBUG 的 `state_transfer` 提供 `raw`、`wire`、`full_wire`、`delta`、`base`。

均值与最大值使用窗口全部样本；p50／p95／p99 使用最近 512 个样本，成本名及计数器各最多 64 个并按窗口清理。Lua 堆为只读采样，不强制游戏 GC；关闭统计时直接调用原函数。

将 `ISAAC_RUN_OUTPUT` 和 `ISAAC_PERFORMANCE_SUMMARY` 设为本轮记录与汇总输出后执行：

```sh
python3 tools/check_performance.py "$ISAAC_RUN_OUTPUT" --output "$ISAAC_PERFORMANCE_SUMMARY"
```

汇总按调用次数加权平均，列出最慢窗口百分位，不把窗口百分位当全局百分位。定位卡顿应同时看渲染间隔、应用成本、网络队列和对象规模；跨层资源加载造成的内存增长不能直接判为泄漏。堆调试、并发负载和录像会干扰性能，需分开对照。

## 带宽测量

[`tools/delayed_relay.py`](https://github.com/BMingSY/isaac-lan/blob/main/tools/delayed_relay.py) 对所有客机下行共享预算，反向输入保留固定延迟；375000 字节／秒对应十进制 3 Mbps。`run_network_engine.py --record-relay` 保存主机原始字节流和逐秒总下行。

`isaac_lan_replay_world` 使用生产解码器还原状态，再比较同批、同更新率的 `wire` 与 `full_wire`，无需启动游戏。[`tools/analyze_delirium_performance.py`](https://github.com/BMingSY/isaac-lan/blob/main/tools/analyze_delirium_performance.py) 汇总载荷、应用频率和帧间隔；状态滞后需要 `tick_ms`／`utc_ms` 时钟校准，战斗成本排除加载窗口。

## 按需性能与资源回归

日常命令见[开发与测试](https://github.com/BMingSY/isaac-lan/blob/main/docs/development-and-testing.md)。CI 覆盖 sanitizer、Lua 实体反复创建／删除与弱引用释放、慢消费者下的有界传输，以及重复分局后的日志句柄清理；不据此推定游戏或未执行 Hook 的资源行为。

性能与压力测试不属于默认发版范围。需要定位相关问题时，单独使用一组隔离主客机，选择对应负载；例如长流程资源检查可运行：

```sh
python3 tools/run_special_routes.py \
  --host "$ISAAC_HOST_LAB" \
  --client "$ISAAC_CLIENT_LAB" \
  --case campaign --performance --output "$ISAAC_RUN_OUTPUT"
```

`campaign` 使用固定路线、Boss 房定位、保护和伤害加速，原版战斗、拾取、出口、换层及羔羊结局仍实际执行；不代表随机无辅助通关。默认不录画面，按需 `--record`。隔离资料逐文件备份／恢复，进程非零退出仍判整轮失败。

前置解锁由 [`tools/progress_fixture.py`](https://github.com/BMingSY/isaac-lan/blob/main/tools/progress_fixture.py) 在启动前写入隔离存档，核对 J460 文件头、区段和校验算法，以临时文件原子替换；必须已有原版基线；角色菜单初始化后禁止修改内存解锁表。

## 原生异常与堆检查

Boss、转场与退出验收的异常采集与性能压测分别安排。`--heap-check` 用独立的 `isaac_lan_heap_watch.exe` 观察已标记目录和已校验路径的进程。异常上下文复制到实验共享区，转储完成后继续原异常链；最多前三次异常、每次最多等 30 秒，无观察器时不等待。正常关闭预留 45 秒，超时终止必须判失败。

完整转储先写 Windows 临时目录，再复制到产物的转储归档；复制失败保留临时文件并报错，不打入安装包。观察器不改 IFEO／注册表、不附加调试器；fail-fast 或更早启动错误不保证捕获，仍检查退出结果。Windows CI 用合成进程验证转储链路，不启动游戏，也不把“未观察到异常”当作已排除所有堆损坏。
