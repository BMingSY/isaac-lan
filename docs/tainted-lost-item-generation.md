# J460 里 Lost 的全队生成特性

以当前支持的原版 J460 二进制为依据，不重新实现随机算法。以下是反汇编的 RVA（相对模块基址的地址），不是公开 C++ 源码行号。

- 文件：isaac-ng.exe，32 位 x86，默认 ImageBase 0x400000。
- SHA-256：7122ac28779925b24e23e2416f231322b1470388bd25e2c08665ad8d53b3ea4f。
- 例如 RVA 0x330530 的默认运行地址是 0x730530；启用地址随机化时用实际模块基址加 RVA。

## 随机道具：攻击性标签及品质重抽

同一原生道具生成流程先查找角色 31（里 Lost），再检查候选道具：

| RVA | 原版指令 | 含义 |
| --- | --- | --- |
| 0x330507 | push 0x1f | 查找里 Lost |
| 0x33050f | call 0x5be630 | PlayerManager::FindPlayerType |
| 0x330514 | test eax, eax | 是否找到里 Lost；此调用只使用返回值的非空性 |
| 0x33051c | mov eax, [ebx+0xb8] | 候选道具的标签 |
| 0x330522 | and eax, 0x100000 | TAG_OFFENSIVE（攻击性） |
| 0x33052a | je 0x3301da | 缺少攻击性标签，重新抽取 |
| 0x330530 | cmp dword ptr [ebx+0xc0], 2 | 候选道具品质与 2 比较 |
| 0x330537 | jge 0x3305a1 | 品质 2 及以上跳过里 Lost 的概率重抽 |
| 0x330572 | push 5 | 随机判定的上界 |
| 0x33058c | call 0x3e9020 | RNG::RandomInt(5) |
| 0x330591 | test eax, eax | 检查随机结果 |
| 0x330593 | je 0x3301da | 结果为 0 时重新抽取，即五分之一 |

因此本版本对品质 **0／1** 的攻击性候选执行五分之一重抽；品质 **2** 不进入这次判定。种子、其他筛选条件、候选耗减与重抽流程全部保留原版行为。

0x3305af 随后查询道具 691（十字圣球），返回点 0x3305b9。其原生品质规则独立于里 Lost，仍由原版执行；全队公共道具表让这个查询看见其他房间的持有者。

## 随机卡牌：神圣卡替换

原版 ItemPool::GetCardEx 位于 0x334180，stdcall，参数为种子、特殊卡概率、符文概率、花色概率、是否允许非卡牌。此处里 Lost 检查被编译为直接遍历玩家名单，未调用上面的 FindPlayerType：

| RVA | 原版指令 | 含义 |
| --- | --- | --- |
| 0x3346b0 | cmp dword ptr [ebp+0xc], 0 | 特殊卡概率为 0 时跳过替换 |
| 0x3346b4 | jbe 0x334754 | 保留原卡牌结果 |
| 0x3346c0 / 0x3346c6 | 读取 Game+0x1baa8 / 0x1baac | 玩家名单起止地址 |
| 0x3346e5 | cmp dword ptr [edx+0x13c0], 0x1f | 检查有效、非幽灵的里 Lost |
| 0x334720–0x33473e | 移位／异或原生 RNG 状态 | 沿用原版随机状态及移位参数 |
| 0x334737 / 0x334740 | mov eax, 0xcccccccd / mul esi | 编译器生成的除以 10 |
| 0x334747–0x33474f | 计算随机结果除以 10 的余数 | 等价于 RandomInt(10) 判定 |
| 0x334742 | mov eax, 0x33 | 神圣卡，ID 51 |
| 0x334751 | cmove ebx, eax | 余数为 0 时替换，概率十分之一 |

普通随机生成允许特殊卡时，全队享受这次判定；调用者明确禁用特殊卡时继续遵循原版限制。不会为每位玩家分别抽一次，也不修改指定生成的固定卡牌。

## 联机处理边界

[角色公共特性表](../src/compat/characters/team_effects.h)声明角色的公共生成／商店特性，[公共道具表](../src/compat/items/team_effects.h)声明公共道具效果。J460 后端只在已校验的调用位置借用现有 TeamScope 完整名单，并立即恢复当前房间名单：

- 道具生成调用点 0x330514 的角色查询看见全队，因此同时恢复攻击性筛选和品质重抽。
- 卡牌生成函数在全队有里 Lost 时临时读取完整名单，覆盖直接遍历名单的原生检查。
- 主机执行随机生成，客机沿用已有实体／库存同步接收生成结果；不复制公共道具到其他玩家库存。
- 飞行、穿透、生命限制、出生库存等属于角色自身的特性；恶魔房支付属于购买者的特性，不通过公共生成名单把这些赋给其他角色。
- 两种店长的恶魔交易都按实际购买者的原版定价结算；里店长的商店升级独立共享。

新增入口与调用点均有启动签名校验；不写道具质量、标签、角色类型或原生对象所有权。

## 复核方法及验收

用 Python pefile 获取 PE 的 memory-mapped image，再用 Capstone 的 x86/32 位模式解码上述范围；地址参数传 RVA，避免把 PE 文件偏移误当作 RVA：

~~~python
import hashlib
from pathlib import Path
import pefile
from capstone import Cs, CS_ARCH_X86, CS_MODE_32

path = Path("isaac-ng.exe")
assert hashlib.sha256(path.read_bytes()).hexdigest() == (
    "7122ac28779925b24e23e2416f231322b1470388bd25e2c08665ad8d53b3ea4f"
)
pe = pefile.PE(str(path))
data = pe.get_memory_mapped_image()
decoder = Cs(CS_ARCH_X86, CS_MODE_32)
for start, stop in [(0x330501, 0x33062e), (0x3346b0, 0x334766)]:
    for instruction in decoder.disasm(data[start:stop], start):
        print(hex(instruction.address), instruction.mnemonic, instruction.op_str)
~~~

[集中实机夹具](../tests/state_item_generation.lua)分房后先记录无公共效果的种子结果，再验证远端十字圣球与里 Lost 的原生生成、禁用特殊卡的边界、神圣卡实体同步。品质概率以以上原生分支为准，夹具不以有限样本声称精确验证 20%。
