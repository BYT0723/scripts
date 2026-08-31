# Icons initial
declare -A icons
icons["cpu"]=""
icons["temp"]=""
icons["memory"]=""
icons["disk"]=""
icons["mail"]="󰇮"
icons["mpd"]=""
icons["notification"]=""
icons["rss"]=""
icons["sing-box"]=""
icons["volume"]=""
icons["volume_off"]=""
icons["volume_mute"]=""

print_date() {
    if [ -f "$HOME/.local/state/dwm/status/date-collapse" ]; then
        date '+%R'
        # date '+'${timeIcons[$((hour % 12))]}' %R'
    else
        date '+%m/%d(%a) %R'
        # date '+ %m/%d(%a) '${timeIcons[$((hour % 12))]}' %R'
        # date '+ %Y-%m-%d(%a) '${timeIcons[$((hour % 12))]}' %R'
    fi
}

print_battery() {
    [ -z "$(command -v acpi)" ] && {
        system-notify critical "Tool Not Found" "please install acpi"
        return
    }

    local status percent fg
    IFS='|' read -r status percent < <(acpi -b | awk -F': |, |%' 'NR==1 {print $2 "|" $3}')
    [ -z "$percent" ] && return

    if [[ "$status" == "Discharging" ]]; then
        ((percent >= 20)) && fg="$white" || fg="$red"
    else
        fg="$green"
    fi

    local x=8 y=11 w=18 h=10 border=1 padding=1
    # 端子宽高
    local rw=2 rh=$((h * 60 / 100))
    # 电池内部宽度
    local inside_w=$((w - rw - 2 * border))
    # 当前电量宽度 (四舍五入)
    local remain_w=$(((inside_w * percent + 50) / 100))

    # 防止低电量时减去 padding 后出现负宽度
    local fill_w=$((remain_w - 2 * padding))
    ((fill_w < 0)) && fill_w=0

    # 端子凸起
    printf '^r%d,%d,%d,%d^' \
        "$x" \
        "$((y + (h - rh) / 2))" \
        "$rw" \
        "$rh"

    # 电池主体外框
    printf '^r%d,%d,%d,%d^' \
        "$((x + rw))" \
        "$y" \
        "$((w - rw))" \
        "$h"

    # 内部背景
    printf '^c%s^' "$black"
    printf '^r%d,%d,%d,%d^' \
        "$((x + rw + border))" \
        "$((y + border))" \
        "$inside_w" \
        "$((h - 2 * border))"

    # 电量
    printf '^c%s^' "$fg"
    printf '^r%d,%d,%d,%d^' \
        "$((x + rw + border + padding + inside_w - remain_w))" \
        "$((y + border + padding))" \
        "$fill_w" \
        "$((h - 2 * border - 2 * padding))"

    printf '^d^^f%d^' "$((w + 2 * x))"
}

print_volume() {
    [ -z "$(command -v amixer)" ] && system-notify critical "Tool Not Found" "please install alsa-utils" && return

    read volume status < <(amixer get Master | awk -F'[][]' 'END{gsub(/%/,"",$2); print $2, $4}')

    if [ "$status" == "off" ]; then
        fg="$red"
        icon=${icons[volume_mute]}
    elif [ "$volume" -eq 0 ]; then
        fg="$yellow"
        icon=${icons[volume_off]}
    else
        fg="$white"
        icon=${icons[volume]}
    fi
    printf "^c$fg^$icon"
    # printf "%s %2d" $icon $volume
}

print_brightness() {
    # 获取第一个 backlight 设备
    local dev
    dev=$(ls /sys/class/backlight | head -n1) || return

    # 读取当前亮度和最大亮度
    local cur max percent
    cur=$(cat /sys/class/backlight/"$dev"/brightness)
    max=$(cat /sys/class/backlight/"$dev"/max_brightness)

    # 计算百分比
    percent=$((100 * cur / max))

    # 输出图标 + 百分比
    local icon="󰃟"
    printf "%s %2d%%" "$icon" "$percent"
}

print_wifi() {
    local wifi=$(iwgetid -r)
    local icon="󰖩"

    [ -z "$wifi" ] && icon="󰖪"

    printf "%s %s" $icon $wifi
}

# Disk free space size
print_disk() {
    local mountpoint=$1
    read avail usage < <(df -h "${mountpoint}" | awk 'NR==2 {gsub(/%/,"",$5);print $4" "$5}')
    local fg="$white"

    [ "$usage" -gt 90 ] && fg="$yellow"
    # output
    printf "^c$fg^${icons[disk]} $avail"
}

# Memory usage
print_mem() {
    read mem_usage mem_used < <(
        awk '
        /MemTotal:/     {total=$2}
        /MemAvailable:/ {avail=$2}
        END {
            used = total - avail
            usage = 100 * used / total
            printf "%d %f", usage, used/1024/1024
        }' /proc/meminfo
    )
    fg="$white"

    [ "$mem_usage" -gt 90 ] && fg="$yellow"
    printf "^c$fg^${icons[memory]}%5.2fG" $mem_used
}

print_cpu() {
    read cpu_usage <"$cpu_usage_path"
    fg=$white

    ((cpu_usage >= 80)) && fg="$yellow"

    # output
    printf "^c$fg^${icons[cpu]}%3d%%" "$cpu_usage"
}

cpu_temperature_filepath=""

print_temperature() {
    if [ -z "$cpu_temperature_filepath" ]; then
        vendor=$(awk '$1=="vendor_id" {print $3;exit}' /proc/cpuinfo)
        case $vendor in
        "GenuineIntel")
            cpu_temperature_filepath=$(awk '$1=="x86_pkg_temp" {sub("/[^/]+$","",FILENAME); print FILENAME}' /sys/class/thermal/thermal_zone*/type)"/temp"
            ;;
        "AuthenticAMD")
            cpu_temperature_filepath=$(awk '$1=="k10temp" {sub("/[^/]+$","",FILENAME); print FILENAME}' /sys/class/hwmon/hwmon*/name)"/temp1_input"
            ;;
        *)
            system-notify critical "[DWM STATUS BAR] Unsupported Arch" "unsupported arch $vendor to get cpu temperature" && return
            ;;
        esac
    fi

    read temp <"$cpu_temperature_filepath"
    temp=$((temp / 1000))

    fg=$white

    [ $temp -ge 70 ] && fg="$yellow"

    printf "^c$fg^${icons["temp"]} ${temp}°C"
}

max_len_output() {
    local input=$1
    local len=${2:-16}
    [ ${#input} -le $len ] && printf "%s" "$input" || printf "%s..." "${input:0:len-3}"
}

print_weather() {
    read -r weather <"$weather_path"
    [ -n "$weather" ] && max_len_output "$weather"
}

# Music Player Daemon
print_mpd() {
    [ ! -f "$mpd_status_path" ] && return

    IFS='|' read songname state <"$mpd_status_path"

    local fg="$white"

    # mpd play status
    [[ $state == "playing" ]] && fg="$blue"

    if [ $mpd_single_pane -gt 0 ]; then
        max_len_output "${icons[mpd]} $songname"
    else
        printf "^c$fg^${icons[mpd]}"
    fi
}

human_speed() {
    local bytes=$1

    if ((bytes < 1024)); then
        printf "%5d B/s" "$bytes"
    elif ((bytes < 1024000)); then
        printf "%5.1f K/s" "$(bc -l <<<"$bytes/1024")"
    else
        printf "%5.1f M/s" "$(bc -l <<<"$bytes/1024000")"
    fi
}

# Network traffic
print_speed() {
    read rx <"$traffic_rx_path"
    read tx <"$traffic_tx_path"
    # output
    printf " "
    human_speed $rx
    printf "  "
    human_speed $tx
}

print_mail() {
    read unread <"$mail_unread_path"
    (($unread > 0)) && printf "^c$yellow^${icons[mail]} $unread"
}

print_rss() {
    read unread <"$rss_unread_path"
    [ -z "$unread" ] && return
    (($unread > 0)) && printf "^c$yellow^${icons[rss]} $unread"
}

print_singbox() {
    pgrep sing-box >/dev/null && printf "^c$white^${icons["sing-box"]}"
}

print_notification() {
    unread=$(dunstctl count history)
    ((unread > 0)) && printf "^c$yellow^${icons[notification]} $unread"
}

print_screencast() {
    local pid_f="/tmp/screencaster_pid"
    local pid
    [ ! -f "$pid_f" ] && return
    read -r pid </tmp/screencaster_pid 2>/dev/null || return
    kill -0 "$pid" 2>/dev/null && printf "^c$red^󰑊"
}
