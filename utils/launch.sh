#!/bin/bash

# 应用启动/重启助手 —— 被 autostart.sh 与 tools/theme.sh 共用 (source)。
# launch <policy> <name> <command...>:
#   check   已在跑 (pid 文件记录) 则跳过, 否则启动
#   restart 先杀掉 pid 文件记录的进程再启动 (新旧不并存)
# pid 文件与 flock 锁按 <name> 命名于 /tmp/dwm-status/autostart-launch-<name>.{pid,lock};
# flock 保证同一 name 的 "检查+启动" 原子, 避免并发重复启动。
launch() {
    local policy=${1:-"check"} name=$2
    shift 2
    local cmd="$*"
    local dir="/tmp/dwm-status"
    local pf="$dir/autostart-launch-$name.pid"
    local pid

    mkdir -p "$dir"

    # 重入/并发互斥: 同一 name 的检查+启动必须原子, 拿不到锁说明另一实例
    # 正在处理, 直接跳过 (该实例会完成启动)
    {
        flock -n 9 || return 1

        # read pid + verify alive (空 pid/文件不存在时 kill 失败 → 重置为空)
        pid=$(cat "$pf" 2>/dev/null)
        kill -0 "$pid" 2>/dev/null || pid=""

        case "$policy" in
        check)
            [ -z "$pid" ] || return 0
            ;;
        restart)
            [ -n "$pid" ] && kill "$pid" 2>/dev/null
            # 等旧进程退出, 避免新旧实例并存 (最多等 2s)
            for _ in {1..20}; do
                [ -n "$pid" ] || break
                kill -0 "$pid" 2>/dev/null || break
                sleep 0.1
            done
            ;;
        esac

        # 9>&- 关闭子进程的锁 fd, 防止后台进程继承锁导致永不释放
        $cmd &>/dev/null 9>&- &
        echo $! >"$pf"
    } 9>"$dir/autostart-launch-$name.lock"
}
