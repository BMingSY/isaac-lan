#!/usr/bin/env python3
"""Prepare disposable game copies. Does not start a game or alter the installation."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--game", type=Path, required=True)
    parser.add_argument("--build", type=Path, required=True)
    parser.add_argument("--lab", type=Path, required=True)
    args = parser.parse_args()
    if args.lab.exists():
        raise SystemExit("Refusing to reuse an existing directory; choose a fresh lab path")
    if not args.game.joinpath("isaac-ng.exe").is_file():
        raise SystemExit("Missing game executable")
    for name in ("isaac_lan_probe.dll", "isaac_lan_lab.exe"):
        if not args.build.joinpath(name).is_file():
            raise SystemExit(f"Missing build artifact: {name}")
    game = args.lab / "game"
    save = args.lab / "profile/Documents/My Games/Binding of Isaac Repentance+"
    save.mkdir(parents=True)
    game.mkdir()
    (args.lab / ".isaac-lan-lab").write_text("Disposable isolated development instance.\n")
    manifest = {}
    for source in args.game.iterdir():
        if source.is_file() and (source.suffix.lower() == ".dll" or source.name in ("isaac-ng.exe", "curl-ca-bundle.crt")):
            shutil.copy2(source, game / source.name)
            manifest[source.name] = hashlib.sha256(source.read_bytes()).hexdigest()
    # Independent copies: even an unexpected resource write cannot reach the live game.
    shutil.copytree(args.game / "resources", game / "resources")
    shutil.copy2(args.build / "isaac_lan_probe.dll", game)
    shutil.copy2(args.build / "isaac_lan_lab.exe", args.lab)
    (game / "steam_appid.txt").write_text("250900\n")
    (save / "options.ini").write_text(
        "[Options]\nSteamCloud=0\nEnableMods=1\nEnableDebugConsole=1\n"
        "Fullscreen=0\nWindowWidth=960\nWindowHeight=540\nWindowPosX=80\nWindowPosY=80\n"
        "VSync=1\nPauseOnFocusLost=0\nMusicVolume=0\nSFXVolume=0\nAnnouncerVoiceMode=0\n")
    testmod = game / "mods/lan_native_internal_probe"
    testmod.mkdir(parents=True)
    # Steam may populate subscribed content in this isolated copy on startup.
    # Seed disabled markers before any Lua can execute; do not copy or modify
    # the user's enabled/disabled state in the real installation.
    for mod in (args.game / "mods").iterdir():
        if mod.is_dir() and mod.name != testmod.name:
            private_mod = game / "mods" / mod.name
            private_mod.mkdir(exist_ok=True)
            (private_mod / "disable.it").touch()
    (testmod / "metadata.xml").write_text(
        '<metadata><name>Internal native probe</name><directory>lan_native_internal_probe</directory><version>dev</version></metadata>\n')
    source = Path(__file__).resolve().parent.parent / "tests/engine_probe.lua"
    shutil.copy2(source, testmod / "main.lua")
    (args.lab / "copied-game-manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    print(args.lab)


if __name__ == "__main__":
    main()
