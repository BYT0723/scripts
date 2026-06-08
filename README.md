# 脚本

> Dwm 下的一些 Shell 脚本,用于辅助 Dwm

## 字体

- rofi 中的字体配置为`JetBrains Mono Nerd Font`以及`Iosevka Nerd Font`,两个字体均可在 Arch 源中安装,`ttf-jetbrains-mono-nerd`和`ttf-iosevka-nerd`
- 中文字体: `noto-fonts-cjk` and `noto-fonts-cjk-fontconfig(aur)`
- 以及`rofi/fonts`中的字体,copy 到`~/.local/share/fonts/`中

## 依赖

### T1 — 系统自带 (coreutils/Xorg/base Arch)

`bash` `awk` `sed` `grep` `find` `sort` `cut` `tr` `date` `sleep` `pgrep` `pkill` `cat` `echo` `printf` `md5sum` `xset` `xsetroot` `xprop` `xrdb` `systemctl` `bc` `curl`

### T2 — 必须安装 (缺失会导致脚本直接失败)

| 包名                | 用途                | 使用位置                                                    |
| ------------------- | ------------------- | ----------------------------------------------------------- |
| `rofi`              | 应用启动器 / dmenu  | dwm-launcher.sh / rofi/scripts/\* / powermenu               |
| `kitty`             | 默认终端模拟器      | dwm-launcher.sh / dwm-statuscmd.sh / wallpaper.sh           |
| `dunst` `libnotify` | 通知守护进程 / 接口 | 全部脚本 (system-notify)                                    |
| `jq`                | JSON 解析           | dwm-status-tools.sh / weather.sh / screencast.sh / clash.sh |
| `acpi`              | 电池状态            | dwm-status-tools.sh / dwm-statuscmd.sh                      |
| `alsa-utils`        | 音量控制 (amixer)   | volume.sh / lock.sh / dwm-status-tools.sh                   |
| `brightnessctl`     | 屏幕亮度            | brightness.sh                                               |
| `setxkbmap`         | 键盘布局            | keyboard.sh / autostart.sh                                  |
| `xdotool`           | X11 自动化          | lock.sh / screenshot.sh / utils/monitor.sh                  |
| `xautolock`         | 定时锁屏守护        | screen.sh                                                   |
| `xprintidle`        | 空闲检测            | lock.sh (\_screen_lock_loop)                                |
| `picom`             | 窗口合成器          | autostart.sh                                                |
| `maim` `xclip`      | 截图                | screenshot.sh                                               |
| `slop`              | 区域选择            | screencast.sh                                               |
| `ffmpeg`            | 屏幕录制 / 音频转码 | screencast.sh / opus-webm.sh                                |
| `feh`               | 图片查看 / 壁纸设置 | wallpaper.sh / screenshot.sh                                |
| `mpv`               | 视频壁纸 / 随机播放 | wallpaper.sh / random_file.sh                               |
| `xrandr`            | 多显示器布局        | monitor-conf.sh / wallpaper.sh / screencast.sh              |

### T3 — AUR / GitHub (不在官方源)

| 包名           | 来源                                                    | 使用位置                     |
| -------------- | ------------------------------------------------------- | ---------------------------- |
| `i3lock-color` | AUR                                                     | lock.sh (锁屏)               |
| `xwinwrap`     | [BYT0723/xwinwrap](https://github.com/BYT0723/xwinwrap) | wallpaper.sh (视频/网页壁纸) |

### T4 — 可选 (缺失时有条件跳过)

`mpc`/`mpd` `networkmanager`/`nm-applet` `fcitx5-im` `lxsession`/`lxpolkit` `udiskie` `bluez`/`bluetoothctl` `newsboat` `yt-dlp` `yazi` `cal`/`ccal` `surf`/`tabbed` `easyeffects` `conky` `sing-box`

---

## 脚本列表

### 核心

| 脚本                  | 功能                    | 依赖                                           |
| --------------------- | ----------------------- | ---------------------------------------------- |
| `autostart.sh`        | DWM 启动入口            | picom / xautolock / i3lock / setxkbmap / dunst |
| `dwm-launcher.sh`     | 快捷键分发 → rofi 菜单  | rofi / kitty                                   |
| `dwm-status.sh`       | 状态栏刷新器            | (sources dwm-status-tools.sh)                  |
| `dwm-status-tools.sh` | 状态栏数据源 + 守护进程 | acpi / alsa-utils / jq / networkmanager / mpc  |
| `dwm-statuscmd.sh`    | 状态栏点击事件处理      | libnotify / kitty                              |
| `dwm-layoutmenu.sh`   | DWM 布局选择器          | rofi                                           |
| `colorscheme.sh`      | 亮色/暗色主题切换       | xrdb / dunstctl / libnotify                    |
| `keyboard.sh`         | 键盘布局切换            | setxkbmap / xset                               |
| `monitor-conf.sh`     | 多显示器布局            | xrandr                                         |

### tools/

| 脚本                | 功能                             | 依赖                                                |
| ------------------- | -------------------------------- | --------------------------------------------------- |
| `lock.sh`           | i3lock-color 锁屏 + suspend 分发 | i3lock / xset / xdotool / xprintidle / amixer / mpc |
| `screen.sh`         | DPMS 自动启停守护                | xautolock / xset / pactl / jq                       |
| `wallpaper.sh`      | 壁纸引擎 (图片/视频/网页)        | feh / mpv / xwinwrap / surf / tabbed                |
| `brightness.sh`     | 屏幕背光控制                     | brightnessctl                                       |
| `volume.sh`         | 音量控制                         | amixer                                              |
| `keyboard.sh`       | 键盘布局 / 速率                  | setxkbmap / xset                                    |
| `touchpad.sh`       | 触控板开关                       | synclient (xf86-input-synaptics)                    |
| `calendar.sh`       | 公历/农历日历                    | cal / ccal                                          |
| `clock.sh`          | cron 闹钟通知                    | libnotify                                           |
| `random_file.sh`    | mpv 随机播放目录内视频           | mpv                                                 |
| `sddm.sh`           | SDDM 主题管理                    | sddm                                                |
| `update-ruleset.sh` | sing-box geo 规则集更新          | curl / wget                                         |
| `youtube/yt.sh`     | yt-dlp 音频下载                  | yt-dlp / ffmpeg                                     |

### utils/ (被其他脚本 source)

| 脚本         | 提供的函数                                                      |
| ------------ | --------------------------------------------------------------- |
| `notify.sh`  | `system-notify()` — 统一通知接口                                |
| `monitor.sh` | `get_monitor_info()` / `get_current_monitor()` — 显示器几何信息 |
| `weather.sh` | `ipinfo-openMeteo()` / `weather-forecast()` — 天气 API          |

### rofi/scripts/

| 脚本              | 功能                                   | 依赖                          |
| ----------------- | -------------------------------------- | ----------------------------- |
| `mpd.sh`          | MPD 音乐控制器                         | mpd / mpc                     |
| `module.sh`       | 系统模块管理 (picom/net/bluetooth/...) | networkmanager / bluez / rofi |
| `screenshot.sh`   | 截图工具 (全屏/区域/窗口)              | maim / xclip / feh / xdotool  |
| `screencast.sh`   | 屏幕录制                               | ffmpeg / slop / ffprobe       |
| `quicklinks.sh`   | URL 书签启动器                         | firefox / chromium            |
| `emoji.sh`        | emoji 选择器                           | rofi-emoji                    |
| `wallpaper.sh`    | 壁纸配置 UI                            | rofi                          |
| `notification.sh` | dunst 通知历史                         | dunst / jq                    |
| `setting.sh`      | 设置管理器 (状态栏/sddm)               | kitty / rofi                  |
| `system-tools.sh` | 日历启动器                             | rofi                          |
| `clash.sh`        | 代理切换                               | sing-box / curl / jq          |
| `common_list.sh`  | 通用 rofi dmenu 子启动器               | rofi                          |

### rofi/powermenu/

| 脚本                    | 功能                                | 依赖                     |
| ----------------------- | ----------------------------------- | ------------------------ |
| `type-1~6/powermenu.sh` | 电源菜单 (关机/重启/锁屏/挂起/注销) | rofi / (sources lock.sh) |

---

> Tips
>
> - `tabbed` 为本人修改过的，可进行 xmbed 嵌入，若直接使用 AUR 中的 tabbed，在使用 web page 可能出现不可预估的问题；
>   本包需要自行编译，将仓库 clone 到本地，执行`sudo make clean install`即可。
> - `i3lock-color` 需要配合 `archlinux-wallpaper` AUR 包提供锁屏壁纸源 (`/usr/share/backgrounds/archlinux/`)。

## Firefox hide tab button

```css
#TabsToolbar {
  #alltabs-button {
    display: none !important;
  }
}
```
