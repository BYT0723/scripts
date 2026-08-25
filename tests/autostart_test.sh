#!/usr/bin/env bash
# autostart.sh launch() 重入/竞态回归测试:
#   A. 并发重入: 多个实例同时 launch check 同一 name, 只允许一个实例启动
#   B. restart: 旧进程退出后新进程才启动 (新旧不并存), 且 pid 文件更新
#   C. 锁不被长驻后台进程继承: 进程存活期间锁须已释放 (否则后续 launch 永远拿不到锁)
#   D. 死 pid 文件: 记录已死进程时 check 应重新启动
# 运行: bash tests/autostart_test.sh

SCRIPT="$HOME/.dwm/autostart.sh"
TEST_DIR=$(mktemp -d)
BIN="$TEST_DIR/bin"
mkdir -p "$BIN"
export PATH="$BIN:$PATH"

# 提取 launch() 函数定义 (顶层有执行代码, 不能直接 source 全文件)
LAUNCH_FN="$TEST_DIR/launch_fn.sh"
sed -n '/^launch() {/,/^}$/p' "$SCRIPT" >"$LAUNCH_FN"
if ! grep -q '^launch() {' "$LAUNCH_FN"; then
    echo "FAIL: cannot extract launch() from $SCRIPT"
    exit 1
fi

NAME="autostart-test-$$"
PF="/tmp/dwm-status/autostart-launch-$NAME.pid"
LF="/tmp/dwm-status/autostart-launch-$NAME.lock"
MARKER="$TEST_DIR/marker"

cleanup() {
    rm -f "$PF" "$LF"
    # 清理测试遗留进程
    local pid
    [ -f "$PF" ] && pid=$(cat "$PF") && kill "$pid" 2>/dev/null
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

# 每次测试独立进程数
marker_sleep() { echo $$ >>"$MARKER"; sleep 1; }

# 长驻进程 (写标记 + 不退出, 由 restart 杀掉)
daemon_cmd() { echo $$ >>"$MARKER"; while :; do sleep 60; done; }

source "$LAUNCH_FN"

# ---- A. 并发重入互斥 ----
for round in 1 2 3 4 5; do
    : >"$MARKER"
    rm -f "$PF" "$LF"
    for _ in $(seq 1 12); do
        launch check "$NAME" marker_sleep &
    done
    wait
    sleep 1.2 # 等 marker_sleep 全部退出, 避免与下一轮混淆
    n=$(wc -l <"$MARKER")
    check "A$round: 12 并发 check 只启动 1 个 (实际 $n)" "[ \"$n\" -eq 1 ]"
done

# ---- B. restart: 新旧不并存 + pid 文件更新 ----
: >"$MARKER"
rm -f "$PF" "$LF"
launch check "$NAME" daemon_cmd
old_pid=$(cat "$PF")
check "B: 首次 check 启动 daemon (pid=$old_pid)" 'kill -0 "$old_pid" 2>/dev/null'

sleep 0.3
launch restart "$NAME" daemon_cmd
new_pid=$(cat "$PF")
check "B: restart 后旧进程已退出 (pid=$old_pid)" '! kill -0 "$old_pid" 2>/dev/null'
check "B: 新进程存活且 pid 文件更新 (new=$new_pid)" '[ -n "$new_pid" ] && [ "$new_pid" != "$old_pid" ] && kill -0 "$new_pid" 2>/dev/null'

# ---- C. check 语义: 存活进程不重复启动 (锁可用性已由 B 的 restart 成功证明) ----
n0=$(wc -l <"$MARKER")
launch check "$NAME" marker_sleep
sleep 0.2
n1=$(wc -l <"$MARKER")
check "C: 存活进程不重复启动 (marker $n0 -> $n1)" "[ \"$n1\" -eq \"$n0\" ]"

# 清理 daemon
launch restart "$NAME" true
sleep 0.2

# ---- D. 死 pid 文件: check 应重新启动 ----
: >"$MARKER"
echo 999999 >"$PF"
launch check "$NAME" marker_sleep
sleep 0.2
check "D: 死 pid 时 check 重新启动" 'kill -0 "$(cat "$PF")" 2>/dev/null'
check "D: pid 文件已更新为活进程" '[ "$(cat "$PF")" != "999999" ]'

# ---- E. restart 在无 pid 文件时正常工作 ----
rm -f "$PF"
launch restart "$NAME" marker_sleep
sleep 0.2
check "E: 无 pid 文件时 restart 直接启动" 'kill -0 "$(cat "$PF")" 2>/dev/null'

if [ "$fail" -eq 0 ]; then
    echo "ALL TESTS PASSED"
else
    echo "SOME TESTS FAILED"
    exit 1
fi