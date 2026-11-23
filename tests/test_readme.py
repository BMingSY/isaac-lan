"""Keep player-facing configuration examples in sync with a fresh installation."""

from configparser import ConfigParser
from pathlib import Path
import re
import subprocess

ROOT = Path(__file__).resolve().parents[1]


def settings(text):
    ini = ConfigParser(interpolation=None)
    ini.optionxform = str
    ini.read_string(text)
    return {section: dict(ini[section]) for section in ini.sections()}


def test_readme_examples_match_first_launch_config(tmp_path):
    writer = tmp_path / "write-config"
    subprocess.run(
        [
            "c++",
            "-std=c++20",
            "-I",
            ROOT / "src",
            ROOT / "src/app/configuration.cpp",
            "-x",
            "c++",
            "-",
            "-o",
            writer,
        ],
        input=(
            '#include "app/configuration.h"\n'
            "int main(int, char** argv) {\n"
            "    return isaac::configuration::load(argv[1]).warnings.empty() ? 0 : 1;\n"
            "}\n"
        ),
        text=True,
        check=True,
    )
    config = tmp_path / "isaac-lan/config.ini"
    subprocess.run([writer, config], check=True)
    expected = settings(config.read_text(encoding="utf-8"))

    for readme in [ROOT / "README.md", *sorted((ROOT / "docs/i18n").glob("README.*.md"))]:
        examples = re.findall(
            r"^```ini\n(.*?)^```$", readme.read_text(encoding="utf-8"), re.M | re.S
        )
        assert len(examples) == 1, readme
        assert settings(examples[0]) == expected, readme
