# .dwm — DWM 辅助脚本集

> DWM 平铺桌面的一套 Shell 脚本：状态栏、rofi 启动器/电源/模块菜单、壁纸引擎（xwallpaper）、亮暗主题自动切换、锁屏/DPMS、截图录屏、代理/音乐/下载等日常工具。

仓库位置约定为 `~/.dwm`（脚本内多处用 `$(dirname "$0")` 相对定位，`tests/*.sh` 默认 `SCRIPT="$HOME/.dwm/..."`）。详细 source 依赖、函数调用链见 [AGENTS.md](./AGENTS.md)，改脚本后须同步更新它。

## Quick Start

1. 克隆到固定位置：
   ```bash
   git clone <repo> ~/.dwm
   ```
2. 安装字体：见下方 §字体（Nerd Font + 中文 + `rofi/fonts/` 自带字体）。
3. 安装依赖（见下方 §依赖，至少先装 T2）：
   ```bash
   sudo pacman -S rofi kitty dunst libnotify jq acpi alsa-utils brightnessctl ddcutil \
     xautolock picom xsettingsd xwallpaper flameshot xclip nsxiv xcolor \
     ffmpeg slop mpv yad file xrandr autorandr wmctrl xdotool
   yay -S i3lock-color rofi-emoji   # AUR
   ```
4. 接入 DWM 启动（`autostart.sh` 即入口，负责 picom/dunst/xsettingsd/壁纸/状态栏/主题 daemon）：
   - 在 `~/.xinitrc` / dwm 启动处加 `bash ~/.dwm/autostart.sh &`，或按需 source 其中片段。
   - 主题自动切换由 `tools/theme.sh auto` daemon 负责（`auto=false` 时自动退出）。
5. 验证：`bash ~/.dwm/dwm-status.sh &` 后状态栏应出现；`bash ~/.dwm/dwm-launcher.sh apps` 应弹出 rofi。

## Commands

| 命令 | 说明 |
| ---- | ---- |
| `bash autostart.sh` | DWM 启动入口（合成器/通知/XSETTINGS/壁纸/状态栏/DPMS/主题 daemon） |
| `bash dwm-launcher.sh {apps\|powermenu\|modules\|...}` | 快捷键分发 → rofi 菜单（横/竖屏自动选 powermenu type） |
| `bash dwm-status.sh [reboot\|reboot-daemon\|reboot-refresh]` | 状态栏 daemon + 刷新循环（`xsetroot -name`） |
| `bash dwm-statuscmd.sh` | 状态栏点击事件分发（音量/亮度/日历/mpd/...） |
| `bash tools/theme.sh {apply light\|dark \| auto [on\|off] \| check}` | 主题切换；`auto` 为日出日落 daemon（60s 轮询，挂起/锁屏安全） |
| `bash tools/wallpaper.sh -m <monitor\|组> {next\|select}`；`-r`；`--theme <mode>` | 壁纸：下一张/选择；daemon 轮换；跟随主题色调切换 |
| `bash tools/lock.sh {lock\|suspend}` | 锁屏（i3lock）/挂起；锁屏期间暂停音乐、静音、STOP `xwallpaperd` 防 DPMS 回弹 |
| `source tools/monitor-brightness.sh`（`read_brightness`/`set_brightness`） | 单屏亮度：eDP 走 `brightnessctl`，外接屏走 `ddcutil setvcp 10`（DP aux 总线回退 + bus 文件缓存） |
| `python3 tools/wallpaper-classify.py [--move] <dir>` | 壁纸 light/dark 初筛（B 规则暗像素占比；`--move` 按 verdict 搬进 `light/`/`dark/`） |
| `bash tests/<name>_test.sh` | 回归测试（见 §测试，共 10 个，全部零外部显示依赖，mock xrandr/ddcutil） |

常用 rofi 入口（`rofi/scripts/` 均为 `module_loop` 注册表菜单，`key|icon|label|status` 四列，见 AGENTS.md §Rofi 模块注册表规范）：`module.sh`（系统总控）、`theme.sh`（主题/亮度/过渡锚点）、`wallpaper.sh`（壁纸/组/随机参数）、`quicklinks-mode.sh`（书签+`@引擎`搜索）、`mpd.sh`（音乐+封面）、`yt-dlp-wrapper.sh`（下载）、`screenshot.sh` / `screencast.sh` / `sing-box.sh` / `scrcpy.sh` / `sddm.sh` / `media-scraping.sh` / `notification.sh` / `emoji.sh`。

## Architecture

```
DWM 启动 → autostart.sh ─┬─ picom / dunst / xsettingsd / snixembed / lxpolkit / batsignal
                         ├─ nm-applet / pasystray / fcitx5 / udiskie
                         ├─ screen.sh (DPMS 守护, parec 录默认输出判响度, 有声不熄屏)
                         ├─ theme.sh auto (日出日落 daemon: 配色二值翻转 + 亮度渐变插值)
                         ├─ wallpaper.sh -r (xwallpaperd 常驻 + bash 随机轮换 daemon)
                         ├─ dwm-status.sh (daemon 采集 + refresh 经 xsetroot -name 推状态栏)
                         └─ keyboard.sh / conky / autorandr --change
```

- **状态栏**：`dwm-status.sh → dwm-status-tools.sh → dwm-status-print.sh + utils/{weather,notify}.sh`，daemon（cpu/流量/天气/邮件/rss/mpd）+ 1s refresh；点击经 `dwm-statuscmd.sh` 分发到 `tools/*`。
- **rofi**：`dwm-launcher.sh`（`is_portrait()` 选横/竖布局）→ `launchers/type-*` / `powermenu/type-*` / `module.sh` 子菜单；`quicklinks-mode.sh` 为 rofi script mode（`ROFI_RETV` 分派，favicon 后台分片并发缓存）。
- **主题**：`tools/theme.sh auto` 60s 轮询（短睡而非一次睡到切换点，挂起唤醒 ≤60s 纠正；i3lock 期间阻塞）。翻转只切配色并后台 hook `wallpaper.sh --theme` 跟随换壁纸；亮度由每轮 `apply_transition_brightness()` 按 `dawn/dusk_minutes + transition_anchor(after/center/before)` 插值。`set_gtk_theme()` 走 GTK 主题名 + gsettings portal 双通道（Firefox 亮暗靠 portal，见 AGENTS.md 已知问题）。
- **壁纸**：渲染层统一 `xwallpaper`（client+daemon IPC，`xwallpaperd` 常驻；图片/视频/网页 → `--image/--video/--web`，`-g --name` 窗口）。状态按 name 持久化（monitor 用 xrandr 名、组用 `grp_<组名>`、全屏用 `Screen`；`--state` 查询，`clear --keep + restore` 做互斥回退），脚本侧不再存 latest 文件。同名 set 即 reload，只清互斥窗口不清自身。
- **锁屏/DPMS**：`lock.sh`（`_lock_before/_lock/_screen_lock_loop/_lock_after`）+ `screen.sh`（xautolock LOCKER）；视频壁纸持续 present 会触发 amdgpu 驱动 unblank，需 `STOP xwallpaperd` 双保险（X 层 `xset q` 标志 stale，不可信）。

## 字体

- rofi 中的字体配置为 `JetBrains Mono Nerd Font` 以及 `Iosevka Nerd Font`，两个字体均可在 Arch 源中安装：`ttf-jetbrains-mono-nerd` 和 `ttf-iosevka-nerd`
- 中文字体：`noto-fonts-cjk`（+ AUR 的 `noto-fonts-cjk-fontconfig` 可选）
- 以及 `rofi/fonts` 中的字体，copy 到 `~/.local/share/fonts/` 中

## 依赖

### T1 — 系统自带 (coreutils/Xorg/base Arch)

`bash` `awk` `sed` `grep` `find` `sort` `cut` `tr` `date` `sleep` `pgrep` `pkill` `cat` `echo` `printf` `md5sum` `xset` `xsetroot` `xrdb` `systemctl` `bc` `curl`

### T2 — 必须安装 (缺失会导致脚本直接失败)

| 包名 | 用途 | 使用位置 |
| ---- | ---- | -------- |
| `rofi` | 应用启动器 / dmenu | dwm-launcher.sh / rofi/scripts/* / powermenu |
| `kitty` | 默认终端模拟器 | dwm-launcher.sh / dwm-statuscmd.sh / wallpaper.sh (yazi 选择器) |
| `dunst` `libnotify` | 通知守护进程 / 接口 | 全部脚本 (system-notify) |
| `jq` | JSON 解析 | dwm-status-tools.sh / weather.sh / screencast.sh / theme.sh / wallpaper.sh / sing-box.sh / media-scraping.sh / notification.sh / quicklinks-mode.sh |
| `acpi` | 电池状态 | dwm-status-tools.sh / dwm-statuscmd.sh |
| `alsa-utils` | 音量控制 (amixer) | volume.sh / lock.sh / dwm-status-tools.sh |
| `brightnessctl` | 笔记本内屏背光 (eDP) | brightness.sh / monitor-brightness.sh / theme.sh |
| `ddcutil` | 外接显示器 DDC 亮度 (`setvcp 10`) | monitor-brightness.sh / theme.sh（过渡插值每轮调用） |
| `setxkbmap` | 键盘布局 | keyboard.sh / autostart.sh |
| `xdotool` | X11 自动化 | lock.sh / screenshot.sh / screencast.sh / utils/monitor.sh / dwm-launcher.sh |
| `wmctrl` | 窗口计数 | rofi/scripts/windows-selector.sh |
| `xautolock` | 定时锁屏守护 | screen.sh |
| `picom` | 窗口合成器 | autostart.sh |
| `xsettingsd` | XSETTINGS 广播 (GTK 主题/字体) | autostart.sh / theme.sh (set_gtk_theme) |
| `dconf` | gsettings (portal color-scheme) | theme.sh (Firefox content 亮暗跟随) |
| `xwallpaper` | 壁纸渲染 (图片/视频/网页, client+daemon IPC) | wallpaper-lib.sh / wallpaper-render.sh / autostart.sh |
| `flameshot` | 截图 | tools/screenshot.sh |
| `xclip` | 剪贴板 | tools/screenshot.sh / color-picker.sh / yt-dlp-wrapper.sh |
| `nsxiv` | 截图预览 / 图片查看 | tools/screenshot.sh |
| `xcolor` | 屏幕取色 | tools/color-picker.sh / module.sh |
| `ffmpeg` `ffprobe` | 屏幕录制 / 视频处理 / 壁纸旋转检测 | tools/screencast.sh / yt-dlp.sh / wallpaper-lib.sh |
| `slop` | 区域选择 | tools/screencast.sh |
| `mpv` | 视频壁纸旋转预览 / 随机播放 | wallpaper-lib.sh (preview_rotation) / random_file.sh |
| `yad` / `zenity` | 表单对话框 | utils/form.sh (quicklinks 表单录入, yad 优先)；主题亮度滑块（FIFO+后台 pid 实时预览，DDC 防积压） |
| `gettext` (`envsubst`) | 路径变量展开 | wallpaper-lib.sh (expand_path) |
| `file` | MIME 校验 | quicklinks-mode.sh (favicon 下载校验) / mpd.sh（封面校验） |
| `xrandr` | 多显示器布局 | monitor-conf.sh / wallpaper.sh / screencast.sh / utils/monitor.sh |

### T3 — AUR / GitHub (不在官方源)

| 包名 | 来源 | 使用位置 |
| ---- | ---- | -------- |
| `i3lock-color` | AUR | lock.sh (锁屏) |
| `rofi-emoji` | AUR | rofi/scripts/emoji.sh |

### T4 — 可选 (缺失时有条件跳过)

`mpc`/`mpd` `networkmanager`/`nm-applet` `fcitx5-im` `lxsession`/`lxpolkit` `udiskie` `bluez`/`bluetoothctl` `newsboat` `yt-dlp` `yazi` `cal`/`ccal` `st` `easyeffects`(默认注释) `conky` `sing-box` `scrcpy`/`android-tools` `xprintidle`(lock.sh 有 fallback) `autorandr` `snixembed` `wireless-tools`(`iwgetid`, 状态栏 wifi 名称) `python3`+`PIL`(wallpaper-classify.py)

---

## 脚本列表

### 核心

| 脚本 | 功能 | 依赖 |
| ---- | ---- | ---- |
| `autostart.sh` | DWM 启动入口 | picom / xsettingsd / dunst / xwallpaper / conky |
| `dwm-launcher.sh` | 快捷键分发 → rofi 菜单 | rofi / kitty / utils/monitor.sh |
| `dwm-status.sh` | 状态栏刷新器 (daemon+refresh) | (sources dwm-status-tools.sh) |
| `dwm-status-tools.sh` | 状态栏数据源 + 守护进程 | acpi / alsa-utils / jq / mpc / curl |
| `dwm-status-print.sh` | 状态栏各模块渲染函数 | (sourced by dwm-status-tools.sh) |
| `dwm-statuscmd.sh` | 状态栏点击事件处理 | libnotify / kitty / tools/* |
| `dwm-layoutmenu.sh` | DWM 布局选择器 | rofi / lib-module.sh |

### tools/

| 脚本 | 功能 | 依赖 |
| ---- | ---- | ---- |
| `lock.sh` | i3lock-color 锁屏 + suspend 分发 | i3lock-color / xset / xdotool / amixer / mpc / xprintidle(可选) |
| `screen.sh` | DPMS 自动启停守护 (有音频自动亮屏) | xautolock / xset / parec / ffmpeg / pactl |
| `wallpaper.sh` | 壁纸引擎 (随机/选择/daemon/跟随主题) | xwallpaper / ffprobe / mpv(旋转预览) / yazi |
| `wallpaper-lib.sh` | 壁纸配置/组管理/渲染接口 | xwallpaper / jq / ffprobe / envsubst |
| `wallpaper-render.sh` | xwallpaper 渲染层 (screen/monitor/group) | xwallpaper |
| `wallpaper-classify.py` | 壁纸 light/dark 初筛（`--move` 自动归档） | python3+PIL / ffmpeg+ffprobe(视频缩略图) |
| `monitor-brightness.sh` | 单屏亮度读写（eDP=brightnessctl，外接屏=ddcutil；DP aux 回退+bus 文件缓存） | brightnessctl / ddcutil / xrandr |
| `screenshot.sh` | 截图 (区域/全屏/窗口/定时) | flameshot / xclip / nsxiv / xdotool |
| `screencast.sh` | 屏幕录制 (含虚拟音频设备) | ffmpeg / slop / pactl / jq / xdotool |
| `brightness.sh` | 屏幕背光控制 | brightnessctl（经 monitor-brightness.sh 分发） |
| `volume.sh` | 音量控制 | amixer |
| `keyboard.sh` | 键盘布局 / 速率 | setxkbmap / xset |
| `monitor-conf.sh` | 多显示器布局 | xrandr |
| `touchpad.sh` | 触控板开关 | synclient (xf86-input-synaptics) |
| `calendar.sh` | 公历/农历日历 | cal / ccal / st |
| `clock.sh` | cron 闹钟通知 | libnotify |
| `random_file.sh` | mpv 随机播放 (含近期加权) | mpv |
| `sddm.sh` | SDDM 主题管理 | sddm |
| `theme.sh` | 亮/暗主题切换 + 日出日落自动切换（含亮度渐变） | xrdb / xsettingsd / gsettings / dunstctl / curl / jq / monitor-brightness.sh |
| `yt-dlp.sh` | yt-dlp 音视频下载 + opus 转码 | yt-dlp / ffmpeg / ffprobe |
| `color-picker.sh` | 屏幕取色 (复制到剪贴板) | xcolor / xclip |
| `clear-cache.sh` | 清理 ~/.cache 过期文件 | find |

### utils/ (被其他脚本 source)

| 脚本 | 提供的函数 |
| ---- | ---------- |
| `notify.sh` | `system-notify()` — 统一通知接口 |
| `monitor.sh` | `get_monitor_info()` / `get_current_monitor()` / `is_portrait()` |
| `weather.sh` | `ipinfo-openMeteo()` / `weather-forecast()` — 天气 API (WMO 映射/预报/告警) |
| `form.sh` | `form_show()` — yad/zenity 通用表单 (quicklinks 录入) |
| `url.sh` | `is_url()` / `valid_url()` — URL 判断/校验 |
| `string.sh` | `trim_str()` — 字符串工具 |

> 死代码: `utils/print.sh` (number2icon), `utils/shell-lib.sh` (echo_note 等) 已无调用方。

### rofi/scripts/

| 脚本 | 功能 | 依赖 |
| ---- | ---- | ---- |
| `launcher_t1~t7` | 应用启动器 (combi 模式; t1/t3 挂载 quicklinks) | rofi / quicklinks-mode.sh |
| `powermenu_t1~t6` | 电源菜单 (关机/重启/锁屏/挂起/注销) | rofi / tools/lock.sh |
| `module.sh` | 系统模块管理 (picom/网络/蓝牙/主题/壁纸/...) | rofi / nmcli / bluetoothctl / tools/* |
| `lib-module.sh` | rofi 模块菜单框架 (parse/loop/confirm) | rofi / util.sh |
| `util.sh` | icon / 配置读写工具 | jq |
| `mpd.sh` | MPD 音乐控制器（含 readpicture 封面缓存复用） | mpd / mpc |
| `screenshot.sh` | 截图菜单 | tools/screenshot.sh |
| `screencast.sh` | 录屏菜单 (含录制中状态/静音开关) | tools/screencast.sh |
| `emoji.sh` | emoji 选择器 | rofi-emoji |
| `theme.sh` | 主题控制菜单 (light/dark/auto/偏移量/亮度滑块/过渡锚点) | tools/theme.sh |
| `wallpaper.sh` | 壁纸配置 UI (monitor/组/随机参数/深色目录) | tools/wallpaper-lib.sh |
| `notification.sh` | dunst 通知历史 | dunst / jq |
| `sddm.sh` | SDDM 主题管理 UI | tools/sddm.sh |
| `media-scraping.sh` | 媒体刮削 docker 服务启停 | docker / jq |
| `quicklinks-mode.sh` | 书签/搜索引擎 (rofi script mode) | jq / curl / file / utils/form.sh / yad |
| `scrcpy.sh` | Android 投屏 (有/无线连接) | scrcpy / android-tools |
| `sing-box.sh` | 代理切换 (Clash API) | sing-box / curl / jq |
| `yt-dlp-wrapper.sh` | yt-dlp 下载 UI (音频/视频/-F) | yt-dlp / tools/yt-dlp.sh |

### rofi/ (主题)

| 目录 | 说明 |
| ---- | ---- |
| `launchers/` | 启动器主题 (type-1~7, 各 style) |
| `powermenu/` | 电源菜单主题 (type-1~6) |
| `applets/` | 模块菜单主题 (type-1~5 + shared) |
| `colors/` | 配色主题 |
| `config.rasi` | 全局配置 |

---

## 配置文件

- `~/.config/dwm/quicklinks.json` — 书签 `links[]`（`id`/`name`/`url`，icon 字段已废弃）；`searcher[]`（`{name, url}`，name 唯一键，`{key}` 占位搜索词，可省略→追加末尾；默认 `searcher[0]`，`@<name>` 指定引擎）
- `~/.config/dwm/wallpaper.json` — `monitors`（按屏/组名键）+ `groups`（成员名单 + enabled）；可选 `video-render{volume, fps}`（`volume>0` 传 `--volume`，`0`/缺省 `--mute`，`fps>0` 传 `--fps`）；`random_image_dir[_dark]` / `random_video_dir[_dark]`（dark 空 fallback light）
- `~/.config/dwm/theme.json` — `auto{enabled, sun_rise/set_offset, dawn/dusk_minutes(默认60, 0=关闭渐变), transition_anchor(after/center/before)}`；`cursor{theme,size}`；`dpi`；`light/dark.colorscheme`（引用 `~/.config/dwm/colorschemes/`）；`brightness.<monitor>`（per-monitor 端点亮度）
- `~/.xsettingsd` — `set_gtk_theme()` 维护 `Net/ThemeName` 行并 `HUP xsettingsd` 广播
- `~/.local/state/dwm/current-theme`、`cache/sun-times`（日出日落缓存）、`~/.local/state/xwallpaper/state`（壁纸持久化，`keep` 区分当前/last）

## 测试

```bash
bash tests/theme_test.sh                        # auto daemon：挂起纠正 / 锁屏阻塞 / 缓存缺失短重试
bash tests/theme-brightness_test.sh             # 亮度插值纯函数 + apply_transition_brightness 集成
bash tests/monitor-brightness_test.sh           # DDC bus 解析（含 DP Invalid 回退）+ DDC 滑块防积压
bash tests/rofi-theme-monitor-brightness_test.sh # yad 滑块 FIFO：OK 保存硬件实测值 / 取消恢复
bash tests/mpd-cover_test.sh                    # readpicture 分块拉取（-q0 + skip_bytes, 4.1s→~50ms）
bash tests/quicklinks-mode_test.sh
bash tests/wallpaper-render_test.sh
bash tests/wallpaper-theme_test.sh
bash tests/lib-module_test.sh
bash tests/autostart_test.sh
```

测试统一 mock `xrandr/brightnessctl/ddcutil/date/sleep/pgrep` 等外部命令（无显示环境下真 `xrandr` 可能枚举幽灵 monitor 导致 hang），`THEME_LOCK` 指向临时路径防与 live daemon 争 flock 锁。详见 AGENTS.md §已知问题。

> Tips
>
> - 壁纸渲染已统一迁移至 `xwallpaper`，图片/视频/网页分别映射 `--image`/`--video`/`--web`，不再依赖 feh/xwinwrap/surf/tabbed；视频旋转预览仍用 mpv (`preview_rotation`)。`xwallpaperd` 常驻由 `wallpaper.sh -r` 启动。
> - `i3lock-color` 需要配合 `archlinux-wallpaper` AUR 包提供锁屏壁纸源 (`/usr/share/backgrounds/archlinux/`)。
> - 截图已从 maim 迁移至 flameshot (`tools/screenshot.sh`)，预览查看器为 nsxiv。
> - rofi script mode 多属性必须用 `\x1f` 连接（仅行尾一个 `\0`），第二个 `\0` 会截断 `ROFI_INFO`。
> - 锁屏 standby 后外屏亮起：视频壁纸持续 present 触发 amdgpu unblank，`lock.sh` 已 `STOP xwallpaperd`，勿改回仅匹配 `xwallpaper`。

## Firefox hide tab button

```css
#TabsToolbar {
  #alltabs-button {
    display: none !important;
  }
}
```
