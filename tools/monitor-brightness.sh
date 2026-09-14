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

# DDC 总线缓存 (文件): 单次 detect 约 1.6s (占过渡 tick 开销 95%+, 而 getvcp
# 仅约 30ms), 但 bus 映射只在热插拔时改变。用当前 active 输出集合做 key,
# 集合变化即失效 (xrandr 枚举约 10ms, 相对 detect 可忽略); 查询失败/文件损坏
# 时不用也不写缓存。必须用文件而非内存变量: 调用方经 $() 子 shell 调用,
# 子 shell 里的内存写会丢失; 文件同时惠及 daemon / rofi 滑块 / 单次 CLI。
# 输出名即文件名 (与 monitor-<output> state 文件同约定); 原子 tmp+mv 写防撕裂。
_ddc_bus_cache_file() { printf '%s/.local/state/dwm/ddc-bus-%s' "$HOME" "$1"; }

# 返回 ddcutil --bus 可用的整数总线号 (经 xrandr CONNECTOR_ID ↔ ddcutil drm_connector_id 匹配)
# DP 显示器 DDC/CI 走 aux 总线，故不能直接读 /sys/class/drm/*/ddc 的 symlink
get_ddc_bus() {
    local output="$1"
    local mset cf cset cbus bus cid
    mset=$(xrandr --listactivemonitors 2>/dev/null | awk 'NR>1 {print $NF}' | sort | tr '\n' ' ')
    cf=$(_ddc_bus_cache_file "$output")
    if [ -f "$cf" ]; then
        IFS='|' read -r cset cbus <"$cf"
        if [ -n "$cbus" ] && [ "$cset" = "$mset" ]; then
            printf '%s' "$cbus"
            return 0
        fi
    fi

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

    bus=$(ddcutil detect --brief 2>/dev/null |
        awk -v cid="$cid" '
            /^[[:space:]]*Display [0-9]+$/ {
                valid = 1
                next
            }
            /^[[:space:]]*Invalid display/ {
                valid = 0
                next
            }
            /^[[:space:]]*I2C bus:/ {
                bus = $NF
                sub(/^\/dev\/i2c-/, "", bus)
                next
            }
            # detect 可能把 DDC 可用的显示器误标为 Invalid
            # (如 DP 经 aux 总线时 slave 0x37 探测失败, 但 getvcp/setvcp 正常):
            # 优先有效条目, 无命中时回退到 Invalid 条目同 drm_connector_id 的总线
            /^[[:space:]]*drm_connector_id:/ && $NF == cid {
                if (valid && valid_bus == "") valid_bus = bus
                else if (!valid && invalid_bus == "") invalid_bus = bus
            }
            END {
                if (valid_bus != "") print valid_bus
                else if (invalid_bus != "") print invalid_bus
            }
        ')
    [[ -z "$bus" ]] && return 1
    mkdir -p "$(dirname "$cf")" && printf '%s|%s\n' "$mset" "$bus" >"$cf.tmp" && mv "$cf.tmp" "$cf"
    printf '%s' "$bus"
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

# 读取单块显示器当前亮度百分比 (eDP → brightnessctl, 其他 → DDC getvcp)
read_brightness() {
    local output="$1"
    if [[ $output =~ ^eDP ]]; then
        local v
        v=$(brightnessctl -m | cut -d',' -f4)
        printf '%s' "${v%\%}"
    else
        monitor_brightness "$output"
    fi
}

# 设置单块显示器亮度百分比 (eDP → brightnessctl, 其他 → DDC setvcp)
set_brightness() {
    local output="$1" value="$2"
    if [[ $output =~ ^eDP ]]; then
        brightnessctl set "${value}%" >/dev/null
    else
        monitor_brightness "$output" "$value"
    fi
}
