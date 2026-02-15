# dwm Configuration Scripts

This repository contains Bash scripts and utilities that enhance the **dwm (Dynamic Window Manager)** with status bars, application launchers, wallpaper management, and system utilities. It is **not** the dwm source code itself.

## Project Architecture

### Status Bar System

The status bar system consists of three interconnected components:

1. **`dwm-status.sh`** – Main refresh loop that calls `dwm-status-tools.sh` every second and updates the bar via `xsetroot -name`.
2. **`dwm-status-tools.sh`** – Modular toolkit containing functions that output colored, icon-decorated segments (CPU, memory, disk, battery, weather, etc.). Each function can be called independently.
3. **`dwm-statuscmd.sh`** – Event handler that maps numeric click areas to actions (e.g., clicking battery segment opens power menu).

**Key Concept:** Status bar segments are numbered (e.g., `\x01` through `\x0d`) and correspond to click handlers in `dwm-statuscmd.sh`.

### Application Launcher System

- **`dwm-launcher.sh`** is the front-end dispatcher that routes to different rofi scripts based on argument.
- Rofi themes are organized in `rofi/launchers/`, `rofi/powermenu/`, `rofi/applets/`.
- Scripts in `rofi/scripts/` use symbolic links (e.g., `launcher_t3` → `../launchers/type-3/launcher.sh`).

### Wallpaper System

- **`tools/wallpaper.sh`** is a sophisticated controller supporting images (via `feh`), videos (via `xwinwrap` + `mpv`), and web pages (via `tabbed` + `surf`).
- Manages process lifecycle: kills existing `xwinwrap` instances before starting new ones.
- Supports random wallpaper rotation with configurable duration and depth.

### Module System

- **`rofi/scripts/module.sh`** provides a toggle interface for system modules (picom, network, bluetooth, notifications, wallpaper).
- Uses `icon` helper functions to show module state in the UI.
- Each module can be enabled/disabled; the script updates the status bar accordingly.

### Autostart System

- **`autostart.sh`** orchestrates startup using two key functions:
  - `launch()` – Checks if process exists before starting (one-time launch).
  - `launch_monitor()` – Continuously monitors and restarts processes if they crash (auto-recovery loop).
- Organized into sections: `desktop_setting()`, `application_launch()`, `keyboard_setting()`.

## Configuration Management

**Critical Distinction:**
- **`configs/`** contains **example/default configuration files** only.
- **`~/.config/dwm/`** (or `${XDG_CONFIG_HOME}/dwm/`) contains the **actual runtime configuration**.
- To configure the system: copy files from `configs/` to `~/.config/dwm/` and edit them there.

Configuration files use simple key-value format:
```bash
# Example from wallpaper.conf
random = 0
random_type = image
random_image_dir = ~/Pictures
```

Scripts use `getConfig()` functions to read these files with fallback to defaults.

## Key Conventions

### Script Organization

- **Main scripts** are in the repository root (prefixed with `dwm-`).
- **Tools** for system control (brightness, volume, wallpaper, keyboard) are in `tools/`.
- **Utilities** for helper functions (weather, notifications, printing, monitoring) are in `utils/`.
- **Rofi scripts** for UI menus are in `rofi/scripts/`.

### Sourcing Pattern

Scripts use relative paths with `$(dirname $0)` to source dependencies:
```bash
source "$(dirname $0)/utils/notify.sh"
source "$(dirname $0)/../utils/notify.sh"  # From subdirectories
```

### Process Management

- **Check before launch:** `[ "$(pgrep "$1")" = "" ] && eval "$2"`
- **Kill by name:** `kill $(pgrep xwinwrap)` – always use exact process names
- **Monitor loop:** Continuously restart crashed processes in background with 60-second interval

### Notification System

All scripts use `libnotify` via `notify-send` for user notifications:
```bash
source "$(dirname $0)/../utils/notify.sh"
system-notify critical "Tool Not Found" "please install tool"
```

Stack tags prevent notification spam: `-h string:x-dunst-stack-tag:$msgTag`

### Status Bar Formatting

- Uses **Nerd Font icons** for visual elements
- **ANSI color codes** defined at top of `dwm-status-tools.sh` (`black`, `yellow`, `green`, `white`, `grey`, `blue`, `red`, `darkblue`)
- **Control characters** (e.g., `\x01`, `\x02`) map to click handlers
- **Pane structure:** `^b$color^$control_code$LEFT_RADIUS$content$RIGHT_RADIUS`

### Caching

- **Temporary files:** `/tmp/dwm-status/` for CPU usage, weather, network traffic, mail/rss counts
- **Persistent cache:** `~/.cache/byt0723/wallpaper/` for wallpaper state

### Dependency Checking

All tool scripts check for required commands before execution:
```bash
[ -z "$(command -v brightnessctl)" ] && system-notify critical "Tool Not Found" "..." && exit
```

### Rofi Script Pattern

Rofi scripts follow consistent structure:
1. Import theme configuration (type and style)
2. Define options array with dynamic state indicators via `icon` helper
3. Map options to IDs in associative array (`optId`)
4. Execute `rofi_cmd()` with standardized theme parameters
5. Handle selection with case statements

## Testing the System

**Test status bar:**
```bash
./dwm-status.sh               # Run refresh loop (Ctrl+C to stop)
./dwm-statuscmd.sh 1 1        # Simulate left-click on segment 1 (date)
```

**Test individual tools:**
```bash
./tools/brightness.sh up      # Increase brightness
./tools/volume.sh toggle      # Toggle mute
./tools/wallpaper.sh -n       # Next random wallpaper
```

**Test launchers:**
```bash
./dwm-launcher.sh terminal    # Open terminal launcher
./dwm-launcher.sh modules     # Open module toggle menu
```

## Important Notes

- **Language:** Bash scripts with AWK and sed for text processing
- **Platform:** Designed for Arch Linux; many scripts assume Arch-specific tools
- **Documentation:** README.md is in Chinese; script comments are mixed Chinese/English
- **Fonts:** Requires **JetBrains Mono Nerd Font** and **Iosevka Nerd Font** installed system-wide or in `~/.local/share/fonts/`
- **dwm patches:** This repository does not contain dwm source or patches. To modify dwm itself, patch and recompile dwm separately.
- **Custom tabbed:** Uses a modified version of `tabbed` for web page wallpapers (must be compiled from https://github.com/BYT0723/tabbed.git)

## Common Dependencies

**Core:** rofi, picom, dunst, xautolock, slock, fcitx5-im  
**Monitoring:** acpi, alsa-utils, light (or brightnessctl), networkmanager, mpc, mpd  
**Utilities:** libnotify, setxkbmap, xset, xrandr, feh, maim, ffmpeg, xwinwrap  
**Fonts:** ttf-jetbrains-mono-nerd, ttf-iosevka-nerd

See README.md table for complete dependency list per script.
