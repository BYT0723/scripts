#!/usr/bin/env bash
# steam-workshop.sh — steamcmd 创意工坊下载核心 (无 rofi 依赖, 可 CLI/单测)
#   sw_parse_itemid <url-or-id>  → stdout itemid
#   sw_fetch_page <url-or-id>    → stdout 工坊页面 HTML (纯数字 ID 自动拼 URL)
#   sw_parse_appid <page>        → stdout appid
#   sw_parse_field <page> <marker> → stdout 标记文本 (HTML 转义解码)
#   sw_parse_appname <page>      → stdout app 名 (可空)
#   sw_parse_title <page>        → stdout 资源名 (可空)
#   sw_page_gated <page>         → 登录门返回 0 (匿名不可见条目)
#   sw_short_error                → steamcmd 全量输出摘一行人类可读错误
#   sw_resolve_appid <url-or-id> → stdout appid (先 ?appid= 参数, 后抓页面)
#   sw_api_info <itemid>         → stdout "appid|app名|资源名" (免 key WebAPI, 登录门条目可用; 需 jq)
#   sw_api_time <itemid>         → stdout "appid|time_updated" (更新检查用; 需 jq)
#   sw_check_updates <root> [scope: appdir 或 appid] → stdout 状态行 (UPDATE|appid|itemid|path / CURRENT|itemid|path / SKIP|itemid|path|reason); 无候选或根非法返回 1
#   sw_run_updates <user>          → stdin UPDATE 行逐条下载+删源; stdout "ok fail[ fids...]"; 只回显, 不 notify
#   sw_sync_updates <root> [user] [scope...] → stdout 首行 "updates currents skips ok fail[ fids...]" + 明细 "OK|itemid|label"/"FAIL|itemid|label"; 无候选返回 1; 公共编排 (auto 与 rofi 共用)
#   sw_label_list [OK|FAIL]      → stdin 明细行 → stdout "label[, …][ (+N more)]" (最多列 10); 只回显
#   sw_result_msg <ok> <ok_labels> <fail> <fail_labels> → stdout 汇总文案; 只回显
#   sw_item_info <url-or-id>     → stdout "appid|app名|资源名" (页面 → WebAPI → 失败)
#   sw_list_users                → stdout "AccountName|PersonaName" 行 (按 Timestamp 倒序)
#   sw_safe_app <appname> <appid>  → stdout 扁平首层目录名 (应用名去空格/非法字符, 为空回退 appid)
#   sw_aurelia_roots                       → stdout Steam 库根列表 (libraries -j → config → 默认)
#   sw_aurelia_find <appid> <itemid>       → stdout 库内落盘深路径 (首个有内容的)
#   sw_flatten_download <deep> <appid> <itemid> [appname] [stopdir] → stdout 扁平路径
#   sw_aurelia_download <appid> <itemid> [appname] → stdout 扁平路径; 失败返回 1 (fallback 用)
#   sw_download <appid> <itemid> [user] [appname] → stdout 扁平落盘路径 <隔离根>/<应用>/<itemid>; rc=0 成功, 2=需终端登录, 1=其他失败
#     driver: STEAM_WORKSHOP_DRIVER=auto (默认) 时有 aurelia 优先 aurelia (忽略 user), 失败 fallback steamcmd; =steamcmd 强制老路
#     隔离根经 +force_install_dir 写入 (见 STEAMCMD_INSTALL_DIR)，缺省 ~/Downloads/steam-workshop (自动 mkdir -p)

STEAM_LOGINUSERS="${STEAM_LOGINUSERS:-$HOME/.local/share/Steam/config/loginusers.vdf}"
# 隔离根: steamcmd +force_install_dir 的值 (非最终内容目录)。
# 最终落盘为 <隔离根>/steamapps/workshop/content/<appid>/<itemid>，
# 不同 appid 各占子目录、互不混；Steam 客户端卸载不触及此处。
# STEAMCMD_INSTALL_DIR 优先，兼容 STEAM_WORKSHOP_DIR，缺省 ~/Downloads/steam-workshop。
STEAMCMD_INSTALL_DIR="${STEAMCMD_INSTALL_DIR:-${STEAM_WORKSHOP_DIR:-$HOME/Downloads/steam-workshop}}"

sw_parse_itemid() {
    local in="$1" id=""
    if [[ "$in" =~ ^[0-9]{4,}$ ]]; then
        id="$in"
    elif [[ "$in" =~ [\?\&]id=([0-9]+) ]]; then
        id="${BASH_REMATCH[1]}"
    fi
    if [[ -z "$id" ]]; then
        return 1
    fi
    echo "$id"
}

sw_fetch_page() {
    local url="$1"
    [[ "$url" =~ ^[0-9]+$ ]] && url="https://steamcommunity.com/sharedfiles/filedetails/?id=$url"
    curl -sSL --max-time 20 --proto '=https' "$url" 2>/dev/null
}

sw_parse_appid() {
    grep -o 'data-appid="[0-9]*"' <<<"$1" | head -1 | grep -o '[0-9]*'
}

sw_parse_field() { # page marker → 文本 (HTML 转义解码)
    local val
    val=$(grep -o "$2\">[^<]*" <<<"$1" | head -1 | sed 's/.*">//')
    sw_decode_entities "$val"
}

sw_parse_appname() {
    sw_parse_field "$1" 'apphub_AppName ellipsis'
}

sw_parse_title() {
    sw_parse_field "$1" 'workshopItemTitle'
}

sw_decode_entities() {
    sed -e 's/&amp;/\&/g' -e 's/&lt;/</g' -e 's/&gt;/>/g' -e 's/&quot;/"/g' -e "s/&#39;/'/g" <<<"$1" | tr '|' ' ' | tr -d '\n'
}

sw_page_gated() { # page → 登录门则返回 0 (受限/隐藏条目, 匿名不可见)
    grep -qi 'you must be logged in to view this item' <<<"$1"
}

sw_short_error() { # steamcmd 全量输出 → 一行人类可读错误 (无则输出空)
    local text="${1:-}" err=""
    [[ -z "$text" && ! -t 0 ]] && text=$(cat)
    err=$(grep -oi 'cached credentials not found\.' <<<"$text" | head -1)
    [[ -z "$err" ]] && err=$(grep -o 'ERROR.*' <<<"$text" | head -1)
    [[ -z "$err" ]] && err=$(grep -oi 'steam guard.*' <<<"$text" | head -1)
    err="${err:0:100}"
    [[ -n "$err" ]] && echo "$err"
}

sw_resolve_appid() {
    local in="$1"
    if [[ "$in" =~ [\?\&]appid=([0-9]+) ]]; then
        echo "${BASH_REMATCH[1]}"
        return 0
    fi
    local page="" appid=""
    page=$(sw_fetch_page "$in") || return 1
    appid=$(sw_parse_appid "$page")
    if [[ -z "$appid" ]]; then
        return 1
    fi
    echo "$appid"
}

sw_api_info() {
    local itemid="$1" resp="" appid="" title="" appname=""
    command -v jq >/dev/null || return 1
    resp=$(curl -sSL --max-time 20 --proto '=https' -X POST \
        'https://api.steampowered.com/ISteamRemoteStorage/GetPublishedFileDetails/v1/' \
        --data-urlencode 'itemcount=1' --data-urlencode "publishedfileids[0]=$itemid" 2>/dev/null) || return 1
    appid=$(jq -r '.response.publishedfiledetails[0] | select(.result == 1) | .consumer_app_id' <<<"$resp")
    if [[ -z "$appid" || "$appid" == "null" ]]; then
        return 1
    fi
    title=$(jq -r '.response.publishedfiledetails[0] | select(.result == 1) | .title // ""' <<<"$resp")
    appname=$(curl -sSL --max-time 10 --proto '=https' \
        "https://store.steampowered.com/api/appdetails?appids=$appid" 2>/dev/null \
        | jq -r --arg id "$appid" '.[$id] | select(.success == true) | .data.name // ""')
    echo "$appid|$(sw_decode_entities "$appname")|$(sw_decode_entities "$title")"
}

_sw_dir_appid() { # 目录名 → appid (纯数字直接用; 取 _<digits> 后缀; 取不到输出空)
    local d="$1"
    if [[ "$d" =~ _([0-9]+)$ ]]; then echo "${BASH_REMATCH[1]}"
    elif [[ "$d" =~ ^[0-9]+$ ]]; then echo "$d"; fi
}

sw_api_time() { # itemid → "appid|time_updated" (更新检查用)
    local itemid="$1" resp="" appid="" updated=""
    command -v jq >/dev/null || return 1
    [[ "$itemid" =~ ^[0-9]+$ ]] || return 1
    resp=$(curl -sSL --max-time 20 --proto '=https' -X POST \
        'https://api.steampowered.com/ISteamRemoteStorage/GetPublishedFileDetails/v1/' \
        --data-urlencode 'itemcount=1' --data-urlencode "publishedfileids[0]=$itemid" 2>/dev/null) || return 1
    appid=$(jq -r '.response.publishedfiledetails[0] | select(.result == 1) | .consumer_app_id' <<<"$resp")
    updated=$(jq -r '.response.publishedfiledetails[0] | select(.result == 1) | .time_updated' <<<"$resp")
    [[ "$appid" =~ ^[0-9]+$ && "$updated" =~ ^[0-9]+$ ]] || return 1
    echo "$appid|$updated"
}

sw_check_updates() { # root [scope: appdir 或 appid] → 待更新/现状/跳过行
    local root="$1" scope="${2:-}"
    [[ -d "$root" ]] || return 1
    # scope 归一化为 appid (纯数字直接用; 目录名取 _<digits> 后缀; 取不到则为空)
    local scope_appid=""
    scope_appid=$(_sw_dir_appid "$scope")
    local -a cand=() # "itemid|path"
    local d itemid parent parent_appid
    while IFS= read -r -d '' d; do
        itemid=$(basename "$d")
        [[ "$itemid" =~ ^[0-9]+$ ]] || continue
        parent=$(basename "$(dirname "$d")")
        if [[ -n "$scope" && "$parent" != "$scope" ]]; then
            parent_appid=$(_sw_dir_appid "$parent")
            [[ -n "$scope_appid" && "$parent_appid" == "$scope_appid" ]] || continue
        fi
        cand+=("$itemid|$d")
    done < <(find "$root" -mindepth 2 -maxdepth 2 -type d -print0 2>/dev/null \
        | LC_ALL=C sort -z | grep -zvzF "$root/steamapps/")
    if [[ -d "$root/steamapps/workshop/content" ]] && [[ -z "$scope" || -n "$scope_appid" ]]; then
        while IFS= read -r -d '' d; do
            itemid=$(basename "$d")
            [[ "$itemid" =~ ^[0-9]+$ ]] || continue
            parent=$(basename "$(dirname "$d")")
            [[ "$parent" =~ ^[0-9]+$ ]] || continue
            [[ -z "$scope" || "$parent" == "$scope_appid" ]] || continue
            cand+=("$itemid|$d")
        done < <(find "$root/steamapps/workshop/content" -mindepth 2 -maxdepth 2 -type d -print0 2>/dev/null | LC_ALL=C sort -z)
    fi
    [[ ${#cand[@]} -gt 0 ]] || return 1
    local entry time_info appid updated mtime
    local -a out=()
    for entry in "${cand[@]}"; do
        IFS='|' read -r itemid d <<<"$entry"
        if ! time_info=$(sw_api_time "$itemid"); then
            out+=("SKIP|$itemid|$d|api-failed")
            continue
        fi
        IFS='|' read -r appid updated <<<"$time_info"
        mtime=$(stat -c %Y "$d" 2>/dev/null) || {
            out+=("SKIP|$itemid|$d|stat-failed")
            continue
        }
        if ((updated > mtime)); then
            out+=("UPDATE|$appid|$itemid|$d")
        else
            out+=("CURRENT|$itemid|$d")
        fi
    done
    printf '%s\n' "${out[@]}" | LC_ALL=C sort
    return 0
}

sw_run_updates() { # stdin UPDATE|appid|itemid|path 行; $1 = steam 用户
    # 逐条下载, 成功且落盘路径变化时删源 (沿用 handle_update 的迁移规则); 只回显, 不 notify
    # stdout: "ok fail[ fids...]" (fids 空格分隔, 全成功时省略)
    local user="${1:-anonymous}" ok=0 fail=0
    local -a failed=()
    local status appid itemid path parent app out
    while IFS='|' read -r status appid itemid path; do
        [[ "$status" == "UPDATE" && -n "$appid" && -n "$itemid" && -n "$path" ]] || continue
        parent=$(basename "$(dirname "$path")")
        app="${parent%_"$appid"}"
        if out=$(sw_download "$appid" "$itemid" "$user" "$app" 2>&1); then
            ((ok++))
            [[ "$out" != "$path" ]] && rm -rf "$path" 2>/dev/null
        else
            ((fail++))
            failed+=("$itemid")
        fi
    done
    if ((${#failed[@]})); then echo "$ok $fail ${failed[*]}"; else echo "$ok $fail"; fi
}

sw_sync_updates() { # root [user] [scope...] → stdout 首行 "updates currents skips ok fail[ fids...]" + 明细 "OK|itemid|label"/"FAIL|itemid|label"; 无候选返回 1; 只回显, 不 notify
    # 公共编排: 逐 scope 检查合并 → 计数 → UPDATE 行跑 sw_run_updates (auto 与 rofi 共用, 调用方只做通知/日志/交互)
    # label = 父目录名/itemid (如 WallpaperEngine_431960/111), 纯本地推导, 零新增网络
    local root="$1"
    local user="${2:-anonymous}"
    shift 2
    local lines="" l s
    if (($# == 0)); then
        lines=$(sw_check_updates "$root" 2>/dev/null) || return 1
    else
        for s in "$@"; do
            l=$(sw_check_updates "$root" "$s" 2>/dev/null) || continue
            lines+="$l"$'\n'
        done
        [[ -n "$lines" ]] || return 1
    fi
    local updates currents skips summary
    updates=$(grep -c '^UPDATE|' <<<"$lines" || true)
    currents=$(grep -c '^CURRENT|' <<<"$lines" || true)
    skips=$(grep -c '^SKIP|' <<<"$lines" || true)
    local -A label_of=()
    local st aid iid pth parent
    while IFS='|' read -r st aid iid pth; do
        [[ "$st" == "UPDATE" && -n "$iid" && -n "$pth" ]] || continue
        parent=$(basename "$(dirname "$pth")")
        label_of["$iid"]="$parent/$iid"
    done <<<"$(grep '^UPDATE|' <<<"$lines")"
    summary=$(grep '^UPDATE|' <<<"$lines" | sw_run_updates "$user")
    echo "$updates $currents $skips $summary"
    local ok fail fids f id
    read -r ok fail fids <<<"$summary"
    local -A is_fail=()
    for f in $fids; do is_fail["$f"]=1; done
    for id in $(printf '%s\n' "${!label_of[@]}" | LC_ALL=C sort); do
        if [[ -n "${is_fail[$id]:-}" ]]; then
            echo "FAIL|$id|${label_of[$id]}"
        else
            echo "OK|$id|${label_of[$id]}"
        fi
    done
}

sw_label_list() { # [want: OK|FAIL, 缺省全要] → stdin 明细行 → stdout "label[, label…][ (+N more)]" (最多列 10); 只回显
    local want="${1:-}" st iid lb
    local -a labels=()
    while IFS='|' read -r st iid lb; do
        [[ -n "$want" && "$st" != "$want" ]] && continue
        [[ -n "$lb" ]] && labels+=("$lb")
    done
    local out="" i
    for ((i = 0; i < ${#labels[@]} && i < 10; i++)); do
        [[ -n "$out" ]] && out+=", "
        out+="${labels[i]}"
    done
    if ((${#labels[@]} > 10)); then
        out+=" (+$((${#labels[@]} - 10)) more)"
    fi
    [[ -n "$out" ]] && echo "$out"
}

sw_result_msg() { # ok ok_labels fail fail_labels → stdout "N updated[: …][, M failed[: …]]"; 只回显
    local ok="$1" ok_labels="$2" fail="$3" fail_labels="$4"
    local msg="$ok updated"
    [[ -n "$ok_labels" ]] && msg+=": $ok_labels"
    if ((fail > 0)); then
        msg+=", $fail failed"
        [[ -n "$fail_labels" ]] && msg+=": $fail_labels"
    fi
    echo "$msg"
}

sw_item_info() {
    local in="$1" page="" appid="" itemid=""
    [[ "$in" =~ [\?\&]appid=([0-9]+) ]] && {
        echo "${BASH_REMATCH[1]}||"
        return 0
    }
    page=$(sw_fetch_page "$in" 2>/dev/null)
    if [[ -n "$page" ]]; then
        appid=$(sw_parse_appid "$page")
        if [[ -n "$appid" ]]; then
            echo "$appid|$(sw_parse_appname "$page")|$(sw_parse_title "$page")"
            return 0
        fi
    fi
    itemid=$(sw_parse_itemid "$in") || return 1
    sw_api_info "$itemid"
}

sw_list_users() {
    [[ -f "$STEAM_LOGINUSERS" ]] || return 1
    local out
    out=$(awk -F'"' '
        $2 ~ /^[0-9]{17,}$/ { if (acc != "") print ts" "acc"|"pers; acc=""; pers=""; ts=0; next }
        $2 == "AccountName" { acc=$4 }
        $2 == "PersonaName" { pers=$4 }
        $2 == "Timestamp" { ts=$4 }
        END { if (acc != "") print ts" "acc"|"pers }
    ' "$STEAM_LOGINUSERS" | sort -rn | cut -d' ' -f2-)
    if [[ -z "$out" ]]; then
        return 1
    fi
    echo "$out"
}

sw_safe_app() { # appname appid → 扁平首层目录名
    local app="$1" id="$2"
    app=$(printf '%s' "$app" | sed 's/[[:space:]]\+//g; s/[^A-Za-z0-9._-]/_/g; s/__*/_/g; s/^_//; s/_$//')
    [[ "$app" == "." || "$app" == ".." ]] && app=""
    if [[ -z "$app" ]]; then
        app=$(printf '%s' "$id" | sed 's/[^A-Za-z0-9._-]/_/g')
        [[ -z "$app" || "$app" == "." || "$app" == ".." ]] && app="unknown"
    fi
    printf '%s' "$app"
}

sw_aurelia_roots() { # stdout Steam 库根列表 (aurelia libraries -j → config → 默认); 无 aurelia/jq 返回 1
    command -v aurelia >/dev/null 2>&1 || return 1
    command -v jq >/dev/null 2>&1 || return 1
    local libs=""
    libs=$(aurelia libraries -j 2>/dev/null | jq -r '.libraries[]?.path // empty' 2>/dev/null)
    if [[ -z "$libs" ]]; then
        libs=$(aurelia config show -j 2>/dev/null | jq -r '.steam_library_path // empty' 2>/dev/null)
    fi
    if [[ -z "$libs" ]]; then
        libs="$HOME/.local/share/Steam"$'\n'"$HOME/.steam/steam"
    fi
    printf '%s\n' "$libs"
}

sw_aurelia_find() { # appid itemid → stdout 库内落盘深路径 (首个有内容的); 找不到返回 1
    local appid="$1" itemid="$2" r d
    while IFS= read -r r; do
        [[ -n "$r" ]] || continue
        d="$r/steamapps/workshop/content/$appid/$itemid"
        if [[ -d "$d" && -n "$(ls -A "$d" 2>/dev/null)" ]]; then
            echo "$d"
            return 0
        fi
    done < <(sw_aurelia_roots)
    return 1
}

sw_flatten_download() { # deep appid itemid [appname] [stopdir] → stdout 扁平路径; mv+prune+acf(仅隔离根)
    local deep="$1" appid="$2" itemid="$3" appname="${4:-}" stopdir="${5:-}"
    [[ -n "$deep" && -e "$deep" ]] || return 1
    local install_dir="${STEAMCMD_INSTALL_DIR:-${STEAM_WORKSHOP_DIR:-$HOME/Downloads/steam-workshop}}"
    [[ -z "$stopdir" ]] && stopdir="$install_dir"
    mkdir -p "$install_dir" 2>/dev/null || return 1
    local safe flat_leaf flat_parent flat_dir path prune
    path="$deep"
    safe=$(sw_safe_app "$appname" "$appid")
    flat_leaf="$safe"
    [[ "$safe" != "$appid" ]] && flat_leaf="${safe}_${appid}"
    flat_parent="$install_dir/$flat_leaf"
    flat_dir="$flat_parent/$itemid"
    if [[ "$path" != "$flat_dir" ]]; then
        mkdir -p "$flat_parent" 2>/dev/null || return 1
        rm -rf "$flat_dir" 2>/dev/null
        mv "$path" "$flat_dir" 2>/dev/null || return 1
        path="$flat_dir"
    fi
    # mv 后深路径只剩空架子: 逐层 rmdir 回收到 stopdir 为止
    # (单 rmdir 不带 -p, 循环条件钉死在 stopdir 内, 不会删到外面;
    #  aurelia 路径 stopdir 取 content/<appid>, 即库内不 prune, 只搬走)
    prune=$(dirname "$deep")
    while [[ "$prune" != "$stopdir" && "$prune" == "$stopdir"/* ]]; do
        rmdir "$prune" 2>/dev/null || break
        prune=$(dirname "$prune")
    done
    # 落盘已搬离深路径, acf 里该 appid 的 Installed/manifest 记录即成幽灵:
    # 下次同 appid 下载时 steamcmd 会按 acf 校验 content/ 下已不存在的文件
    # (content_log: CFileReader errno 2 → Missing game files → 整单 Failure)。
    # 成功即删 (下次全量重下, 反正 content 已搬空); 失败保留以便续传。
    # (appid 已在函数入口校验为纯数字, 路径钉死在隔离根内;
    #  aurelia 落盘不在隔离根, 不碰 acf)
    if [[ "$stopdir" == "$install_dir" ]]; then
        rm -f "$install_dir/steamapps/workshop/appworkshop_${appid}.acf" 2>/dev/null
    fi
    echo "$path"
}

sw_aurelia_download() { # appid itemid [appname] → stdout 扁平路径; 任何失败返回 1 (调用方 fallback steamcmd)
    local appid="$1" itemid="$2" appname="${3:-}"
    [[ "$appid" =~ ^[0-9]+$ && "$itemid" =~ ^[0-9]+$ ]] || return 1
    command -v aurelia >/dev/null 2>&1 || return 1
    command -v jq >/dev/null 2>&1 || return 1
    local log deep stopdir
    log=$(mktemp)
    # </dev/null: 禁止读调用方 stdin (sw_run_updates 正用 stdin 喂 UPDATE 行);
    # 无会话需交互时直接失败走 fallback, 不挂起
    if ! aurelia workshop install --no-recurse "$itemid" </dev/null >"$log" 2>&1; then
        cat "$log" >&2
        rm -f "$log"
        return 1
    fi
    rm -f "$log"
    deep=$(sw_aurelia_find "$appid" "$itemid") || return 1
    # 库内不 prune: stopdir 钉在 content/<appid> (== dirname(deep)), prune 循环零次执行
    stopdir=$(dirname "$deep")
    sw_flatten_download "$deep" "$appid" "$itemid" "$appname" "$stopdir"
}

sw_download() {
    local appid="$1" itemid="$2" user="${3:-anonymous}" appname="${4:-}"
    [[ "$appid" =~ ^[0-9]+$ && "$itemid" =~ ^[0-9]+$ ]] || return 1
    # driver: STEAM_WORKSHOP_DRIVER=auto (默认) 且有 aurelia 时优先 aurelia
    # (忽略 user, 走 aurelia 自身登录会话); 失败则落回 steamcmd。
    # STEAM_WORKSHOP_DRIVER=steamcmd 强制老路。
    # 注意: 调用方 (sw_run_updates) 会把 stderr 并入 stdout 比对路径,
    # 故 aurelia 失败输出必须暂存、仅 steamcmd 也失败时才打出, 否则污染路径比对致误删。
    local aur_err=""
    if [[ "${STEAM_WORKSHOP_DRIVER:-auto}" == "auto" ]]; then
        local aur_out
        if aur_out=$(sw_aurelia_download "$appid" "$itemid" "$appname" 2>&1); then
            echo "$aur_out"
            return 0
        fi
        aur_err="$aur_out"
    fi
    local -a login_arg=(+login anonymous)
    [[ "$user" != "anonymous" ]] && login_arg=(+login "$user")

    local install_dir="${STEAMCMD_INSTALL_DIR:-${STEAM_WORKSHOP_DIR:-$HOME/Downloads/steam-workshop}}"
    mkdir -p "$install_dir" 2>/dev/null || return 1

    local log rc=0 path=""
    log=$(mktemp)
    steamcmd +force_install_dir "$install_dir" "${login_arg[@]}" +workshop_download_item "$appid" "$itemid" +quit >"$log" 2>&1
    rc=$?

    path=$(grep -o 'Success\. Downloaded item [0-9]* to "[^"]*"' "$log" | head -1 | sed 's/.* to "//; s/"$//')
    if [[ $rc -eq 0 && -n "$path" && -e "$path" ]] \
        && sw_flatten_download "$path" "$appid" "$itemid" "$appname"; then
        rc=0
    elif grep -qiE 'invalid password|steam guard|not logged on|access denied|no subscription|logon failure|rate limit' "$log"; then
        rc=2
    else
        rc=1
    fi
    [[ $rc -ne 0 ]] && { [[ -n "$aur_err" ]] && printf '%s\n' "$aur_err" >&2; cat "$log" >&2; }
    rm -f "$log"
    return $rc
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    case "${1:-}" in
    parse) shift; sw_parse_itemid "$@" ;;
    appid) shift; sw_resolve_appid "$@" ;;
    info) shift; sw_item_info "$@" ;;
    users) shift; sw_list_users "$@" ;;
    download) shift; sw_download "$@" ;;
    *)
        echo "usage: $0 {parse|appid|info|users|download} ..." >&2
        exit 1
        ;;
    esac
fi
