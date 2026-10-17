#!/usr/bin/env bash

# dwm 窗口 open/close 时由 dwm 调起, 环境变量:
# ACTION      open / close
# WID         window id
# CLASS       window class
# TITLE       window title
# TAGS        window dwm tag number
# MON         window monitor number

# echo "$ACTION [$TAGS $MON] $CLASS [$TITLE] $WID" >>$HOME/window-hook.log

# ---- handlers: 动作, 耗时的一律后台化, 不阻塞 dwm 同步调用 ----
handle_refresh_mail() {
    local tools_dir
    tools_dir="$(dirname "${BASH_SOURCE[0]}")"
    # 缺配置/缺依赖静默跳过 (不动 update_mail 本体)
    [[ -f $HOME/.config/dwm/mail.json ]] || return 0
    command -v jq >/dev/null 2>&1 || return 0
    command -v curl >/dev/null 2>&1 || return 0
    (
        source "$tools_dir/dwm-status-tools.sh"
        update_mail
    ) &
}

# ---- 组合配置: 一行三列 "<action>|<trigger-spec>|<handler>" ----
# action: 与 $ACTION 精确相等才继续, "*" 通配任何 action (与 trigger 是 AND 关系)。
# trigger-spec 两形式: "func:<名>" 调函数 (0=命中);
#   "cmd:<条件>" 直接 eval (one-liner, 整行用单引号防提前展开, 条件里引号照写)。
# 加新事件 = 加一行 (+ 按需写 trigger_*/handle_*), 不动分派循环。
WINDOWHOOK_RULES=(
    'close|cmd:[[ $CLASS == "org.mozilla.Thunderbird" ]]|handle_refresh_mail'
)

# 分派: 首个 "|" 前为 action, 末个 "|" 后为 handler, 中间为 trigger-spec
# (首/末切分保证 cmd: 里可含 "||"); 顺序遍历, 全命中全执行;
# 单个失败/缺失不中断后续, 恒返回 0。
windowhook_dispatch() {
    local rule rest action spec handler name
    for rule in "${WINDOWHOOK_RULES[@]}"; do
        action=${rule%%|*}
        rest=${rule#*|}
        handler=${rest##*|}
        spec=${rest%|*}

        [[ -n $action && (${ACTION:-} == "$action" || $action == "*") ]] || continue

        case $spec in
        func:*)
            name=${spec#func:}
            declare -F "$name" >/dev/null 2>&1 || continue
            "$name" || continue
            ;;
        cmd:*)
            eval "${spec#cmd:}" || continue
            ;;
        *) continue ;;
        esac

        declare -F "$handler" >/dev/null 2>&1 || continue
        "$handler" || true
    done
    return 0
}

if [[ -z ${WINDOWHOOK_NO_DISPATCH:-} ]]; then
    windowhook_dispatch
fi
