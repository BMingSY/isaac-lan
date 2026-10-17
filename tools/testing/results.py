"""Common native-run outcome and evidence envelope; retain suite-specific details."""

import json
import sys
from xml.etree import ElementTree as ET
from testing.engine import BackendCleanupError, stop_child


SCHEMA_VERSION = 1


def write_report(output, report):
    temporary = output / "report.json.tmp"
    temporary.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
    temporary.replace(output / "report.json")
    status = report["status"]
    suite = ET.Element(
        "testsuite",
        name=output.name,
        tests="1",
        failures=str(int(status == "failed")),
        errors=str(int(status == "error")),
        skipped=str(int(status in {"skipped", "not_run"})),
    )
    case = ET.SubElement(suite, "testcase", name=output.name, classname="engine")
    if status != "passed":
        tag = {"failed": "failure", "error": "error"}.get(status, "skipped")
        ET.SubElement(case, tag, message=report.get("error", status))
    ET.SubElement(case, "system-out").text = "Detailed evidence: report.json"
    ET.ElementTree(suite).write(output / "junit.xml", encoding="utf-8", xml_declaration=True)


def finish_run(protected, report, output, *, process=None):
    """Called in finally: stop the backend before checking/restoring protected data."""
    error = sys.exc_info()[1]
    if error is not None:
        report["error"] = str(error) or type(error).__name__
        report["passed"] = False
    stopped = (
        not isinstance(error, BackendCleanupError)
        and report.get("error_type") != "BackendCleanupError"
    )
    try:
        stop_child(process)
    except BaseException as cleanup_error:
        report["cleanup_error"] = str(cleanup_error) or type(cleanup_error).__name__
        report["passed"] = False
        stopped = False
    try:
        if not stopped:
            raise RuntimeError("Backend cleanup is unfinished; protected data was not replaced")
        restoration = protected.restore()
        report["restoration"] = restoration
        for source, actual in restoration.items():
            if source in report.get("protected", {}):
                report["protected"][source]["after"] = actual
        report["restored"] = True
        (output / "restored.json").write_text(json.dumps(restoration, indent=2) + "\n")
    except BaseException as restoration_error:
        report["restoration_error"] = str(restoration_error) or type(restoration_error).__name__
        report["restored"] = False
        report["passed"] = False
    # Only the suite's assertion evaluator can claim completion.
    report.setdefault("passed", False)
    if report.get("error") or report.get("returncode", 0) != 0:
        report["passed"] = False
    report["schema_version"] = SCHEMA_VERSION
    infrastructure_error = (
        any(report.get(key) for key in ("cleanup_error", "restoration_error"))
        or report.get("error_type", "AssertionError") != "AssertionError"
    )
    report["status"] = (
        "error"
        if infrastructure_error or (error is not None and not isinstance(error, AssertionError))
        else "passed"
        if report["passed"]
        else "failed"
    )
    write_report(output, report)
