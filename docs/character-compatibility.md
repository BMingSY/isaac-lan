# 角色兼容清单

| 角色 | 兼容后的效果 |
| --- | --- |
| 里店长 | 队伍中有里店长时，全队商店采用里店长的布局和定价，首层及分房后均生效。 |
| 里游魂（Tainted Lost） | 全队共享其道具筛选、低品质道具重抽和神圣卡生成特性，分房后仍生效。 |
| 骸骨／灵魂（Forgotten／Soul） | 同步当前及隐藏形态的生命，包括灵魂心、黑心和骨心。 |
| 里莉莉丝 | 跟班绳索同步原生几何与材质，在客机本地绘制，不执行客机跟班攻击逻辑。 |
| 里骸骨（Tainted Forgotten） | 灵魂保留本地行走预测，骨架使用主机的运动轨迹，不随灵魂方向输入产生步行偏移。 |
| 联机幽灵 | 所在房间没有在线存活队友时随队转移，使用目标房间中存活队友的位置落地；仍有存活队友同房时保留自由移动，客机预测允许飞越坑洞与地面障碍。 |

里游魂的原版 J460 生成规则：只保留攻击性候选，品质 0／1 额外有五分之一概率重抽；允许特殊卡时有十分之一概率替换为神圣卡。后端仅在生成查询期间借用完整名单，保留原版种子与算法；个人生命、飞行与出生库存不共享。入口与签名见 [`entrypoints.h`](https://github.com/BMingSY/isaac-lan/blob/main/src/engine/versions/j460/entrypoints.h) 和 [`signatures.inc`](https://github.com/BMingSY/isaac-lan/blob/main/src/engine/versions/j460/signatures.inc)。
