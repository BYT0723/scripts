#!/usr/bin/env bash
# tools/screencast.sh 麦克风声道回归测试:
#   A. 单声道源 (PipeWire channel map 可能是 aux0) → loopback 必须 channels=1 channel_map=mono,
#      否则混入立体声 sink 时只进左声道
#   B. 立体声源 → 不强制单声道 (保留立体声)
#   C. 查不到源信息 → 不过度降混
# 运行: bash tests/screencast-mic-mono_test.sh

cd "$(dirname "$0")/.." || exit 1

TOOLS_DIR="$(cd "$(dirname "$0")/../tools" && pwd)"
TEST_DIR=$(mktemp -d)
BIN="$TEST_DIR/bin"
mkdir -p "$BIN"
LOG="$TEST_DIR/log"
SOURCES_JSON="$TEST_DIR/sources.json"
export LOG SOURCES_JSON
export PATH="$BIN:$PATH"

cat >"$BIN/_mock" <<'EOF'
#!/bin/bash
app=${0##*/}
printf '%s\n' "$app $*" >>"$LOG"
case "$app" in
    pactl)
        case "$*" in
            get-default-sink) echo test-sink ;;
            get-default-source) echo test-mic ;;
            "-f json list sources") cat "$SOURCES_JSON" ;;
            load-module*) echo 1000 ;;
        esac
        ;;
esac
exit 0
EOF
chmod +x "$BIN/_mock"
ln -sf _mock "$BIN/pactl"

# 备份真实录屏用的临时文件, 避免测试覆盖正在进行的录制状态
BACKUP="$TEST_DIR/backup"
mkdir -p "$BACKUP"
for f in /tmp/screencast_sink /tmp/screencast_default_sink /tmp/screencast_default_source; do
    [ -f "$f" ] && cp -p "$f" "$BACKUP/$(basename "$f")"
done

cleanup() {
    rm -f /tmp/screencast_sink /tmp/screencast_default_sink /tmp/screencast_default_source
    for f in "$BACKUP"/*; do
        [ -e "$f" ] && cp -p "$f" "/tmp/$(basename "$f")"
    done
    rm -rf "$TEST_DIR"
}
trap cleanup EXIT

fail=0
check() { # $1=用例名 $2=断言表达式 (eval 后 0 为通过)
    if eval "$2" >/dev/null 2>&1; then
        echo "PASS: $1"
    else
        echo "FAIL: $1"
        fail=1
    fi
}

reset() {
    : >"$LOG"
    rm -f /tmp/screencast_sink /tmp/screencast_default_sink /tmp/screencast_default_source
}

export SCREENCAST_NO_DISPATCH=1
# shellcheck source=../tools/screencast.sh
source "$TOOLS_DIR/screencast.sh"

# ---- A. 单声道源 (aux0) ----
reset
cat >"$SOURCES_JSON" <<'JSON'
[{"name":"test-mic","sample_specification":"s16le 1ch 48000Hz","channel_map":"aux0"}]
JSON
setup_virtual_devices
check "A1: 单声道源按 mono 上混 (左右声道都有声)" \
    'grep -qE "module-loopback source=test-mic sink=screencast_sink channels=1 channel_map=mono .*device.description=ScreencastMic" "$LOG"'
check "A2: 桌面 loopback 不受影响" \
    'grep -qE "module-loopback source=test-sink.monitor sink=screencast_sink .*device.description=ScreencastDesktop" "$LOG"'
check "A3: 麦克风 loopback 模块 id 被记录 (供 stop 清理)" \
    '[ -s /tmp/screencast_default_source ]'

# ---- B. 立体声源 ----
reset
cat >"$SOURCES_JSON" <<'JSON'
[{"name":"test-mic","sample_specification":"s32le 2ch 48000Hz","channel_map":"front-left,front-right"}]
JSON
setup_virtual_devices
check "B1: 立体声源不强制单声道" \
    '! grep -qE "module-loopback source=test-mic .* channels=" "$LOG"'
check "B2: 立体声源仍正常接入" \
    'grep -qE "module-loopback source=test-mic sink=screencast_sink .*device.description=ScreencastMic" "$LOG"'

# ---- C. 查不到源信息 ----
reset
echo '[]' >"$SOURCES_JSON"
setup_virtual_devices
check "C1: 查不到源信息时不过度降混" \
    '! grep -qE "module-loopback source=test-mic .* channels=" "$LOG"'

if [ "$fail" -ne 0 ]; then
    echo "screencast-mic-mono: FAILED"
    exit 1
fi
echo "screencast-mic-mono: OK"
