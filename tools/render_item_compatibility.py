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
        "## 额外兼容",
        "",
        "这里汇总 Mod 对原版效果的调整。全队共享效果在分房时也生效。",
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
                        item.get("name_zh", item["name"]),
                        STATUSES[entry.get("status", "untested")],
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
        "兼容验证：**已验证**＝单独效果已验证正常；**待验证**＝尚未确认单独效果；**不兼容**＝已复现问题；**待确认**＝疑似问题。只通过基础流程检查的仍列为“待验证”。",
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
            "| ID | 实体 ID | 名称 | 兼容验证 | 已知问题 | Mod 效果调整 |",
            "| --- | --- | --- | --- | --- | --- |",
        ]
        for item in group:
            entry = conclusion(known.get(item["key"], {}), audit.get(item["key"], {}))
            subtype = "<颜色>" if kind == "pill" else item["entity_subtype"]
            entity = f"{item['entity_type']}.{item['entity_variant']}.{subtype}"
            status = STATUSES[entry.get("status", "untested")]
            impact = entry.get("impact", "待确认") if entry.get("status") in ISSUE_STATUSES else "—"
            effect = entry.get("effect", "—")
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
        "## 验证工具",
        "",
        "[`run_item_audit.py`](https://github.com/BMingSY/isaac-lan/blob/main/tools/run_item_audit.py) 使用隔离主客机，打开属性栏和道具栏。每项重新开局清除上项效果，复用进程与连接。",
        "",
        "- `--mode mega`：超级蘑菇使用、换房和结束恢复，覆盖主客机持有及同房／分房。",
        "- `--mode sweep`：全清单基础扫描，默认主机同房、客机分房；主动道具、卡牌和药丸通过按键使用，普通／大药丸分别记录。",
        "- `--mode effects`：有明确效果断言的逐项验证；核对对应属性、归属和双端状态，缺少证据不能通过。",
        "- `--mode stress`：大量道具和弹幕压力测试，单独运行；记录实际数量、帧间隔和同步耗时。",
        "",
        "必填参数：`--host`、`--client`、`--build`、`--output`。`--case` 选择单项，`--record` 保留画面，`--continue-after-failure` 在异常清理后继续。",
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
