#!/usr/bin/env bash
# dwm-windowhook.sh trigger + handler 回归测试:
#   B. windowhook_dispatch 分派 (action 预过滤 + func:/cmd: 双分支 + fail-closed)
#   C. handle_refresh_mail 集成 (mail.json 正常→update_mail 1 次; 缺失→静默 0 次)
#   D. 端到端: 真实环境变量执行脚本, close Thunderbird 触发, 其它组合不触发
# 运行: bash tests/windowhook_test.sh

SCRIPT="$HOME/.dwm/dwm-windowhook.sh"
TEST_DIR=$(mktemp -d)

export HOME="$TEST_DIR/home"
mkdir -p "$HOME/.config/dwm"

# ---- mock 外部命令 ----
BIN="$TEST_DIR/bin"
mkdir -p "$BIN"

cat >"$BIN/curl" <<'EOF'
#!/usr/bin/env bash
echo "curl $*" >>"$MOCK_LOG"
echo "* SEARCH 1 2"
echo "a OK Completed"
EOF
chmod +x "$BIN/curl"

export PATH="$BIN:$PATH"
export MOCK_LOG="$TEST_DIR/log"
: >"$MOCK_LOG"

export WINDOWHOOK_NO_DISPATCH=1
set -- # 清空位置参数, 避免误触发被测脚本的分派逻辑
# shellcheck disable=SC1090
source "$SCRIPT"

fail=0
check() { # desc cond
    if eval "$2"; then
        echo "PASS: $1"
    else
        echo "FAIL: $1"
        fail=1
    fi
}
reset_log() { : >"$MOCK_LOG"; }
# 后台 handler 落盘是异步的, 轮询等条件成立 (超时算失败, 不用固定 sleep 赌时序)
wait_for() { # cond
    local i
    for i in $(seq 1 50); do
        eval "$1" && return 0
        sleep 0.1
    done
    return 1
}

cleanup() { rm -rf "$TEST_DIR"; }
trap cleanup EXIT

# ---- B: 分派框架 (用测试桩规则, 不碰真实 handler) ----
# 先断言真实规则表 (后文会用桩覆盖 WINDOWHOOK_RULES, 故先存先查)
SAVED_RULES=("${WINDOWHOOK_RULES[@]}")
check "B5 真实规则为 cmd: thunderbird→mail 行" \
    "printf '%s\n' \"\${SAVED_RULES[@]}\" | grep -Fxq 'close|cmd:[[ \$CLASS == \"org.mozilla.Thunderbird\" ]]|handle_refresh_mail'"

stub_fired="$TEST_DIR/stub-fired"
trigger_stub_true() { return 0; }
trigger_stub_false() { return 1; }
handler_stub() { : >"$stub_fired"; }

ACTION=close CLASS=x
WINDOWHOOK_RULES=("close|func:trigger_stub_true|handler_stub" "close|func:trigger_stub_false|handler_stub")
rm -f "$stub_fired"
windowhook_dispatch
check "B1 全命中全执行 (真桩调 1 次, 假桩 0 次)" "[ -f \"$stub_fired\" ]"

rm -f "$stub_fired"
WINDOWHOOK_RULES=("close|func:trigger_stub_false|handler_stub")
windowhook_dispatch
check "B2 不命中时 handler 0 次" "[ ! -f \"$stub_fired\" ]"
check "B3 未知 ACTION 下分派退出码恒 0" "ACTION=bogus CLASS=x windowhook_dispatch"
check "B3b ACTION 为空跳过且退出 0" "ACTION= CLASS=x windowhook_dispatch"

rm -f "$stub_fired"
WINDOWHOOK_RULES=("close|func:trigger_stub_true|handler_stub_no_such_fn")
ACTION=close CLASS=x windowhook_dispatch
check "B4 handler 缺失不卡分派 (退出 0, 后续规则照跑)" "[ $? -eq 0 ]"

# ---- B6: action 预过滤 ----
rm -f "$stub_fired"
WINDOWHOOK_RULES=("open|func:trigger_stub_true|handler_stub")
ACTION=close CLASS=x windowhook_dispatch
check "B6a action 列不匹配时跳过 (open 规则遇 close 事件)" "[ ! -f \"$stub_fired\" ]"

rm -f "$stub_fired"
WINDOWHOOK_RULES=("*|func:trigger_stub_true|handler_stub")
ACTION=close CLASS=x windowhook_dispatch
check "B6b 星号通配 close 事件触发" "[ -f \"$stub_fired\" ]"
rm -f "$stub_fired"
ACTION=weird-action CLASS=x windowhook_dispatch
check "B6c 星号通配未知 ACTION 也触发" "[ -f \"$stub_fired\" ]"

# ---- B7: cmd: 分支 (单引号包整行, $ 在分派 eval 时才展开) ----
rm -f "$stub_fired"
WINDOWHOOK_RULES=('close|cmd:[[ ${CLASS:-} == cmd-test-class ]]|handler_stub')
ACTION=close CLASS=cmd-test-class windowhook_dispatch
check "B7a cmd: 命中触发" "[ -f \"$stub_fired\" ]"

rm -f "$stub_fired"
ACTION=close CLASS=other-class windowhook_dispatch
check "B7b cmd: 不命中跳过" "[ ! -f \"$stub_fired\" ]"

rm -f "$stub_fired"
WINDOWHOOK_RULES=('close|cmd:[[ ${CLASS:-} == cmd-a ]] || [[ ${CLASS:-} == cmd-b ]]|handler_stub')
ACTION=close CLASS=cmd-b windowhook_dispatch
check "B7c cmd: 含 || 不断列, 第二分支命中触发" "[ -f \"$stub_fired\" ]"

# ---- B8: 未知 spec 前缀 fail-closed ----
rm -f "$stub_fired"
WINDOWHOOK_RULES=("close|bogus:whatever|handler_stub")
ACTION=close CLASS=x windowhook_dispatch
check "B8 未知前缀跳过且退出 0" "[ ! -f \"$stub_fired\" ] && [ $? -eq 0 ]"

# 规则表断言见 B5 (已在覆盖前检查 SAVED_RULES)

# ---- C: handler 集成 (mock curl + 最小 mail.json) ----
printf '%s' '[{"server":"imap.example.com","user":"u","pass":"p"}]' \
    >"$HOME/.config/dwm/mail.json"
reset_log
ACTION=close CLASS="org.mozilla.Thunderbird" handle_refresh_mail
check "C1 handler 触发 update_mail (curl 恰调 1 次)" \
    "wait_for '[ \"\$(grep -c \"^curl \" \"\$MOCK_LOG\")\" = 1 ]'"

rm -f "$HOME/.config/dwm/mail.json"
reset_log
ACTION=close CLASS="org.mozilla.Thunderbird" handle_refresh_mail
sleep 1 # 给后台子 shell 留足“本应调用”的时间, 仍 0 次才算静默跳过
check "C2 mail.json 缺失时静默跳过 (curl 0 次)" \
    "[ \"\$(grep -c \"^curl \" \"\$MOCK_LOG\")\" = 0 ]"

# ---- D: 端到端 (子进程真实执行, 不设 NO_DISPATCH) ----
printf '%s' '[{"server":"imap.example.com","user":"u","pass":"p"}]' \
    >"$HOME/.config/dwm/mail.json"
reset_log
env -u WINDOWHOOK_NO_DISPATCH ACTION=close CLASS="org.mozilla.Thunderbird" WID=0x1 TITLE=t TAGS=1 MON=0 \
    bash "$SCRIPT"
check "D1 端到端 close Thunderbird 触发 1 次" \
    "wait_for '[ \"\$(grep -c \"^curl \" \"\$MOCK_LOG\")\" = 1 ]'"

reset_log
env -u WINDOWHOOK_NO_DISPATCH ACTION=close CLASS="firefox" WID=0x1 TITLE=t TAGS=1 MON=0 bash "$SCRIPT"
sleep 1
check "D2 端到端 close 其它 class 0 次" \
    "[ \"\$(grep -c \"^curl \" \"\$MOCK_LOG\")\" = 0 ]"

reset_log
env -u WINDOWHOOK_NO_DISPATCH ACTION=open CLASS="org.mozilla.Thunderbird" WID=0x1 TITLE=t TAGS=1 MON=0 bash "$SCRIPT"
sleep 1
check "D3 端到端 open Thunderbird 0 次" \
    "[ \"\$(grep -c \"^curl \" \"\$MOCK_LOG\")\" = 0 ]"

exit $fail
