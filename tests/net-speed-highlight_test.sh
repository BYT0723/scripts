#!/usr/bin/env bash
# print_speed 上2下5高亮回归测试
# 运行: bash tests/net-speed-highlight_test.sh
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

# 确定性分隔符：删掉 collapse 标记
rm -f "$HOME/.local/state/dwm/status/net-traffic-collapse"

TMP="$(mktemp)"
network_traffic_path="$TMP"

run_speed() { # rx tx
    echo "eth0 ethernet 192.168.1.2 $1 $2" >"$TMP"
    print_speed
}

Y="$yellow"

# 1. 空闲无黄
out=$(run_speed 0 0)
check "idle 无 yellow" '[[ "$out" != *"$Y"* ]]'

# 2. 上行 3MiB 高亮
out=$(run_speed 0 3145728)
check "tx 3M 含 yellow" '[[ "$out" == *"$Y"* ]]'

# 3. 下行 6MiB 高亮
out=$(run_speed 6291456 0)
check "rx 6M 含 yellow" '[[ "$out" == *"$Y"* ]]'

# 4. 边界下不亮：rx 4.9M + tx 1.9M
out=$(run_speed 5138022 1992294)
check "边界无 yellow" '[[ "$out" != *"$Y"* ]]'

# 5. 双高：两个方向都黄（出现 >=2 次）
out=$(run_speed 6291456 3145728)
n=$(grep -o -F "$Y" <<<"$out" | wc -l)
check "双高 yellow x2" '[ "$n" -ge 2 ]'

# 6. 单高只染一边：tx 高时 rx 图标段不带黄
out=$(run_speed 0 3145728)
check "tx高 rx段不黄" '[[ "$(grep -o -F "$Y" <<<"$out" | wc -l)" -eq 1 ]]'

rm -f "$TMP"
exit $fail
