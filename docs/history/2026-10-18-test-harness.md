# 测试执行层重构验证（2026-10-18）

候选提交 `6ec2228`，基于 `main` 的 `75aacff`。验证范围是测试工具、场景组合、异常清理和报告；没有修改生产玩法或原生后端。本记录不是发版全量验收。

## 构建与离线检查

- `tools/test.py --profile full --sanitizers`：86 项 CTest、273 项 pytest 和 19 项子测试通过，证据轮次 `harness-offline-final-02`。
- 最后补充完成状态异常的清理后，执行器专项 23 项、格式和全部脚本／生成脚本语法检查通过。初轮发现的 LANBOT 夹具追加第二个 `return` 的错误已改为读取显式场景契约，并通过回归；初轮结果保留于 `harness-offline-01`。
- Windows x86 Release 构建成功，11 项原生 ABI 检查通过，证据 `native-abi.xml`。Windows 网络与安装包检查由 PR CI 执行，结果以对应运行记录为准。

冻结产物标识 `test-harness-build-20261017`，SHA-256：

| 产物 | SHA-256 |
| --- | --- |
| `isaac_lan_probe.dll` | `a4086e36d7437cfe108a20e22216fce35978c74cf58100c810c5a1dc48d3137a` |
| `winmm.dll` | `22ebccbf0ad327cd2a748eae416c73606f60d50571a3f59ec988a213a11be35f` |
| 路线组合 `suite.lua` | `6d6bcee55d91a1b7db4e19143e3b1b688045acd8d447d2372d7303c491bd640c` |
| 最终连续玩法 `suite.lua` | `91d260e1c8209893afe41dc272fb64a9f3d8c743fa0d1a7b5d614cb18cfbb480` |

## 实机结果

使用独立、有归属标记的 `test-harness-host-20261017`、`test-harness-client-20261017`，端口 52380，单向附加延迟 75 ms，启用堆检查和双端 500 ms 画面采样。没有操作其他测试或手动游戏实例。

| 证据轮次 | 范围与结果 | 另起进程的原因 |
| --- | --- | --- |
| `test-harness-native-20261017-01` | 移动通过；换层场景在五点骰子断言后、进入下一层附近主机发生 `C0000005`，整轮失败 | 首轮 |
| `test-harness-native-20261018-baseline` | 使用 `75aacff` 的原始组合器和夹具，同 DLL、配置和场景通过 | 首轮进程崩溃，进行基线对照 |
| `test-harness-native-20261018-02` | 新组合器通过移动、主客机 Forget Me Now、五点骰子和客机 R Key；两端正常退出 | 用完全相同的首轮脚本复核异常 |
| `test-harness-continuous-20261018-01` | 临时验证命令误用 `--no-luadebug`，夹具无法访问 `io`，初始化失败；客机未启动 | 切换到要求一次起局的连续玩法组合器 |
| `test-harness-continuous-20261018-02` | 移动、进房、主动道具双端完成且正常退出；临时评估器匹配了错误的起局日志字段，整轮报告失败 | 修正启动配置后重试 |
| `test-harness-continuous-20261018-03` | 最终候选通过三个连续场景，两端各一次起局，正常退出，无堆异常转储 | 修正评估字段并验证最终异常清理改动 |

每轮均复用组内主客机进程，结束后恢复保护资料并逐文件核对哈希；全部恢复成功。原始失败报告、双端日志、截图、备份及首轮 `40228-1.dmp` 留在各轮测试产物，没有覆盖失败轮次。画面仅抽查相关场景和转场，不构成性能或完整画面验收。

## 未解决及未验证

首轮主机异常定位于 `Lua5.3.3r.dll + 0x281a`。原始组合器对照通过，新组合器同脚本复测也通过，现归类为**偶发、未定位**；不能据此认定已修复或断定与重构无关。

未执行默认发版的全 Boss、全部结局路线、全安装流程，也未执行全道具、角色、Mod 或性能专项。具体执行约定见[开发与测试](https://github.com/BMingSY/isaac-lan/blob/main/docs/development-and-testing.md)。
