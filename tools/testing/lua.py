"""Serialize fixture parameters and compose explicit Lua scenario contracts."""

import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]


def bundle_input(source):
    """Embed test input support for either native sandbox or offline execution."""
    return (
        "_IsaacLanTestInput = (function()\n"
        + (ROOT / "tests/support/input.lua").read_text(encoding="utf-8")
        + "\nend)()\n"
        + source
    )


def literal(value):
    if value is None:
        return "nil"
    if isinstance(value, bool):
        return str(value).lower()
    if isinstance(value, (str, int, float)):
        return json.dumps(value, ensure_ascii=False)
    if isinstance(value, (list, tuple)):
        return "{" + ",".join(literal(item) for item in value) + "}"
    if isinstance(value, dict):
        return "{" + ",".join("[" + literal(k) + "]=" + literal(v) for k, v in value.items()) + "}"
    raise TypeError(f"Unsupported Lua fixture value: {type(value).__name__}")


def factory(script, *, options=None, prelude=""):
    source = (ROOT / "tests" / script).read_text()
    return (
        "function()\n"
        + "for key, value in pairs("
        + literal(options or {})
        + ") do _IsaacLanTest[key] = value end\n"
        + prelude
        + "\n"
        + source
        + "\nend"
    )


def support():
    return (
        "local createScenario = (function()\n"
        + (ROOT / "tests/support/scenario.lua").read_text()
        + "\nend)()\n"
    )


def write_suite(output, factories):
    if not factories:
        raise ValueError("A native suite must contain at least one scenario")
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(
        support()
        + "local fixtures = {\n"
        + ",\n".join(factories)
        + "\n}\n"
        + (ROOT / "tests/special_suite_driver.lua").read_text()
    )
