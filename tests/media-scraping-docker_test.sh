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
is-active)
    case "${!#}" in
    docker.socket) active=$(cat "$TEST_DIR/sock_active" 2>/dev/null) ;;
    *) active=$(cat "$TEST_DIR/svc_active" 2>/dev/null) ;;
    esac
    [ "$active" = "1" ] && exit 0 || exit 3
    ;;
start | stop)
    verb="$1"
    shift
    # 本机实测: 一次 systemctl 带多个 unit 会被 polkit 直接拒绝 (无 challenge)
    if [ "$#" -gt 1 ]; then
        echo "Failed to enqueue jobs: Access denied" >&2
        exit 4
    fi
    unit="$1"
    case "$verb $unit" in
    "start docker.service")
        if [ -f "$TEST_DIR/start_fail" ]; then
            echo "${START_FAIL_MSG:-boom}" >&2
            exit 4
        fi
        echo 1 >"$TEST_DIR/svc_active"
        echo 1 >"$TEST_DIR/sock_active" # Requires= 连带拉起 socket
        ;;
    "start docker.socket") echo 1 >"$TEST_DIR/sock_active" ;;
    "stop docker.socket")
        if [ -f "$TEST_DIR/stop_fail" ]; then
            echo "${STOP_FAIL_MSG:-boom}" >&2
            exit 4
        fi
        echo 0 >"$TEST_DIR/sock_active"
        # Requires= 传播: 停 socket 连带停 service (no_propagation 关掉以测兜底)
        [ -f "$TEST_DIR/no_propagation" ] || echo 0 >"$TEST_DIR/svc_active"
        ;;
    "stop docker.service")
        if [ -f "$TEST_DIR/stop_fail" ]; then
            echo "${STOP_FAIL_MSG:-boom}" >&2
            exit 4
        fi
        echo 0 >"$TEST_DIR/svc_active"
        ;;
    esac
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
    echo 0 >"$TEST_DIR/sock_active"
    : >"$TEST_DIR/running_containers"
    rm -f "$TEST_DIR"/compose_state_* "$TEST_DIR/start_fail" "$TEST_DIR/stop_fail" "$TEST_DIR/no_propagation"
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

# ---------------- D: down 后 0 容器 → 单 unit 停 socket (连带停 service) ----------------
reset_state
echo 1 >"$TEST_DIR/svc_active"
echo 1 >"$TEST_DIR/sock_active"
set_compose jellyfin running
_toggle hub jellyfin metatube
check "D1 走了 down" 'grep -q "^launch down hub$" "$MOCK_LOG"'
check "D2 停 socket 用单 unit 调用" 'grep -q "^systemctl stop docker.socket$" "$MOCK_LOG"'
check "D3 不发多 unit 调用" '! grep -q "^systemctl stop docker.service docker.socket$" "$MOCK_LOG"'
check "D4 down 之后才 stop" '[ "$(grep -n "^launch down hub" "$MOCK_LOG" | cut -d: -f1)" -lt "$(grep -n "^systemctl stop" "$MOCK_LOG" | cut -d: -f1)" ]'
check "D5 Requires 传播已停 service → 不再单独 stop" '! grep -q "^systemctl stop docker.service$" "$MOCK_LOG"'
check "D6 成功停止不打扰 (不发通知)" '! grep -q "^notify " "$MOCK_LOG"'

# 兜底: socket 停了但 service 还在 (unit 关系变化) → 再单独停 service
reset_state
echo 1 >"$TEST_DIR/svc_active"
echo 1 >"$TEST_DIR/sock_active"
set_compose jellyfin running
touch "$TEST_DIR/no_propagation"
_toggle hub jellyfin metatube
check "D7 service 仍在 → 兜底单独停 service" 'grep -q "^systemctl stop docker.service$" "$MOCK_LOG"'

# ---------------- E: 仍有其他容器 → 不停 daemon ----------------
reset_state
echo 1 >"$TEST_DIR/svc_active"
set_compose jellyfin running
printf 'aaa\nbbb\n' >"$TEST_DIR/running_containers"
_toggle hub jellyfin metatube
check "E1 有活动容器 → 不停 daemon" '! grep -q "systemctl stop" "$MOCK_LOG"'

# ---------------- F: 失败原因透出到通知 (不再只有笼统文案) ----------------
reset_state
echo 1 >"$TEST_DIR/svc_active"
echo 1 >"$TEST_DIR/sock_active"
set_compose jellyfin running
touch "$TEST_DIR/stop_fail"
export STOP_FAIL_MSG="Failed to enqueue jobs: Access denied"
_toggle hub jellyfin metatube
check "F1 stop 失败 → critical" 'grep -q "^notify -u critical" "$MOCK_LOG"'
check "F2 stop 失败 → 通知带真实原因" 'grep -q "Access denied" "$MOCK_LOG"'

reset_state
touch "$TEST_DIR/start_fail"
export START_FAIL_MSG="Interactive authentication required."
_toggle hub jellyfin metatube >/dev/null 2>&1
check "F3 start 失败 → 通知带真实原因" 'grep -q "Interactive authentication required" "$MOCK_LOG"'

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
check "S5 不再有多 unit systemctl 调用" '! grep -qE "systemctl (start|stop) docker\.[a-z]+ docker\.[a-z]+" "$SCRIPT"'

exit "$fail"
