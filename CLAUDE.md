# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

This repository contains configuration scripts and utilities for the **dwm (Dynamic Window Manager)** window manager. It is not the dwm source code itself, but a collection of Bash scripts that enhance dwm with status bars, application launchers, wallpaper management, and system utilities. The scripts are designed for Arch Linux and rely on various X11 utilities.

## Project Structure

- `autostart.sh` – Main startup script that launches status bar, wallpaper, and background services.
- `dwm-status.sh` – Refreshes the dwm status bar (calls `dwm-status-tools.sh`).
- `dwm-status-tools.sh` – Toolkit of status‑bar functions (CPU, memory, battery, weather, etc.).
- `dwm-statuscmd.sh` – Handles click events on the status‑bar segments.
- `dwm-launcher.sh` – Unified rofi‑based launcher for terminals, applications, power menu, etc.
- `dwm-layoutmenu.sh` – Layout menu script.
- `configs/` – Default configuration files (quicklinks, wallpaper, key mappings).
- `tools/` – System utilities (brightness, volume, wallpaper, lock screen, monitor configuration).
- `utils/` – Helper scripts (weather, notifications, printing, monitoring).
- `rofi/` – Rofi configuration and scripts (launchers, power menu, applets, modules).
- `xorg.conf.d/` – Xorg configuration files for keyboard and touchpad.
- `_deprecated/` – Old proxy‑related scripts.

## Common Commands

**Start dwm with these scripts:**
Ensure `autostart.sh` is executed when dwm starts (typically from `~/.xinitrc` or a display manager). The script will launch the status bar, wallpaper, and all background services.

**Test the status bar:**

```bash
./dwm-status.sh               # Run the status‑bar refresh loop
./dwm-statuscmd.sh <number>   # Simulate a click on status‑bar segment <number>
```

**Launch the application menu:**

```bash
./dwm-launcher.sh terminal    # Open terminal launcher
./dwm-launcher.sh applications # Open application launcher
./dwm-launcher.sh powermenu   # Open power menu
```

**Use individual tools:**

```bash
./tools/brightness.sh up      # Increase screen brightness
./tools/volume.sh toggle      # Toggle audio mute
./tools/wallpaper.sh -r       # Reload wallpaper (supports image, video, web page)
./tools/keyboard.sh set delay 250  # Set keyboard repeat delay
```

**Module management (toggle picom, network, bluetooth, etc.):**

```bash
./rofi/scripts/module.sh      # Open the module toggle menu
```

**Quick links (browser bookmarks):**

```bash
./rofi/scripts/quicklinks.sh  # Open quick‑links menu
```

## Architecture

### Status Bar System

- **Refresh loop:** `dwm-status.sh` calls `dwm-status-tools.sh` every second and updates the bar via `xsetroot -name`.
- **Toolkit:** `dwm-status-tools.sh` contains modular functions that output colored, icon‑decorated segments (CPU, memory, disk, battery, weather, etc.).
- **Click events:** `dwm-statuscmd.sh` maps numeric click areas to actions (e.g., click on battery segment opens a power menu).

### Application Launcher

- `dwm-launcher.sh` is a front‑end that invokes different rofi themes and scripts based on the argument.
- Rofi themes are stored in `rofi/launchers/`, `rofi/powermenu/`, `rofi/applets/`.
- Supports terminal launcher, application launcher, power menu, MPD control, system modules, screenshot, screencast, quick links, and emoji picker.

### Wallpaper System

- `tools/wallpaper.sh` is a sophisticated controller that can set images, videos, or web pages as wallpapers.
- Uses `feh` for images, `xwinwrap` + `mpv` for videos, and `tabbed` + `surf` for web pages.
- Configuration in `configs/wallpaper_default.conf` and `configs/wallpaperKeyMap_default.conf`.

### Module System

- `rofi/scripts/module.sh` provides a toggle interface for system modules (picom, network, bluetooth, notifications, wallpaper).
- Each module can be enabled/disabled; the script updates the status bar accordingly.

### Autostart System

- `autostart.sh` is modular, with sections for desktop settings, application launch, and keyboard settings.
- Uses `launch()` and `launch_monitor()` functions to manage background processes and restart them if they crash.

## Configuration

- Configuration files are expected in `${XDG_CONFIG_HOME:-$HOME/.config}/dwm/`. The `configs/` directory contains default versions.
- Fonts must be installed system‑wide or in `~/.local/share/fonts/`. The scripts assume **JetBrains Mono Nerd Font** and **Iosevka Nerd Font** are available.
- Many scripts rely on standard Arch Linux packages (see the table in `README.md` for a full list of dependencies).
- The main `README.md` is written in Chinese; many script comments are also in Chinese. Key configuration parameters are often indicated with English variable names.

## Development Notes

- **Language:** Bash shell scripts with some AWK and sed.
- **Status bar formatting:** Uses Nerd Font icons and ANSI color codes.
- **Event handling:** Status‑bar clicks are mapped via `dwm-statuscmd.sh` using the numeric output of `dwm-status-tools.sh`.
- **Caching:** Temporary files are stored in `/tmp/dwm-status/` and `~/.cache/byt0723/wallpaper/`.
- **Patch management:** This repository does not contain dwm patches. To modify dwm itself, you need to patch and recompile the dwm source separately.
- **Documentation:** Additional documentation is available in `doc/proxy.md` (proxy setup) and `rofi/README.md` (rofi configuration).

## Important Dependencies (Partial List)

- **Core:** rofi, picom, dunst, xautolock, slock, fcitx5‑im
- **Monitoring:** acpi, alsa‑utils, light, networkmanager, mpc, mpd
- **Utilities:** libnotify, setxkbmap, xset, xrandr, feh, maim, ffmpeg
- **Fonts:** ttf‑jetbrains‑mono‑nerd, ttf‑iosevka‑nerd, Chinese fonts

Refer to `README.md` (written in Chinese) for a complete dependency table and installation guidance.
