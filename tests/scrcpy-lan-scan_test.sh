#!/usr/bin/env bash
# rofi/scripts/scrcpy.sh Scan LAN 回归测试:
#   A. _mdns_scan 解析三列 name|type|addr, 跳过表头/空行/脏行 (name 含空格保留)
#   B. `adb mdns check` 失败 → _mdns_scan 非 0 且无输出
#   C. _get_devices 不再过滤 `._adb-tls-connect._tcp` (自动连上的无线设备可见)
#   D. 扫描为空 → notify 提示, 不弹子菜单
#   E. connect 类型 → `adb connect` + 起 scrcpy
#   F. pairing 类型 → 跳过地址输入直问配对码 → `adb pair` → 走手动 connect
#   G. 已在 `adb devices` 中的 connect 条目去重, 不进子菜单
#   H. check 失败时 handle_lan_scan 直接 notify, 不弹子菜单
#   S. 静态: 主菜单含 lan-scan 注册行 + SCRCPY_NO_DISPATCH 测试缝
#
# 背景: 原 _get_devices() 用 `grep -v '_adb-tls-connect'` 把 mDNS 自动发现的
# 已连设备过滤掉; 无线连接全靠手填 IP:端口。`adb mdns services` 实测 ~20ms
# 返回局域网 `_adb-tls-connect._tcp` / `_adb-tls-pairing._tcp` 广播。
#
# 因 scrcpy.sh 顶层直接跑菜单 (module_loop 阻塞), 测试用 SCRCPY_NO_DISPATCH=1
# source (缝的实现抄 dwm-windowhook.sh 的 WINDOWHOOK_NO_DISPATCH=1 先例);
# module_sub_rofi/module_input 用函数 double 覆盖 (抄
# rofi-theme-monitor-brightness_test.sh 思路)。
# 运行: bash tests/scrcpy-lan-scan_test.sh

REPO="$(cd "$(dirname "$0")/.." && pwd)"
SCRCPY_SH="$REPO/rofi/scripts/scrcpy.sh"
TEST_DIR=$(mktemp -d)
export TEST_DIR
export HOME="$TEST_DIR/home"
mkdir -p "$HOME/.config/dwm" "$HOME/.local/state/dwm"

# ---- mock 外部命令 ----
BIN="$TEST_DIR/bin"
mkdir -p "$BIN"

cat >"$BIN/adb" <<'EOF'
#!/usr/bin/env bash
echo "adb $*" >>"$MOCK_LOG"
target=""
if [ "$1" = "-s" ]; then target="$2"; shift 2; fi
case "$1" in
mdns)
    case "$2" in
    check)
        [ -n "$ADB_MDNS_CHECK_FAIL" ] && exit 1
        echo "mdns daemon version test"
        exit 0
        ;;
    services)
        cat "$ADB_MDNS_SERVICES"
        exit 0
        ;;
    esac
    ;;
devices)
    if [ -f "$TEST_DIR/paired.flag" ] && [ -n "$ADB_DEVICES_AFTER" ] && [ -f "$ADB_DEVICES_AFTER" ]; then
        cat "$ADB_DEVICES_AFTER"
    else
        cat "$ADB_DEVICES"
    fi
    exit 0
    ;;
connect)
    [ -n "$ADB_CONNECT_FAIL" ] && exit 1
    echo "already connected to $2"
    exit 0
    ;;
shell)
    shift
    cat >/dev/null # 像真 adb 一样吃掉 stdin (回归: while read 循环里调 adb 不得吞行)
    if [ "$1" = "settings" ]; then
        printf '%s' "$ADB_SHELL_DEVICE_NAME"
    elif [ "$1" = "getprop" ]; then
        if [ "$2" = "ro.serialno" ]; then
            case "$target" in
            *OTHER*) printf '%s' "${ADB_SHELL_SERIALNO_OTHER:-SN-OTHER}" ;;
            *) printf '%s' "$ADB_SHELL_SERIALNO" ;;
            esac
        else
            printf '%s' "$ADB_SHELL_MODEL"
        fi
    fi
    exit 0
    ;;
pair)
    [ -n "$ADB_PAIR_FAIL" ] && exit 1
    touch "$TEST_DIR/paired.flag"
    echo "Successfully paired to $2"
    exit 0
    ;;
esac
exit 0
EOF

cat >"$BIN/notify-send" <<'EOF'
#!/usr/bin/env bash
echo "notify-send $*" >>"$MOCK_LOG"
EOF

cat >"$BIN/scrcpy" <<'EOF'
#!/usr/bin/env bash
echo "scrcpy $*" >>"$MOCK_LOG"
EOF

cat >"$BIN/rofi" <<'EOF'
#!/usr/bin/env bash
echo "rofi CALLED (should be stubbed)" >>"$MOCK_LOG"
exit 1
EOF

chmod +x "$BIN"/*
export PATH="$BIN:$PATH"
export MOCK_LOG="$TEST_DIR/log"
: >"$MOCK_LOG"
export ADB_MDNS_SERVICES="$TEST_DIR/services.txt"
export ADB_DEVICES="$TEST_DIR/devices.txt"

set_devices() { printf '%s\n' "$1" >"$ADB_DEVICES"; }
set_services() { printf '%s\n' "$1" >"$ADB_MDNS_SERVICES"; }

DEFAULT_DEVICES='List of devices attached
emulator-5554	device product:sdk model:Pixel_8 device:emu64
adb-ABC123-JK._adb-tls-connect._tcp	device product:dada model:24129PN74C device:dada transport_id:1'

DEFAULT_SERVICES='List of discovered mdns services
adb-ABC123-JK	_adb-tls-connect._tcp	192.168.1.5:1111
Pixel8	_adb-tls-connect._tcp	192.168.1.20:2222
My Phone	_adb-tls-pairing._tcp	192.168.1.30:3333
badline-with-two-cols'

# ---- 加载被测脚本 (顶层菜单被 SCRCPY_NO_DISPATCH 跳过) ----
# 预置 stub: 若 lib-module.sh 因 $0 路径 source 失败 (实现前), 顶层仍能跑完不阻塞
module_parse() { :; }
module_loop() { return 1; }
export SCRCPY_NO_DISPATCH=1
# shellcheck disable=SC1090
source "$SCRCPY_SH"

module_sub_rofi() {
    cat >"$SUBMENU_GOT"
    printf '%s' "$SUBMENU_CHOICE"
}
module_input() {
    echo "input:$1" >>"$MOCK_LOG"
    case "$1" in
    "Pairing Code") printf '%s' "$PAIR_CODE" ;;
    "Device Address") printf '%s' "$CONNECT_ADDR" ;;
    "Pairing Address") printf '%s' "$PAIR_ADDR_MANUAL" ;;
    esac
}
export SUBMENU_GOT="$TEST_DIR/submenu.txt"
export SUBMENU_CHOICE="" PAIR_CODE="" CONNECT_ADDR="" PAIR_ADDR_MANUAL=""

fail=0
check() { # desc cond
    if eval "$2"; then
        echo "PASS: $1"
    else
        echo "FAIL: $1"
        fail=1
    fi
}
reset_state() {
    : >"$MOCK_LOG"
    rm -f "$SUBMENU_GOT"
    SUBMENU_CHOICE="" PAIR_CODE="" CONNECT_ADDR="" PAIR_ADDR_MANUAL=""
    unset ADB_MDNS_CHECK_FAIL ADB_CONNECT_FAIL ADB_PAIR_FAIL
    unset ADB_SHELL_DEVICE_NAME ADB_SHELL_MODEL ADB_SHELL_SERIALNO ADB_SHELL_SERIALNO_OTHER
    rm -f "$TEST_DIR/paired.flag"
    unset ADB_DEVICES_AFTER
    rm -f /tmp/scrcpy_pid_192_168_1_* /tmp/scrcpy_pid_10_0_0_*
}

cleanup() {
    rm -rf "$TEST_DIR"
    rm -f /tmp/scrcpy_pid_192_168_1_* /tmp/scrcpy_pid_10_0_0_*
}
trap cleanup EXIT

# ---- S: 静态接线 ----
check "S1 主菜单含 lan-scan 注册行" "grep -q '\"lan-scan\"' \"\$SCRCPY_SH\""
check "S2 SCRCPY_NO_DISPATCH 测试缝" "grep -q 'SCRCPY_NO_DISPATCH' \"\$SCRCPY_SH\""
check "S3 主循环持续交互 (空扫描 notify 后回上级菜单)" "grep -q 'while \[ -z \"\$_quit\" \]' \"\$SCRCPY_SH\" && grep -q 'module_loop || break' \"\$SCRCPY_SH\""
check "S4 起 scrcpy 后退出菜单" "grep -q '_quit=1' \"\$SCRCPY_SH\""
check "S5 通知一律走 utils/notify.sh (无裸 notify-send)" "! grep -q 'notify-send' \"\$SCRCPY_SH\""
check "S6 source utils/notify.sh" "grep -q 'utils/notify.sh' \"\$SCRCPY_SH\""

# ---- A: _mdns_scan 解析 ----
set_devices "$DEFAULT_DEVICES"
set_services "$DEFAULT_SERVICES"
scan_out=$(_mdns_scan)
check "A1 解析出 3 条 (脏行/空行跳过)" "[ \"\$(printf '%s\n' \"\$scan_out\" | grep -c .)\" = 3 ]"
check "A2 connect 条目三列正确" "printf '%s\n' \"\$scan_out\" | grep -qF 'Pixel8|_adb-tls-connect._tcp|192.168.1.20:2222'"
check "A3 含空格 name 的 pairing 条目保留" "printf '%s\n' \"\$scan_out\" | grep -qF 'My Phone|_adb-tls-pairing._tcp|192.168.1.30:3333'"

# ---- B: check 失败 ----
export ADB_MDNS_CHECK_FAIL=1
scan_out=$(_mdns_scan 2>/dev/null)
scan_rc=$?
check "B1 check 失败返回非 0" "[ \"$scan_rc\" != 0 ]"
check "B2 check 失败无输出" "[ -z \"$scan_out\" ]"
unset ADB_MDNS_CHECK_FAIL

# ---- C: _get_devices 不再过滤 mdns 设备 ----
check "C1 自动连上的无线设备在列表可见" "_get_devices | grep -qF 'adb-ABC123-JK._adb-tls-connect._tcp'"

# ---- D: 扫描为空 ----
reset_state
set_devices "$DEFAULT_DEVICES"
set_services 'List of discovered mdns services'
handle_lan_scan
check "D1 空结果 notify 提示" "grep -q 'notify-send.*No.*device' \"\$MOCK_LOG\""
check "D2 空结果不弹子菜单" "[ ! -f \"\$SUBMENU_GOT\" ]"

# ---- E: (已移除) 扫描子菜单不再列 connect 条目, 只留 pairing ----

# ---- F: pairing 跳地址直问码 ----
reset_state
set_devices "$DEFAULT_DEVICES"
set_services "$DEFAULT_SERVICES"
SUBMENU_CHOICE="192.168.1.30:3333"
PAIR_CODE="123456"
CONNECT_ADDR="192.168.1.20:2222"
handle_lan_scan
check "F1 跳过地址输入 (未问 Pairing Address)" "! grep -qF 'input:Pairing Address' \"\$MOCK_LOG\""
check "F2 问配对码" "grep -qF 'input:Pairing Code' \"\$MOCK_LOG\""
check "F3 adb pair 用扫描到的地址+码" "grep -qF 'adb pair 192.168.1.30:3333 123456' \"\$MOCK_LOG\""
check "F4 配对成功后走手动 connect" "grep -qF 'adb connect 192.168.1.20:2222' \"\$MOCK_LOG\""

# ---- G: 去重只留新设备 ----
reset_state
set_devices "$DEFAULT_DEVICES"
set_services "$DEFAULT_SERVICES"
SUBMENU_CHOICE=""
: >"$SUBMENU_GOT"
handle_lan_scan || true
check "G1 子菜单不含 connect 条目 (只留 pairing)" "! grep -qF '192.168.1.20:2222' \"\$SUBMENU_GOT\""
check "G2 子菜单 pairing 行是裸 addr" "grep -qFx '192.168.1.30:3333' \"\$SUBMENU_GOT\""
check "G3 子菜单只有 addr, 无实例名" "! grep -qE 'Pixel8|My Phone|adb-' \"\$SUBMENU_GOT\""

# ---- P: 配对成功后按同名 connect 广播直接连 ----
reset_state
set_devices "$DEFAULT_DEVICES"
set_services 'List of discovered mdns services
adb-P1AA-bb	_adb-tls-pairing._tcp	10.0.0.9:3333
adb-P1AA-bb	_adb-tls-connect._tcp	10.0.0.9:4444'
SUBMENU_CHOICE="10.0.0.9:3333"
PAIR_CODE="654321"
handle_lan_scan
check "P1 配对成功后直连同名 connect 地址" "grep -qF 'adb connect 10.0.0.9:4444' \"\$MOCK_LOG\""
check "P2 直连成功不问手动地址" "! grep -qF 'input:Device Address' \"\$MOCK_LOG\""

# ---- P3: 配对/连接广播名不一致时按同 IP 关联 ----
reset_state
set_devices "$DEFAULT_DEVICES"
set_services 'List of discovered mdns services
adb-DIFF-aa	_adb-tls-pairing._tcp	10.0.0.9:3333
adb-OTHER-bb	_adb-tls-connect._tcp	10.0.0.9:4444'
SUBMENU_CHOICE="10.0.0.9:3333"
PAIR_CODE="654321"
handle_lan_scan
check "P3 名不一致时按同 IP 直连" "grep -qF 'adb connect 10.0.0.9:4444' \"\$MOCK_LOG\""
check "P4 名不一致时不问手动地址" "! grep -qF 'input:Device Address' \"\$MOCK_LOG\""

# ---- Q: 同名 connect 广播缺失时回退手动输入 ----
reset_state
set_devices "$DEFAULT_DEVICES"
set_services 'List of discovered mdns services
adb-QQ00-zz	_adb-tls-pairing._tcp	10.0.0.9:3333'
SUBMENU_CHOICE="10.0.0.9:3333"
PAIR_CODE="654321"
CONNECT_ADDR="10.0.0.9:5555"
handle_lan_scan
check "Q1 无同名 connect 时回退手动输入" "grep -qF 'input:Device Address' \"\$MOCK_LOG\""
check "Q2 回退后连手动填的地址" "grep -qF 'adb connect 10.0.0.9:5555' \"\$MOCK_LOG\""

# ---- P5/P6: 广播名对不上但配对期间自动连上了 → 按新出现的设备直起 ----
reset_state
set_devices 'List of devices attached
emulator-5554	device product:sdk model:Pixel_8 device:emu64'
export ADB_DEVICES_AFTER="$TEST_DIR/devices_after.txt"
printf '%s\n' 'List of devices attached' \
    'emulator-5554	device product:sdk model:Pixel_8 device:emu64' \
    'adb-OTHER-bb._adb-tls-connect._tcp	device product:dada model:24129PN74C device:dada transport_id:1' \
    >"$ADB_DEVICES_AFTER"
set_services 'List of discovered mdns services
adb-DIFF-aa	_adb-tls-pairing._tcp	10.0.0.9:3333'
SUBMENU_CHOICE="10.0.0.9:3333"
PAIR_CODE="654321"
handle_lan_scan
check "P5 自动连上的新设备直接起 scrcpy" "grep -qF -- '-s adb-OTHER-bb._adb-tls-connect._tcp' \"\$MOCK_LOG\""
check "P6 不问手动地址" "! grep -qF 'input:Device Address' \"\$MOCK_LOG\""

# ---- R: 配对后已自动连上 (mdns 无 connect 广播, devices 有 serial) 则直起 ----
reset_state
set_devices 'List of devices attached
adb-RR11-tt._adb-tls-connect._tcp	device product:dada model:24129PN74C device:dada transport_id:1'
set_services 'List of discovered mdns services
adb-RR11-tt	_adb-tls-pairing._tcp	10.0.0.9:3333'
SUBMENU_CHOICE="10.0.0.9:3333"
PAIR_CODE="654321"
handle_lan_scan
check "R1 已自动连上时直接起 scrcpy" "grep -qF -- '-s adb-RR11-tt._adb-tls-connect._tcp' \"\$MOCK_LOG\""
check "R2 不问手动地址" "! grep -qF 'input:Device Address' \"\$MOCK_LOG\""

# ---- H: check 失败 ----
reset_state
set_devices "$DEFAULT_DEVICES"
set_services "$DEFAULT_SERVICES"
export ADB_MDNS_CHECK_FAIL=1
handle_lan_scan
check "H1 check 失败 notify 不可用" "grep -q 'notify-send.*mdns\\|notify-send.*discovery\\|notify-send.*unavailable' \"\$MOCK_LOG\""
check "H2 check 失败不弹子菜单" "[ ! -f \"\$SUBMENU_GOT\" ]"

# ---- N: 友好名 ----
export ADB_SHELL_DEVICE_NAME="My Phone"
check "N1 device_name 优先" "[ \"\$(_device_friendly_name 'adb-ABC123-JK._adb-tls-connect._tcp')\" = 'My Phone' ]"

export ADB_SHELL_DEVICE_NAME="null"
export ADB_SHELL_MODEL="Pixel 8"
check "N2 device_name 为 null 时回退 ro.product.model" "[ \"\$(_device_friendly_name 'adb-ABC123-JK._adb-tls-connect._tcp')\" = 'Pixel 8' ]"

export ADB_SHELL_DEVICE_NAME=$'My Phone\r'
unset ADB_SHELL_MODEL
check "N3 剥掉 adb shell 的回车" "[ \"\$(_device_friendly_name 'adb-ABC123-JK._adb-tls-connect._tcp')\" = 'My Phone' ]"

unset ADB_SHELL_DEVICE_NAME
unset ADB_SHELL_MODEL
check "N4 都拿不到时返回空" "[ -z \"\$(_device_friendly_name 'adb-ABC123-JK._adb-tls-connect._tcp')\" ]"

# ---- T: 主菜单无线设备显示友好名 (serial|label 双列, 首列仍是完整 serial) ----
reset_state
set_devices "$DEFAULT_DEVICES"
export ADB_SHELL_DEVICE_NAME="My Phone"
dev_line=$(_get_devices | grep -F 'adb-ABC123-JK._adb-tls-connect._tcp')
check "T1 无线设备行格式为 serial|友好名 (短id)" "[ \"\$dev_line\" = 'adb-ABC123-JK._adb-tls-connect._tcp|My Phone (ABC123-JK)' ]"
check "T2 首列是完整 serial" "[ \"\$(printf '%s\n' \"\$dev_line\" | cut -d'|' -f1)\" = 'adb-ABC123-JK._adb-tls-connect._tcp' ]"

unset ADB_SHELL_DEVICE_NAME
unset ADB_SHELL_MODEL
dev_line=$(_get_devices | grep -F 'adb-ABC123-JK._adb-tls-connect._tcp')
check "T3 无友好名时回退 短id (model)" "[ \"\$dev_line\" = 'adb-ABC123-JK._adb-tls-connect._tcp|ABC123-JK (24129PN74C)' ]"

dev_line=$(_get_devices | grep -F 'emulator-5554')
check "T4 USB 显示不变" "[ \"\$dev_line\" = 'emulator-5554|emulator-5554 (Pixel 8)' ]"

# ---- T5/T6: 手动 adb connect 的纯 ip:port serial 也显示友好名 ----
reset_state
set_devices 'List of devices attached
10.0.0.7:5555	device product:sdk model:Pixel_8 device:emu'
export ADB_SHELL_DEVICE_NAME="My Phone"
dev_line=$(_get_devices | grep -F '10.0.0.7:5555')
check "T5 纯 TCP 显示友好名 (ip:port)" "[ \"\$dev_line\" = '10.0.0.7:5555|My Phone (10.0.0.7:5555)' ]"

unset ADB_SHELL_DEVICE_NAME
unset ADB_SHELL_MODEL
dev_line=$(_get_devices | grep -F '10.0.0.7:5555')
check "T6 纯 TCP 无友好名时维持原样" "[ \"\$dev_line\" = '10.0.0.7:5555|10.0.0.7:5555 (Pixel 8)' ]"

# ---- W: 短 id 提取 ----
check "W1 去 adb- 前缀和 mdns 后缀" "[ \"\$(_short_serial 'adb-ABC123-JK._adb-tls-connect._tcp')\" = 'ABC123-JK' ]"
check "W2 非 mdns serial 原样返回" "[ \"\$(_short_serial 'emulator-5554')\" = 'emulator-5554' ]"

# ---- W3/W4: while read 循环里调 adb 不得吞掉后面的行 ----
reset_state
set_devices 'List of devices attached
adb-ABC123-JK._adb-tls-connect._tcp	device product:dada model:24129PN74C device:dada transport_id:1
emulator-5554	device product:sdk model:Pixel_8 device:emu64'
export ADB_SHELL_DEVICE_NAME="My Phone"
dev_all=$(_get_devices)
check "W3 无线行在前时后面的行不被吞" "printf '%s\n' \"\$dev_all\" | grep -qF 'emulator-5554|emulator-5554 (Pixel 8)'"
check "W4 无线行本身正常" "printf '%s\n' \"\$dev_all\" | grep -qF 'adb-ABC123-JK._adb-tls-connect._tcp|My Phone (ABC123-JK)'"

# ---- M1/M2/M3: 同一手机手动+自动两个 entry 只显示手动连的行 (按 ro.serialno 分组) ----
reset_state
export ADB_SHELL_SERIALNO="SN-PHONE"
dup_in='10.0.0.9:5555|Phone (10.0.0.9:5555)
adb-PHONE-aa._adb-tls-connect._tcp|Phone (PHONE-aa)'
dup_out=$(printf '%s\n' "$dup_in" | _filter_dup_devices)
check "M1 同序列号只留手动连的行" "[ \"\$dup_out\" = '10.0.0.9:5555|Phone (10.0.0.9:5555)' ]"

dup_in='10.0.0.9:5555|Phone (10.0.0.9:5555)
adb-OTHER-bb._adb-tls-connect._tcp|Phone (OTHER-bb)'
dup_out=$(printf '%s\n' "$dup_in" | _filter_dup_devices)
check "M2 不同序列号两行都留" "[ \"\$(printf '%s\n' \"\$dup_out\" | grep -c .)\" = 2 ]"

unset ADB_SHELL_SERIALNO
unset ADB_SHELL_SERIALNO_OTHER
dup_out=$(printf '%s\n' "$dup_in" | _filter_dup_devices)
check "M3 序列号拿不到时不合并" "[ \"\$(printf '%s\n' \"\$dup_out\" | grep -c .)\" = 2 ]"

# ---- V: 扫描子菜单也显示短名 ----
reset_state
set_devices "$DEFAULT_DEVICES"
set_services 'List of discovered mdns services
adb-NEW99-qr	_adb-tls-connect._tcp	10.0.0.5:1111
adb-NEW99-qr	_adb-tls-pairing._tcp	10.0.0.5:2222'
SUBMENU_CHOICE=""
handle_lan_scan || true
check "V1 子菜单只有 pairing 行" "grep -qFx '10.0.0.5:2222' \"\$SUBMENU_GOT\""
check "V2 子菜单不含 connect 条目" "! grep -qF '10.0.0.5:1111' \"\$SUBMENU_GOT\""
check "V3 子菜单不含实例名" "! grep -q 'adb-' \"\$SUBMENU_GOT\""

# ---- U: 配对→同名直连成功, 通知带友好名 ----
reset_state
set_devices "$DEFAULT_DEVICES"
set_services 'List of discovered mdns services
adb-UU77-vv	_adb-tls-pairing._tcp	10.0.0.9:3333
adb-UU77-vv	_adb-tls-connect._tcp	10.0.0.9:4444'
SUBMENU_CHOICE="10.0.0.9:3333"
PAIR_CODE="654321"
export ADB_SHELL_DEVICE_NAME="My Phone"
handle_lan_scan
check "U1 Connected 通知带友好名" "grep -qF 'Connected: My Phone' \"\$MOCK_LOG\""

exit $fail
