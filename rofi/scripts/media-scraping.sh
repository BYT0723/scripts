#!/usr/bin/env bash

ROFI_DIR="$(dirname "$(dirname "${BASH_SOURCE[0]}")")"
WORK_DIR="$(dirname "$ROFI_DIR")"
MEDIA_DIR="${MEDIA_DIR:-$HOME/Applications/media-scraping}"
COMPOSE_FILE="$MEDIA_DIR/docker-compose.yml"

MODULE_THEME="$ROFI_DIR/applets/type-1/style-2.rasi"
MODULE_NAME="󰎁 Media Scraping"
MODULE_MESG="Media Hub And Scraper"

source "$(dirname "${BASH_SOURCE[0]}")"/util.sh
source "$(dirname "${BASH_SOURCE[0]}")"/lib-module.sh
source "$WORK_DIR/utils/notify.sh"

HUB=("jellyfin" "metatube")
SCRAPER=("sonarr" "radarr" "prowlarr" "bazarr" "qbittorrent")

# Toggle 顺带管 docker.service 生命周期: daemon 没起时 up 必失败, 关完最后一个
# 容器后 daemon 也没必要常驻。**一条 systemctl 只能带一个 unit**: 本机一次传多个
# unit 会被 polkit 直接 "Failed to enqueue jobs: Access denied" (连认证弹窗都不发起,
# 实测 `systemctl start getty@tty9 getty@tty11` 同样被拒), 单 unit 才会正常弹窗。
_docker_service_active() { systemctl is-active --quiet docker.service 2>/dev/null; }

# 失败原因要能看见: 原先 2>/dev/null 把 polkit/systemd 的错误全吞了, 只能看到笼统文案
_docker_start() {
    _docker_service_active && return 0
    local err
    if err=$(systemctl start docker.service 2>&1); then
        system-notify normal "Docker" "docker.service 未运行, 已启动"
        return 0
    fi
    system-notify critical "Docker" "启动 docker.service 失败: ${err:-未知错误}"
    return 1
}

_docker_stop_if_idle() {
    _docker_service_active || return 0
    # 全局口径: 其他 compose 项目还有容器在跑就不停 daemon
    local n
    n=$(docker ps -q 2>/dev/null | wc -l)
    [[ "$n" -eq 0 ]] || return 0
    # 停 socket 一条就够: docker.service Requires=docker.socket, 停 socket 会连带停
    # service; 反过来只停 service 时 socket 还活着, 会被下一次连接重新触发 daemon。
    local err
    if ! err=$(systemctl stop docker.socket 2>&1); then
        system-notify critical "Docker" "停止 docker.socket 失败: ${err:-未知错误}"
        return 0
    fi
    # 兜底: 若 unit 关系变成不依赖 socket, service 还会活着, 再单独收一次
    _docker_service_active && systemctl stop docker.service >/dev/null 2>&1
    return 0
}

_toggle() {
    local target="$1"
    shift
    local services=("$@")

    # daemon 没跑时组内不可能有容器在跑, 跳过 probe (省掉 N 次必然失败的 docker 调用)
    local any_running=false
    if _docker_service_active; then
        for svc in "${services[@]}"; do
            local state
            state=$(docker compose -f "$COMPOSE_FILE" ps --format json "$svc" 2>/dev/null | jq -r '.State // "stopped"')
            [[ "$state" == "running" ]] && any_running=true && break
        done
    fi

    if $any_running; then
        bash "$MEDIA_DIR/launch.sh" down "$target"
        _docker_stop_if_idle
    else
        _docker_start || return 1
        bash "$MEDIA_DIR/launch.sh" up "$target"
    fi
}

_is_running() {
    # 先看 service 状态: daemon 停着时 probe 只会经 socket 把它激活唤醒, 且必然失败
    _docker_service_active || return 1
    for svc in "$@"; do
        local state
        state=$(docker compose -f "$COMPOSE_FILE" ps --format json "$svc" 2>/dev/null | jq -r '.State // "stopped"')
        [[ "$state" != "running" ]] && return 1
    done
    return 0
}

module_parse <<MODULES
open-hub|󰎁|Hub (jellyfin)|
open-index|󰎁|Index (prowlarr)|
open-movie|󰎁|Movie (radarr)|
open-tv|󰎁|TV (sonarr)|
open-downloader|󰎁|Downloader (qbittorrent)|
open-subtitle|󰎁|Subtitle (bazarr)|
toggle-hub|󰙉|Toggle Hub|cmd:_is_running jellyfin metatube && echo " " || echo " "
toggle-scraper|󰙉|Toggle Scraper|cmd:_is_running sonarr radarr prowlarr bazarr qbittorrent && echo " " || echo " "
MODULES

handle_toggle_hub() { _toggle hub "${HUB[@]}"; }
handle_toggle_scraper() { _toggle scraper "${SCRAPER[@]}"; }
handle_open_hub() { _is_running "${HUB[@]}" && bash "$MEDIA_DIR/open.sh" "${HUB[@]}"; }
handle_open_index() { _is_running prowlarr && bash "$MEDIA_DIR/open.sh" prowlarr; }
handle_open_movie() { _is_running radarr && bash "$MEDIA_DIR/open.sh" radarr; }
handle_open_tv() { _is_running sonarr && bash "$MEDIA_DIR/open.sh" sonarr; }
handle_open_downloader() { _is_running qbittorrent && bash "$MEDIA_DIR/open.sh" qbittorrent; }
handle_open_subtitle() { _is_running bazarr && bash "$MEDIA_DIR/open.sh" bazarr; }

# 测试缝: MEDIA_SCRAPING_NO_DISPATCH=1 时只加载函数, 不跑菜单 (抄 scrcpy.sh)
if [[ -z "${MEDIA_SCRAPING_NO_DISPATCH:-}" ]]; then
    while module_loop; do :; done
fi
