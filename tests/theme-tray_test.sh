#!/usr/bin/env bash
# theme.sh restart_snixembed 回归测试:
#   仅当 PATH 中存在 snixembed 时才调 launch restart (其余托盘程序靠 icon 主题即时重载)。
# 运行: bash tests/theme-tray_test.sh
SCRIPT="$HOME/.dwm/tools/theme.sh"

fail=0
check() { # desc cond
    if eval "$2"; then
        echo "PASS: $1"
    else
        echo "FAIL: $1"
        fail=1
    fi
}

TMP=$(mktemp -d)
# 提取 restart_snixembed (theme.sh 顶层有 dispatcher, 不能整体 source)
sed -n '/^restart_snixembed() {/,/^}$/p' "$SCRIPT" >"$TMP/fn.sh"
if ! grep -q '^restart_snixembed() {' "$TMP/fn.sh"; then
    echo "FAIL: cannot extract restart_snixembed() from $SCRIPT"
    exit 1
fi
source "$TMP/fn.sh"

LOG="$TMP/launch.log"
launch() { echo "$*" >>"$LOG"; } # 拦截, 不真启动

# 场景 1: snixembed 存在
BIN="$TMP/bin"; mkdir -p "$BIN"
printf '#!/bin/sh\n' >"$BIN/snixembed"; chmod +x "$BIN/snixembed"
OLD_PATH="$PATH"; PATH="$BIN"
: >"$LOG"; restart_snixembed
PATH="$OLD_PATH"
check "snixembed 存在则 launch restart" 'grep -q "^restart snixembed snixembed$" "$LOG"'
check "仅 1 条调用" '[ "$(wc -l <"$LOG")" -eq 1 ]'

# 场景 2: snixembed 缺失
PATH="$TMP/empty"; mkdir -p "$PATH"
: >"$LOG"; restart_snixembed
PATH="$OLD_PATH"
check "snixembed 缺失则零调用" '[ ! -s "$LOG" ]'

check "恒返回 0" 'restart_snixembed >/dev/null 2>&1'

rm -rf "$TMP"
exit $fail
