#!/usr/bin/env bash
# rofi/scripts/media-scraping.sh Toggle 联动 docker.service 回归测试:
#   A. daemon 未运行 → 先 `systemctl start docker.service` 再 `launch.sh up`
#   B. daemon 已运行 → 不调 systemctl start
#   C. systemctl start 失败 → 不调 launch.sh up, 发 critical 通知
#   D. down 后全局活动容器为 0 → stop docker.service + docker.socket
#   E. down 后仍有其他容器在跑 → 不停 daemon
#   G. _is_running 在 service inactive 时 rc=1 且不 spawn docker (避免 socket 激活唤醒 daemon)
#   H/I. _is_running 的 all-running / 有停的 判定不变
#   S. 静态: BASH_SOURCE 取路径 / MEDIA_SCRAPING_NO_DISPATCH 测试缝 / source utils/notify.sh
#
# 背景: docker.socket 是 ListenStream=/run/docker.sock + Triggers=docker.service,
# 只停 docker.service 的话本菜单每次构建的 `docker compose ps` 会经 socket 把 daemon
# 立刻拉回来 → 必须连带停 socket, 且 _is_running 先看 service 状态再决定是否 probe。
#
# 因脚本顶层跑 `while module_loop`, 测试用 MEDIA_SCRAPING_NO_DISPATCH=1 source
# (缝的实现抄 tests/scrcpy-lan-scan_test.sh 的先例)。
# 运行: bash tests/media-scraping-docker_test.sh

fail=0
check() { # desc cond
    if eval "$2"; then
        echo "PASS: $1"
    else
        echo "FAIL: $1"
        fail=1
    fi
}

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$REPO/rofi/scripts/media-scraping.sh"

TEST_DIR=$(mktemp -d)
trap 'rm -rf "$TEST_DIR"' EXIT
export TEST_DIR
export HOME="$TEST_DIR/home"
mkdir -p "$HOME"

MEDIA_DIR="$TEST_DIR/media"
mkdir -p "$MEDIA_DIR"
printf 'services: {}\n' >"$MEDIA_DIR/docker-compose.yml"
cat >"$MEDIA_DIR/launch.sh" <<'EOF'
#!/usr/bin/env bash
echo "launch $*" >>"$MOCK_LOG"
exit 0
EOF
chmod +x "$MEDIA_DIR/launch.sh"

MOCK_LOG="$TEST_DIR/mock.log"
export MOCK_LOG

# ---- mock 外部命令 ----
BIN="$TEST_DIR/bin"
mkdir -p "$BIN"

cat >"$BIN/systemctl" <<'EOF'
#!/usr/bin/env bash
echo "systemctl $*" >>"$MOCK_LOG"
case "$1" in
is-active) [ "$(cat "$TEST_DIR/svc_active" 2>/dev/null)" = "1" ] && exit 0 || exit 3 ;;
start)
    [ -f "$TEST_DIR/start_fail" ] && exit 1
    echo 1 >"$TEST_DIR/svc_active"
    exit 0
    ;;
stop)
    [ -f "$TEST_DIR/stop_fail" ] && exit 1
    echo 0 >"$TEST_DIR/svc_active"
    exit 0
    ;;
esac
exit 0
EOF

cat >"$BIN/docker" <<'EOF'
#!/usr/bin/env bash
echo "docker $*" >>"$MOCK_LOG"
case "$1" in
ps)
    # docker ps -q → 每行一个运行中容器
    cat "$TEST_DIR/running_containers" 2>/dev/null
    exit 0
    ;;
compose)
    # docker compose -f <file> ps --format json <svc>
    svc="${!#}"
    if [ "$(cat "$TEST_DIR/compose_state_$svc" 2>/dev/null)" = "running" ]; then
        echo '{"State":"running"}'
    else
        echo '{"State":"exited"}'
    fi
    exit 0
    ;;
esac
exit 0
EOF

cat >"$BIN/notify-send" <<'EOF'
#!/usr/bin/env bash
echo "notify $*" >>"$MOCK_LOG"
exit 0
EOF

chmod +x "$BIN"/*

reset_state() {
    : >"$MOCK_LOG"
    echo 0 >"$TEST_DIR/svc_active"
    : >"$TEST_DIR/running_containers"
    rm -f "$TEST_DIR"/compose_state_* "$TEST_DIR/start_fail" "$TEST_DIR/stop_fail"
}
set_compose() { # svc state
    echo "$2" >"$TEST_DIR/compose_state_$1"
}

# ---- 加载被测脚本 (顶层菜单被 MEDIA_SCRAPING_NO_DISPATCH 跳过) ----
export MEDIA_DIR
export MEDIA_SCRAPING_NO_DISPATCH=1
export PATH="$BIN:$PATH"
# shellcheck disable=SC1090
source "$SCRIPT"

# ---------------- A: daemon 未运行 → 先 start 再 up ----------------
reset_state
_toggle hub jellyfin metatube
check "A1 daemon 未运行 → 调 systemctl start" 'grep -q "^systemctl start docker.service" "$MOCK_LOG"'
check "A2 先 start 后 up" '[ "$(grep -n "systemctl start docker.service" "$MOCK_LOG" | cut -d: -f1)" -lt "$(grep -n "^launch up hub" "$MOCK_LOG" | cut -d: -f1)" ]'
check "A3 up 目标正确" 'grep -q "^launch up hub$" "$MOCK_LOG"'
check "A4 自启发通知" 'grep -q "^notify -u normal" "$MOCK_LOG"'

# ---------------- B: daemon 已运行 → 不 start ----------------
reset_state
echo 1 >"$TEST_DIR/svc_active"
set_compose jellyfin exited
set_compose metatube exited
_toggle hub jellyfin metatube
check "B1 daemon 已运行 → 不 start" '! grep -q "systemctl start" "$MOCK_LOG"'
check "B2 仍走 up" 'grep -q "^launch up hub$" "$MOCK_LOG"'

# ---------------- C: start 失败 → 不 up + critical ----------------
reset_state
touch "$TEST_DIR/start_fail"
_toggle hub jellyfin metatube >/dev/null 2>&1
check "C1 start 失败 → 不调 launch" '! grep -q "^launch " "$MOCK_LOG"'
check "C2 发 critical 通知" 'grep -q "^notify -u critical" "$MOCK_LOG"'

# ---------------- D: down 后 0 容器 → stop service + socket ----------------
reset_state
echo 1 >"$TEST_DIR/svc_active"
set_compose jellyfin running
_toggle hub jellyfin metatube
check "D1 走了 down" 'grep -q "^launch down hub$" "$MOCK_LOG"'
check "D2 停 daemon 连带停 socket" 'grep -q "^systemctl stop docker.service docker.socket$" "$MOCK_LOG"'
check "D3 down 之后才 stop" '[ "$(grep -n "^launch down hub" "$MOCK_LOG" | cut -d: -f1)" -lt "$(grep -n "^systemctl stop" "$MOCK_LOG" | cut -d: -f1)" ]'
check "D4 停止发通知" 'grep -q "^notify -u normal" "$MOCK_LOG"'

# ---------------- E: 仍有其他容器 → 不停 daemon ----------------
reset_state
echo 1 >"$TEST_DIR/svc_active"
set_compose jellyfin running
printf 'aaa\nbbb\n' >"$TEST_DIR/running_containers"
_toggle hub jellyfin metatube
check "E1 有活动容器 → 不停 daemon" '! grep -q "systemctl stop" "$MOCK_LOG"'

# ---------------- G: _is_running 门禁 ----------------
reset_state
_is_running jellyfin metatube
rc=$?
check "G1 service inactive → rc=1" '[ "$rc" -eq 1 ]'
check "G2 service inactive → 不 spawn docker" '! grep -q "^docker " "$MOCK_LOG"'

# ---------------- H/I: 判定不变 ----------------
reset_state
echo 1 >"$TEST_DIR/svc_active"
set_compose jellyfin running
set_compose metatube running
_is_running jellyfin metatube
if [ $? -eq 0 ]; then rc=0; else rc=1; fi
check "H1 全部 running → rc=0" '[ "$rc" -eq 0 ]'

reset_state
echo 1 >"$TEST_DIR/svc_active"
set_compose jellyfin running
set_compose metatube exited
if _is_running jellyfin metatube; then rc=0; else rc=1; fi
check "I1 有停的 → rc=1" '[ "$rc" -eq 1 ]'

# ---------------- S: 静态守卫 ----------------
check "S1 source 用 BASH_SOURCE 取路径" 'grep -q "BASH_SOURCE\[0\]" "$SCRIPT"'
check "S2 MEDIA_SCRAPING_NO_DISPATCH 测试缝" 'grep -q "MEDIA_SCRAPING_NO_DISPATCH" "$SCRIPT"'
check "S3 source utils/notify.sh" 'grep -q "utils/notify.sh" "$SCRIPT"'
check "S4 MEDIA_DIR 可环境变量覆盖" 'grep -qF "MEDIA_DIR=\"\${MEDIA_DIR:-" "$SCRIPT"'

exit "$fail"
