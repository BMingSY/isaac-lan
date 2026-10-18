# 2026-10-18 道具效果补充验收

原始范围 203 项中，195 项所选场景通过，6 项确认存在兼容问题，2 项本轮未复现历史反馈并保留待确认状态。基础流程或触发前提不成立的场景不计效果通过。本轮只修改测试工具、夹具、判定器和文档，没有修复生产玩法。

## 候选与范围

- 执行日期：2026-10-18 至 2026-10-19（香港时间）。
- 候选提交：`422474516ed5e3b45beaf2ea389151e47a5a95ea`。
- 原生 DLL SHA-256：`ef5783255e6b42bbdb6bf1a06783063d61a639485d17cb9afc7c3ea4819cc5f3`。
- 游戏：忏悔＋ `1.9.7.17.J460`；EXE SHA-256：`7122ac28779925b24e23e2416f231322b1470388bd25e2c08665ad8d53b3ea4f`。
- 范围固定为 183 个饰品、18 个未完成道具及织布魔偶、错误技这 2 个历史疑似道具；卡牌、符文和药丸沿用[此前验收](https://github.com/BMingSY/isaac-lan/blob/main/docs/history/2026-10-18-item-effects.md)，本轮不重复遍历。
- 基础条件是主机持有同房、客机持有分房；按效果增加原生消耗、碰撞、拾取、移除、房间、楼层、角色与随机生成条件。长子名分覆盖 35 个角色场景的两种持有条件，里游魂另补四种房间／持有方组合。
- 结论限于实际场景，不代表所有道具组合、全部随机效果、四人联机或发布前默认验收。

## 已复核问题

| 项目 | 触发条件 | 影响 | 证据 |
| --- | --- | --- | --- |
| 寻人启事（`trinket:23`） | 主机同房或客机分房持有寻人启事，受到致命伤害并触发原生复活。 | 复活后的游魂仍存活且不是联机幽灵，但角色持续不可见，影响复活后的角色辨识与位置判断；本轮未据此断言移动或射击失效。 | `trinket-lifecycle-04`、`native-remaining-05`；相关画面已审阅。 |
| 赎罪（`collectible:673`） | 客机分房持有赎罪，实际进入原生恶魔房，出现十字标记，未取走任何交易道具或掉落物后离开并换层。 | 下一层没有获得伤害提升和魂心奖励；主机同房／分房、客机同房对照均获得奖励。 | `native-remaining-05`、`trinket-followup-06b`、`serial-recovery-14`；相关画面已审阅。 |
| 发夹（`trinket:120`） | 主机或客机持有发夹，以空充能的六面骰实际穿过房门进入尚有Boss的房间；另一名玩家留在门外。 | 进入Boss房后六面骰充能仍为0，无法获得发夹提供的进房充满主动道具效果。 | `serial-recovery-14`；相关画面已审阅。 |
| 蓝钥匙（`trinket:150`） | 主机或客机持有蓝钥匙，在无钥匙状态通过普通房间到未进入过的宝箱房的上锁房门。 | 无饰品时门仍锁住，持有后可直接进入宝箱房且不消耗钥匙；跳过了应生成的蓝色战斗房及其中战斗。 | `serial-recovery-14`；相关画面已审阅。 |
| 门挡（`trinket:124`） | 主机或客机持有门挡，通过正常方向输入穿门进入仍有敌人的普通房间；队友留在原房。 | 进入后原入口关闭，门挡未能保持入口开启，战斗结束前无法按预期从入口退回。 | `serial-recovery-14`；相关画面已审阅。 |
| 长子名分（`collectible:619`） | 客机分房使用里游魂，持有长子名分并受到致命伤害，触发本房复活。 | 复活本身成功，但同房近处敌人没有受到应有的200点复活爆炸伤害；主机同房／分房和客机同房对照可造成伤害。 | `native-followup-16-a`、`native-followup-16-b`、`native-followup-18-a`；相关画面已审阅。 |

## 执行、对照与恢复

所有游戏均位于有归属标记的隔离目录，使用独立资料与端口。每组复用主客机进程和连接，切换道具不重启进程；轮次结束、夹具修改后重新装载、启动／退出验证或异常恢复才重新启动。原始日志、录像、转储、源文件快照与哈希保留在 `item-effects-completion-20261018` 产物中，没有提交到文档目录。只计主客机均有结束记录的条件，已结束条件不能使后续中断的整批变为通过。

首次扩大到 5 组时，Windows 在 19:05 记录事件 2004（虚拟内存不足）。06b、07-a/c/main 等轮次中断或启动失败；恢复期增加到 4 组后，19:56 再次出现事件 2004，10-a/b/c、11 随后异常退出，12 未成功开始。10-a 客机还有 `C0000005` 转储，不能仅凭资源告警排除原生问题。13-b 为降低内存占用主动中止，之后 14 使用一组完成 236 个条件。用户后来明确授权停止 Maono 服务及其进程，服务自动启动设置未改；释放内存后最多使用三组，所有操作由同一个执行者调度。没有控制用户手动游玩的实例。

03 的特殊房间描述不适用于夹具；06/07 的炸弹夹具使用了错误 API，06 主机保留 `C0000005` 和一个转储；16-a/b 在跳坑夹具嵌套换层时遇到空用例引用而终止。上述失败均保留原证据，修正夹具后另开轮次，原生异常不因发现夹具错误而被抹去。

原生对照没有建立 LAN 会话：15 的自动加载／菜单／双窗口焦点与退出流程出现失败，15c/d 只有已实际完成的控制数据用于复核，不能称整批通过；19、21、23、24 采用主机本地合作、客机停留菜单的方式，客机完成标记不作为效果证据。对照区分了合作模式下的迷彩与褪色照片、老茧伤害源、扁形虫冲量、里该隐随机分解掉落、手镯举石、召回和原生隐藏目标提示。

修正过严或错误的判定时，保存新的判定器快照、事件摘要哈希及理由。14/16/22 的复核文件、人工用例复核和画面索引与原报告分别保留。示例包括：枚举别名不等于游戏阶段不同；拾取必须等待动画结束；安全剪刀转换后已被收集的炸弹应计入库存；饰品触发只统计实际消耗；原生里该隐分解数量不要求每次恰好翻倍。没有用主机数据代替客机结果，也没有直接写入预期效果作为成功证据。

## 场景残留专项

针对用户反馈的“离房返回后，客机仍显示破坏瞬间”，以当前候选测试普通石头、爆炸石和爆桶，在破坏后第 1、6、20、90 帧离房，主客机先后返回并重复离房／重进。17e 的四组双端网格状态一致，相关画面均已查看，未复现破坏瞬间持续定格；按用户要求没有修改生产代码。仍能看到客机缺少部分碎石和焦痕，不能将此轮描述为画面完全一致。结论不覆盖所有自然穿门、布局或网络延迟；用户原始反馈来自 v0.4.2，本轮结论只针对当前候选。

17/17b 也正常退出；17b 的黑石并非爆炸石，不能充当爆炸石证据。17c/d 的夹具错误地在主机使用只适用于副本的移除接口，清理阶段超时并被强制结束，退出码 `FFFFFFFF`、堆监视退出码 5、无转储，资料恢复通过；17e 改用游戏原生移除接口。17e 双端退出码 0、堆监视退出码 0、无转储，逐文件恢复核对通过。

## 已结束轮次

下表保留原报告的断言数；后续独立复核不回写原成绩。所有列出的轮次均已完成隔离资料恢复并核对哈希。“正常退出”与效果通过是不同结论。

| 轮次 | 双端完成 | 原判定通过 | 正常退出 | 报告 SHA-256 |
| --- | ---: | ---: | --- | --- |
| `conditional-remaining-07` | 0 | 0 | 是 | `6f00ad8caa7855233640891cbe2c58bc95965d4fbdc48101fd4bdf2b86f942f5` |
| `manual-confirmation-11` | 8 | 7 | 否 | `33281da5ff0d9e4243673293d139e6b6a5708f4f3fb5badaca0a115c2b947a4c` |
| `native-focused-03` | 8 | 1 | 是 | `b1df54381de271991450152ebe124f7da357b872c2925f0b94a24e5c49c83020` |
| `native-followup-12` | 0 | 0 | 否 | `ac85159ed9ed54488578ddfa15f2a1be99fb685c93f2dcaf03e0aee99ba184eb` |
| `native-followup-16-a` | 36 | 23 | 是 | `4162e286d1f54241d8c618c2880d9fc9cb863c09b9e8006e63eefee1f911e566` |
| `native-followup-16-b` | 34 | 19 | 是 | `286c3b6319e2d058d7bae452ab2d3c3eb90817d8f524923af909bddf198c5d5a` |
| `native-followup-18-a` | 17 | 2 | 是 | `30929fd945792ab802d84a4718fbd5ee2ce00624ebbdc551febf453342c5b5ac` |
| `native-followup-18-b` | 17 | 4 | 是 | `13edfe2c62ebcf564fdb015bff7fc786b4b473f4fa1428ac6e339b3f08c7b595` |
| `native-followup-20-a` | 10 | 7 | 是 | `6973f759a452aa0dde890ada8c2bba8f047f9ec8109887d848f192a832763e4b` |
| `native-followup-20-b` | 10 | 4 | 是 | `b73c1134ef9cc26e17c1d7ffbd413a58efabb6f7d77f96ede3df3040f7de6852` |
| `native-followup-22-a` | 8 | 5 | 是 | `70338c2fbb3634fedc366eea811448826711ca554c30c63c8a68d76aaf966559` |
| `native-followup-25-a` | 8 | 5 | 是 | `bcb29172837e9fff4a73b10ae7f3282fd0845accb8ba43fe12c2d49fa0e2367b` |
| `native-followup-27-a` | 4 | 4 | 是 | `ef7f9db1c6bc11527f6311a704deca3050152ba9d4161dc948ae53b861dff401` |
| `native-remaining-05` | 166 | 109 | 是 | `270e0584a6e6ef4858182f01444d36fedcf98af99be7eec839f3d86053c62e55` |
| `parallel-07-a` | 0 | 0 | 否 | `20cacc2c61bccb963f80d3e537d932ab938da63d7806ab114d43a51eb34deb7c` |
| `parallel-07-b` | 0 | 0 | 是 | `a53e8f4b5b42a420abcb4a3068b9e4cbc33c4c9e7e44a40b271eef3e2e6b6517` |
| `parallel-07-c` | 0 | 0 | 是 | `2137a0f2cc7ac9894cc159094b1975e1932ec2527bedeb72bea593c9a8f573a8` |
| `parallel-07-d` | 0 | 0 | 是 | `fa6f039062067dcb94c5727a0ca1c6797e925f515aa6c21c03929382c016344d` |
| `parallel-07-main` | 0 | 0 | 否 | `64e1fe6440f029ed4d586ff8cfad4a89a53b733cc2bf57e5e4701e65ef08cb43` |
| `parallel-recovery-10-a` | 5 | 3 | 否 | `9275e29a0c3a196c7ce247edc07c551e32d244dfe27e8360e8a80ae2304a7cef` |
| `parallel-recovery-10-b` | 5 | 3 | 否 | `6314123b3cf92de6d5ab1e20707e64903bbe139d1c39383c59b9f1b936bec68f` |
| `parallel-recovery-10-c` | 10 | 5 | 否 | `c7f5db511d44cdf7a7e9de31b8a057d92d7613b9a8be0ecc49f46d020e619bcf` |
| `remaining-recovery-13-a` | 23 | 14 | 是 | `dbdeeed62b3afa16c6782d53bdaa2059d0ce0c07c90472fac0e805ec505587b0` |
| `remaining-recovery-13-b` | 1 | 0 | 是 | `870220b4a7321e7a8650e4a41b0f37d30366aea92d5e294396745055e27d0795` |
| `serial-recovery-14` | 236 | 148 | 是 | `aa4f4bf5a744ff1b3a72148af489816a9b5571b947156c35c91e445d7c0dcdf6` |
| `trinket-conditions-02` | 40 | 18 | 是 | `cbdf8e45129880feb9c05e62d3ed60ecf622a9c7d9f60527958154a8d17dcac1` |
| `trinket-direct-01` | 50 | 42 | 是 | `d84855e457310a33c7d23ce93c5e03183e8f919cfa8f1d943be86a9bf7f3b4d7` |
| `trinket-followup-06` | 46 | 19 | 否 | `438ee8f62cee5489bc0c52d2aabba3cf5185d49d96114824e72baa98c9ee6106` |
| `trinket-followup-06b` | 55 | 31 | 否 | `eac0a561880b370d6497d1d5e1f916fc2f3735822d91aabc93b15e26496b2ab1` |
| `trinket-lifecycle-04` | 94 | 70 | 是 | `eb674253c4ce4ced0480dd32be20d67994e8e84a7482a1b76bba8049c118f327` |
| `visual-followup-09` | 2 | 0 | 是 | `820dc14a803ac9b01265d33a068437dcb9102312af2b2ae2d57e893bf46a89b9` |

原生对照及场景专项报告：

| 轮次 | 执行结果 | 恢复 | 报告 SHA-256 |
| --- | --- | --- | --- |
| `grid-residue-17` | 完成 | 通过 | `49b7ec5a61eb26bcdece63a0dd3f41b6c15477aea3b081390da3b7f79d8a8b9e` |
| `grid-residue-17b` | 完成 | 通过 | `279f6d34b89489ff7632cb1561e3f0d56b27e0ce1814109facc12dd54c807fa0` |
| `grid-residue-17c` | 失败／未完成 | 通过 | `98bbe368336c7ea735ade2aff9517a8f93bd5d54d8580941e9e9f2e1071c4a76` |
| `grid-residue-17d` | 失败／未完成 | 通过 | `9e688a412f15fb0792f6c2432d32dece39b4fd3ca0ee03c152ea374e6539a234` |
| `grid-residue-17e` | 完成 | 通过 | `f14d9679630f06b129604abf050151703ebe0c8d06ec0b5a5bf9743117c164ee` |
| `native-coop-control-15` | 失败／未完成 | 通过 | `66d7604b48a81bac7fa84c312616faa55ceba6e768711428a34001be531928d9` |
| `native-coop-control-15b` | 失败／未完成 | 通过 | `1239f1736c230fd244166345e6e821855d87e9e7d250b0a547f5c0ff1b567270` |
| `native-coop-control-15c` | 失败／未完成 | 通过 | `325015d48c4ddb5768435fe11aec7fcbc7dd3be9d1e3c97524f7414f8b5147cd` |
| `native-coop-control-15d` | 失败／未完成 | 通过 | `b8c00636eb44c27cf996fc9ebf6918a136e3d9fd48bbd2cab3e22be4acd2240d` |
| `native-prerequisite-control-19` | 完成 | 通过 | `0fab046a166a6c8d515ce8ce48c899a026738b0cc2dc16a0e8de0aedbd7b4c7c` |
| `native-prerequisite-control-21` | 完成 | 通过 | `a426226f49e075339332988ef4a255cc4f16b56db3630369ecfb0ab2ee55c062` |
| `native-prerequisite-control-23` | 完成 | 通过 | `6de2599bdb22ca60d55858d584246cabcca5c924fa4df2fdc8b2a3e3ed7e4625` |
| `native-prerequisite-control-24` | 完成 | 通过 | `f3cb65dff6962d78eb260bb851adfa74a312187cb408c10931099e3d09d87b3e` |

## 逐项结论

“通过”只覆盖对应证据轮次的独立效果、归属和双端状态；具体用例与额外矩阵保存在[验收数据](https://github.com/BMingSY/isaac-lan/blob/main/tests/fixtures/item_audit_findings.json)的 `rechecks`／`completion_acceptance` 中。历史疑似反馈保留在兼容清单中。

| 项目 | 名称 | 本轮状态 | 证据轮次 |
| --- | --- | --- | --- |
| `collectible:60` | 梯子 | 通过 | `native-followup-18-a`、`native-followup-18-b` |
| `collectible:208` | 冠军腰带 | 通过 | `parallel-recovery-10-a` |
| `collectible:276` | 以撒的心脏 | 通过 | `native-followup-20-b` |
| `collectible:282` | 跳跃教程 | 通过 | `native-followup-20-b` |
| `collectible:396` | 心室手术刀 | 通过 | `native-remaining-05` |
| `collectible:445` | 狗牙 | 通过 | `native-followup-25-a` |
| `collectible:492` | 嘿，听好！ | 通过 | `native-followup-27-a` |
| `collectible:497` | 迷彩内裤 | 通过 | `remaining-recovery-13-a`、`serial-recovery-14` |
| `collectible:498` | 二元性 | 通过 | `trinket-followup-06b` |
| `collectible:527` | 自我先生！ | 通过 | `serial-recovery-14` |
| `collectible:550` | 铲子碎片 | 通过 | `native-remaining-05` |
| `collectible:604` | 妈妈的手镯 | 通过 | `native-followup-25-a` |
| `collectible:619` | 长子名分 | 不兼容 | `native-followup-16-a`、`native-followup-16-b`、`native-followup-18-a` |
| `collectible:635` | 织布魔偶 | 本轮未复现，历史反馈保留 | `remaining-recovery-13-a` |
| `collectible:673` | 赎罪 | 不兼容 | `native-remaining-05`、`trinket-followup-06b`、`serial-recovery-14` |
| `collectible:681` | 黑洞宝宝 | 通过 | `serial-recovery-14` |
| `collectible:692` | 血色羁绊 | 通过 | `native-remaining-05` |
| `collectible:711` | 生死逆转 | 通过 | `native-followup-16-a`、`native-followup-16-b` |
| `collectible:714` | 召回 | 通过 | `native-followup-22-a` |
| `collectible:721` | 错误技 | 本轮未复现，历史反馈保留 | `native-followup-16-a`、`remaining-recovery-13-a`、`serial-recovery-14` |
| `trinket:1` | 被吞下的硬币 | 通过 | `trinket-direct-01` |
| `trinket:2` | 石化大便 | 通过 | `remaining-recovery-13-a`、`serial-recovery-14` |
| `trinket:3` | 7号电池 | 通过 | `native-remaining-05` |
| `trinket:4` | 损坏的遥控器 | 通过 | `native-remaining-05` |
| `trinket:5` | 紫心奖章 | 通过 | `parallel-recovery-10-c` |
| `trinket:6` | 断掉的磁铁 | 通过 | `trinket-lifecycle-04` |
| `trinket:7` | 念珠段 | 通过 | `trinket-followup-06` |
| `trinket:8` | 游戏卡带 | 通过 | `trinket-lifecycle-04` |
| `trinket:9` | 波动虫 | 通过 | `trinket-conditions-02` |
| `trinket:10` | 扭扭虫 | 通过 | `trinket-direct-01` |
| `trinket:11` | 环形虫 | 通过 | `trinket-direct-01` |
| `trinket:12` | 扁形虫 | 通过 | `serial-recovery-14` |
| `trinket:13` | 商店积分 | 通过 | `native-remaining-05` |
| `trinket:14` | 老茧 | 通过 | `native-followup-16-a`、`native-followup-16-b` |
| `trinket:15` | 幸运石 | 通过 | `native-remaining-05` |
| `trinket:16` | 妈妈的脚趾甲 | 通过 | `native-followup-16-a`、`native-followup-16-b` |
| `trinket:17` | 黑色口红 | 通过 | `trinket-conditions-02` |
| `trinket:18` | 圣经小册 | 通过 | `trinket-conditions-02` |
| `trinket:19` | 回形针 | 通过 | `native-remaining-05` |
| `trinket:20` | 猴爪 | 通过 | `trinket-lifecycle-04` |
| `trinket:21` | 神秘纸片 | 通过 | `serial-recovery-14` |
| `trinket:22` | 恶魔的尾巴 | 通过 | `trinket-conditions-02` |
| `trinket:23` | 寻人启事 | 不兼容 | `trinket-lifecycle-04`、`native-remaining-05` |
| `trinket:24` | 屁股硬币 | 通过 | `trinket-followup-06` |
| `trinket:25` | 神秘糖果 | 通过 | `serial-recovery-14` |
| `trinket:26` | 钩形虫 | 通过 | `trinket-direct-01` |
| `trinket:27` | 鞭形虫 | 通过 | `trinket-direct-01` |
| `trinket:28` | 碎安卡十字 | 通过 | `serial-recovery-14` |
| `trinket:29` | 鱼头 | 通过 | `native-remaining-05` |
| `trinket:30` | 角膜炎 | 通过 | `trinket-direct-01` |
| `trinket:31` | 图钉 | 通过 | `trinket-direct-01` |
| `trinket:32` | 裸盖蘑菇 | 通过 | `trinket-followup-06` |
| `trinket:33` | 脐带 | 通过 | `native-followup-16-a`、`native-followup-22-a` |
| `trinket:34` | 小孩的心脏 | 通过 | `native-remaining-05` |
| `trinket:36` | 生锈的钥匙 | 通过 | `native-remaining-05` |
| `trinket:38` | 妈妈的珍珠 | 通过 | `trinket-conditions-02` |
| `trinket:40` | 红补丁 | 通过 | `trinket-direct-01` |
| `trinket:41` | 火柴棍 | 通过 | `native-remaining-05` |
| `trinket:42` | 幸运脚趾 | 通过 | `native-remaining-05` |
| `trinket:43` | 诅咒的头骨 | 通过 | `trinket-lifecycle-04` |
| `trinket:44` | 保险瓶盖 | 通过 | `native-remaining-05` |
| `trinket:45` | 黑桃A | 通过 | `native-remaining-05` |
| `trinket:46` | 以撒的叉子 | 通过 | `native-remaining-05` |
| `trinket:48` | 遗失的书页 | 通过 | `trinket-lifecycle-04` |
| `trinket:49` | 染血硬币 | 通过 | `trinket-lifecycle-04` |
| `trinket:50` | 焦灼硬币 | 通过 | `trinket-lifecycle-04` |
| `trinket:51` | 扁平硬币 | 通过 | `trinket-lifecycle-04` |
| `trinket:52` | 假币 | 通过 | `trinket-lifecycle-04` |
| `trinket:53` | 血虱 | 通过 | `native-followup-16-a`、`native-followup-16-b` |
| `trinket:54` | 以撒的头 | 通过 | `native-remaining-05` |
| `trinket:55` | 抹大拉的信仰 | 通过 | `trinket-lifecycle-04` |
| `trinket:56` | 犹大的舌头 | 通过 | `serial-recovery-14` |
| `trinket:57` | ???的灵魂 | 通过 | `native-remaining-05` |
| `trinket:58` | 参孙的发髻 | 通过 | `trinket-lifecycle-04` |
| `trinket:59` | 该隐的眼睛 | 通过 | `native-remaining-05` |
| `trinket:60` | 夏娃的鸟爪 | 通过 | `trinket-lifecycle-04` |
| `trinket:61` | 左断手 | 通过 | `trinket-lifecycle-04` |
| `trinket:62` | 闪亮岩石 | 通过 | `visual-followup-09` |
| `trinket:63` | 安全剪刀 | 通过 | `native-followup-16-a`、`native-followup-16-b` |
| `trinket:64` | 彩虹虫 | 通过 | `native-remaining-05` |
| `trinket:65` | 长条虫 | 通过 | `trinket-direct-01` |
| `trinket:66` | 懒懒虫 | 通过 | `trinket-direct-01` |
| `trinket:67` | 碎裂六面骰 | 通过 | `serial-recovery-14` |
| `trinket:68` | 超级磁铁 | 通过 | `serial-recovery-14` |
| `trinket:69` | 褪色的全家福 | 通过 | `parallel-recovery-10-c`、`serial-recovery-14` |
| `trinket:70` | 虱子 | 通过 | `native-remaining-05` |
| `trinket:71` | 鲍勃的膀胱 | 通过 | `native-remaining-05` |
| `trinket:72` | 钮扣电池 | 通过 | `manual-confirmation-11`、`native-followup-18-b`、`serial-recovery-14` |
| `trinket:73` | 雷管 | 通过 | `serial-recovery-14` |
| `trinket:74` | 饰钉定位器 | 通过 | `serial-recovery-14` |
| `trinket:75` | 错误 | 通过 | `native-remaining-05` |
| `trinket:76` | 筹码 | 通过 | `native-remaining-05` |
| `trinket:77` | 水疱 | 通过 | `serial-recovery-14` |
| `trinket:78` | 秒针 | 通过 | `trinket-followup-06b` |
| `trinket:79` | 无名无尽 | 通过 | `trinket-followup-06b` |
| `trinket:80` | 黑色羽毛 | 通过 | `native-remaining-05` |
| `trinket:81` | 盲目的怒火 | 通过 | `native-remaining-05` |
| `trinket:82` | 黄金马蹄铁 | 通过 | `parallel-recovery-10-a`、`serial-recovery-14` |
| `trinket:83` | 商店钥匙 | 通过 | `serial-recovery-14` |
| `trinket:84` | 贪婪的肋骨 | 通过 | `native-followup-18-a`、`parallel-recovery-10-a`、`parallel-recovery-10-b`、`serial-recovery-14` |
| `trinket:85` | 业报 | 通过 | `parallel-recovery-10-b`、`serial-recovery-14` |
| `trinket:86` | 小幼虫 | 通过 | `native-remaining-05` |
| `trinket:87` | 妈妈的吊坠 | 通过 | `trinket-conditions-02` |
| `trinket:88` | 不！ | 通过 | `trinket-conditions-02` |
| `trinket:89` | 儿童栓绳 | 通过 | `native-remaining-05` |
| `trinket:90` | 棕色雷管 | 通过 | `trinket-followup-06b` |
| `trinket:91` | 胎粪 | 通过 | `manual-confirmation-11` |
| `trinket:92` | 碎裂的王冠 | 通过 | `trinket-direct-01` |
| `trinket:93` | 用过的尿布 | 通过 | `native-remaining-05` |
| `trinket:94` | 鱼尾 | 通过 | `trinket-followup-06b` |
| `trinket:95` | 黑牙 | 通过 | `trinket-conditions-02` |
| `trinket:96` | 衔尾虫 | 通过 | `native-remaining-05` |
| `trinket:97` | 扁桃体 | 通过 | `trinket-lifecycle-04` |
| `trinket:98` | 鼻涕泡 | 通过 | `trinket-direct-01` |
| `trinket:99` | 超级弹球 | 通过 | `trinket-direct-01` |
| `trinket:100` | 亮灯泡 | 通过 | `trinket-direct-01` |
| `trinket:101` | 暗灯泡 | 通过 | `trinket-direct-01` |
| `trinket:102` | 塔罗牌残片 | 通过 | `native-remaining-05` |
| `trinket:103` | 等号！ | 通过 | `trinket-lifecycle-04` |
| `trinket:104` | 许愿骨 | 通过 | `trinket-lifecycle-04` |
| `trinket:105` | 午餐袋 | 通过 | `trinket-lifecycle-04` |
| `trinket:106` | 丢失的瓶塞 | 通过 | `trinket-followup-06b` |
| `trinket:107` | 乌鸦的心 | 通过 | `serial-recovery-14` |
| `trinket:108` | 核桃 | 通过 | `trinket-lifecycle-04` |
| `trinket:109` | 胶带 | 通过 | `native-remaining-05` |
| `trinket:110` | 银币 | 通过 | `native-remaining-05` |
| `trinket:111` | 染血王冠 | 通过 | `native-remaining-05` |
| `trinket:112` | 充钱游戏 | 通过 | `serial-recovery-14` |
| `trinket:113` | 战争蝗虫 | 通过 | `trinket-followup-06b` |
| `trinket:114` | 瘟疫蝗虫 | 通过 | `trinket-followup-06b` |
| `trinket:115` | 饥荒蝗虫 | 通过 | `trinket-followup-06b` |
| `trinket:116` | 死亡蝗虫 | 通过 | `serial-recovery-14` |
| `trinket:117` | 征服蝗虫 | 通过 | `trinket-followup-06b` |
| `trinket:118` | 蝙蝠翅膀 | 通过 | `serial-recovery-14` |
| `trinket:119` | 干细胞 | 通过 | `trinket-lifecycle-04` |
| `trinket:120` | 发夹 | 不兼容 | `serial-recovery-14` |
| `trinket:122` | 黄油！ | 通过 | `manual-confirmation-11` |
| `trinket:123` | 银丝羽毛 | 通过 | `serial-recovery-14` |
| `trinket:124` | 门挡 | 不兼容 | `serial-recovery-14` |
| `trinket:125` | 扩接电线 | 通过 | `trinket-followup-06b` |
| `trinket:126` | 腐烂硬币 | 通过 | `trinket-lifecycle-04` |
| `trinket:127` | 儿童弯勺 | 通过 | `native-remaining-05` |
| `trinket:128` | 指骨 | 通过 | `native-remaining-05` |
| `trinket:129` | 崩掉牙 | 通过 | `trinket-direct-01` |
| `trinket:130` | 嚼烂的笔 | 通过 | `trinket-direct-01` |
| `trinket:131` | 神圣硬币 | 通过 | `trinket-lifecycle-04` |
| `trinket:132` | 损坏的注射器 | 通过 | `native-remaining-05` |
| `trinket:133` | 短引线 | 通过 | `trinket-lifecycle-04` |
| `trinket:134` | 巨豆 | 通过 | `trinket-followup-06b` |
| `trinket:135` | 打火机 | 通过 | `serial-recovery-14` |
| `trinket:136` | 损坏的挂锁 | 通过 | `native-remaining-05` |
| `trinket:137` | 勿忘草 | 通过 | `serial-recovery-14` |
| `trinket:138` | 'M | 通过 | `native-remaining-05` |
| `trinket:139` | 泪滴护符 | 通过 | `native-followup-16-a`、`native-followup-16-b` |
| `trinket:140` | 所多玛之果 | 通过 | `serial-recovery-14` |
| `trinket:141` | 失落摇篮曲 | 通过 | `native-remaining-05` |
| `trinket:142` | 伯大尼的信仰 | 通过 | `trinket-lifecycle-04` |
| `trinket:143` | 老旧电容 | 通过 | `native-remaining-05` |
| `trinket:144` | 脑形虫 | 通过 | `serial-recovery-14` |
| `trinket:145` | 满分考卷 | 通过 | `trinket-lifecycle-04` |
| `trinket:146` | 恶魔王冠 | 通过 | `serial-recovery-14` |
| `trinket:147` | 充能硬币 | 通过 | `trinket-lifecycle-04` |
| `trinket:148` | 友谊项链 | 通过 | `native-remaining-05` |
| `trinket:149` | 紧急按钮 | 通过 | `native-remaining-05` |
| `trinket:150` | 蓝钥匙 | 不兼容 | `serial-recovery-14` |
| `trinket:151` | 扁锉 | 通过 | `native-followup-16-a`、`native-followup-16-b`、`remaining-recovery-13-a`、`serial-recovery-14` |
| `trinket:152` | 望远镜片 | 通过 | `trinket-lifecycle-04` |
| `trinket:153` | 妈妈的发髻 | 通过 | `native-remaining-05` |
| `trinket:154` | 骰子袋 | 通过 | `serial-recovery-14` |
| `trinket:155` | 神圣王冠 | 通过 | `native-remaining-05` |
| `trinket:156` | 母亲的吻 | 通过 | `trinket-direct-01` |
| `trinket:157` | 扑克牌残片 | 通过 | `trinket-lifecycle-04` |
| `trinket:158` | 破损的口袋 | 通过 | `trinket-lifecycle-04` |
| `trinket:159` | 镀金钥匙 | 通过 | `native-remaining-05` |
| `trinket:160` | 幸运袋 | 通过 | `trinket-lifecycle-04` |
| `trinket:161` | 邪恶王冠 | 通过 | `native-remaining-05` |
| `trinket:162` | 阿撒泻勒的残角 | 通过 | `native-followup-18-b`、`serial-recovery-14` |
| `trinket:163` | 粪蛋 | 通过 | `serial-recovery-14` |
| `trinket:164` | 火药圈 | 通过 | `trinket-lifecycle-04` |
| `trinket:165` | 滚啊！ | 通过 | `native-followup-16-a` |
| `trinket:166` | 塑型黏土 | 通过 | `native-remaining-05` |
| `trinket:167` | 抛光骨头 | 通过 | `serial-recovery-14` |
| `trinket:168` | 空壳心 | 通过 | `trinket-lifecycle-04` |
| `trinket:169` | 儿童涂鸦 | 通过 | `serial-recovery-14` |
| `trinket:170` | 水晶钥匙 | 通过 | `native-remaining-05` |
| `trinket:171` | 店主的协议 | 通过 | `native-followup-16-a`、`native-followup-16-b` |
| `trinket:172` | 诅咒硬币 | 通过 | `serial-recovery-14` |
| `trinket:173` | 你的灵魂 | 通过 | `serial-recovery-14` |
| `trinket:174` | 数字冰箱贴 | 通过 | `native-followup-16-a`、`native-followup-16-b` |
| `trinket:175` | 奇怪的钥匙 | 通过 | `serial-recovery-14` |
| `trinket:176` | 小血团 | 通过 | `serial-recovery-14` |
| `trinket:177` | 纹身贴 | 通过 | `native-followup-20-b`、`native-followup-25-a`、`serial-recovery-14` |
| `trinket:178` | 被吞下的M80鞭炮 | 通过 | `trinket-lifecycle-04` |
| `trinket:179` | 赛车遥控器 | 通过 | `serial-recovery-14` |
| `trinket:181` | 扩展电路板 | 通过 | `serial-recovery-14` |
| `trinket:182` | 伯大尼的精华 | 通过 | `serial-recovery-14` |
| `trinket:183` | 双胞胎 | 通过 | `native-remaining-05` |
| `trinket:184` | 领养协议书 | 通过 | `native-followup-16-a`、`native-followup-16-b` |
| `trinket:185` | 蟋蟀腿 | 通过 | `serial-recovery-14` |
| `trinket:186` | 亚玻伦的挚友 | 通过 | `serial-recovery-14` |
| `trinket:187` | 碎掉的眼镜 | 通过 | `native-followup-18-a`、`native-followup-18-b`、`parallel-recovery-10-c` |
| `trinket:188` | 冰块 | 通过 | `native-remaining-05` |
| `trinket:189` | 巴风特之印 | 通过 | `trinket-lifecycle-04` |

## 离线验证

验收判定器、工具、夹具与隔离资料保护的 244 个定向 Python 用例通过；Python／Lua／打包脚本语法、`tools/format.py --check`、PowerShell 格式、文档生成一致性和 `git diff --check` 通过。离线通过不代替上述实机结果。
