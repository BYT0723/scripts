#!/usr/bin/env bash
# steam-workshop-auto.sh — 开机异步一次性自动更新工坊内容 (autostart 后台调用)
# 用法: steam-workshop-auto.sh [appid...] (缺省 431960)
# 行为: 有更新→下载→汇总通知+日志; 全 CURRENT/全 SKIP/无候选→静默(只日志); 锁被占→直接退出
# 注意: 只下载不重设当前壁纸; 内部无 & 后台, 不继承 flock FD (见 theme.sh _auto_lock 注释的不变量)

AUTO_DIR="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"
source "$AUTO_DIR/steam-workshop.sh"
source "$AUTO_DIR/../utils/notify.sh"

AUTO_LOCK="${STEAM_WORKSHOP_AUTO_LOCK:-/tmp/dwm-status/steam-workshop-auto.lock}"
AUTO_LOG="${STEAM_WORKSHOP_AUTO_LOG:-$HOME/.local/state/dwm/steam-workshop-auto.log}"
AUTO_ROOT="${STEAMCMD_INSTALL_DIR:-${STEAM_WORKSHOP_DIR:-$HOME/Downloads/steam-workshop}}"

auto_log() { printf '%s %s\n' "$(date '+%F %T')" "$*" >>"$AUTO_LOG"; }

main() {
    local -a appids=("$@")
    ((${#appids[@]} == 0)) && appids=(431960)
    local a
    for a in "${appids[@]}"; do
        [[ "$a" =~ ^[0-9]+$ ]] || { echo "usage: $0 [appid...]" >&2; return 1; }
    done
    mkdir -p "$(dirname "$AUTO_LOCK")" "$(dirname "$AUTO_LOG")" 2>/dev/null
    exec >>"$AUTO_LOG" 2>&1
    exec 9>"$AUTO_LOCK" 2>/dev/null || return 0
    if command -v flock >/dev/null 2>&1; then
        flock -n 9 2>/dev/null || return 0
    fi

    auto_log "check appids=${appids[*]} root=$AUTO_ROOT"
    local lines updates currents skips
    lines=$(for a in "${appids[@]}"; do sw_check_updates "$AUTO_ROOT" "$a" 2>/dev/null; done)
    updates=$(grep -c '^UPDATE|' <<<"$lines")
    currents=$(grep -c '^CURRENT|' <<<"$lines")
    skips=$(grep -c '^SKIP|' <<<"$lines")
    auto_log "result updates=$updates current=$currents skipped=$skips"
    if ((updates == 0)); then
        ((currents == 0)) && auto_log "check skipped (all SKIP or no candidates)"
        return 0
    fi
    local summary ok fail fids
    summary=$(grep '^UPDATE|' <<<"$lines" | sw_run_updates anonymous)
    read -r ok fail fids <<<"$summary"
    auto_log "done ok=$ok fail=$fail fids=$fids"
    if ((fail == 0)); then
        system-notify normal "Steam Workshop" "Auto update done"$'\n'"$ok updated"
    else
        system-notify critical "Steam Workshop" "Auto update done"$'\n'"$ok updated, $fail failed: $fids"
    fi
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
