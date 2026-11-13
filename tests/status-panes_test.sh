#!/usr/bin/env bash
# dwm-status.sh panes() 回归测试:
#   A. block 只带 status id + 内容, 不再注入 ^b pane 底色
#      (底色由 dwm 的 SchemeStatus + loadxrdb(dwm.col_black) 决定, 与
#       writer 的 xrdb -query 同源同值, 故 ^b 是重复写入)
#   B. 空 block 只留 id 字节, 由 dwm 的 bar_blocks 丢弃 (无可见文本)
#      (weather 例外: 颜色码本身算可见文本, 必须带内容才输出)
#   C. battery 的 ^r/^f/^d 图形码原样透传
#   D. 静态守卫: 不再出现 new_pane / ^b$black^ 注入, 且每个 block 独占一行
#      (绘制顺序由 dwm config.h 决定, 注册顺序只服务于阅读)
#
# A/B 按 block 集合比对而非拼接顺序: 顺序不属于契约, 无害重排不应误报。
#
# 因 dwm-status.sh 顶层 case 会启动 daemon, 无法整体 source,
# 这里用 awk 提取 panes() + mock print_*。
# 运行: bash tests/status-panes_test.sh

set -uo pipefail

DWM=${DWM:-"$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"}
SCRIPT="$DWM/dwm-status.sh"
fail=0
pass=0

ok() { pass=$((pass + 1)); printf '  ok   %s\n' "$1"; }
no() { fail=$((fail + 1)); printf '  FAIL %s\n' "$1"; }

# 断言输出恰好由给定的 block 组成: 每个必须出现, 且不剩任何多余字节
# (顺序不限 -- 绘制顺序由 dwm config.h 决定, writer 侧行序仅供阅读)
assert_blocks() {
    local out=$1 b rest
    shift
    rest=$out
    for b in "$@"; do
        [[ $rest == *"$b"* ]] || return 1
        rest=${rest/"$b"/}
    done
    [[ -z $rest ]]
}

# ---- 提取被测函数 (顶层 case 会启动 daemon, 不能整体 source) ----
eval "$(awk '/^panes\(\)/,/^}/' "$SCRIPT")"

source "$DWM/status-ids.sh"

# ---- mock: 颜色变量 + print_* ----
black=BLACK blue=BLUE white=WHITE cyan=CYAN

set_all() {
    print_weather() { printf 'W'; }
    print_speed() { printf 'S'; }
    print_cpu() { printf 'C'; }
    print_mem() { printf 'M'; }
    print_disk() { printf 'D'; }
    print_rss() { printf 'R'; }
    print_mail() { printf 'L'; }
    print_notification() { printf 'N'; }
    print_screencast() { printf 'T'; }
    print_docker() { printf 'K'; }
    print_proxy() { printf 'X'; }
    print_mpd() { printf 'P'; }
    print_volume() { printf 'V'; }
    print_battery() { printf 'A'; }
    print_date() { printf 'Z'; }
}


echo "== A: 全有值, 每块 id + 内容齐全, 无 ^b =="
set_all
out=$(panes)

expect=(
    "${ST_CPU_BYTE}C" "${ST_MEM_BYTE}M" "${ST_DISK_BYTE}D"
    "${ST_RSS_BYTE}R" "${ST_MAIL_BYTE}L" "${ST_NOTIFY_BYTE}N"
    "${ST_NET_BYTE}^cWHITE^S"
    "${ST_WEATHER_BYTE}^cBLUE^W"
    "${ST_DOCKER_BYTE}K"
    "${ST_SCREENCAST_BYTE}T" "${ST_PROXY_BYTE}X"
    "${ST_MPD_BYTE}P" "${ST_VOLUME_BYTE}V"
    "${ST_BATTERY_BYTE}A"
    "${ST_DATE_BYTE}^cCYAN^Z"
)

assert_blocks "$out" "${expect[@]}" && ok "blocks match" || {
    no "blocks match"
    printf '  got: %q\n' "$out"
}
[[ "$out" != *"^b${black}^"* ]] && ok "no ^b pane colour" || no "no ^b pane colour"

echo "== B: 空 block 只留 id 字节 =="
print_weather() { :; }
print_rss() { :; }
print_mail() { :; }
print_notification() { :; }
print_screencast() { :; }
print_docker() { :; }
out=$(panes)

expect=(
    "${ST_CPU_BYTE}C" "${ST_MEM_BYTE}M" "${ST_DISK_BYTE}D"
    "${ST_RSS_BYTE}" "${ST_MAIL_BYTE}" "${ST_NOTIFY_BYTE}"
    "${ST_NET_BYTE}^cWHITE^S"
    "${ST_DOCKER_BYTE}"
    "${ST_SCREENCAST_BYTE}" "${ST_PROXY_BYTE}X"
    "${ST_MPD_BYTE}P" "${ST_VOLUME_BYTE}V"
    "${ST_BATTERY_BYTE}A"
    "${ST_DATE_BYTE}^cCYAN^Z"
)

assert_blocks "$out" "${expect[@]}" && ok "empty blocks keep only their id" || {
    no "empty blocks keep only their id"
    printf '  got: %q\n' "$out"
}

echo "== C: battery 图形码透传 =="
set_all
print_battery() { printf '^r8,11,2,6^^d^^f34^'; }
out=$(panes)
[[ "$out" == *'^r8,11,2,6^^d^^f34^'* ]] && ok "graphics kept" || no "graphics kept"

echo "== D: 静态守卫 =="
grep -q 'new_pane' "$SCRIPT" && no "new_pane removed" || ok "new_pane removed"
grep -qF '^b$black^' "$SCRIPT" && no "no ^b injection" || ok "no ^b injection"
batch=$(awk '/^panes\(\)/,/^}/' "$SCRIPT" | grep -c 'panes+=.*ST_[A-Z0-9_]*_BYTE.*ST_[A-Z0-9_]*_BYTE')
((batch == 0)) && ok "one block per registration line" || no "one block per registration line"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
exit $((fail > 0))
