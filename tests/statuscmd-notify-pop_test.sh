#!/usr/bin/env bash
# dwm-statuscmd.sh 通知块左键回归测试:
#   左键要"全部弹出"通知历史。dunstctl history-pop 单次只弹一条
#   (dunstctl(1): "Redisplay the notification that was most recently closed",
#    可选参数是 ID, 不是条数), 故必须循环 count history 次。
#
# dwm-statuscmd.sh 顶层会按 $1 分发, 故意传不存在的 cmdIndex (999) 使其空转;
# $0 为 "bash" 时 WORK_DIR="." , 所以在仓库根目录下 source 即可解析依赖。
# 运行: bash tests/statuscmd-notify-pop_test.sh

set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TEST_DIR=$(mktemp -d)
trap 'rm -rf "$TEST_DIR"' EXIT

FAKE_BIN="$TEST_DIR/bin"
POP_LOG="$TEST_DIR/pops"
mkdir -p "$FAKE_BIN"
export POP_LOG MOCK_COUNT=0

cat >"$FAKE_BIN/dunstctl" <<'EOF'
#!/usr/bin/env bash
case "${1:-}" in
count) printf '%s\n' "${MOCK_COUNT:-0}" ;;
history-pop) printf 'pop %s\n' "${2:-latest}" >>"$POP_LOG" ;;
esac
EOF
chmod +x "$FAKE_BIN/dunstctl"

pass=0
fail=0
ok() { pass=$((pass + 1)); printf '  ok   %s\n' "$1"; }
no() { fail=$((fail + 1)); printf '  FAIL %s\n' "$1"; }

# 取出左键 action 字面量 (不执行)
action=$(cd "$ROOT" && bash -c 'source ./dwm-statuscmd.sh 999 1; printf "%s" "${actions[$ST_NOTIFY,$left]}"')

# 在 cwd=仓库根 的子 shell 里执行左键 action, 返回 history-pop 次数
pop_count() { # $1=history 条数
    : >"$POP_LOG"
    (
        cd "$ROOT" &&
            MOCK_COUNT="$1" PATH="$FAKE_BIN:$PATH" \
                bash -c 'source ./dwm-statuscmd.sh 999 1; eval "${actions[$ST_NOTIFY,$left]}"'
    ) >/dev/null 2>&1
    grep -c '^pop ' "$POP_LOG" 2>/dev/null || true
}

# ---- 1. 静态: 左键不再是无参数的单次 history-pop ----
if [[ "$action" == "dunstctl history-pop" ]]; then
    no "left click is not bare 'dunstctl history-pop'"
else
    ok "left click is not bare 'dunstctl history-pop'"
fi
if [[ "$action" == *history-pop* && "$action" == *"count history"* ]]; then
    ok "left click loops over count history"
else
    no "left click loops over count history (got: $action)"
fi

# ---- 2. 历史 3 条 → 弹 3 次 (旧代码只弹 1 次) ----
got=$(pop_count 3)
if [[ "$got" == 3 ]]; then
    ok "3 history entries -> 3 pops"
else
    no "3 history entries -> 3 pops (got: ${got:-0})"
fi

# ---- 3. 历史为空 → 零次调用, 不报错 ----
: >"$POP_LOG"
(
    cd "$ROOT" && MOCK_COUNT=0 PATH="$FAKE_BIN:$PATH" \
        bash -c 'source ./dwm-statuscmd.sh 999 1; eval "${actions[$ST_NOTIFY,$left]}"'
) >/dev/null 2>&1
rc=$?
got=$(grep -c '^pop ' "$POP_LOG" 2>/dev/null || true)
if [[ $rc -eq 0 && "${got:-0}" == 0 ]]; then
    ok "empty history -> no pops, rc=0"
else
    no "empty history -> no pops, rc=0 (rc=$rc pops=${got:-0})"
fi

echo
if [[ $fail -ne 0 ]]; then
    echo "FAILED"
    exit 1
fi
echo "ALL PASS"
