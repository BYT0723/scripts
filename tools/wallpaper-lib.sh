_WALLPAPER_LIB_DIR="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"
source "$_WALLPAPER_LIB_DIR/../utils/monitor.sh"

wallpaper_launch_delay=1

# wallpaper configuration file
conf="$HOME/.config/dwm/wallpaper.json"
cache_wallpaper_dir="$HOME/.cache/wallpaper"
mkdir -p "$cache_wallpaper_dir"

# Create default config if missing
[ ! -f "$conf" ] && jq -n '{
    "render": {
        "video": {
            "fps": 30
        }
    },
    "monitors": [],
    "groups": []
}' >"$conf"

# 当前壁纸状态 (latest) 已由 xwallpaper 持久化管理
# (state 文件按 name 记录 type/path/rotation/geom, daemon 启动自动恢复)。
# 本文件仅保留 rotation_cache (文件方向角度缓存, 非当前状态)。
rotation_cache="$cache_wallpaper_dir/rotation_cache"

# Define the default configuration
declare -A config
config["random"]=0
config["random_type"]="image"
config["random_image_dir"]="~/Pictures"
config["random_video_dir"]="~/Videos"
config["random_depth"]=3
config["duration"]=30

# ---- xwallpaper 渲染接口 (共享给 wallpaper.sh 与 rofi 脚本) ----

# 可选的视频按键配置 (mpv input.conf 格式)
_WALLPAPER_KEYBINDS="${WALLPAPER_KEYBINDS:-$HOME/.config/dwm/wallpaper.keys}"

# 构造并执行 xwallpaper set 命令。
# 用法: xw_set <type> <rect> <target> <filepath> [<rotate>]
# type ∈ image|video|page (page 映射为 xwallpaper 的 web 后端)
xw_set() {
    local type="$1"
    local rect="$2"
    local target="$3"
    local filepath="$4"
    local rotate="${5:-}"

    local backend="$type"
    [ "$backend" = "page" ] && backend="web"

    local args=(set "--$backend" -g "$rect" --name "$target")
    if [ "$type" = "video" ]; then
        args+=(--mute)
        [ -n "$rotate" ] && args+=(--rotate "$rotate")
        local fps
        fps=$(getConfig render.video.fps)
        [ -n "$fps" ] && [[ $fps -gt 0 ]] && args+=(--fps "$fps")
        [ -n "$_WALLPAPER_KEYBINDS" ] && [ -f "$_WALLPAPER_KEYBINDS" ] &&
            args+=(--keybinds "$_WALLPAPER_KEYBINDS")
    fi
    xwallpaper "${args[@]}" "$filepath"
}

# 移除一个 target 的壁纸窗口 (monitor 名 / grp_<组名> / Screen)
xw_clear() {
    local target="$1"
    xwallpaper clear -m "$target"
}

# 移除窗口但保留 last 状态 (xwallpaper clear --keep); restore 命令可将其恢复
xw_clear_keep() {
    local target="$1"
    xwallpaper clear --keep -m "$target"
}

# 清空所有壁纸窗口 (Screen + 所有 monitor + 所有 group)。
# monitor/group 用 --keep 保留 last, 供 screen 清除后 restore 恢复
xw_clear_all() {
    xw_clear "Screen"

    local mon
    while IFS= read -r mon; do
        [ -z "$mon" ] && continue
        xw_clear_keep "$mon"
    done < <(xrandr --listactivemonitors 2>/dev/null | awk 'NR>1 {print $NF}')

    local grp
    while IFS= read -r grp; do
        [ -z "$grp" ] && continue
        xw_clear_keep "grp_${grp// /_}"
    done < <(group_names)
}

# 设置 monitor/group 壁纸前清除全屏壁纸窗口; screen 曾激活时 restore 回退被 keep 的 last 壁纸
xw_clear_screen_and_restore() {
    local was_screen=false
    [ -n "$(xwallpaper state 2>/dev/null | awk -F'\t' '$1=="Screen"')" ] && was_screen=true
    xw_clear "Screen"
    $was_screen && xwallpaper restore
}

# 设置壁纸。旋转角度取全局 WALLPAPER_ROTATION。
# 用法: xw_apply <type> <rect> <target> <filepath>
# 当前壁纸状态由 xwallpaper 持久化 (daemon 重启自动恢复), 本层不再写缓存文件。
# 成功返回 0；失败打印错误并返回 1。
xw_apply() {
    local type="$1"
    local rect="$2"
    local target="$3"
    local filepath="$4"

    if ! xw_set "$type" "$rect" "$target" "$filepath" "${WALLPAPER_ROTATION:-}"; then
        error "xwallpaper set failed"
        return 1
    fi
    return 0
}

# 若 monitor 尚无配置，用脚本内默认值初始化写入 config
ensure_monitor_config() {
    local monitor="$1"
    [ -z "$monitor" ] && return
    jq -e --arg m "$monitor" '.monitors[$m]' "$conf" >/dev/null 2>&1 && return

    local obj
    obj=$(for k in "${!config[@]}"; do printf '"%s": "%s",' "$k" "${config[$k]}"; done)
    obj="{${obj%,}}"
    jq --arg m "$monitor" ".monitors[\$m] = $obj" "$conf" >"$conf.tmp" && mv "$conf.tmp" "$conf"
}

# Get configuration value by key, with fallback to defaults
# Usage: getConfig [-m <monitor>] <key>
getConfig() {
    local monitor=""
    [ "$1" = "-m" ] && monitor="$2" && shift 2
    local key="$1"

    if [ -f "$conf" ]; then
        if [ -n "$monitor" ]; then
            local val=$(jq -r ".monitors[\"$monitor\"].$key // empty" "$conf" 2>/dev/null)
            [ -n "$val" ] && echo "$val" && return
        fi
        # Try defaults
        local val=$(jq -r ".defaults.$key // empty" "$conf" 2>/dev/null)
        [ -n "$val" ] && echo "$val" && return
        # Try top-level
        local val=$(jq -r ".$key // empty" "$conf" 2>/dev/null)
        [ -n "$val" ] && echo "$val" && return
    fi

    # Hardcoded fallback
    echo "${config[$key]}"
}

# ---- Group functions ----

has_group() {
    [ -n "$1" ] && jq -e ".groups[\"$1\"]" "$conf" >/dev/null 2>/dev/null
}

group_names() {
    jq -r '.groups // {} | keys[]' "$conf" 2>/dev/null
}

get_group_members() {
    local group="$1"
    jq -r ".groups[\"$group\"].members[]" "$conf" 2>/dev/null
}

get_group_enabled() {
    local group="$1"
    local val=$(jq -r ".groups[\"$group\"].enabled" "$conf" 2>/dev/null)
    [ "$val" = "null" ] || [ -z "$val" ] && echo "true" || echo "$val"
}

group_for_monitor() {
    local monitor="$1"
    local all="${2:-}"
    [ -z "$monitor" ] && return 1
    while IFS= read -r grp; do
        [ -z "$grp" ] && continue
        if [ -z "$all" ]; then
            [ "$(get_group_enabled "$grp")" != "true" ] && continue
        fi
        local members=" $(echo $(get_group_members "$grp")) "
        [[ "$members" == *" $monitor "* ]] && {
            echo "$grp"
            return 0
        }
    done < <(group_names)
    return 1
}

is_group_member() {
    group_for_monitor "$1" >/dev/null
}

# Utility functions
expand_path() {
    local path="$1"
    path=$(printf '%s\n' "$path" | envsubst)
    echo "${path/#\~/$HOME}"
}

detect_file_type() {
    local filepath="$1"
    local baseFilename=$(basename "${filepath// /_}")
    local Type="${baseFilename##*.}"

    case "$Type" in
    mp4 | mkv | avi | webm) echo "video" ;;
    jpg | jpeg | png) echo "image" ;;
    html | htm) echo "page" ;;
    *) echo "page" ;;
    esac
}

# 返回视频有效显示尺寸: 编码横屏但带 ±90 rotation 元数据的手机竖拍视频实际为竖屏,
# 仅读 width,height 会误判方向。
get_video_dim() {
    local file="$1"
    local dims w h rot
    dims=$(ffprobe -v error -select_streams v:0 \
        -show_entries stream=width,height \
        -of csv=p=0 "$file" 2>/dev/null | tr ',' ' ')
    [ -n "$dims" ] || return
    read w h <<<"$dims"
    rot=$(ffprobe -v error -select_streams v:0 \
        -show_entries stream_side_data=rotation \
        -of default=nw=1:nk=1 "$file" 2>/dev/null)
    case "$rot" in
    90 | -90 | 270 | -270) echo "$h $w" ;;
    *) echo "$w $h" ;;
    esac
}

# Returns 0 (true) if monitor and video have different orientation (landscape vs portrait)
orientation_mismatch() {
    local mw="$1" mh="$2" vw="$3" vh="$4"
    local ml=false vl=false
    [ "$mw" -gt "$mh" ] && ml=true
    [ "$vw" -gt "$vh" ] && vl=true
    [ "$ml" != "$vl" ]
}

get_group_dim() {
    local group="$1"
    local min_x="" min_y="" max_x="" max_y="" first=true
    local idx w h x y info
    while IFS= read -r member; do
        [ -z "$member" ] && continue
        info=$(get_monitor_info "$member" 2>/dev/null)
        [ -z "$info" ] && continue
        read idx w h x y <<<"$info"
        if $first; then
            min_x="$x"
            min_y="$y"
            max_x="$((x + w))"
            max_y="$((y + h))"
            first=false
        else
            [ "$x" -lt "$min_x" ] && min_x="$x"
            [ "$y" -lt "$min_y" ] && min_y="$y"
            [ "$((x + w))" -gt "$max_x" ] && max_x="$((x + w))"
            [ "$((y + h))" -gt "$max_y" ] && max_y="$((y + h))"
        fi
    done < <(get_group_members "$group")
    [ -z "$min_x" ] && {
        error "No active members in group '$group'"
        return 1
    }
    echo "$((max_x - min_x)) $((max_y - min_y)) $min_x $min_y"
}

# Returns "width height" for the selected monitor (or screen)
get_monitor_dim() {
    local select="$1"
    if [[ "$select" == "Screen" ]]; then
        get_screen_size | sed 's/\([0-9]*\)x\([0-9]*\).*/\1 \2/'
    elif has_group "$select"; then
        get_group_dim "$select" | awk '{print $1, $2}'
    else
        xrandr --current | awk -v m="$select" '
            $1==m {for(i=1;i<=NF;i++) if($i ~ /^[0-9]+x[0-9]+/) {split($i,a,"[x+]"); print a[1], a[2]; exit}}
        '
    fi
}

# Launch mpv preview with r=cycle rotation, q=quit; returns final rotation angle
# 初始 video-rotate=0 (而非 90): mpv 的 video-rotate 叠加在元数据之上, 硬编码 90 会让竖屏视频初始显示为横屏,
# 且 watch-later 不写默认值 0 时 fallback 不能回落到 90。返回值与 xwallpaper --rotate 同引擎同语义。
preview_rotation() {
    local file="$1"
    local tmp=$(mktemp -d)
    local wld="$tmp/watch_later"
    mkdir -p "$wld"
    cat >"$tmp/input.conf" <<'EOF'
r cycle-values video-rotate "0" "90" "180" "270"
q quit
EOF
    mpv \
        --no-config \
        --no-osc \
        --video-rotate=0 \
        --loop \
        --mute \
        --audio-client-name=wallpaper \
        --input-conf="$tmp/input.conf" \
        --save-position-on-quit \
        --watch-later-directory="$wld" \
        --watch-later-options="video-rotate" \
        --autofit=800x600 \
        "$file" &>/dev/null
    local rotate
    rotate=$(grep -h '^video-rotate=' "$wld"/* 2>/dev/null | head -1 | cut -d= -f2)
    rm -rf "$tmp"
    echo "${rotate:-0}"
}

find_wallpapers() {
    local dir="$1"
    local depth="$2"
    local pattern="$3" # regex pattern for file extensions

    # Expand path
    dir=$(expand_path "$dir")

    if [ ! -d "$dir" ]; then
        error "Directory does not exist: $dir"
        return 1
    fi

    # Use mapfile to read all matching files into array
    local files=()
    if ! mapfile -t files < <(find "$dir" -maxdepth "$depth" -type f -regextype posix-extended -regex "$pattern" 2>/dev/null); then
        error "Failed to search for wallpapers in $dir"
        return 1
    fi

    if [ ${#files[@]} -eq 0 ]; then
        error "No matching wallpapers found in $dir"
        return 1
    fi

    # Output each file on a new line
    printf '%s\n' "${files[@]}"
}

TERM=${TERMINAL:-"kitty --class float-term -o font_size=8 -o initial_window_width=160c -o initial_window_height=48c"}

handle_error() {
    local level="$1" # error, warning, info
    local message="$2"
    local exit_code="${3:-0}"

    case "$level" in
    "error")
        echo -e "\033[31mError: $message\033[0m" >&2
        # Use existing system-notify function if available
        if command -v system-notify >/dev/null 2>&1; then
            system-notify critical "Wallpaper Error" "$message"
        fi
        ;;
    "warning")
        echo -e "\033[33mWarning: $message\033[0m" >&2
        if command -v system-notify >/dev/null 2>&1; then
            system-notify normal "Wallpaper Warning" "$message"
        fi
        ;;
    "info")
        echo -e "\033[32mInfo: $message\033[0m"
        if command -v system-notify >/dev/null 2>&1; then
            system-notify low "Wallpaper Info" "$message"
        fi
        ;;
    esac

    [ "$exit_code" -ne 0 ] && exit "$exit_code"
}

error() {
    handle_error "error" "$1" "${2:-0}"
}

# print help information
echo_help() {
    echo -e "Help Message"
    echo "      -r | --run             run wallpaper daemon"
    echo "      -m <mon> <next|select> apply to specific monitor"
}

clean_target() {
    local type="$1"
    local target="$2"

    case "$type" in
    screen)
        xw_clear "Screen"
        ;;
    mon)
        local idx="$target"
        local mon_name
        mon_name=$(xrandr --listactivemonitors 2>/dev/null | awk -v i="$idx" 'NR>1 && $1+0==i {print $NF; exit}')
        if [ -n "$mon_name" ]; then
            xw_clear "$mon_name"
            local grp=$(group_for_monitor "$mon_name" all)
            if [ -n "$grp" ]; then
                local gs="${grp// /_}"
                xw_clear "grp_${gs}"
            fi
        fi
        ;;
    grp)
        local gs="${target// /_}"
        xw_clear "grp_${gs}"
        while IFS= read -r mon_name; do
            [ -z "$mon_name" ] && continue
            xw_clear "$mon_name"
        done < <(get_group_members "$target")
        ;;
    esac
}

get_screen_size() {
    xrandr | awk -F',' '{for(i=1;i<=NF;i++) if($i ~ /current/) print $i}' | awk '{print $2 $3 $4}'
}

# ---- Shared helpers for tools/wallpaper.sh and rofi/scripts/wallpaper.sh ----

_WALLPAPER_HOME_DIR="$(dirname "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")")"
source "$_WALLPAPER_HOME_DIR/rofi/scripts/lib-module.sh"

# Format xrandr monitor list for display. Single monitor returns just its name.
get_monitor_list_text() {
    local monitor_icon="󰍹"
    local group_icon=""
    local monitors_list=$(xrandr --listactivemonitors 2>/dev/null)

    if [ "$(echo "$monitors_list" | wc -l)" = 2 ]; then
        echo "$monitors_list" | awk 'END{print $NF}'
        return
    fi

    local screen_dim=$(get_screen_size | sed 's/+.*//')
    printf "%s %-26s %s\n" "$monitor_icon" "Screen" "$screen_dim"
    echo "$monitors_list" | awk -v icon="$monitor_icon" 'NR > 1 {
        gsub("/[0-9]+", "", $3)
        split($3, a, "+")
        split(a[1], b, "x")
        printf "%s %-26s %sx%s\n", icon, $NF, b[1], b[2]
    }'

    while IFS= read -r grp; do
        [ -z "$grp" ] && continue
        [ "$(get_group_enabled "$grp")" != "true" ] && continue
        local dims=$(get_group_dim "$grp" 2>/dev/null) || continue
        local gw gh
        read gw gh _ _ <<<"$dims"
        printf "%s %-26s %sx%s\n" "$group_icon" "$grp" "$gw" "$gh"
    done < <(group_names)
}

# Pick config directory via yazi, write to wallpaper.json
pick_config_dir() {
    local monitor="$1"
    local key="$2"
    local json_path=".monitors[\"$monitor\"]"
    local cur=$(getConfig -m "$monitor" "$key")
    local cur_dir=$(expand_path "$cur")
    [ ! -d "$cur_dir" ] && cur_dir="$HOME"
    local tmp=$(mktemp)
    YAZI_CONFIG_HOME=$HOME/.config/yazi_wallpaper $TERM yazi "$cur_dir" --chooser-file="$tmp"
    local chosen=$(cat "$tmp" 2>/dev/null)
    rm -f "$tmp"
    if [ -n "$chosen" ]; then
        [ -d "$chosen" ] && chosen="$chosen" || chosen=$(dirname "$chosen")
        jq --arg d "$chosen" "${json_path}.${key} = \$d" "$conf" >"$conf.tmp" && mv "$conf.tmp" "$conf"
    fi
}

# Prompt for a numeric config value via rofi, validate, and write to wallpaper.json
set_numeric_config() {
    local monitor="$1"
    local key="$2"
    local prompt="$3"
    local mesg="$4"
    local min="${5:-1}"
    local max="${6:-99999}"

    local json_path=".monitors[\"$monitor\"]"
    local cur=$(getConfig -m "$monitor" "$key")
    local new=$(module_input "$prompt" "$mesg" "$cur")
    [ -n "$new" ] && [ "$new" -ge "$min" ] 2>/dev/null && [ "$new" -le "$max" ] 2>/dev/null &&
        jq "${json_path}.${key} = $new" "$conf" >"$conf.tmp" && mv "$conf.tmp" "$conf"
}
