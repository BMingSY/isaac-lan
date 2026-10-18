#!/usr/bin/env python3
"""Render the compatibility inventory from the native catalog and reviewed findings."""

import argparse
import json
from pathlib import Path

from item_audit import ROOT

STATUSES = {
    "untested": "待验证",
    "basic_pass": "待验证",
    "incomplete": "待验证",
    "problem": "不兼容",
    "crash": "不兼容",
    "verified": "已验证",
    "reported": "待确认",
    "suspected": "待确认",
}
KINDS = {"collectible": "道具", "trinket": "饰品", "card": "卡牌与符文", "pill": "药丸效果"}
ISSUE_STATUSES = {"problem", "crash", "reported", "suspected"}


def cell(value):
    return str(value).replace("|", "\\|").replace("\n", " ")


def item_name(item, entry):
    name = item.get("name_zh", item["name"])
    note = entry.get("name_note", "内部" if item.get("hidden") else "")
    return name + (f"（{note}）" if note else "")


def conclusion(known, audit):
    value = {**known, **audit}
    severity = {"reported": 1, "suspected": 1, "problem": 2, "crash": 3}
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
        "## 已知不兼容",
        "",
        "这里只列已记录的效果异常及其影响；修复后的实机复验通过前保留原结论。“待确认”表示尚未复现或尚不能确定原因，不等同已确认不兼容。",
        "",
        "| 类型 | ID | 名称 | 状态 | 触发条件 | 影响 | 当前处理 |",
        "| --- | --- | --- | --- | --- | --- | --- |",
    ]
    for item in items:
        entry = conclusion(known.get(item["key"], {}), audit.get(item["key"], {}))
        if entry.get("status") not in ISSUE_STATUSES:
            continue
        lines.append(
            "| "
            + " | ".join(
                cell(value)
                for value in (
                    KINDS[item["kind"]],
                    item["id"],
                    item_name(item, entry),
                    STATUSES[entry["status"]],
                    entry.get("trigger", "尚未确定稳定触发条件"),
                    entry.get("impact", "影响待确认"),
                    entry.get("fix", "—"),
                )
            )
            + " |"
        )
    lines += [
        "",
        "## 额外兼容",
        "",
        "这里汇总 Mod 对原版效果的调整。全队共享效果在分房时也生效；本表验证状态针对调整后的效果，不能用旧版个人效果验收替代共享规则验收。",
        "",
        "| ID | 名称 | 兼容验证 | Mod 效果调整 |",
        "| --- | --- | --- | --- |",
    ]
    for item in items:
        entry = conclusion(known.get(item["key"], {}), audit.get(item["key"], {}))
        if entry.get("effect") and entry["effect"] != "—":
            lines.append(
                "| "
                + " | ".join(
                    cell(value)
                    for value in (
                        item["id"],
                        item_name(item, entry),
                        STATUSES[entry.get("effect_status", entry.get("status", "untested"))],
                        entry["effect"],
                    )
                )
                + " |"
            )
    lines += [
        "",
        "## 完整清单",
        "",
        f"范围：忏悔＋ `{catalog['game']}` 的实际配置，共 {len(items)} 项。隐藏／内部道具也保留；空缺 ID 不补造条目。",
        "",
        "兼容验证：**已验证**＝记录范围内的独立效果、归属与双端状态已验证正常；**待验证**＝尚未确认单独效果；**不兼容**＝已复现问题；**待确认**＝疑似问题。只通过基础流程检查、触发条件未成立或证据不完整的仍列为“待验证”；不代表所有道具组合和角色变体均已覆盖。",
        "",
        "未记录问题或没有额外调整的格子用“—”。",
        "",
        "实体 ID 指拾取物，格式为 `类型.变体.子类型`。药丸子类型是颜色编号，与药丸效果 ID 不同。",
        "",
    ]
    for kind, title in KINDS.items():
        group = [item for item in items if item["kind"] == kind]
        lines += [
            f"### {title}（{len(group)}）",
            "",
            "| ID | 实体 ID | 名称 | 兼容验证 | 问题／验证限制 | Mod 效果调整 |",
            "| --- | --- | --- | --- | --- | --- |",
        ]
        for item in group:
            entry = conclusion(known.get(item["key"], {}), audit.get(item["key"], {}))
            subtype = "<颜色>" if kind == "pill" else item["entity_subtype"]
            entity = f"{item['entity_type']}.{item['entity_variant']}.{subtype}"
            recorded_status = entry.get("status", "untested")
            status = STATUSES[
                recorded_status
                if recorded_status in ISSUE_STATUSES
                else entry.get("effect_status", recorded_status)
            ]
            impact = (
                entry.get("impact", "待确认")
                if entry.get("status") in ISSUE_STATUSES
                else entry.get("limitation", "—")
            )
            if recorded_status == "verified" and entry.get("effect_status") == "untested":
                impact = "调整后的共享效果尚未实机复验；原独立效果验收记录保留。"
            effect = entry.get("effect", "—")
            lines.append(
                "| "
                + " | ".join(
                    cell(value)
                    for value in (
                        item["id"],
                        f"`{entity}`",
                        item_name(item, entry),
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
        "验证操作与默认范围见[开发与测试](https://github.com/BMingSY/isaac-lan/blob/main/docs/development-and-testing.md#道具效果专项)。逐项结论、未决项及证据范围见[验收记录](https://github.com/BMingSY/isaac-lan/blob/main/docs/history/2026-10-18-item-effects.md)。",
        "",
        "清单源数据：[`item_catalog.json`](https://github.com/BMingSY/isaac-lan/blob/main/tests/fixtures/item_catalog.json)；验证记录与证据标识：[`item_audit_findings.json`](https://github.com/BMingSY/isaac-lan/blob/main/tests/fixtures/item_audit_findings.json)。运行结果见对应 PR。",
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
