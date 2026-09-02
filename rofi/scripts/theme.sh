#!/usr/bin/env bash

ROFI_DIR="$(dirname "$(dirname "$0")")"
WORK_DIR="$(dirname "$ROFI_DIR")"

MODULE_THEME="$ROFI_DIR/applets/type-1/style-2.rasi"
MODULE_MAX_LINES=8
MODULE_NAME="☀ Theme"
ITEM_SPACE_WIDTH=34

source "$(dirname "$0")"/util.sh
source "$(dirname "$0")"/lib-module.sh
source "$WORK_DIR/tools/theme.sh"

THEME_CONF="$HOME/.config/dwm/theme.json"

get_auto_stat() { jq -r '.auto.enabled // false' "$THEME_CONF" 2>/dev/null; }
get_cur() { cat "$HOME/.local/state/dwm/current-theme" 2>/dev/null; }
get_rise() { jq -r '.auto.sun_rise_offset // 0' "$THEME_CONF" 2>/dev/null; }
get_set() { jq -r '.auto.sun_set_offset // 0' "$THEME_CONF" 2>/dev/null; }

get_sun_message() {
    local times sunrise sunset
    times=$(get_sun_times 2>/dev/null) || return 1
    read sunrise sunset _ <<<"$times"
    printf "  %s |   %s" "$(date -d "@$sunrise" +%H:%M)" "$(date -d "@$sunset" +%H:%M)"
}

module_parse <<MODULES
toggle| |Toggle|str:$(get_cur)
auto|󰃡 |Auto (sunrise/sunset)|str:$([ "$(get_auto_stat)" = "true" ] && echo "" || echo "")
monitor_brightness|󰃠 |Monitor Brightness
rise_offset| |Rise offset|str:$(get_rise)m
set_offset| |Set offset|str:$(get_set)m
conf|󱔏 |Edit config|
MODULES

sun_mesg=$(get_sun_message 2>/dev/null) || true
MODULE_MESG="system theme${sun_mesg:+ | $sun_mesg}"

handle_toggle() {
    local cur mode
    cur=$(get_cur)
    if [ "$cur" = "light" ]; then mode="dark"; else mode="light"; fi
    /bin/bash "$WORK_DIR/tools/theme.sh" apply "$mode"
}
handle_auto() {
    local cur
    cur=$(get_auto_stat)
    if [ "$cur" = "true" ]; then
        /bin/bash "$WORK_DIR/tools/theme.sh" auto off
    else
        /bin/bash "$WORK_DIR/tools/theme.sh" auto on
    fi
}
handle_monitor_brightness() {
    local monitor brightness value last original chosen yad_fd yad_pid tmpdir fifo status

    # 循环: 调完一个显示器后回到选择, 可连续调节多个, ESC 退出
    while true; do
        chosen=$(while read -r monitor; do
            printf "󰍹 %-32s %4s\n" "$monitor" "$(read_brightness "$monitor")"
        done < <(
            xrandr --listactivemonitors 2>/dev/null |
                awk 'NR > 1 {print $NF}'
        ) | module_sub_rofi "󰃠 Monitor Brightness" "Control brightness of monitors")
        [ -z "$chosen" ] && break

        read -r _ monitor brightness <<<"$chosen"
        original="$brightness"
        [[ -z "$brightness" ]] && brightness=50

        # FIFO + 后台 pid ($!) 替代 coproc: bash 读完全部输出后可能清理 coproc 的
        # YAD_PID (wait 时为空 → 退出码误判), 后台 pid 稳定; 循环内 $last 记录最终值
        # (最后一次 read 读到 EOF 时会把 $value 清空)
        tmpdir=$(mktemp -d) || return
        fifo="$tmpdir/out"
        mkfifo "$fifo" || { rm -rf "$tmpdir"; return; }
        yad \
            --scale \
            --title="Monitor Brightness" \
            --text="$monitor" \
            --min-value=0 \
            --max-value=100 \
            --value="$brightness" \
            --step=2 \
            --print-partial >"$fifo" 2>/dev/null &
        yad_pid=$!
        exec {yad_fd}<"$fifo"

        while IFS= read -r value <&"$yad_fd"; do
            last="$value"
            if [[ $monitor =~ ^eDP ]]; then
                # eDP brightnessctl 响应即时, 逐值应用保持实时反馈
                set_brightness "$monitor" "$value"
            else
                # DDC/CI 单次调用 ~200ms, 拖动时积压会大幅滞后:
                # 丢弃积压值, 滑动暂停 30ms 后只应用最新值
                while IFS= read -t 0.03 -r value <&"$yad_fd"; do
                    last="$value"
                done
                set_brightness "$monitor" "$last"
            fi
        done
        exec {yad_fd}<&-
        rm -rf "$tmpdir"

        wait "$yad_pid"
        status=$?

        if ((status == 0)); then
            # OK: 以硬件实际亮度为准 (eDP brightnessctl / DDC getvcp),
            # 读取失败时回退循环内最后读到的值
            value=$(read_brightness "$monitor")
            [ -n "$value" ] || value="$last"
            [ -n "$value" ] || continue
            jq \
                --arg monitor "$monitor" \
                --argjson brightness "$value" \
                --arg mode "$(get_cur)" \
                '.[$mode].brightness[$monitor] = $brightness' \
                "$THEME_CONF" >"${THEME_CONF}.tmp" &&
                mv "${THEME_CONF}.tmp" "$THEME_CONF"
        else
            # 取消/ESC: 恢复原亮度
            set_brightness "$monitor" "$original"
        fi
    done
}

_handle_offset() {
    local field="$1" prompt="$2" getter="$3"
    local cur val
    cur=$("$getter")
    val="$(module_input "$prompt" "negative = before, positive = after" "$cur")"
    [ -z "$val" ] && return
    [[ "$val" =~ ^-?[0-9]+$ ]] || {
        system-notify normal "Invalid" "must be an integer"
        return
    }
    jq ".$field = $val" "$THEME_CONF" >"${THEME_CONF}.tmp" && mv "${THEME_CONF}.tmp" "$THEME_CONF"
    if [ "$(get_auto_stat)" = "true" ]; then
        pf="/tmp/dwm-status/autostart-launch-theme-auto.pid"
        [ -f "$pf" ] && kill "$(cat "$pf")" 2>/dev/null
        rm -f "$pf"
        /bin/bash "$WORK_DIR/tools/theme.sh" auto >/dev/null 2>&1 &
    fi
}
handle_rise_offset() { _handle_offset "auto.sun_rise_offset" "Rise offset (min)" get_rise; }
handle_set_offset() { _handle_offset "auto.sun_set_offset" "Set offset (min)" get_set; }
handle_conf() {
    local checksum_before auto_before
    checksum_before=$(md5sum "$THEME_CONF" 2>/dev/null)
    auto_before=$(get_auto_stat)

    ${TERMINAL:-kitty} -e ${EDITOR:-nvim} "$THEME_CONF" 2>/dev/null || {
        system-notify normal "Error" "failed to open editor"
        return
    }

    [ "$(md5sum "$THEME_CONF" 2>/dev/null)" = "$checksum_before" ] && return

    local auto_after
    auto_after=$(get_auto_stat)

    if [ "$auto_before" != "$auto_after" ]; then
        if [ "$auto_after" = "true" ]; then
            /bin/bash "$WORK_DIR/tools/theme.sh" auto on
        else
            /bin/bash "$WORK_DIR/tools/theme.sh" auto off
        fi
    elif [ "$auto_after" = "true" ]; then
        local pf="/tmp/dwm-status/autostart-launch-theme-auto.pid"
        [ -f "$pf" ] && kill "$(cat "$pf")" 2>/dev/null
        rm -f "$pf"
        /bin/bash "$WORK_DIR/tools/theme.sh" auto >/dev/null 2>&1 &
    fi

    local cur
    cur=$(get_cur)
    [ -n "$cur" ] || return
    _do_theme_change "$cur"
    pkill -SIGHUP dwm
}

module_loop
