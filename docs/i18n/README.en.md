# Isaac LAN

[简体中文](https://github.com/BMingSY/isaac-lan/blob/main/README.md) · English

Play *The Binding of Isaac* with 2–4 players over a LAN. One installation supports both Windows game builds, **Repentance v1.7.9b.J835** and **Repentance+ v1.9.7.19.J511**. [Download Isaac LAN](https://github.com/BMingSY/isaac-lan/releases/latest)

## Features

- Explore and fight in separate rooms on the same floor. Use the minimap to find your teammates and regroup.
- Play with other mods enabled and use the game's built-in multiplayer interface.
- Check connection latency and reconnect after a disconnect.

## Install or update

Close the game and extract the release ZIP.

### Windows

Run `Install.cmd` and select `isaac-ng.exe` in your game directory.

### Linux or Steam Deck (Proton)

Use Proton 11.0-2 or later. From the extracted directory, run the following command with the path to your game installation.

```sh
python3 install.py --game-directory "/path/to/The Binding of Isaac Rebirth"
```

In the game's Steam properties, set **Launch Options** to the following.

```text
WINEDLLOVERRIDES="winmm=n,b" %command%
```

## Host or join a game

All players need the same game build and Isaac LAN version. Launch through Steam, select a save slot and open the third item on the main menu.

| Game | Menu |
| --- | --- |
| Repentance | Online |
| Repentance+ | Online → LAN Co-op |

1. The host checks the port (UDP 29506 by default), selects **Create Room** and shares the address and port with the other players.
2. Each guest enters the host's IPv4 address, IPv6 address or domain name and port, then selects **Join Room**.
3. Once everyone has chosen a character and is ready, the host starts the run.

## Uninstall

Close the game first. The uninstaller keeps your settings, multiplayer saves and logs.

- **Windows** — Run `Uninstall.cmd` and select `isaac-ng.exe` in your game directory.
- **Linux or Steam Deck** — Run the installation command with `--mode Uninstall` appended. Remove the Steam launch option you added for Isaac LAN.

## Settings and logs

The first launch creates `isaac-lan/config.ini` in the game directory. On later launches, Isaac LAN adds missing settings and keeps your existing values. Restart the game after editing the file.

```ini
[network]
; Guest input updates per second. Each player can choose 30 or 60 (default).
; At 30, input uses less bandwidth and can take one extra render frame.
; The host simulation rate and your local rendering rate are independent of this setting.
input_hz = 60

[players]
; Opacity of other players on your screen, from 0 (invisible) to 100 (original).
others_opacity = 100
; Predict your own movement as a guest. Set false to show only positions the host confirms.
movement_prediction = true

[logging]
; Available levels are DEBUG, INFO, WARN and ERROR.
level = INFO

[diagnostics]
; Enable performance.jsonl in the log directory when investigating stutter.
performance = false
; Sampling interval in milliseconds, from 100 to 60000.
sample_interval_ms = 1000

[chat]
; Chat background opacity, from 0 (transparent) to 100 (opaque).
background_opacity = 70
; PNG, JPG/JPEG or BMP. Use an absolute path or a path relative to config.ini.
; For example, backgrounds/chat.png. Leave empty for a solid background.
; Images are scaled to the chat panel and retain transparency.
background_image =
; Solid background, border/dividers and UI text. Use six hex digits without #.
background_color = 231B18
border_color = 79604C
text_color = E8DFCB
```

Isaac LAN saves logs alongside the game's `log.txt`, grouped by launch and run. `startup.log` covers startup and shutdown. `runtime.log` records events during a run. You can delete old logs manually.

## Build from source

You need CMake, Ninja, 32-bit MinGW-w64, and the sources for Dear ImGui v1.92.6 and MinHook v1.3.4. Set `ISAAC_IMGUI_SOURCE` and `ISAAC_MINHOOK_SOURCE` to their source directories, then run the following from the repository root.

```sh
for backend in repentance repentance_plus
do
  cmake -S . -B "build-$backend" -G Ninja \
    -DCMAKE_TOOLCHAIN_FILE=cmake/mingw-x86.cmake \
    -DCMAKE_BUILD_TYPE=Release -DISAAC_LAN_BACKEND="$backend" \
    -DIMGUI_SOURCE_DIR="$ISAAC_IMGUI_SOURCE" \
    -DMINHOOK_SOURCE_DIR="$ISAAC_MINHOOK_SOURCE"
  cmake --build "build-$backend" --target isaac_lan_probe isaac_lan_check
done
cmake --build build-repentance_plus --target isaac_lan_loader
python3 tools/build_package.py --build build-repentance --build build-repentance_plus --output dist/Isaac-LAN
```

The technical documentation and third-party mod integration guide are available in Chinese. [Architecture and development](https://github.com/BMingSY/isaac-lan/tree/main/docs) · [Third-party mod API](https://github.com/BMingSY/isaac-lan/blob/main/docs/third-party-mod-integration.md)

## Report a problem

In multiplayer chat, enter `/feedback` followed by a description. On success, the game shows a feedback ID. If the upload fails, it shows where the feedback package was saved locally.

The package includes the game and extension versions, multiplayer logs from the last two launches, the game's `log.txt` and the extension's `config.ini`. It goes to the author's server and only the author can view the upload. Windows usernames in paths are redacted. [Feedback collection details (Chinese)](https://github.com/BMingSY/isaac-lan/blob/main/docs/feedback.md)

For GitHub reports, include the game and extension versions, host or guest role, reproduction steps and enabled mods. If you have a feedback ID, include it so the author can find the logs. [Open an issue](https://github.com/BMingSY/isaac-lan/issues/new/choose)

## Contributing and license

To contribute, see the [contribution guide](https://github.com/BMingSY/isaac-lan/blob/main/CONTRIBUTING.md#english).

Do not sell this mod or any modified version of it. See the [project license](https://github.com/BMingSY/isaac-lan/blob/main/LICENSE).
