#!/usr/bin/env bash
# print_volume 抗阻塞回归测试:
#   A. amixer 正常 → 输出音量图标 (开机/未静音)
#   B. amixer 返回 off → 静音图标 + 红色
#   C. 音频服务卡死 (amixer 不返回) → 必须限时返回, 不得拖停 refresh 循环
#   D. amixer 失败/无 Master → 静默返回, 不得对空值做整数比较 (无 stderr)
#
# 背景: amixer 走 ALSA default (本机为 pipewire-pulse 插件). USB 声卡卡在控制
# 传输时 pipewire-pulse 不响应, 单次 amixer 阻塞 ~30s; launch_refresh 是串行
# `panes(); sleep 1`, 一个慢 block 就让整条状态栏 30s 才刷新一次 (见 AGENTS.md
# 状态栏已知问题). 旧代码无 timeout, 场景 C 会跑满 MOCK_AMIXER_HANG 秒.
# 运行: bash tests/status-volume-hang_test.sh

set -u
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$REPO/dwm-status-print.sh"

white=W red=R yellow=Y black=B
system-notify() { :; }

fail=0
pass=0
ok() {
    pass=$((pass + 1))
    printf '  ok   %s\n' "$1"
}
no() {
    fail=$((fail + 1))
    printf '  FAIL %s\n' "$1"
}

TMPBIN=$(mktemp -d)
trap 'rm -rf "$TMPBIN"' EXIT
PATH="$TMPBIN:$PATH"

# MOCK_AMIXER_HANG: 不返回 (exec 保证 timeout 杀的就是持有管道的进程)
# MOCK_AMIXER_LINE: 正常输出行 (awk -F'[][]' 取倒数第二字段 + 最后字段)
# 未设置 LINE 且未设置 HANG: 模拟找不到 Master, 直接失败
cat >"$TMPBIN/amixer" <<'EOF'
#!/usr/bin/env bash
if [[ -n ${MOCK_AMIXER_HANG:-} ]]; then
    exec sleep "$MOCK_AMIXER_HANG"
fi
[[ -n ${MOCK_AMIXER_LINE:-} ]] || exit 1
printf '%s\n' "$MOCK_AMIXER_LINE"
EOF
chmod +x "$TMPBIN/amixer"

echo "== A: 正常音量 =="
out=$(MOCK_AMIXER_LINE="  Front Left: Playback 21050 [32%] [on]" print_volume)
[[ $out == *"${icons[volume]}"* && $out == *"^c$white^"* ]] && ok "volume icon + white" || no "volume icon + white ($out)"

echo "== B: 静音 =="
out=$(MOCK_AMIXER_LINE="  Front Left: Playback 21050 [32%] [off]" print_volume)
[[ $out == *"${icons[volume_mute]}"* && $out == *"^c$red^"* ]] && ok "mute icon + red" || no "mute icon + red ($out)"

echo "== C: 音频服务卡死必须限时返回 =="
start=$(date +%s%N)
out=$(MOCK_AMIXER_HANG=10 print_volume 2>/dev/null)
elapsed=$((( $(date +%s%N) - start) / 1000000))
((elapsed < 3000)) && ok "returns in ${elapsed}ms (< 3000ms)" || no "stalled ${elapsed}ms"
[[ -z $out ]] && ok "no partial output" || no "no partial output ($out)"

echo "== D: 无 Master 静默失败 =="
err=$(print_volume 2>&1 >/dev/null)
[[ -z $err ]] && ok "no stderr noise" || no "no stderr noise ($err)"
out=$(print_volume)
[[ -z $out ]] && ok "empty output" || no "empty output ($out)"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
exit $((fail > 0))
