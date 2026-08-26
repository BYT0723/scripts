# 脚本

> Dwm 下的一些 Shell 脚本,用于辅助 Dwm

## 字体

- rofi 中的字体配置为`JetBrains Mono Nerd Font`以及`Iosevka Nerd Font`,两个字体均可在 Arch 源中安装,`ttf-jetbrains-mono-nerd`和`ttf-iosevka-nerd`
- 中文字体: `noto-fonts-cjk` and `noto-fonts-cjk-fontconfig(aur)`
- 以及`rofi/fonts`中的字体,copy 到`~/.local/share/fonts/`中

## 依赖

### T1 — 系统自带 (coreutils/Xorg/base Arch)

`bash` `awk` `sed` `grep` `find` `sort` `cut` `tr` `date` `sleep` `pgrep` `pkill` `cat` `echo` `printf` `md5sum` `xset` `xsetroot` `xrdb` `systemctl` `bc` `curl`

### T2 — 必须安装 (缺失会导致脚本直接失败)

| 包名                   | 用途                              | 使用位置                                                                     |
| ---------------------- | --------------------------------- | ---------------------------------------------------------------------------- |
| `rofi`                 | 应用启动器 / dmenu                | dwm-launcher.sh / rofi/scripts/\* / powermenu                                |
| `kitty`                | 默认终端模拟器                    | dwm-launcher.sh / dwm-statuscmd.sh / wallpaper.sh (yazi 选择器)              |
| `dunst` `libnotify`    | 通知守护进程 / 接口               | 全部脚本 (system-notify)                                                     |
| `jq`                   | JSON 解析                         | dwm-status-tools.sh / weather.sh / screencast.sh / theme.sh / wallpaper.sh / sing-box.sh / media-scraping.sh / notification.sh / quicklinks-mode.sh |
| `acpi`                 | 电池状态                          | dwm-status-tools.sh / dwm-statuscmd.sh                                       |
| `alsa-utils`           | 音量控制 (amixer)                 | volume.sh / lock.sh / dwm-status-tools.sh                                    |
| `brightnessctl`        | 屏幕亮度                          | brightness.sh                                                                |
| `setxkbmap`            | 键盘布局                          | keyboard.sh / autostart.sh                                                   |
| `xdotool`              | X11 自动化                        | lock.sh / screenshot.sh / screencast.sh / utils/monitor.sh / dwm-launcher.sh |
| `xautolock`            | 定时锁屏守护                      | screen.sh                                                                    |
| `picom`                | 窗口合成器                        | autostart.sh                                                                 |
| `xsettingsd`           | XSETTINGS 广播 (GTK 主题/字体)    | autostart.sh / theme.sh (set_gtk_theme)                                      |
| `dconf`                | gsettings (portal color-scheme)   | theme.sh (Firefox content 亮暗跟随)                                          |
| `xwallpaper`           | 壁纸渲染 (图片/视频/网页)         | wallpaper-lib.sh / wallpaper-render.sh / autostart.sh                        |
| `flameshot`            | 截图                              | tools/screenshot.sh                                                          |
| `xclip`                | 剪贴板                            | tools/screenshot.sh / color-picker.sh / yt-dlp-wrapper.sh                    |
| `nsxiv`                | 截图预览 / 图片查看               | tools/screenshot.sh                                                          |
| `xcolor`               | 屏幕取色                          | tools/color-picker.sh / module.sh                                            |
| `ffmpeg` `ffprobe`     | 屏幕录制 / 视频处理               | tools/screencast.sh / yt-dlp.sh / wallpaper-lib.sh (视频旋转检测)            |
| `slop`                 | 区域选择                          | tools/screencast.sh                                                          |
| `mpv`                  | 视频壁纸旋转预览 / 随机播放       | wallpaper-lib.sh (preview_rotation) / random_file.sh                         |
| `yad` / `zenity`       | 表单对话框                        | utils/form.sh (quicklinks 表单录入, yad 优先)                                |
| `gettext` (`envsubst`) | 路径变量展开                      | wallpaper-lib.sh (expand_path)                                               |
| `file`                 | MIME 校验                         | quicklinks-mode.sh (favicon 下载校验)                                        |
| `xrandr`               | 多显示器布局                      | monitor-conf.sh / wallpaper.sh / screencast.sh / utils/monitor.sh            |

### T3 — AUR / GitHub (不在官方源)

| 包名           | 来源 | 使用位置              |
| -------------- | ---- | --------------------- |
| `i3lock-color` | AUR  | lock.sh (锁屏)        |
| `rofi-emoji`   | AUR  | rofi/scripts/emoji.sh |

### T4 — 可选 (缺失时有条件跳过)

`mpc`/`mpd` `networkmanager`/`nm-applet` `fcitx5-im` `lxsession`/`lxpolkit` `udiskie` `bluez`/`bluetoothctl` `newsboat` `yt-dlp` `yazi` `cal`/`ccal` `st` `easyeffects`(默认注释) `conky` `sing-box` `scrcpy`/`android-tools` `xprintidle`(lock.sh 有 fallback) `autorandr` `snixembed` `wireless-tools`(`iwgetid`, 状态栏 wifi 名称)

---

## 脚本列表

### 核心

| 脚本                  | 功能                       | 依赖                                            |
| --------------------- | -------------------------- | ----------------------------------------------- |
| `autostart.sh`        | DWM 启动入口               | picom / xsettingsd / dunst / xwallpaper / conky |
| `dwm-launcher.sh`     | 快捷键分发 → rofi 菜单     | rofi / kitty / utils/monitor.sh                 |
| `dwm-status.sh`       | 状态栏刷新器 (daemon+refresh) | (sources dwm-status-tools.sh)                |
| `dwm-status-tools.sh` | 状态栏数据源 + 守护进程    | acpi / alsa-utils / jq / mpc / curl             |
| `dwm-status-print.sh` | 状态栏各模块渲染函数       | (sourced by dwm-status-tools.sh)                |
| `dwm-statuscmd.sh`    | 状态栏点击事件处理         | libnotify / kitty / tools/\*                    |
| `dwm-layoutmenu.sh`   | DWM 布局选择器             | rofi / lib-module.sh                            |

### tools/

| 脚本                | 功能                               | 依赖                                                        |
| ------------------- | ---------------------------------- | ----------------------------------------------------------- |
| `lock.sh`           | i3lock-color 锁屏 + suspend 分发   | i3lock-color / xset / xdotool / amixer / mpc / xprintidle(可选) |
| `screen.sh`         | DPMS 自动启停守护 (有音频自动亮屏) | xautolock / xset / pw-dump 或 pactl / jq                    |
| `wallpaper.sh`      | 壁纸引擎 (随机/选择/daemon)        | xwallpaper / ffprobe / mpv(旋转预览) / yazi                  |
| `wallpaper-lib.sh`  | 壁纸配置/组管理/渲染接口           | xwallpaper / jq / ffprobe / envsubst                        |
| `wallpaper-render.sh` | xwallpaper 渲染层 (screen/monitor/group) | xwallpaper                                        |
| `screenshot.sh`     | 截图 (区域/全屏/窗口/定时)         | flameshot / xclip / nsxiv / xdotool                          |
| `screencast.sh`     | 屏幕录制 (含虚拟音频设备)          | ffmpeg / slop / pactl / jq / xdotool                         |
| `brightness.sh`     | 屏幕背光控制                       | brightnessctl                                                |
| `volume.sh`         | 音量控制                           | amixer                                                       |
| `keyboard.sh`       | 键盘布局 / 速率                    | setxkbmap / xset                                             |
| `monitor-conf.sh`   | 多显示器布局                       | xrandr                                                       |
| `touchpad.sh`       | 触控板开关                         | synclient (xf86-input-synaptics)                            |
| `calendar.sh`       | 公历/农历日历                      | cal / ccal / st                                              |
| `clock.sh`          | cron 闹钟通知                      | libnotify                                                    |
| `random_file.sh`    | mpv 随机播放 (含近期加权)          | mpv                                                          |
| `sddm.sh`           | SDDM 主题管理                      | sddm                                                         |
| `theme.sh`          | 亮/暗主题切换 + 日出日落自动切换   | xrdb / xsettingsd / gsettings / dunstctl / kitten / curl / jq |
| `yt-dlp.sh`         | yt-dlp 音视频下载 + opus 转码      | yt-dlp / ffmpeg / ffprobe                                   |
| `color-picker.sh`   | 屏幕取色 (复制到剪贴板)            | xcolor / xclip                                               |
| `clear-cache.sh`    | 清理 ~/.cache 过期文件             | find                                                         |

### utils/ (被其他脚本 source)

| 脚本         | 提供的函数                                                        |
| ------------ | ----------------------------------------------------------------- |
| `notify.sh`  | `system-notify()` — 统一通知接口                                  |
| `monitor.sh` | `get_monitor_info()` / `get_current_monitor()` / `is_portrait()`  |
| `weather.sh` | `ipinfo-openMeteo()` / `weather-forecast()` — 天气 API (WMO 映射/预报/告警) |
| `form.sh`    | `form_show()` — yad/zenity 通用表单 (quicklinks 录入)             |
| `url.sh`     | `is_url()` / `valid_url()` — URL 判断/校验                        |
| `string.sh`  | `trim_str()` — 字符串工具                                         |

> 死代码: `utils/print.sh` (number2icon), `utils/shell-lib.sh` (echo_note 等) 已无调用方。

### rofi/scripts/

| 脚本                | 功能                                   | 依赖                          |
| ------------------- | -------------------------------------- | ----------------------------- |
| `launcher_t1~t7`    | 应用启动器 (combi 模式; t1/t3 挂载 quicklinks) | rofi / quicklinks-mode.sh |
| `powermenu_t1~t6`   | 电源菜单 (关机/重启/锁屏/挂起/注销)    | rofi / tools/lock.sh          |
| `module.sh`         | 系统模块管理 (picom/网络/蓝牙/主题/壁纸/...) | rofi / nmcli / bluetoothctl / tools/* |
| `lib-module.sh`     | rofi 模块菜单框架 (parse/loop/confirm) | rofi / util.sh                |
| `util.sh`           | icon / 配置读写工具                    | jq                            |
| `mpd.sh`            | MPD 音乐控制器                         | mpd / mpc                     |
| `screenshot.sh`     | 截图菜单                               | tools/screenshot.sh           |
| `screencast.sh`     | 录屏菜单 (含录制中状态/静音开关)       | tools/screencast.sh           |
| `emoji.sh`          | emoji 选择器                           | rofi-emoji                    |
| `theme.sh`          | 主题控制菜单 (light/dark/auto/偏移量)  | tools/theme.sh                |
| `wallpaper.sh`      | 壁纸配置 UI (monitor/组/随机参数)      | tools/wallpaper-lib.sh        |
| `notification.sh`   | dunst 通知历史                         | dunst / jq                    |
| `sddm.sh`           | SDDM 主题管理 UI                       | tools/sddm.sh                 |
| `media-scraping.sh` | 媒体刮削 docker 服务启停               | docker / jq                   |
| `quicklinks-mode.sh`| 书签/搜索引擎 (rofi script mode)       | jq / curl / file / utils/form.sh / yad |
| `scrcpy.sh`         | Android 投屏 (有/无线连接)             | scrcpy / android-tools        |
| `sing-box.sh`       | 代理切换 (Clash API)                   | sing-box / curl / jq          |
| `yt-dlp-wrapper.sh` | yt-dlp 下载 UI (音频/视频/-F)          | yt-dlp / tools/yt-dlp.sh      |

### rofi/ (主题)

| 目录           | 说明                                          |
| -------------- | --------------------------------------------- |
| `launchers/`   | 启动器主题 (type-1~7, 各 style)               |
| `powermenu/`   | 电源菜单主题 (type-1~6)                       |
| `applets/`     | 模块菜单主题 (type-1~5 + shared)              |
| `colors/`      | 配色主题                                      |
| `config.rasi`  | 全局配置                                      |

---

> Tips
>
> - 壁纸渲染已统一迁移至 `xwallpaper`,图片/视频/网页分别映射 `--image`/`--video`/`--web`,不再依赖 feh/xwinwrap/surf/tabbed;视频旋转预览仍用 mpv (`preview_rotation`)。`xwallpaper --daemon` 由 autostart.sh 启动。
> - `i3lock-color` 需要配合 `archlinux-wallpaper` AUR 包提供锁屏壁纸源 (`/usr/share/backgrounds/archlinux/`)。
> - 截图已从 maim 迁移至 flameshot (`tools/screenshot.sh`),预览查看器为 nsxiv。

## Firefox hide tab button

```css
#TabsToolbar {
  #alltabs-button {
    display: none !important;
  }
}
```
