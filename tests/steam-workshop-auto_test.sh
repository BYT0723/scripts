#!/usr/bin/env bash
# tools/steam-workshop-auto.sh 开机异步自动更新回归测试 (mock steamcmd/curl/notify-send, 无网络无弹窗)
#   有更新→下载+汇总通知+日志 / 全 CURRENT→静默(只日志) / 全 SKIP(断网)→静默+日志 / 锁被占→直接退出
# 运行: bash tests/steam-workshop-auto_test.sh

SCRIPT="$HOME/.dwm/tools/steam-workshop-auto.sh"
TEST_DIR=$(mktemp -d)
SLEEP_PID=""
trap 'kill "$SLEEP_PID" 2>/dev/null; rm -rf "$TEST_DIR"' EXIT
export HOME="$TEST_DIR/home"
mkdir -p "$HOME"

FAIL=0
check() { # desc cond
    if eval "$2"; then
        echo "ok: $1"
    else
        echo "FAIL: $1"
        FAIL=1
    fi
}

# ---- fake bin: steamcmd (按请求 itemid 回显) + curl (API_DYNAMIC/CURL_FAIL) + notify-send ----
FAKE_BIN="$TEST_DIR/bin"
mkdir -p "$FAKE_BIN"
cat >"$FAKE_BIN/steamcmd" <<'EOF'
#!/usr/bin/env bash
echo "$*" >>"${STEAMCMD_ARGS_LOG:-/dev/null}"
args=($*)
for ((i = 0; i < ${#args[@]}; i++)); do
    [[ "${args[i]}" == "+workshop_download_item" ]] && { appid="${args[i+1]}"; itemid="${args[i+2]}"; }
done
case "${STEAMCMD_MODE:-success}" in
success) mkdir -p "$STEAMCMD_OUTDIR/$itemid"; echo "Success. Downloaded item $itemid to \"$STEAMCMD_OUTDIR/$itemid\" (100 bytes)" ;;
auth) echo "ERROR! Download item $itemid failed (Access Denied)."; echo "ERROR: Invalid Password" ;;
error) echo "ERROR! Download item $itemid failed (Connection Timeout)." ;;
esac
EOF
cat >"$FAKE_BIN/curl" <<'EOF'
#!/usr/bin/env bash
[[ -n "${CURL_FAIL:-}" ]] && exit 1
id=$(grep -o 'publishedfileids\[0\]=[0-9]*' <<<"$*" | grep -o '[0-9]*$')
if [[ " ${DELETED_IDS:-} " == *" $id "* ]]; then result=9; else result=1; fi
if [[ " ${UPDATED_IDS:-} " == *" $id "* ]]; then ts=9999999999; else ts=100; fi
printf '{"response":{"result":1,"resultcount":1,"publishedfiledetails":[{"publishedfileid":"%s","result":%s,"consumer_app_id":431960,"time_updated":%s}]}}' "$id" "$result" "$ts"
EOF
cat >"$FAKE_BIN/notify-send" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$NOTIFY_LOG"
EOF
# 屏蔽宿主真实 aurelia: 保持本测试走 steamcmd 老路 (aurelia 行为由 steam-workshop_test.sh 覆盖)
cat >"$FAKE_BIN/aurelia" <<'EOF'
#!/usr/bin/env bash
echo "aurelia not available in this test segment" >&2
exit 1
EOF
chmod +x "$FAKE_BIN"/*
export PATH="$FAKE_BIN:$PATH"

# ---- fixture ----
UPROOT="$TEST_DIR/uproot"
mkdir -p "$UPROOT/WallpaperEngine_431960/111" "$UPROOT/WallpaperEngine_431960/222" \
    "$UPROOT/OtherApp_999999/444"
touch -d '2001-01-01' "$UPROOT/WallpaperEngine_431960/111" "$UPROOT/OtherApp_999999/444"

run_auto() { # [extra env already exported]; runs script with given appids
    STEAMCMD_INSTALL_DIR="$UPROOT" \
        STEAM_WORKSHOP_AUTO_LOCK="$TEST_DIR/auto.lock" \
        STEAM_WORKSHOP_AUTO_LOG="$TEST_DIR/auto.log" \
        STEAMCMD_OUTDIR="$TEST_DIR/dl-out" STEAMCMD_ARGS_LOG="$TEST_DIR/steamcmd.args" \
        NOTIFY_LOG="$TEST_DIR/notify.log" \
        bash "$SCRIPT" "$@"
}

reset_marks() {
    rm -f "$TEST_DIR"/auto.log "$TEST_DIR"/notify.log "$TEST_DIR"/steamcmd.args
    : >"$TEST_DIR/notify.log"
}

# ---- 1. 有更新: 下载+汇总通知+日志, 默认 appid 生效, 他 app 排除 ----
reset_marks
export STEAMCMD_MODE=success API_DYNAMIC=1 UPDATED_IDS="111 444" DELETED_IDS=""
run_auto
check "auto: 有更新则下载 (匿名, 仅 431960)" 'grep -q "+workshop_download_item 431960 111" "$TEST_DIR/steamcmd.args" && grep -q "+login anonymous" "$TEST_DIR/steamcmd.args" && ! grep -q "workshop_download_item 431960 444" "$TEST_DIR/steamcmd.args"'
check "auto: 汇总通知" 'grep -q "Auto update done" "$TEST_DIR/notify.log" && grep -q "1 updated" "$TEST_DIR/notify.log"'
check "auto: 通知带 id+名称" 'grep -q "WallpaperEngine_431960/111" "$TEST_DIR/notify.log"'
check "auto: 日志记录检查与结果" 'grep -q "appids=431960" "$TEST_DIR/auto.log" && grep -q "updates=1" "$TEST_DIR/auto.log"'
unset API_DYNAMIC UPDATED_IDS DELETED_IDS

# ---- 2. 全 CURRENT: 静默 (只日志) ----
reset_marks
export API_DYNAMIC=1 UPDATED_IDS="" DELETED_IDS=""
run_auto
check "auto: 全最新则静默" '[[ ! -s $TEST_DIR/notify.log ]]'
check "auto: 静默仍写日志" 'grep -q "updates=0" "$TEST_DIR/auto.log"'
unset API_DYNAMIC UPDATED_IDS DELETED_IDS

# ---- 3. 全 SKIP (断网): 静默 + 日志记 skip ----
reset_marks
export CURL_FAIL=1 API_DYNAMIC=1 UPDATED_IDS="111"
run_auto
check "auto: 断网则静默" '[[ ! -s $TEST_DIR/notify.log ]]'
check "auto: 断网记日志" 'grep -q "skipped" "$TEST_DIR/auto.log"'
unset CURL_FAIL API_DYNAMIC UPDATED_IDS

# ---- 4. 锁被占: 直接退出, 无下载无通知 ----
reset_marks
export API_DYNAMIC=1 UPDATED_IDS="111"
flock "$TEST_DIR/auto.lock" sleep 30 &
SLEEP_PID=$!
sleep 0.2
run_auto
kill "$SLEEP_PID" 2>/dev/null
SLEEP_PID=""
check "auto: 锁被占直接退出" '[[ ! -f $TEST_DIR/steamcmd.args && ! -s $TEST_DIR/notify.log ]]'
unset API_DYNAMIC UPDATED_IDS

# ---- 5. 空根目录: 静默退出 ----
reset_marks
mkdir -p "$TEST_DIR/emptyroot"
STEAMCMD_INSTALL_DIR="$TEST_DIR/emptyroot" \
    STEAM_WORKSHOP_AUTO_LOCK="$TEST_DIR/auto2.lock" \
    STEAM_WORKSHOP_AUTO_LOG="$TEST_DIR/auto2.log" \
    STEAMCMD_OUTDIR="$TEST_DIR/dl-out2" STEAMCMD_ARGS_LOG="$TEST_DIR/steamcmd2.args" \
    NOTIFY_LOG="$TEST_DIR/notify2.log" \
    bash "$SCRIPT" 431960
check "auto: 空根目录静默退出" '[[ ! -s $TEST_DIR/notify2.log ]]'

exit $FAIL
