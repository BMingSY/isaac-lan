"""The cross-platform artifact runs the registered cases, including failures."""

import json
import shutil
import subprocess
import xml.etree.ElementTree as ET

import pytest

from bundle_ctest import bundle, configure


@pytest.fixture
def native_build(tmp_path):
    source = tmp_path / "source"
    source.mkdir()
    (source / "main.c").write_text(
        "#include <stdio.h>\n#include <string.h>\n"
        "int main(int argc, char **argv) {\n"
        '  puts(argc > 1 ? argv[1] : "missing argument");\n'
        '  return argc != 2 || strcmp(argv[1], "pass ${literal} [=[text]=]; space");\n'
        "}\n"
    )
    (source / "CMakeLists.txt").write_text(
        "cmake_minimum_required(VERSION 3.20)\n"
        "project(bundle_fixture C)\n"
        "enable_testing()\n"
        "add_executable(probe main.c)\n"
        "add_test(NAME first COMMAND probe [==[pass ${literal} [=[text]=]; space]==])\n"
        "add_test(NAME second COMMAND probe [==[pass ${literal} [=[text]=]; space]==])\n"
        "add_test(NAME fails COMMAND probe wrong)\n"
        'set_tests_properties(first second fails PROPERTIES TIMEOUT 3 LABELS "offline;core")\n'
        "set_tests_properties(second PROPERTIES RESOURCE_LOCK shared-resource COST 2)\n"
        "add_test(NAME lua-only COMMAND missing-interpreter)\n"
        "set_tests_properties(lua-only PROPERTIES LABELS lua)\n"
    )
    build = tmp_path / "build"
    subprocess.run(["cmake", "-S", str(source), "-B", str(build)], check=True, capture_output=True)
    subprocess.run(["cmake", "--build", str(build)], check=True, capture_output=True)
    return build


def test_relocated_bundle_keeps_cases_arguments_properties_and_failure(native_build, tmp_path):
    output = tmp_path / "artifact"
    bundle(native_build, output)
    shutil.rmtree(native_build)
    moved = tmp_path / "other machine with spaces"
    output.rename(moved)
    configure(moved)
    listing = json.loads(
        subprocess.check_output(
            ["ctest", "--test-dir", str(moved), "--show-only=json-v1"], text=True
        )
    )
    cases = {case["name"]: case for case in listing["tests"]}
    assert set(cases) == {"first", "second", "fails"}
    properties = {p["name"]: p["value"] for p in cases["second"]["properties"]}
    assert properties["TIMEOUT"] == 3
    assert properties["RESOURCE_LOCK"] == ["shared-resource"]
    assert properties["COST"] == 2
    directories = {
        prop["value"]
        for case in cases.values()
        for prop in case["properties"]
        if prop["name"] == "WORKING_DIRECTORY"
    }
    assert len(directories) == 3
    report = tmp_path / "report.xml"
    result = subprocess.run(
        ["ctest", "--test-dir", str(moved), "-j", "2", "--output-junit", str(report)],
        capture_output=True,
        text=True,
    )
    assert result.returncode != 0
    tests = {case.attrib["name"]: case for case in ET.parse(report).findall("testcase")}
    assert tests["first"].find("failure") is None
    assert tests["second"].find("failure") is None
    assert tests["fails"].find("failure") is not None


def test_bundle_rejects_missing_binary_instead_of_dropping_test(native_build, tmp_path):
    (native_build / "probe").unlink()
    with pytest.raises(ValueError, match="Missing executable"):
        bundle(native_build, tmp_path / "artifact")


def test_bundle_does_not_overwrite_an_existing_artifact(native_build, tmp_path):
    artifact = tmp_path / "artifact"
    artifact.mkdir()
    sentinel = artifact / "owned.txt"
    sentinel.write_text("keep")
    with pytest.raises(FileExistsError):
        bundle(native_build, artifact)
    assert sentinel.read_text() == "keep"
