#!/usr/bin/env python3
"""Bundle registered native CTest cases for execution on a different machine."""

import argparse
import json
from pathlib import Path
import re
import shutil
import subprocess


def literal(value):
    """Quote a literal CMake argument without interpreting variables or escapes."""
    if isinstance(value, list):
        value = ";".join(map(str, value))
    elif isinstance(value, bool):
        value = "TRUE" if value else "FALSE"
    else:
        value = str(value)
    equals = "="
    while "]" + equals + "]" in value:
        equals += "="
    return "[" + equals + "[" + value + "]" + equals + "]"


def bundle(build, output):
    build, output = Path(build).resolve(), Path(output).resolve()
    catalog = json.loads(
        subprocess.check_output(
            ["ctest", "--test-dir", str(build), "--show-only=json-v1", "-LE", "lua"],
            text=True,
        )
    )
    if not catalog["tests"]:
        raise ValueError("No native CTest cases were registered")
    binaries = set()
    names = set()
    cases = []
    for case in catalog["tests"]:
        name = case["name"]
        if not re.fullmatch(r"[A-Za-z0-9_.-]+", name) or name in names:
            raise ValueError(f"Invalid or duplicate test name: {name}")
        names.add(name)
        command = case.get("command", [])
        if not command:
            raise ValueError(f"Missing executable for {name}")
        binary = Path(command[0]).resolve()
        if binary.parent != build or not binary.is_file():
            raise ValueError(f"Test executable must exist in the build directory: {binary}")
        binaries.add(binary)
        properties = []
        for prop in case["properties"]:
            if prop["name"] == "WORKING_DIRECTORY":
                if Path(prop["value"]).resolve() != build:
                    raise ValueError(f"Non-relocatable working directory for {name}")
            else:
                properties.append(prop)
        cases.append(
            {"name": name, "command": [binary.name, *command[1:]], "properties": properties}
        )
    output.mkdir(parents=True, exist_ok=False)
    for binary in sorted(binaries):
        shutil.copy2(binary, output / binary.name)
    (output / "tests.json").write_text(json.dumps(cases, indent=2) + "\n", encoding="utf-8")
    print(f"Bundled {len(names)} CTest cases from {len(binaries)} executables")


def configure(directory):
    directory = Path(directory).resolve()
    cases = json.loads((directory / "tests.json").read_text(encoding="utf-8"))
    lines = ["# Generated from the bundled CTest registrations on this runner."]
    for case in cases:
        name = case["name"]
        command = [str(directory / case["command"][0]), *case["command"][1:]]
        args = " ".join(literal(arg) for arg in command)
        lines.append(f"add_test({literal(name)} {args})")
        for prop in case["properties"]:
            lines.append(
                f"set_tests_properties({literal(name)} PROPERTIES {prop['name']} {literal(prop['value'])})"
            )
        work = directory / "work" / name
        work.mkdir(parents=True, exist_ok=True)
        lines.append(
            f"set_tests_properties({literal(name)} PROPERTIES WORKING_DIRECTORY {literal(work.as_posix())})"
        )
    (directory / "CTestTestfile.cmake").write_text("\n".join(lines) + "\n", encoding="utf-8")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    export = commands.add_parser("export", help="Package the native build's registered tests")
    export.add_argument("--build", type=Path, required=True)
    export.add_argument("--output", type=Path, required=True)
    run = commands.add_parser("configure", help="Resolve bundle paths on the test runner")
    run.add_argument("directory", type=Path)
    args = parser.parse_args()
    if args.command == "export":
        bundle(args.build, args.output)
    else:
        configure(args.directory)


if __name__ == "__main__":
    main()
