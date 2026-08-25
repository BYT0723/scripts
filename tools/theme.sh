#!/usr/bin/env bash

WORK_DIR=$(dirname "$(dirname "${BASH_SOURCE[0]}")")
THEME_CONF="$HOME/.config/dwm/theme.json"

source "$WORK_DIR/utils/notify.sh"

# ---------- helpers ----------

get_theme_config() {
    local mode="$1" key="$2"
    jq -r ".[\"$mode\"][\"$key\"] // empty" "$THEME_CONF"
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
    local mode="$1"
    [ -z "$mode" ] && return

    local theme
    theme=$(get_theme_config "$mode" "fcitx5") || return
    [ -z "$theme" ] && return

    if [ ! -d "/usr/share/fcitx5/themes/$theme" ]; then
        system-notify normal "Fcitx5 Theme Not Found" "fcitx5 theme \"$theme\" is not found, please make sure the theme exists"
        return
    fi

    local file="$HOME/.config/fcitx5/conf/classicui.conf"
    [ -f "$file" ] || return

    _ensure_config_line "$file" "^Theme=.*" "Theme=$theme"

    fcitx5 -r &
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

    local theme icon_theme
    theme=$(get_theme_config "$mode" "gtk") || return
    icon_theme=$(get_theme_config "$mode" "icon") || return
    [ -z "$theme" ] && return

    local gtk2_cfg="$HOME/.gtkrc-2.0"
    local gtk3_cfg="$HOME/.config/gtk-3.0/settings.ini"
    local gtk4_cfg="$HOME/.config/gtk-4.0/settings.ini"

    _ensure_config_line "$gtk2_cfg" '^gtk-theme-name=.*' 'gtk-theme-name="'"$theme"'"'
    _ensure_config_line "$gtk2_cfg" '^gtk-icon-theme-name=.*' 'gtk-icon-theme-name="'"$icon_theme"'"'
    for conf in "$gtk3_cfg" "$gtk4_cfg"; do
        if [ -f "$conf" ] && grep -q '^\[Settings\]' "$conf" 2>/dev/null; then
            _ensure_config_line "$conf" '^gtk-theme-name=.*' "gtk-theme-name=$theme"
            _ensure_config_line "$conf" '^gtk-icon-theme-name=.*' "gtk-icon-theme-name=$icon_theme"
        else
            mkdir -p "$(dirname "$conf")"
            {
                echo "[Settings]"
                echo "gtk-theme-name=$theme"
                echo "gtk-icon-theme-name=$icon_theme"
            } >>"$conf"
        fi
    done

    # 运行时广播双通道 (以上仅为持久配置, 供应用启动时读取):
    # 1. XSETTINGS: GTK 应用 (含 Firefox UI) 监听 gtk-theme-name 变化即时刷新
    _ensure_config_line "$HOME/.xsettingsd" '^Net/ThemeName.*' 'Net/ThemeName "'"$theme"'"'
    if ! pgrep -x xsettingsd >/dev/null 2>&1; then
        xsettingsd &>/dev/null &
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
    fi
}

# ---------- theme apply ----------

_do_theme_change() {
    local mode="$1"
    [ -z "$mode" ] && return

    set_dwm_theme "$mode"
    set_rofi_theme "$mode"
    set_kitty_theme "$mode" &
    set_qt_theme "$mode"
    set_gtk_theme "$mode"
    set_fcitx5_theme "$mode"

    [ -f "$HOME/.Xresources" ] && xrdb -merge "$HOME/.Xresources"

    set_dunst_theme "$mode"

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
        IFS=, read LAT LON < <(curl -m 2 -fsS https://ipinfo.io/loc) || exit
        local json tz sr1 ss1 sr2
        json=$(curl -m 5 -fsS "https://api.open-meteo.com/v1/forecast?latitude=$LAT&longitude=$LON&daily=sunrise,sunset&forecast_days=2&timezone=auto") || exit
        tz=$(echo "$json" | jq -r '.timezone // "UTC"')
        sr1=$(echo "$json" | jq -r '.daily.sunrise[0]')
        ss1=$(echo "$json" | jq -r '.daily.sunset[0]')
        sr2=$(echo "$json" | jq -r '.daily.sunrise[1]')
        sr_ep=$(TZ="$tz" date -d "$sr1" +%s)
        ss_ep=$(TZ="$tz" date -d "$ss1" +%s)
        sr2_ep=$(TZ="$tz" date -d "$sr2" +%s)
        mkdir -p "$(dirname "$cache")"
        printf '%s|%s|%s|%s\n' "$today" "$sr_ep" "$ss_ep" "$sr2_ep" >"${cache}.tmp" && mv "${cache}.tmp" "$cache"
        rm -f "$lock"
    ) &
    disown
    return 1
}

auto_daemon() {
    local auto
    auto=$(get_auto_config "auto.enabled")
    [ "$auto" = "true" ] || exit 0

    while true; do
        auto=$(get_auto_config "auto.enabled")
        [ "$auto" = "true" ] || exit 0

        local times sunrise sunset next_sunrise
        if times=$(get_sun_times 2>/dev/null); then
            read sunrise sunset next_sunrise <<<"$times"
        fi
        [ -n "$sunrise" ] && [ -n "$sunset" ] && [ -n "$next_sunrise" ] || {
            sleep 1800
            continue
        }

        local rise_off set_off
        rise_off=$(get_auto_config "auto.sun_rise_offset")
        rise_off=$((${rise_off:-0} * 60))
        set_off=$(get_auto_config "auto.sun_set_offset")
        set_off=$((${set_off:-0} * 60))

        local now desired next_switch
        now=$(date +%s)

        if [ "$now" -lt "$((sunrise + rise_off))" ]; then
            desired="dark"
            next_switch="$((sunrise + rise_off))"
        elif [ "$now" -lt "$((sunset + set_off))" ]; then
            desired="light"
            next_switch="$((sunset + set_off))"
        else
            desired="dark"
            next_switch="$((next_sunrise + rise_off))"
        fi

        local cur
        cur=$(get_current_theme)
        if [ "$cur" != "$desired" ]; then
            # 锁屏期间阻塞等待 (避免与 dwm SIGHUP 重启竞态), 解锁后立即切换
            while pgrep -x i3lock >/dev/null 2>&1; do
                sleep 5
            done
            _do_theme_change "$desired"
            tool-notify low "Auto Theme" "switched to $desired theme"
            pkill -SIGHUP dwm
            sleep 0.5
        fi

        # sleep 计时在挂起(休眠)期间暂停, 一次性睡到切换点会导致唤醒后
        # 主题切换延迟数小时; 故 60s 内轮询重算, 挂起唤醒后最多 60s 纠正
        local remain=$((next_switch - now))
        if [ "$remain" -gt 0 ]; then
            [ "$remain" -gt 60 ] && remain=60
            sleep "$remain"
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
    _do_theme_change "$mode"
    pkill -SIGHUP dwm
    [ "$(get_auto_config "auto.enabled")" = "true" ] && "$0" auto off
    exit 0
    ;;
auto)
    pf="/tmp/dwm-status/autostart-launch-theme-auto.pid"
    case "$2" in
    on)
        jq '.auto.enabled = true' "$THEME_CONF" >"${THEME_CONF}.tmp" &&
            mv "${THEME_CONF}.tmp" "$THEME_CONF"
        local pid
        [ -f "$pf" ] && pid=$(cat "$pf")
        [ -n "${pid:-}" ] && kill -0 "$pid" 2>/dev/null && exit 0
        "$0" auto >/dev/null 2>&1 &
        mkdir -p "$(dirname "$pf")"
        echo $! >"$pf"
        tool-notify low "Auto Theme" "auto switch enabled"
        ;;
    off)
        jq '.auto.enabled = false' "$THEME_CONF" >"${THEME_CONF}.tmp" &&
            mv "${THEME_CONF}.tmp" "$THEME_CONF"
        [ -f "$pf" ] && kill "$(cat "$pf")" 2>/dev/null
        rm -f "$pf"
        tool-notify low "Auto Theme" "auto switch disabled"
        ;;
    *) auto_daemon ;;
    esac
    ;;
esac
