#!/usr/bin/env bash
# docker 状态块回归测试：汇总函数 + print_docker 颜色 + daemon 写缓存
# 运行: bash tests/docker-status_test.sh
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
source "$REPO/dwm-status-tools.sh"

# 确定性颜色（不依赖 xrdb）
white=W blue=B yellow=Y red=R

TMPD="$(mktemp -d)"
docker_count_path="$TMPD/count"
docker_list_path="$TMPD/list"
docker_disk_path="$TMPD/disk"
export TMPD

# --- docker_summarize ---
out=$(docker_summarize <<'EOF'
running|Up 2 hours|web
running|Up 1 hour (unhealthy)|api
restarting|Restarting (1) 5 seconds ago|worker
exited|Exited (0) 3 days ago|old
EOF
)
check "汇总 2 4 1 1" '[ "$out" == "2 4 1 1" ]'

out=$(docker_summarize </dev/null)
check "空列表 0 0 0 0" '[ "$out" == "0 0 0 0" ]'

# --- print_docker ---
check "无缓存文件空输出" '[ -z "$(print_docker)" ]'

echo "0 0 0 0" >"$docker_count_path"
out=$(print_docker)
check "idle 白色显示 0" '[ "$out" == "^cW^  0" ]'

echo "2 2 0 0" >"$docker_count_path"
out=$(print_docker)
check "运行中蓝色" '[ "$out" == "^cB^  2" ]'

echo "2 3 0 1" >"$docker_count_path"
out=$(print_docker)
check "restarting 黄色" '[ "$out" == "^cY^  2" ]'

echo "2 3 1 0" >"$docker_count_path"
out=$(print_docker)
check "unhealthy 红色+感叹数" '[ "$out" == "^cR^  2 !1" ]'

# --- update_docker_daemon（mock docker/pgrep，真实跑两轮） ---
docker() {
    case "$1" in
    ps) printf 'running|Up 2 hours|web\nrunning|Up 1 hour (unhealthy)|api\nexited|Exited (0)|old\n' ;;
    system) printf 'Images 5 1GB 500MB\nContainers 3 10MB 0B\n' ;;
    esac
    return 0
}
pgrep() { return 0; }

update_docker_daemon 1 1 &
dp=$!
for _ in $(seq 1 50); do
    [ -f "$docker_count_path" ] && [ -f "$docker_disk_path" ] && break
    sleep 0.1
done
kill $dp 2>/dev/null
wait $dp 2>/dev/null

check "daemon 写 count" '[ "$(cat "$docker_count_path")" == "2 3 1 0" ]'
check "daemon 写 list 3 行" '[ "$(wc -l <"$docker_list_path")" -eq 3 ]'
check "daemon 写 disk" 'grep -q "^Images" "$docker_disk_path"'

# daemon 停掉时清缓存（parity：之前 pgrep 守卫无输出）
pgrep() { return 1; }
rm -f "$docker_count_path"
update_docker_daemon 1 1 &
dp=$!
sleep 1.5
kill $dp 2>/dev/null
wait $dp 2>/dev/null
check "daemon 停则无 count" '[ ! -f "$docker_count_path" ]'
check "停则 print 空" '[ -z "$(print_docker)" ]'

rm -rf "$TMPD"
exit $fail
