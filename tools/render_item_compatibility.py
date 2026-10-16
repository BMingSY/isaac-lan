#!/usr/bin/env python3
"""Render the compatibility inventory from the native catalog and reviewed findings."""

import argparse
import json
from pathlib import Path

from item_audit import ROOT

STATUSES = {
    "untested": "未验证",
    "basic_pass": "基础检查通过；效果待专项",
    "incomplete": "验证未完成",
    "problem": "发现异常",
    "crash": "复现崩溃",
    "verified": "专项已验证",
    "reported": "用户反馈；未完全定位",
}
KINDS = {"collectible": "道具", "trinket": "饰品", "card": "卡牌与符文", "pill": "药丸效果"}


def cell(value):
    return str(value).replace("|", "\\|").replace("\n", " ")


def conclusion(known, audit):
    value = {**known, **audit}
    severity = {"reported": 1, "problem": 2, "crash": 3}
    if known.get("status") in severity and severity[known["status"]] >= severity.get(
        audit.get("status"), 0
    ):
        value.update({key: known[key] for key in ("status", "impact") if key in known})
    elif known.get("status") == "verified" and audit.get("status") not in {"crash", "problem"}:
        value.update({key: known[key] for key in ("status", "impact") if key in known})
    return value


def render(catalog, findings):
    known, audit = findings.get("known", {}), findings.get("audit", {})
    items = catalog["items"]
    lines = [
        "# 道具与效果兼容清单",
        "",
        f"范围：忏悔＋ `{catalog['game']}` 的实际配置，共 {len(items)} 项。隐藏／内部道具也保留；空缺 ID 不补造条目。",
        "",
        "“基础检查通过”仅代表该场景的赋予、使用／发射、同步与退出完成，不代表所有条件效果、组合和路线已验证。未验证不等于不兼容。异常按未生效、崩溃、客机重连、非原版效果分类；已有的联机共享规则单独注明。",
        "",
        "实体 ID 采用 `类型.变体.子类型`，这里指地上的拾取物。药丸效果 ID 与颜色编号不同：实体为 `5.70.<颜色>`，颜色到效果的对应关系随本局变化；大药丸另测，不把效果 ID 当成实体子类型。",
        "",
        "## 当前已知问题",
        "",
        "| 项目 | 影响与验证范围 |",
        "| --- | --- |",
    ]
    for item in items:
        entry = conclusion(known.get(item["key"], {}), audit.get(item["key"], {}))
        if entry.get("status") in {"problem", "crash", "reported"}:
            lines.append(
                f"| {cell(item.get('name_zh', item['name']))}（{item['id']}） | {cell(entry.get('impact', '详见该项记录'))} |"
            )
    lines += [
        "",
        "## 验证方式",
        "",
        "[`run_item_audit.py`](https://github.com/BMingSY/isaac-lan/blob/main/tools/run_item_audit.py) 使用带归属标记的隔离主客机，打开属性栏和道具栏。每项重新开局以清除上项效果，复用进程；异常后保留证据，再恢复剩余项目。",
        "",
        "- `--mode mega`：超级蘑菇，主客机持有 × 同房／分房，正常按键使用、持续期间换房和结束恢复。",
        "- `--mode sweep`：全清单基础扫描，默认主机同房、客机分房；主动道具／卡牌走按键，药丸按效果 ID 调用原生使用接口，普通／大药丸分别记录。",
        "- `--mode stress`：空背包基线、100／300／500 种被动道具、1000 份早餐、100／500／1000／2000 颗泪弹或敌弹，以及组合负载。记录实际数量、双端帧间隔、同步耗时和原始状态大小。压力测量单独运行。",
        "",
        "工具参数必须指定 `--host`、`--client`、`--build`、`--output`；`--case` 可选单项，`--record` 保留画面，`--continue-after-failure` 在异常清理后继续。完整条件效果仍需专项断言；瞬间生成全部道具和固定弹幕属于容量测试。",
        "",
        "清单源数据为 [`item_catalog.json`](https://github.com/BMingSY/isaac-lan/blob/main/tests/fixtures/item_catalog.json)，结论与测试产物标识为 [`item_audit_findings.json`](https://github.com/BMingSY/isaac-lan/blob/main/tests/fixtures/item_audit_findings.json)。验证范围和结果见对应 PR；运行工具会保留双端日志、画面、哈希和崩溃转储。",
        "",
    ]
    for kind, title in KINDS.items():
        group = [item for item in items if item["kind"] == kind]
        lines += [
            f"## {title}（{len(group)}）",
            "",
            "| ID | 实体 ID | 名称 | 兼容验证 | 未兼容的影响 | 兼容后的效果／目标 |",
            "| --- | --- | --- | --- | --- | --- |",
        ]
        for item in group:
            entry = conclusion(known.get(item["key"], {}), audit.get(item["key"], {}))
            subtype = "<颜色>" if kind == "pill" else item["entity_subtype"]
            entity = f"{item['entity_type']}.{item['entity_variant']}.{subtype}"
            status = STATUSES[entry.get("status", "untested")]
            impact = entry.get(
                "impact",
                "尚未确认"
                if entry.get("status", "untested") != "verified"
                else "所列专项未发现异常",
            )
            effect = entry.get("effect", "原版效果；待完整验证")
            lines.append(
                "| "
                + " | ".join(
                    cell(value)
                    for value in (
                        item["id"],
                        f"`{entity}`",
                        item.get("name_zh", item["name"])
                        + ("（内部）" if item.get("hidden") else ""),
                        status,
                        impact,
                        effect,
                    )
                )
                + " |"
            )
        lines.append("")
    lines += [
        "公共效果的范围由 [`team_effects.h`](https://github.com/BMingSY/isaac-lan/blob/main/src/compat/items/team_effects.h) 声明。恶魔／天使房概率相关的全队叠加规则见[概率说明](https://github.com/BMingSY/isaac-lan/blob/main/docs/shared-deal-chances.md)。",
        "",
    ]
    return "\n".join(lines)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    text = render(
        json.loads((ROOT / "tests/fixtures/item_catalog.json").read_text()),
        json.loads((ROOT / "tests/fixtures/item_audit_findings.json").read_text()),
    )
    path = ROOT / "docs/item-effect-compatibility.md"
    if args.check:
        if path.read_text() != text:
            raise SystemExit("Compatibility document differs from catalog/findings")
    else:
        path.write_text(text)


if __name__ == "__main__":
    main()
