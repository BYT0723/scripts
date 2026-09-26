#!/usr/bin/env bash

WORK_DIR=$(dirname "$(dirname "${BASH_SOURCE[0]}")")
THEME_CONF="$HOME/.config/dwm/theme.json"

source "$WORK_DIR/utils/notify.sh"
source "$WORK_DIR/tools/monitor-brightness.sh"

# ---------- helpers ----------

get_theme_config() {
    local mode="$1" key="$2"
    jq -r --arg mode "$mode" --arg key "$key" \
        '.[$mode] | getpath($key | split("."))? // empty' "$THEME_CONF"
}

_ensure_config_line() {
    local file="$1" search="$2" replacement="$3"
    if grep -q "$search" "$file" 2>/dev/null; then
        sed -i "s|$search|$replacement|" "$file"
    else
        echo "$replacement" >>"$file"
    fi
}

# ---------- queries ----------

get_current_theme() { cat "$HOME/.local/state/dwm/current-theme" 2>/dev/null; }

get_bg_fg_colors() {
    xrdb -query | awk -F': *' '
    {
      gsub(/^[ \t]+|[ \t]+$/, "", $2)
      map[$1] = $2
    }
    END {
      print map["dwm.col_black"], map["dwm.col_white"]
    }
  '
}

# ---------- setters ----------
set_monitor_brightness() {
    local mode="$1"
    [ -z "$mode" ] && return

    local brightness
    while read -r monitor; do
        brightness=$(get_theme_config "$mode" "brightness.$monitor")
        [[ $brightness =~ ^[0-9]+$ ]] || brightness=50
        ((brightness <= 100)) || brightness=50
        set_brightness "$monitor" "$brightness"
    done < <(xrandr --listactivemonitors 2>/dev/null | awk 'NR>1 {print $NF}')
}

set_dwm_theme() {
    local mode="$1"
    [ -z "$mode" ] && return

    local file="$HOME/.Xresources"
    local cs_dir="$HOME/.config/dwm/colorschemes"
    local scheme

    scheme=$(jq -r ".[\"$mode\"].colorscheme // empty" "$THEME_CONF")

    sed -i '/^dwm\.col_/d' "$file"
    [ -n "$scheme" ] && [ -f "$cs_dir/$scheme.json" ] &&
        jq -r 'to_entries[] | "dwm.col_\(.key): \(.value)"' "$cs_dir/$scheme.json" >>"$file"

    mkdir -p "$HOME/.local/state/dwm"
    echo "$mode" >"$HOME/.local/state/dwm/current-theme"

    local cursor_theme cursor_size dpi
    cursor_theme=$(jq -r '.cursor.theme // empty' "$THEME_CONF")
    cursor_size=$(jq -r '.cursor.size // empty' "$THEME_CONF")
    dpi=$(jq -r '.dpi // empty' "$THEME_CONF")
    [ -n "$cursor_theme" ] && _ensure_config_line "$file" "^Xcursor.theme:.*" "Xcursor.theme: $cursor_theme"
    [ -n "$cursor_size" ] && _ensure_config_line "$file" "^Xcursor.size:.*" "Xcursor.size: $cursor_size"
    [ -n "$dpi" ] && _ensure_config_line "$file" "^Xft.dpi:.*" "Xft.dpi: $dpi"
}

set_rofi_theme() {
    local mode="$1"
    [ -z "$mode" ] && return

    local theme
    theme=$(get_theme_config "$mode" "rofi") || return
    [ -z "$theme" ] && return

    files=(
        "$WORK_DIR"/rofi/launchers/*/shared/colors.rasi
        "$WORK_DIR"/rofi/powermenu/*/shared/colors.rasi
        "$WORK_DIR"/rofi/applets/shared/colors.rasi
    )

    sed -E -i \
        "s|/[^/\"]+\.rasi|/$theme.rasi|g" \
        "${files[@]}"
}

set_fcitx5_theme() {
    local theme=$(get_theme_config light "fcitx5") || return
    local dark_theme=$(get_theme_config dark "fcitx5") || return
    [ -z "$theme" ] && return
    [ -z "$dark_theme" ] && dark_theme=$theme

    if [ ! -d "/usr/share/fcitx5/themes/$theme" ]; then
        system-notify normal "Fcitx5 Theme Not Found" "fcitx5 theme \"$theme\" is not found, please make sure the theme exists"
        return
    fi

    local file="$HOME/.config/fcitx5/conf/classicui.conf"
    [ -f "$file" ] || return

    # fcitx5 经 UseDarkTheme 跟随系统深浅色, 三键与当前相同则无需重复设置/重启 (幂等)
    local cur_theme cur_dark cur_use
    cur_theme=$(sed -n 's/^Theme=//p' "$file")
    cur_dark=$(sed -n 's/^DarkTheme=//p' "$file")
    cur_use=$(sed -n 's/^UseDarkTheme=//p' "$file")
    [ "$cur_theme" = "$theme" ] && [ "$cur_dark" = "$dark_theme" ] && [ "$cur_use" = "True" ] && return 0

    _ensure_config_line "$file" "^Theme=.*" "Theme=$theme"
    _ensure_config_line "$file" "^DarkTheme=.*" "DarkTheme=$dark_theme"
    _ensure_config_line "$file" "^UseDarkTheme=.*" "UseDarkTheme=True"

    fcitx5 -r 9>&- &
    local new_pid
    for i in {1..10}; do
        sleep 0.1
        new_pid=$(pgrep -n fcitx5 2>/dev/null) && break
    done
    if [ -n "$new_pid" ]; then
        mkdir -p "/tmp/dwm-status" &&
            echo "$new_pid" >"/tmp/dwm-status/autostart-launch-fcitx5.pid"
    fi
}

set_kitty_theme() {
    local mode="$1"
    [ -z "$(command -v kitten)" ] && return
    [ -z "$mode" ] && return

    local theme
    theme=$(get_theme_config "$mode" "kitty") || return
    [ -z "$theme" ] && return

    kitten themes "$theme"
}

set_qt_theme() {
    [ "$QT_QPA_PLATFORMTHEME" = "gtk3" ] && return 0

    if ! grep -q 'QT_QPA_PLATFORMTHEME=gtk3' "$HOME/.xprofile" 2>/dev/null; then
        echo 'export QT_QPA_PLATFORMTHEME=gtk3' >>"$HOME/.xprofile"
        system-notify low "Qt Theme" "QT_QPA_PLATFORMTHEME=gtk3 written to ~/.xprofile, relogin needed"
    fi
}

set_dunst_theme() {
    local mode="$1"
    [ -z "$mode" ] && return

    local cfg="$HOME/.config/dunst/dunstrc"
    local icon_theme=$(get_theme_config "$mode" "icon") || return

    read bg fg < <(get_bg_fg_colors)
    [ -z "$bg" ] && return

    if grep -q 'background' "$cfg"; then
        sed -i "s/^\([[:space:]]*\)background[[:space:]]*=.*/\1background = \"$bg\"/" "$cfg"
    else
        echo "background = \"$bg\"" >>"$cfg"
    fi

    if grep -q 'foreground' "$cfg"; then
        sed -i "s/^\([[:space:]]*\)foreground[[:space:]]*=.*/\1foreground = \"$fg\"/" "$cfg"
    else
        echo "foreground = \"$fg\"" >>"$cfg"
    fi

    if grep -q 'frame_color' "$cfg"; then
        sed -i "s/^\([[:space:]]*\)frame_color[[:space:]]*=.*/\1frame_color = \"$fg\"/" "$cfg"
    else
        echo "frame_color = \"$fg\"" >>"$cfg"
    fi

    if grep -q 'icon_theme' "$cfg"; then
        sed -i "s/^\([[:space:]]*\)icon_theme[[:space:]]*=.*/\1icon_theme = \"$icon_theme\"/" "$cfg"
    else
        echo "icon_theme = \"$icon_theme\"" >>"$cfg"
    fi

    dunstctl reload 2>/dev/null || killall -SIGUSR1 dunst
}

set_gtk_theme() {
    local mode="$1"
    [ -z "$mode" ] && return

    local theme icon_theme cursor_theme cursor_size
    theme=$(get_theme_config "$mode" "gtk") || return
    icon_theme=$(get_theme_config "$mode" "icon") || return
    [ -z "$theme" ] && return
    cursor_theme=$(jq -r '.cursor.theme // empty' "$THEME_CONF")
    cursor_size=$(jq -r '.cursor.size // empty' "$THEME_CONF")

    local gtk2_cfg="$HOME/.gtkrc-2.0"
    local gtk3_cfg="$HOME/.config/gtk-3.0/settings.ini"
    local gtk4_cfg="$HOME/.config/gtk-4.0/settings.ini"

    _ensure_config_line "$gtk2_cfg" '^gtk-theme-name=.*' 'gtk-theme-name="'"$theme"'"'
    _ensure_config_line "$gtk2_cfg" '^gtk-icon-theme-name=.*' 'gtk-icon-theme-name="'"$icon_theme"'"'
    [ -n "$cursor_theme" ] && _ensure_config_line "$gtk2_cfg" '^gtk-cursor-theme-name.*' 'gtk-cursor-theme-name="'"$cursor_theme"'"'
    [ -n "$cursor_size" ] && _ensure_config_line "$gtk2_cfg" '^gtk-cursor-theme-size.*' "gtk-cursor-theme-size=$cursor_size"
    for conf in "$gtk3_cfg" "$gtk4_cfg"; do
        if [ -f "$conf" ] && grep -q '^\[Settings\]' "$conf" 2>/dev/null; then
            _ensure_config_line "$conf" '^gtk-theme-name=.*' "gtk-theme-name=$theme"
            _ensure_config_line "$conf" '^gtk-icon-theme-name=.*' "gtk-icon-theme-name=$icon_theme"
            [ -n "$cursor_theme" ] && _ensure_config_line "$conf" '^gtk-cursor-theme-name=.*' "gtk-cursor-theme-name=$cursor_theme"
            [ -n "$cursor_size" ] && _ensure_config_line "$conf" '^gtk-cursor-theme-size=.*' "gtk-cursor-theme-size=$cursor_size"
        else
            mkdir -p "$(dirname "$conf")"
            {
                echo "[Settings]"
                echo "gtk-theme-name=$theme"
                echo "gtk-icon-theme-name=$icon_theme"
                [ -n "$cursor_theme" ] && echo "gtk-cursor-theme-name=$cursor_theme"
                [ -n "$cursor_size" ] && echo "gtk-cursor-theme-size=$cursor_size"
            } >>"$conf"
        fi
    done

    # 运行时广播双通道 (以上仅为持久配置, 供应用启动时读取):
    # 1. XSETTINGS: GTK 应用 (含 Firefox UI) 监听 gtk-theme-name 变化即时刷新
    _ensure_config_line "$HOME/.xsettingsd" '^Net/ThemeName.*' 'Net/ThemeName "'"$theme"'"'
    [ -n "$cursor_theme" ] && _ensure_config_line "$HOME/.xsettingsd" '^Gtk/CursorThemeName.*' 'Gtk/CursorThemeName "'"$cursor_theme"'"'
    [ -n "$cursor_size" ] && _ensure_config_line "$HOME/.xsettingsd" '^Gtk/CursorThemeSize.*' "Gtk/CursorThemeSize $cursor_size"
    if ! pgrep -x xsettingsd >/dev/null 2>&1; then
        # 9>&-: auto_daemon 持 flock FD 9 时调到此处, 常驻的 xsettingsd 绝不能继承它,
        # 否则 daemon 重启后新实例永远拿不到锁而秒退 (与 sleep 孤儿占锁同类 bug)
        xsettingsd 9>&- &>/dev/null &
        disown
        sleep 0.3
    fi
    pkill -HUP -x xsettingsd

    # 2. portal: Firefox content 的 prefers-color-scheme 由 xdg-desktop-portal
    #    的 color-scheme 决定 (Firefox 将 default=0 硬映射为 light), 必须同步 gsettings
    if command -v gsettings >/dev/null 2>&1; then
        local cs="prefer-$mode"
        gsettings set org.gnome.desktop.interface color-scheme "$cs" ||
            system-notify normal "Theme Sync" "gsettings color-scheme 设置失败, portal 通道未生效"
        # 光标: GTK/Firefox 经 XSETTINGS 未命中时回退到 gsettings, 必须与 theme.json 对齐
        # (否则 Xcursor.size=24 而 Firefox=36, 差 1.5x)
        [ -n "$cursor_theme" ] && gsettings set org.gnome.desktop.interface cursor-theme "$cursor_theme" 2>/dev/null
        [ -n "$cursor_size" ] && gsettings set org.gnome.desktop.interface cursor-size "$cursor_size" 2>/dev/null
    fi
}

# ---------- theme apply ----------

_do_theme_change() {
    local mode="$1" nobright="$2"
    [ -z "$mode" ] && return

    # daemon 自动翻转时跳过一次性端点亮度 (由每轮插值负责，避免切换瞬间闪到端点)；
    # 手动 apply 保留端点亮度 (apply 后 auto 关闭，无后续插值)。
    # 必须同步执行 (不可 `&`): 后台化会让先启动但更慢的 job (DDC 单次 ~200ms,
    # 首次 detect ~1.6s) 在返回后才落盘, 用旧主题亮度覆盖后启动的新主题 —— 表现为
    # "dark 主题却是 light 亮度", 且窗口外 daemon 不自愈。同步则后调用者最后写, 值正确。
    if [ "$nobright" != "nobright" ]; then
        set_monitor_brightness "$mode"
    fi
    set_dwm_theme "$mode"
    set_rofi_theme "$mode"
    # 9>&-: daemon 持 flock FD 9, 所有后台任务一律关闭继承 (见 _auto_lock 注释)
    set_kitty_theme "$mode" 9>&- &
    set_qt_theme "$mode"
    set_gtk_theme "$mode"
    set_fcitx5_theme

    [ -f "$HOME/.Xresources" ] && xrdb -merge "$HOME/.Xresources"

    set_dunst_theme "$mode"

    # 壁纸跟随主题色调 (后台执行, 不阻塞后续 SIGHUP; 失败不影响主题切换退出码)
    # mode 非空由函数顶部 early-return 保证, 此处只需确认脚本可执行
    if [ -x "$WORK_DIR/tools/wallpaper.sh" ]; then
        ("$WORK_DIR/tools/wallpaper.sh" --theme "$mode" 9>&- &)
    fi

    # Wait for all theme changes to settle (especially fcitx5 restart,
    # xrdb merge, and GTK/Qt theme reload) before the SIGHUP that
    # follows. Otherwise dwm restart races with tray client re-init,
    # causing blank icons and frozen Electron/GTK clients (e.g. xunlei).
    sleep 0.3
}

# ---------- auto theme ----------

get_auto_config() {
    local key="$1"
    jq -r ".$key // empty" "$THEME_CONF" 2>/dev/null
}

# ---------- 亮度渐变 (brightness-transition) ----------
# 插值曲线单点封装: 输入/输出均为 milliscale 0..1000，两头快、中间慢
# (cubic warp s(u)=2u^3-3u^2+2u)：起止斜率约 2 倍、中段约 0.5 倍。
# 翻转瞬间快速脱离旧端点（dark 配深色 + 高亮度最眨眼的阶段不停留），
# 中段缓慢巡航，收尾快速贴合新端点；对称单调，中点严格 500。
# 纯 bash 整数运算（单次除法，四舍五入），无外部依赖。
# 以后太阳高度方案只需替换这一个函数。
_brightness_curve() {
    local t="$1"
    ((t < 0)) && t=0
    ((t > 1000)) && t=1000
    printf '%s' $(((2000 * t + 2 * t * t * t / 1000 - 3 * t * t + 500) / 1000))
}

# 插值: from → to，按 elapsed/duration 进度经 _brightness_curve 缓动后取值。
# duration<=0 直接取 to；elapsed 越界钳制。
_brightness_at() {
    local from="$1" to="$2" elapsed="$3" duration="$4"
    if [ "$duration" -le 0 ] 2>/dev/null; then
        printf '%s' "$to"
        return
    fi
    ((elapsed < 0)) && elapsed=0
    ((elapsed > duration)) && elapsed="$duration"
    local t=$((elapsed * 1000 / duration))
    t=$(_brightness_curve "$t")
    ((t < 0)) && t=0
    ((t > 1000)) && t=1000
    printf '%s' $((from + (to - from) * t / 1000))
}

# 过渡时长配置读取: 缺失/非法 → 60，0 = 关闭渐变
_transition_minutes() {
    local v
    v=$(get_auto_config "auto.$1")
    [[ $v =~ ^[0-9]+$ ]] || v=60
    printf '%s' "$v"
}

# 锚点归一化: after | center | before, 非法 → after
_normalize_anchor() {
    case "$1" in
    after | center | before) printf '%s' "$1" ;;
    *) printf 'after' ;;
    esac
}

# 锚点配置读取: after(默认) | center | before，非法 → after
_transition_anchor() {
    _normalize_anchor "$(get_auto_config "auto.transition_anchor")"
}

# daemon 单实例守卫：flock 非阻塞拿锁，拿不到返回 1 (调用者直接 exit 0)。
# 锁 FD (9) 在进程内保持到 daemon 退出。autostart 直起的 daemon 无 pid 文件，
# `auto on` 的 kill -0 认不出它，并发 on 也有竞态，都靠此兜底。
# flock 缺失时 fail-open (旧行为：允许运行)。
# 注意：daemon 内所有 sleep / 后台子 shell 必须以 9>&- 启动，不继承此 FD，
# 否则父 daemon 被 kill 后孤儿进程继续占锁，新 daemon 永远拿不到锁而秒退。
_auto_lock() {
    command -v flock >/dev/null 2>&1 || return 0
    local lock="$1"
    mkdir -p "$(dirname "$lock")" 2>/dev/null || return 1
    exec 9>"$lock" 2>/dev/null || return 1
    flock -n 9 2>/dev/null || return 1
}

# 过渡窗口起止 (输出 "start end")，anchor 非法回退 after
# after: [point, point+dur] 事件时开始、事件后结束
# center: 对称窗口，事件时正好中点
# before: [point-dur, point] 事件时已达新端点
_window_at() {
    local point="$1" dur="$2" anchor
    anchor=$(_normalize_anchor "$3")
    if [ "$dur" -le 0 ] 2>/dev/null; then
        printf '%s %s' "$point" "$point"
    elif [ "$anchor" = "center" ]; then
        local start=$((point - dur / 2))
        printf '%s %s' "$start" $((start + dur))
    elif [ "$anchor" = "before" ]; then
        printf '%s %s' $((point - dur)) "$point"
    else
        printf '%s %s' "$point" $((point + dur))
    fi
}

_dawn_window() { _window_at "$1" "$2" "$3"; }

_dusk_window() { _window_at "$1" "$2" "$3"; }

# 二值主题判定 (锚点无关，配色始终在 rise/set 翻转)
_theme_at() {
    local now="$1" rise="$2" set_pt="$3"
    if [ "$now" -lt "$rise" ] 2>/dev/null; then
        printf 'dark'
    elif [ "$now" -lt "$set_pt" ] 2>/dev/null; then
        printf 'light'
    else
        printf 'dark'
    fi
}

# 单 monitor 目标亮度: 窗口内插值，窗口外取端点 (dusk 重叠优先)
_monitor_brightness_at() {
    local now="$1" rise="$2" set_pt="$3" dawn="$4" dusk="$5" anchor="$6" dark="$7" light="$8"
    anchor=$(_normalize_anchor "$anchor")
    local ds de ss se
    read ds de <<<"$(_dawn_window "$rise" "$dawn" "$anchor")"
    read ss se <<<"$(_dusk_window "$set_pt" "$dusk" "$anchor")"
    if [ "$dusk" -gt 0 ] 2>/dev/null && [ "$now" -ge "$ss" ] && [ "$now" -lt "$se" ]; then
        _brightness_at "$light" "$dark" $((now - ss)) "$dusk"
    elif [ "$dawn" -gt 0 ] 2>/dev/null && [ "$now" -ge "$ds" ] && [ "$now" -lt "$de" ]; then
        _brightness_at "$dark" "$light" $((now - ds)) "$dawn"
    elif [ "$(_theme_at "$now" "$rise" "$set_pt")" = "light" ]; then
        printf '%s' "$light"
    else
        printf '%s' "$dark"
    fi
}

# 是否需要写亮度：过渡窗口内（含终点），或某侧关闭渐变时的二值对齐。
# 窗口外返回 1（手动/OSD 调的不抢回来）。
_should_apply_at() {
    local now="$1" rise="$2" set_pt="$3" dawn="$4" dusk="$5" anchor="$6"
    local ds de ss se theme
    read ds de <<<"$(_dawn_window "$rise" "$dawn" "$anchor")"
    read ss se <<<"$(_dusk_window "$set_pt" "$dusk" "$anchor")"
    if [ "$dawn" -gt 0 ] 2>/dev/null && [ "$now" -ge "$ds" ] && [ "$now" -le "$de" ]; then return 0; fi
    if [ "$dusk" -gt 0 ] 2>/dev/null && [ "$now" -ge "$ss" ] && [ "$now" -le "$se" ]; then return 0; fi
    theme=$(_theme_at "$now" "$rise" "$set_pt")
    if [ "$theme" = "light" ] && [ "$dawn" -le 0 ] 2>/dev/null; then return 0; fi
    if [ "$theme" = "dark" ] && [ "$dusk" -le 0 ] 2>/dev/null; then return 0; fi
    return 1
}

# 按当前时刻把每块 active monitor 亮度设为插值目标。
# 只在过渡窗口内写：窗口外完全不动（手动/OSD 调的不抢回来）。
# 某侧 duration=0 视为该侧关闭渐变，按旧二值语义持续对齐端点。
# 与当前硬件值差 <1 跳过 (避免 DDC 无谓写入)；读不到当前值时直接写。
apply_transition_brightness() {
    local now="$1" rise="$2" set_pt="$3" dawn="$4" dusk="$5" anchor="$6"
    _should_apply_at "$now" "$rise" "$set_pt" "$dawn" "$dusk" "$anchor" || return 0
    local monitor dark light target cur diff
    while read -r monitor; do
        dark=$(get_theme_config dark "brightness.$monitor")
        [[ $dark =~ ^[0-9]+$ ]] && ((dark <= 100)) || dark=50
        light=$(get_theme_config light "brightness.$monitor")
        [[ $light =~ ^[0-9]+$ ]] && ((light <= 100)) || light=50
        target=$(_monitor_brightness_at "$now" "$rise" "$set_pt" "$dawn" "$dusk" "$anchor" "$dark" "$light")
        cur=$(read_brightness "$monitor" 2>/dev/null)
        if [[ $cur =~ ^[0-9]+$ ]]; then
            diff=$((target > cur ? target - cur : cur - target))
            ((diff < 1)) && continue
        fi
        set_brightness "$monitor" "$target"
    done < <(xrandr --listactivemonitors 2>/dev/null | awk 'NR>1 {print $NF}')
}

get_sun_times() {
    local cache="$HOME/.local/state/dwm/cache/sun-times" today
    today=$(date +%F)
    local cdate sr_ep ss_ep sr2_ep
    if [ -f "$cache" ]; then
        IFS='|' read -r cdate sr_ep ss_ep sr2_ep <"$cache"
        if [ "$cdate" = "$today" ] && [ -n "$sr_ep" ] && [ -n "$ss_ep" ] && [ -n "$sr2_ep" ]; then
            echo "$sr_ep $ss_ep $sr2_ep"
            return 0
        fi
    fi

    local lock="$HOME/.local/state/dwm/cache/sun-times.fetching"
    if [ -f "$lock" ] && find "$lock" -mmin -1 2>/dev/null | grep -q .; then
        return 1
    fi
    rm -f "$lock"

    mkdir -p "$(dirname "$lock")"
    touch "$lock"
    (
        exec 9>&- # 见 _auto_lock：不继承 flock 锁
        IFS=, read LAT LON < <(curl -m 2 -fsS https://ipinfo.io/loc) || exit
        # 坐标非法直接丢弃 (不写缓存、不删锁: 保留 1 分钟 throttle, 见下)
        [[ $LAT =~ ^-?[0-9.]+$ && $LON =~ ^-?[0-9.]+$ ]] || exit
        local json tz sr1 ss1 sr2
        json=$(curl -m 5 -fsS "https://api.open-meteo.com/v1/forecast?latitude=$LAT&longitude=$LON&daily=sunrise,sunset&forecast_days=2&timezone=auto") || exit
        tz=$(echo "$json" | jq -r '.timezone // "UTC"')
        sr1=$(echo "$json" | jq -r '.daily.sunrise[0] // empty')
        ss1=$(echo "$json" | jq -r '.daily.sunset[0] // empty')
        sr2=$(echo "$json" | jq -r '.daily.sunrise[1] // empty')
        [ -n "$sr1" ] && [ -n "$ss1" ] && [ -n "$sr2" ] || exit
        sr_ep=$(TZ="$tz" date -d "$sr1" +%s) || exit
        ss_ep=$(TZ="$tz" date -d "$ss1" +%s) || exit
        sr2_ep=$(TZ="$tz" date -d "$sr2" +%s) || exit
        # epoch 非法或时序颠倒 (ss>sr, sr2>ss) 视为脏数据丢弃, 不写缓存
        # (date -d "" 会静默返回当前时间, 必须拦掉)
        [[ $sr_ep =~ ^[0-9]+$ && $ss_ep =~ ^[0-9]+$ && $sr2_ep =~ ^[0-9]+$ ]] || exit
        [ "$ss_ep" -gt "$sr_ep" ] && [ "$sr2_ep" -gt "$ss_ep" ] || exit
        mkdir -p "$(dirname "$cache")"
        printf '%s|%s|%s|%s\n' "$today" "$sr_ep" "$ss_ep" "$sr2_ep" >"${cache}.tmp" && mv "${cache}.tmp" "$cache"
        rm -f "$lock"
    ) >/dev/null 2>&1 &
    disown
    return 1
}

auto_daemon() {
    _auto_lock "${THEME_LOCK:-/tmp/dwm-status/theme-auto.lock}" || exit 0
    local auto
    auto=$(get_auto_config "auto.enabled")
    # 三态: true=运行; 显式 false/未知非空值=关闭→退出;
    # 空=配置瞬时不可读(编辑器非原子写的瞬间 jq 失败)或缺 key→进主循环短重试, 不退出
    # (直接退出会导致一次瞬时抖动杀死 daemon, 且永不自愈)
    [ "$auto" = "false" ] && exit 0
    [ -n "$auto" ] && [ "$auto" != "true" ] && exit 0

    while true; do
        auto=$(get_auto_config "auto.enabled")
        [ "$auto" = "false" ] && exit 0
        [ -n "$auto" ] && [ "$auto" != "true" ] && exit 0
        if [ "$auto" != "true" ]; then
            # 空=读失败, 短重试不退出 (见函数首注释)
            sleep 10 9>&-
            continue
        fi

        local times sunrise sunset next_sunrise
        if ! times=$(get_sun_times 2>/dev/null); then
            # 缓存缺失时已触发后台异步拉取, 短轮询等待即可 (.fetching 锁防刷,
            # 1 分钟内不重复拉); 不能睡 1800: 开机首次无缓存会延迟切换半小时
            sleep 30 9>&-
            continue
        fi
        read sunrise sunset next_sunrise <<<"$times"
        # 缓存手改/损坏时非数字会坍缩成 epoch 0 (bash 空变量即 0),
        # remain 恒负→无 sleep 热循环, desired 恒 dark→SIGHUP 风暴; 必须拦掉
        if ! [[ $sunrise =~ ^[0-9]+$ && $sunset =~ ^[0-9]+$ && $next_sunrise =~ ^[0-9]+$ ]]; then
            sleep 30 9>&-
            continue
        fi

        local rise_off set_off
        rise_off=$(get_auto_config "auto.sun_rise_offset")
        [[ $rise_off =~ ^-?[0-9]+$ ]] || rise_off=0
        rise_off=$((rise_off * 60))
        set_off=$(get_auto_config "auto.sun_set_offset")
        [[ $set_off =~ ^-?[0-9]+$ ]] || set_off=0
        set_off=$((set_off * 60))

        local now desired next_switch rise set_pt dawn dusk anchor
        now=$(date +%s)

        rise=$((sunrise + rise_off))
        set_pt=$((sunset + set_off))
        dawn=$(_transition_minutes dawn_minutes)
        dawn=$((dawn * 60))
        dusk=$(_transition_minutes dusk_minutes)
        dusk=$((dusk * 60))
        anchor=$(_transition_anchor)

        desired=$(_theme_at "$now" "$rise" "$set_pt")
        if [ "$now" -lt "$rise" ]; then
            next_switch="$rise"
        elif [ "$now" -lt "$set_pt" ]; then
            next_switch="$set_pt"
        else
            next_switch="$((next_sunrise + rise_off))"
        fi

        local cur
        cur=$(get_current_theme)
        if [ -n "$desired" ] && [ "$cur" != "$desired" ]; then
            # 锁屏期间阻塞等待 (避免与 dwm SIGHUP 重启竞态), 解锁后立即切换;
            # 等待中重查 enabled: 锁屏期间 auto off 必须生效, 不补 stale 翻转
            while pgrep -x i3lock >/dev/null 2>&1; do
                sleep 5 9>&-
                [ "$(get_auto_config "auto.enabled")" = "false" ] && exit 0
            done
            # 翻转时的亮度策略 (窗口内外有别):
            # 窗口内 → nobright，只切配色，亮度由每轮插值接管 (翻转点插值正好在旧端点，
            #   若设新端点会闪一下)；窗口外 → 带端点一次性写入，否则之后再也没人写亮度
            #   (插值在窗口外故意不动)，导致配色与亮度永久错位 (如夜间启动 daemon、
            #   挂起跨过窗口、锁屏延迟翻转)。
            if _should_apply_at "$now" "$rise" "$set_pt" "$dawn" "$dusk" "$anchor"; then
                _do_theme_change "$desired" nobright
            else
                _do_theme_change "$desired"
            fi
            tool-notify low "Auto Theme" "switched to $desired theme"
            # _do_theme_change 空模式 early-return 时 current-theme 不变,
            # 以文件校验为准再 SIGHUP, 避免无意义重启风暴
            [ "$(get_current_theme)" = "$desired" ] && pkill -SIGHUP dwm
            sleep 0.5 9>&-
        fi

        # 每轮按当前时刻重算插值亮度 (过渡期内自然每 60s 步进)；
        # 锁屏期间跳过 (解锁后下一轮纠正)
        if ! pgrep -x i3lock >/dev/null 2>&1; then
            apply_transition_brightness "$now" "$rise" "$set_pt" "$dawn" "$dusk" "$anchor"
        fi

        # sleep 计时在挂起(休眠)期间暂停, 一次性睡到切换点会导致唤醒后
        # 主题切换延迟数小时; 故 60s 内轮询重算, 挂起唤醒后最多 60s 纠正
        local remain=$((next_switch - now))
        if [ "$remain" -gt 0 ]; then
            [ "$remain" -gt 60 ] && remain=60
            sleep "$remain" 9>&-
        fi
    done
}

case "$1" in
check)
    pkgs=(
        "tela-icon-theme-git"
        "orchis-theme"
        "fcitx5-themes-candlelight"
        "xsettingsd"
        "dconf"
    )
    missing=()
    for pkg in "${pkgs[@]}"; do
        if ! pacman -Qi "$pkg" &>/dev/null; then
            missing+=("$pkg")
        fi
    done
    if [ ${#missing[@]} -gt 0 ]; then
        system-notify normal "Installing Themes" "Installing: ${missing[*]}"
        paru -S --noconfirm --needed "${missing[@]}"
    else
        system-notify normal "Themes Check" "All theme packages are already installed"
    fi
    ;;
apply)
    mode="$2"
    [ -z "$mode" ] && exit 1
    # 先停 daemon：否则它在切换间隙 tick 一次就会用插值覆盖手动端点亮度
    [ "$(get_auto_config "auto.enabled")" = "true" ] && "$0" auto off
    _do_theme_change "$mode"
    pkill -SIGHUP dwm
    exit 0
    ;;
auto)
    pf="/tmp/dwm-status/autostart-launch-theme-auto.pid"
    case "$2" in
    on)
        jq '.auto.enabled = true' "$THEME_CONF" >"${THEME_CONF}.tmp" 2>/dev/null &&
            mv "${THEME_CONF}.tmp" "$THEME_CONF" || {
            system-notify normal "Auto Theme" "theme.json 写入失败, auto 未启用"
            exit 1
        }
        pid=""
        [ -f "$pf" ] && pid=$(cat "$pf")
        if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then exit 0; fi
        # pid 文件不可靠 (autostart 直起的 daemon 无 pid 文件, flock 才是单一真实来源):
        # 锁被占说明已有实例在跑, 直接复用, 不再 spawn (否则新实例拿不到锁秒退,
        # 还会用死 pid 覆盖 pid 文件)
        if ! ( _auto_lock "${THEME_LOCK:-/tmp/dwm-status/theme-auto.lock}" ) 2>/dev/null; then
            tool-notify low "Auto Theme" "auto switch enabled"
            exit 0
        fi
        "$0" auto >/dev/null 2>&1 &
        mkdir -p "$(dirname "$pf")"
        echo $! >"$pf"
        tool-notify low "Auto Theme" "auto switch enabled"
        ;;
    off)
        jq '.auto.enabled = false' "$THEME_CONF" >"${THEME_CONF}.tmp" 2>/dev/null &&
            mv "${THEME_CONF}.tmp" "$THEME_CONF" || {
            system-notify normal "Auto Theme" "theme.json 写入失败"
            exit 1
        }
        if [ -f "$pf" ]; then
            off_pid=$(cat "$pf")
            [[ $off_pid =~ ^[0-9]+$ ]] && kill "$off_pid" 2>/dev/null
        fi
        rm -f "$pf"
        # 兜底无 pid 文件的 daemon (如 autostart 直起的 `theme.sh auto`)：
        # 行尾锚定只命中 daemon (`...theme.sh auto`)，不命中 `auto off` 自身
        pkill -f 'theme\.sh auto$' 2>/dev/null
        tool-notify low "Auto Theme" "auto switch disabled"
        ;;
    *) auto_daemon ;;
    esac
    ;;
esac
