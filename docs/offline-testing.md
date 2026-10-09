# 离线测试流程

日常开发、调试和回归默认执行离线测试。`tools/test.py` 只运行格式、语法、可移植 CTest 和 pytest，不导入游戏启动器、不读取游戏安装或存档、不发送窗口输入。实机回归保留在独立工具中，集中在最终验收阶段执行。

## 日常测试与最终验收约定

1. 日常迭代先用离线用例复现和修复问题，运行与改动相关的检查；完成实现后执行完整离线检查和所需构建。
2. 最终验收前列出本次所有待实机验证的问题、相关回归和检查项，注明预期结果、准备条件，以及是否确实需要退出／重启游戏。
3. 将可共用游戏进程的场景集中在同一次启动中验证；联机场景主机和客机各启动一次，尽量复用进程和连接。每项结束清理夹具、恢复必要状态，再验证下一项。
4. 退出、重新启动、启动时加载等必须关闭游戏的检查单独安排。无需退出游戏的换局、重连等优先复用进程；仅在场景需要或进程异常无法恢复时关闭／重启，并记录原因。
5. 逐项记录通过、失败、阻塞或未执行及对应证据；漏测项目继续保留为待验证。实机发现的问题优先沉淀为离线回归，修复后再集中复验。

当前 `gameplay` 已能合并部分兼容场景，但现有实机工具尚未保证全部用例自动复用一次启动。执行最终验收前应按清单安排顺序和分组，不能直接把默认工具的多次启动当成一次集中验收。

任务明确要求不启动游戏时，最终实机验收也保留为待验证。离线通过只证明所覆盖的规则，不代替原生引擎和画面的验证。

## 运行

需要 Python 3.10+、CMake、C++ 编译器和 Lua 5.3。使用与游戏相同的 Lua 语言版本；只有其他版本时直接失败，不跳过相关检查。安装依赖：

```sh
python3 -m venv .deps/checks
.deps/checks/bin/pip install -r tools/requirements-ci.txt
```

格式检查还需要已有开发流程中的 StyLua，见[开发与测试](development-and-testing.md#缩进与格式)。

```sh
.deps/checks/bin/python tools/test.py
.deps/checks/bin/python tools/test.py --profile full
```

两者都不启动游戏。第一次配置并构建 `build-offline`，之后复用构建目录。

| 配置 | 每个属性测试的生成预算 | 状态机最多动作数 | 用途 |
| --- | --- | --- | --- |
| `fast`，默认 | 25 个例子 | 20 | 日常修改、PR |
| `full` | 200 个例子 | 60 | 扩展离线验证 |

Hypothesis 可以额外运行缓存失败样例并执行缩减；表中是生成预算，不是精确执行计数。只测相关领域或固定场景：

```sh
.deps/checks/bin/python -m pytest -m state -q
.deps/checks/bin/python -m pytest -m behavior -q
.deps/checks/bin/python -m pytest tests/offline/test_behavior.py -k saved_stall -q
```

只列出用例和现有实机清单，不执行场景：

```sh
.deps/checks/bin/python tools/test.py --list
.deps/checks/bin/python tools/test.py --list-engine
```

`--list-engine` 通过语法树读取现有声明，包含统一入口中的定向场景、正常操作流程，以及尚未登记的旧脚本。脚本存在不等于已通过，组合套件也不重复计为新场景。

## 结构与覆盖

| 组件 | 职责 |
| --- | --- |
| CTest | 原有 C++ 协议、存档、输入及 Lua 接入回归，统一标记为 `offline` |
| pytest | 场景选择、参数化、环境清理、耗时和 JUnit 报告 |
| Hypothesis | 生成数据和动作序列，寻找并缩减失败用例 |
| `tests/offline/lua_worker.lua` | 持续运行的 Lua 5.3 进程，执行生产模块 |
| `tests/fixtures/offline_*.lua` | 小型玩家、实体和运动模型，明确支持的接口 |

生产环境和测试共用 `src/bridge/state/codec.lua`、`inventory.lua`、`entities.lua`。原有协议格式保持不变；状态桥接负责原生读写、精灵、楼层及呈现，共用模块负责编解码、资源应用和实体分配／关系恢复。

第一阶段覆盖：

- 编解码边界、截断、损坏数据和非有限浮点数。
- 金币等资源收敛、重复快照无额外变化、道具替换与槽位、幽灵库存跳过契约。
- 多节实体前向引用、父子关系、身份替换、删除、重复快照，以及玩家和其他房间实体的保留。
- 真实 `bot.step` 的四向过门、三种风格、速度／半径／起点组合、绕墙、留守、换房释放旧输入、暂停恢复和会话重置。
- 资源、实体快照与托管命令的生成动作序列。

行为测试使用虚拟时间、简化惯性和碰撞，模拟帧不等待真实时间。状态测试的模型给出独立的期望资源、身份和关系；直接检查结果，不通过重新应用快照来掩盖错误。

当前没有离线覆盖原生双人同时过门、特殊角色生命周期、死亡副作用、原生动画、Hook 调用约定和实际画面；不会据此关闭百变怪结算、里双子消失等待测试 Issue。后续扩展房间／楼层边界和录制观察数据时继续保留这一区分。

## 失败记录与回放

每次统一运行在 `test-runs/offline-时间-进程号/` 保存阶段日志、耗时、`summary.json` 和 `pytest.xml`。失败场景额外保存 Lua 请求／响应；Hypothesis 在失败报告中给出缩减后的参数或动作序列。

```sh
.deps/checks/bin/python tools/replay_offline.py /path/to/failure.json
```

回放只执行保存的请求，打印当前输出。旧输出仅作诊断，不能把已知错误当成正确答案。确认失败条件后，将请求加入 `tests/offline/replays/`，并在固定回归中写明确的预期结果。

已保存门前／路径点停滞的固定回归。行为模型验证任务是否完成，不用于证明实际引擎物理、敌人 AI 或实机走位质量。

## CI 与迁移顺序

PR 使用 `fast` 配置。手动触发 CI 时可选择 `full`；报告与失败请求作为测试产物保留。Windows x86 构建和真实 Winsock 测试继续运行，它们不需要游戏。

每个实机场景逐步拆成离线规则与原生验收。先让离线测试能抓住已知错误，再减少对应实机检查的运行频率。输入、资源、去重、关系和事务顺序优先迁移；角色机制、动画和画面保留少量定向场景。准备实机场景时可直接布置目标房间和实体，菜单／控制台／物理输入链路由专门的入口场景覆盖。

框架说明：[pytest 标签](https://docs.pytest.org/en/stable/example/markers.html)、[Hypothesis 状态机](https://hypothesis.readthedocs.io/en/latest/stateful.html)。
