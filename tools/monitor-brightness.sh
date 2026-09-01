#!/usr/bin/env bash

get_brightness() {
    local output="$1"

    xrandr --verbose --current |
        awk -v output="$output" '
            $0 ~ "^" output " connected" { found=1; next }
            found && /Brightness:/ {
                print $2
                exit
            }
            found && /^[^[:space:]]/ { exit }
        '
}

# 修改输出给显示器的gamma值来使显示器黑屏，但依然有背光
toggle_monitor() {
    local output="$1"
    local state="$HOME/.local/state/dwm/status/monitor-$output"
    local cur

    if [[ -f "$state" ]]; then
        cur=$(<"$state")
        xrandr --output "$output" --brightness "$cur"
        rm -f "$state"
        return
    fi

    cur=$(get_brightness "$output")

    if awk -v cur="$cur" 'BEGIN { exit !(cur > 0) }'; then
        mkdir -p "$(dirname "$state")"
        printf '%s\n' "$cur" >"$state"
        xrandr --output "$output" --brightness 0
    fi
}

# 返回 ddcutil --bus 可用的整数总线号 (经 xrandr CONNECTOR_ID ↔ ddcutil drm_connector_id 匹配)
# DP 显示器 DDC/CI 走 aux 总线，故不能直接读 /sys/class/drm/*/ddc 的 symlink
get_ddc_bus() {
    local output="$1"
    local cid

    cid=$(
        xrandr --props |
            awk -v output="$output" '
            $0 ~ "^" output " connected" {
                found = 1
                next
            }

            found && /^[^[:space:]]/ {
                exit
            }

            found && /CONNECTOR_ID:/ {
                print $2
                exit
            }
        '
    ) || return 1

    [[ -z "$cid" ]] && return 1

    ddcutil detect --brief 2>/dev/null |
        awk -v cid="$cid" '
            /^[[:space:]]*I2C bus:/ {
                bus = $NF
            }
            /^Display [0-9]+$/ {
                valid = 1
                next
            }
            /^Invalid display/ {
                valid = 0
                next
            }
            valid && /^[[:space:]]*drm_connector_id:/ && $NF == cid {
                gsub(/^\/dev\/i2c-/, "", bus)
                print bus
                exit
            }
        '
}

# 读取 (省略 value) 或设置 (带 value) 显示器硬件亮度 (VCP 0x10)
monitor_brightness() {
    local output="$1"
    local value="$2"
    local bus

    bus=$(get_ddc_bus "$output") || return 1
    [[ -n "$bus" ]] || return 1

    if [[ -n "$value" ]]; then
        ddcutil --bus "$bus" setvcp 10 "$value" >/dev/null 2>&1
    else
        ddcutil --bus "$bus" getvcp 10 2>/dev/null |
            sed -n 's/.*current value = *\([0-9][0-9]*\),.*/\1/p'
    fi
}
