#!/usr/bin/env bash

ROFI_DIR="$(dirname "$(dirname "$0")")"
WORK_DIR="$(dirname "$ROFI_DIR")"

MODULE_THEME="$ROFI_DIR/applets/type-1/style-2.rasi"
MODULE_WIDTH=550
MODULE_NAME="󰄟 Scrcpy"
MODULE_SEARCH_BAR="true"
MODULE_FONT="JetBrains Mono Nerd Font 14"

source "$(dirname "${BASH_SOURCE[0]}")"/util.sh
source "$(dirname "${BASH_SOURCE[0]}")"/lib-module.sh
source "$WORK_DIR/utils/notify.sh"

# --mouse-bind 默认 bhsn:++++, 首位改 - 禁用右键→BACK (右键忽略, Shift+点击仍直通设备)
SCRCPY_FLAGS=" \
--video-codec=h265 \
--video-bit-rate=8M \
--max-size=1600 \
--max-fps=60 \
--audio-buffer=200 \
--shortcut-mod=lalt \
--keyboard=uhid \
--mouse-bind=-hsn:++++ \
--turn-screen-off \
--power-off-on-close \
"

# scrcpy 窗口聚焦时的按键映射: X11 keysym 名 → 滑动方向 (up/down/back)
# 键名用 `xmodmap -pke` 查; 换键只改这张表, 逻辑不用动
declare -A SCRCPY_KEYMAP=(
    [Up]=down
    [Down]=up
    [Left]=back
)

_sanitize_key() {
    echo "$1" | tr -c '[:alnum:]' '_'
}

_device_pid_file() {
    echo "/tmp/scrcpy_pid_$(_sanitize_key "$1")"
}

_scrcpy_keys_pid_file() {
    echo "/tmp/scrcpy_keys_$(_sanitize_key "$1")"
}

_check_deps() {
    if ! command -v adb &>/dev/null; then
        tool-notify critical "Scrcpy" "adb not found. Please install android-tools."
        exit 1
    fi
    if ! command -v scrcpy &>/dev/null; then
        tool-notify critical "Scrcpy" "scrcpy not found."
        exit 1
    fi
}

_filter_dup_devices() { # stdin serial|label 行 → 同一手机手动+自动两个 entry 只留手动连的行
    local lines=$(cat)
    local serial label wserials=()
    while IFS='|' read -r serial label; do
        if [[ "$serial" == *._adb-tls-connect._tcp || "$serial" =~ ^[0-9]+\.[0-9.]+:[0-9]+$ ]]; then
            wserials+=("$serial")
        fi
    done <<<"$lines"
    if [ "${#wserials[@]}" -lt 2 ]; then
        printf '%s\n' "$lines"
        return
    fi
    # 按硬件序列号分组 (广播时有时无, ro.serialno 稳定; timeout 防挂, 拿不到的不参与合并)
    declare -A _sn_of=() _sn_has_plain=()
    local s sn
    for s in "${wserials[@]}"; do
        sn=$(timeout 3 adb -s "$s" shell getprop ro.serialno </dev/null 2>/dev/null | tr -d '\r')
        [ -z "$sn" ] && continue
        [ "$sn" = "unknown" ] && continue
        _sn_of[$s]=$sn
        [[ "$s" == *:* && "$s" != *._adb-tls-connect._tcp ]] && _sn_has_plain[$sn]=1
    done
    while IFS='|' read -r serial label; do
        if [[ "$serial" == *._adb-tls-connect._tcp ]] && [ -n "${_sn_of[$serial]:-}" ] && [ -n "${_sn_has_plain[${_sn_of[$serial]}]:-}" ]; then
            continue
        fi
        printf '%s|%s\n' "$serial" "$label"
    done <<<"$lines"
}
_short_serial() { # $1=serial → 去 adb- 前缀和 ._adb-tls-connect._tcp 后缀
    local s="$1"
    s="${s#adb-}"
    s="${s%._adb-tls-connect._tcp}"
    printf '%s' "$s"
}

_get_devices() { # 输出双列: serial|label (label 是显示文本, 首列供 _device_map 取键)
    adb devices -l </dev/null 2>/dev/null | grep -w device | while read -r serial _ rest; do
        local model=$(echo "$rest" | grep -oP 'model:\K\S+')
        if [[ "$serial" == *._adb-tls-connect._tcp || "$serial" == *:* ]]; then
            local friendly=$(_device_friendly_name "$serial")
            local short=$(_short_serial "$serial") # 纯 ip:port 无前后缀可去, 原样返回
            if [ -n "$friendly" ]; then
                echo "${serial}|${friendly} (${short})"
            elif [ -n "$model" ]; then
                echo "${serial}|${short} (${model//_/ })"
            else
                echo "${serial}|${short}"
            fi
        else
            [ -n "$model" ] && echo "${serial}|${serial} (${model//_/ })" || echo "${serial}|${serial}"
        fi
    done
}

_device_friendly_name() { # $1=serial → 用户起的设备名, 拿不到返回空
    local serial="$1" name=""
    if command -v timeout &>/dev/null; then
        name=$(timeout 3 adb -s "$serial" shell settings get global device_name </dev/null 2>/dev/null | tr -d '\r')
        if [ -z "$name" ] || [ "$name" = "null" ]; then
            name=$(timeout 3 adb -s "$serial" shell getprop ro.product.model </dev/null 2>/dev/null | tr -d '\r')
        fi
    fi
    printf '%s' "$name"
}

_mdns_scan() { # 局域网 mDNS 发现, 输出三列: name|type|addr
    adb mdns check </dev/null >/dev/null 2>&1 || return 1
    adb mdns services </dev/null 2>/dev/null | tail -n +2 | awk '
        NF >= 3 && $(NF-1) ~ /^_adb-tls-(connect|pairing)\._tcp$/ {
            addr = $NF; type = $(NF-1); NF -= 2; print $0"|"type"|"addr
        }'
}

_is_device_connected() {
    local pid_file=$(_device_pid_file "$1")
    if [ -f "$pid_file" ]; then
        kill -0 "$(cat "$pid_file")" 2>/dev/null && return 0
        rm -f "$pid_file"
    fi
    return 1
}

_display_rotation() { # $1=serial → 0..3 当前旋转 (1/3 为横屏), 拿不到回 0
    local serial="$1" dump override rot w h
    dump=$(adb -s "$serial" shell dumpsys display </dev/null 2>/dev/null | tr -d '\r')
    [ -n "$dump" ] || {
        printf '0'
        return
    }
    # 首选 displayId 0 的 mOverrideDisplayInfo 行 (当前生效值; mBase/displayShape 是静态值不可信,
    # 曾误命中 displayShape{... rotation=0 ...} 导致横屏判 0)
    override=$(printf '%s\n' "$dump" | grep -E 'mOverrideDisplayInfo=.*displayId 0([^0-9]|$)' | head -n1)
    if [ -n "$override" ]; then
        # `, app 2670 x 1200,` 即当前方向尺寸, 宽>高即横屏 (1/3 不区分, _swipe 只关心换不换)
        if [[ "$override" =~ ,\ app\ ([0-9]+)\ x\ ([0-9]+), ]]; then
            w=${BASH_REMATCH[1]}
            h=${BASH_REMATCH[2]}
            if [ "$w" -gt "$h" ]; then
                printf '1'
            else
                printf '0'
            fi
            return
        fi
        rot=$(printf '%s\n' "$override" | grep -Eo 'rotation [0-3]' | head -n1 | grep -Eo '[0-3]')
        if [[ "$rot" =~ ^[0-3]$ ]]; then
            printf '%s' "$rot"
            return
        fi
    fi
    # 回退老格式 (部分 ROM 的 mCurrentRotation= 行)
    rot=$(printf '%s\n' "$dump" | grep -Eo '(mCurrentRotation|rotation)=[0-3]' | head -n1 | grep -Eo '[0-3]')
    [[ "$rot" =~ ^[0-3]$ ]] && printf '%s' "$rot" || printf '0'
}

_swipe() { # $1=serial $2=up|down|back: 单指滑动 (up/down 短视频上下切换, 25%~75%; back 左边缘右滑返回, x 5%→40%, y 50%)
    local serial="$1" dir="$2" size w h x y1 y2 rot tmp x1 x2 y
    size=$(adb -s "$serial" shell wm size </dev/null 2>/dev/null | tr -d '\r' |
        awk -F': ' '/Override size/ {o=$2} /Physical size/ {p=$2} END {print (o ? o : p)}')
    [[ "$size" =~ ^([0-9]+)x([0-9]+)$ ]] || return 1
    w=${BASH_REMATCH[1]}
    h=${BASH_REMATCH[2]}
    # wm size 是自然方向尺寸, 不随旋转变化; input 坐标系随旋转变化, 横屏时交换 w/h
    rot=$(_display_rotation "$serial")
    if [[ "$rot" == 1 || "$rot" == 3 ]]; then
        tmp=$w
        w=$h
        h=$tmp
    fi
    x=$((w / 2))
    case "$dir" in
        up) y1=$((h * 3 / 4)); y2=$((h / 4)) ;;
        down) y1=$((h / 4)); y2=$((h * 3 / 4)) ;;
        back) x1=$((w / 20)); x2=$((w * 2 / 5)); y=$((h / 2)) ;;
        *) return 1 ;;
    esac
    if [[ "$dir" == back ]]; then
        adb -s "$serial" shell input swipe "$x1" "$y" "$x2" "$y" 200 </dev/null >/dev/null 2>&1
    else
        adb -s "$serial" shell input swipe "$x" "$y1" "$x" "$y2" 200 </dev/null >/dev/null 2>&1
    fi
}

_watch_scrcpy_keys() { # $1=serial $2=scrcpy pid: 只在 scrcpy 窗口聚焦时按 SCRCPY_KEYMAP 转成滑动
    local serial="$1" pid="$2" wid="" i line rc etype latch="" state ksym dir pid_file
    command -v xev >/dev/null 2>&1 && command -v xdotool >/dev/null 2>&1 || return
    for i in $(seq 1 50); do
        # xdotool search 默认 --any, 必须 --all, 否则 --pid 条件不生效
        wid=$(xdotool search --all --onlyvisible --pid "$pid" --class scrcpy 2>/dev/null | head -n1)
        [ -n "$wid" ] && break
        kill -0 "$pid" 2>/dev/null || return
        sleep 0.2
    done
    [ -z "$wid" ] && return
    pid_file=$(_scrcpy_keys_pid_file "$serial")
    echo "$BASHPID" >"$pid_file"

    coproc XEV { exec xev -id "$wid" -event keyboard 2>/dev/null; }
    # 退出时带走 xev (coproc 的 exec 保证 XEV_PID 就是 xev), 并清理自己的 pid 文件
    trap 'kill "$XEV_PID" 2>/dev/null; [ "$(cat "$pid_file" 2>/dev/null)" = "$BASHPID" ] && rm -f "$pid_file"' EXIT
    trap 'exit 1' TERM INT HUP
    while kill -0 "$pid" 2>/dev/null; do
        IFS= read -r -t 2 -u "${XEV[0]}" line
        rc=$?
        if [ "$rc" -gt 0 ]; then
            [ "$rc" -gt 128 ] || break # 超时继续等, EOF (xev 退出) 结束
            continue
        fi
        case "$line" in
            KeyPress*) etype=press ;;
            KeyRelease*) etype=release; latch="" ;;
        esac
        [ "$etype" = press ] || continue
        [[ "$line" =~ state\ (0x[0-9a-fA-F]+),\ keycode\ [0-9]+\ \(keysym\ 0x[0-9a-fA-F]+,\ ([A-Za-z0-9_]+)\) ]] || continue
        state=$((BASH_REMATCH[1]))
        ksym=${BASH_REMATCH[2]}
        dir=${SCRCPY_KEYMAP[$ksym]:-}
        [ -n "$dir" ] || continue
        [ -z "$latch" ] || continue
        ((state & ~0x13)) && continue # 带 Ctrl/Alt/Super 的组合留给 scrcpy/app 自己 (0x13 = Shift|Lock|Mod2)
        latch=1
        _swipe "$serial" "$dir"
    done
}

_connect() {
    local serial="$1"
    nohup scrcpy ${SCRCPY_FLAGS} -s "$serial" >/dev/null 2>&1 &
    local pid=$!
    echo "$pid" >"$(_device_pid_file "$serial")"
    _watch_scrcpy_keys "$serial" "$pid" </dev/null >/dev/null 2>&1 &
    _quit=1 # scrcpy 已起, 退出菜单 (其余 handler 返回后回到上级菜单)
}

_disconnect() {
    local pid_file=$(_device_pid_file "$1") keys_pid_file=$(_scrcpy_keys_pid_file "$1")
    if [ -f "$keys_pid_file" ]; then
        kill "$(cat "$keys_pid_file")" 2>/dev/null
        rm -f "$keys_pid_file"
    fi
    if [ -f "$pid_file" ]; then
        kill "$(cat "$pid_file")" 2>/dev/null
        rm -f "$pid_file"
    fi
}

_check_deps

_connect_addr() { # $1=addr: adb connect + 通知 + 起 scrcpy
    local connect_addr="$1"
    if ! adb connect "$connect_addr" </dev/null 2>/dev/null; then
        tool-notify critical "Scrcpy" "Connect failed."
        return 1
    fi
    local friendly=$(_device_friendly_name "$connect_addr")
    if [ -n "$friendly" ]; then
        tool-notify normal "Scrcpy" "Connected: $friendly ($connect_addr)"
    else
        tool-notify normal "Scrcpy" "Connected: $connect_addr"
    fi

    _connect "$connect_addr"
}

handle_lan_scan() {
    local scan
    if ! scan=$(_mdns_scan); then
        tool-notify critical "Scrcpy" "mDNS discovery unavailable."
        return
    fi

    # 只列 pairing 广播: 没配对的设备点 connect 鉴权必失败;
    # 已配对的设备在线会自动连上 (第一层菜单), 掉线重连走手动输入
    local menu="" name type addr
    while IFS='|' read -r name type addr; do
        [ "$type" = "_adb-tls-pairing._tcp" ] || continue
        [ -z "$addr" ] && continue
        menu+="$addr"$'\n'
    done <<<"$scan"

    if [ -z "$menu" ]; then
        tool-notify normal "Scrcpy" "No pairable devices found. Open 'Pair device with pairing code' on your phone."
        return
    fi

    local chosen=$(printf '%s' "$menu" | module_sub_rofi "Scan LAN" "Pairing address shown on your phone")
    [[ -z "$chosen" ]] && return

    addr="${chosen%% *}"
    local pair_name=$(printf '%s\n' "$scan" | awk -F'|' -v a="$addr" '$3 == a && $2 == "_adb-tls-pairing._tcp" {print $1; exit}')
    _pair_with_addr "$addr" "$pair_name"
}

handle_wireless_connect() {
    local connect_addr=$(module_input "Device Address" "IP and port from Wireless Debugging screen")
    [[ -z "$connect_addr" ]] && return

    _connect_addr "$connect_addr"
}

_pair_with_addr() { # $1=pair addr [$2=pair name]: 问码 → pair → 同 IP 直连/新连直起/已连直起/回退手动
    local pair_addr="$1" pair_name="${2:-}"
    local before=" $(adb devices </dev/null 2>/dev/null | awk 'NR > 1 && $2 == "device" {print $1}' | tr '\n' ' ') "
    local pair_code=$(module_input "Pairing Code" "6-digit code displayed on your device")
    [[ -z "$pair_code" ]] && return

    if ! adb pair "$pair_addr" "$pair_code" </dev/null 2>/dev/null; then
        tool-notify critical "Scrcpy" "Pairing failed."
        return
    fi
    tool-notify normal "Scrcpy" "Paired: $pair_addr"

    # 配对/连接广播实例名未必相同, 同 IP 才是同一台手机 (仅 IPv4 形如 1.2.3.4:port)
    local pair_ip=""
    [[ "$pair_addr" =~ ^[0-9]+\.[0-9.]+:[0-9]+$ ]] && pair_ip="${pair_addr%:*}"
    if [ -n "$pair_ip" ]; then
        local conn_addr=$(printf '%s\n' "$(_mdns_scan 2>/dev/null)" | awk -F'|' -v ip="$pair_ip" '$2 == "_adb-tls-connect._tcp" && index($3, ip ":") == 1 {print $3; exit}')
        if [ -n "$conn_addr" ]; then
            _connect_addr "$conn_addr"
            return
        fi
    fi
    # 配对期间新出现的无线设备 (adb 已自动连上, 广播随之消失): 恰好一个才用
    local serial new_serial="" new_count=0
    for serial in $(adb devices </dev/null 2>/dev/null | awk 'NR > 1 && $2 == "device" && $1 ~ /_adb-tls-connect\._tcp$/ {print $1}'); do
        [[ "$before" == *" $serial "* ]] && continue
        new_serial="$serial"
        new_count=$((new_count + 1))
    done
    if [ "$new_count" = 1 ]; then
        local friendly=$(_device_friendly_name "$new_serial")
        tool-notify normal "Scrcpy" "Connected: ${friendly:-$new_serial}"
        _connect "$new_serial"
        return
    fi
    if [ -n "$pair_name" ]; then
        local serial="${pair_name}._adb-tls-connect._tcp"
        if adb devices </dev/null 2>/dev/null | awk -v s="$serial" 'NR > 1 && $1 == s && $2 == "device" {found=1} END {exit !found}'; then
            local friendly=$(_device_friendly_name "$serial")
            tool-notify normal "Scrcpy" "Connected: ${friendly:-$serial}"
            _connect "$serial"
            return
        fi
    fi

    handle_wireless_connect
}

handle_wireless_pair() {
    local pair_addr=$(module_input "Pairing Address" "IP and port shown in pairing section")
    [[ -z "$pair_addr" ]] && return

    _pair_with_addr "$pair_addr"
}

_build_menu() { # 组菜单 + 派发 handler (每轮重建, 状态实时); 被 main() 循环调用
devices=$(_get_devices | _filter_dup_devices)

declare -A _device_map
menu_lines=""

if [ -n "$devices" ]; then
    while IFS='|' read -r serial label; do
        [ -z "$serial" ] && continue
        key="device_$(_sanitize_key "$serial")"
        _device_map[$key]="$serial"

        if _is_device_connected "$serial"; then
            icon=""
        else
            icon=""
        fi

        printf -v _line "%s|%s|%s|\n" "$key" "$icon" "$label"
        menu_lines+="$_line"
    done <<<"$devices"
fi

printf -v _line "%s|%s|%s|\n" "lan-scan" "󰈀" "Scan LAN"
menu_lines+="$_line"
printf -v _line "%s|%s|%s|\n" "wireless-connect" "󰈀" "Wireless Connect"
menu_lines+="$_line"
printf -v _line "%s|%s|%s|\n" "wireless-pair" "󰐺" "Pair New Device"
menu_lines+="$_line"

module_parse <<<"$menu_lines"

connected=0
for key in "${!_device_map[@]}"; do
    serial="${_device_map[$key]}"
    esc_serial="${serial//\'/\'\\\'\'}" # serial 进 eval 单引号, 先转义 (名来自 adb, 不可信)
    if _is_device_connected "$serial"; then
        eval "handle_${key}() { _disconnect '${esc_serial}'; }"
        ((connected++))
    else
        eval "handle_${key}() { _connect '${esc_serial}'; }"
    fi
done

if [ "$connected" -gt 0 ]; then
    MODULE_MESG="$connected device(s) connected"
else
    MODULE_MESG="Select device or connect wirelessly"
fi
}

main() {
    _quit=""
    while [ -z "$_quit" ]; do
        _build_menu
        module_loop || break
    done
}

[ -z "$SCRCPY_NO_DISPATCH" ] && main
