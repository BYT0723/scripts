#!/usr/bin/env /bin/bash

WORK_DIR=$(dirname "$(dirname "$0")")

source $WORK_DIR/utils/monitor.sh
source "$WORK_DIR/utils/notify.sh"

#
# Focus: Do not use spaces in paths and filenames, unexpected consequences may occur
#

wallpaper_launch_delay=1

# wallpaper configuration file
conf="$HOME/.config/dwm/wallpaper.conf"
cache_wallpaper_dir="$HOME/.cache/wallpaper"
mkdir -p "$cache_wallpaper_dir"
wallpaper_latest="$cache_wallpaper_dir/wallpaper_latest"
wallpaper_full_latest="${wallpaper_latest}_full"
wallpaper_pid="$cache_wallpaper_dir/wallpaper_pid"
wallpaper_full_pid="${wallpaper_pid}_full"

# Define the default configuration
declare -A config
config["random"]=0
config["random_type"]="image"
config["random_image_dir"]="~/Pictures"
config["random_video_dir"]="~/Videos"
config["random_depth"]=3
config["duration"]=30
cmd="feh --no-fehbg --bg-scale /usr/share/backgrounds/archlinux/small.png"

# Get configuration value by key, with fallback to defaults
getConfig() {
    local key="$1"
    local value=""

    # Try reading from config file
    if [ -f "$conf" ]; then
        value=$(grep -E "^[[:space:]]*${key}[[:space:]]*=" "$conf" 2>/dev/null \
            | tail -1 | sed "s/^[^=]*=[[:space:]]*//;s/[[:space:]]*$//")
    fi

    # Fallback to default
    if [ -z "$value" ]; then
        value="${config[$key]}"
    fi

    echo "$value"
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
        mp4|mkv|avi|webm) echo "video" ;;
        jpg|jpeg|png) echo "image" ;;
        html|htm) echo "page" ;;
        *) echo "page" ;;
    esac
}

get_video_dim() {
	local file="$1"
	ffprobe -v error -select_streams v:0 \
		-show_entries stream=width,height \
		-of csv=p=0 "$file" 2>/dev/null | tr ',' ' '
}

# Returns 0 (true) if monitor and video have different orientation (landscape vs portrait)
orientation_mismatch() {
	local mw="$1" mh="$2" vw="$3" vh="$4"
	local ml=false vl=false
	[ "$mw" -gt "$mh" ] && ml=true
	[ "$vw" -gt "$vh" ] && vl=true
	[ "$ml" != "$vl" ]
}

# Returns "width height" for the selected monitor (or screen)
get_monitor_dim() {
	local select="$1" list="$2"
	if [[ "$select" == "Screen" ]]; then
		get_screen_size | sed 's/\([0-9]*\)x\([0-9]*\).*/\1 \2/'
	else
		local mon="$select"
		[[ "$mon" == "ALL" ]] && mon=$(echo "$list" | awk 'NR>1 {print $NF; exit}')
		xrandr --current | awk -v m="$mon" '
			$1==m {for(i=1;i<=NF;i++) if($i ~ /^[0-9]+x[0-9]+/) {split($i,a,"[x+]"); print a[1], a[2]; exit}}
		'
	fi
}

# Launch mpv preview with r=cycle rotation, q=quit; returns final rotation angle
preview_rotation() {
	local file="$1"
	local tmp=$(mktemp -d)
	local wld="$tmp/watch_later"; mkdir -p "$wld"
	cat > "$tmp/input.conf" <<'EOF'
r cycle-values video-rotate "90" "270" "0"
q quit
EOF
	mpv --no-config --no-osc --video-rotate=90 --loop \
		--input-conf="$tmp/input.conf" \
		--save-position-on-quit \
		--watch-later-directory="$wld" \
		--watch-later-options="video-rotate" \
		--autofit=800x600 \
		"$file" &>/dev/null
	local rotate="90"
	for f in "$wld"/*; do
		[ -f "$f" ] && rotate=$(grep "^video-rotate=" "$f" | cut -d= -f2) && break
	done
	rm -rf "$tmp"
	echo "${rotate:-90}"
}

find_wallpapers() {
    local dir="$1"
    local depth="$2"
    local pattern="$3"  # regex pattern for file extensions

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

check_command() {
    local cmd="$1"
    local friendly_name="$2"

    if ! command -v "$cmd" >/dev/null 2>&1; then
        error "Command '$cmd' not found. Please install $friendly_name"
        return 1
    fi
    return 0
}

safe_kill_pidfile() {
    local pidfile="$1"
    local signal="${2:-TERM}"

    if [ -f "$pidfile" ]; then
        local pid=$(cat "$pidfile" 2>/dev/null)
        if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
            kill -"$signal" "$pid" 2>/dev/null
            sleep 0.1
            if kill -0 "$pid" 2>/dev/null; then
                kill -KILL "$pid" 2>/dev/null
            fi
        fi
        rm -f "$pidfile"
    fi
}

TERM=${TERMINAL:-"kitty --class float-term -o font_size=8 -o initial_window_width=160c -o initial_window_height=48c"}


handle_error() {
    local level="$1"  # error, warning, info
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
	echo "      -r | --run             run wallpaper"
	echo "      -s | --set <path>      set wallpaper"
	echo "      -n | --next            random next wallpaper"
	echo "      -S | --select          use yazi select wallpaper to set"
}

clean_latest() {
    local monitor_index=$1

    # 开启 nullglob，保证通配符为空时不会报错
    shopt -s nullglob

    # Clean up full screen wallpaper
    safe_kill_pidfile "$wallpaper_full_pid"
    [ -f "$wallpaper_full_latest" ] && rm -f "$wallpaper_full_latest"

    local files=()
    if [ -n "$monitor_index" ]; then
        files=("${wallpaper_pid}_${monitor_index}")
    else
        files=("${wallpaper_pid}"_*)
    fi

    # 遍历每个匹配文件
    for f in "${files[@]}"; do
        [ ! -f "$f" ] && continue
        safe_kill_pidfile "$f"
        # Remove corresponding latest file
        local latest_file="${f/$wallpaper_pid/$wallpaper_latest}"
        [ -f "$latest_file" ] && rm -f "$latest_file"
    done
}

launch_video_xwinwrap() {
	# command detection using check_command
	check_command xwinwrap "xwinwrap (https://github.com/BYT0723/xwinwrap)" || return 1
	check_command mpv "mpv" || return 1

	local position=$1
	shift
	local rotate="$1"
	shift
	local filepath=$@

	local keymapConf=$(getConfig video_keymap_conf)
	keymapConf=$(expand_path "$keymapConf")

	[ -n "$rotate" ] && rotate="--video-rotate=$rotate"

	xwinwrap -ov -g "$position" -- mpv -wid WID "$filepath" \
		--no-config \
		--load-scripts=no \
		--no-keepaspect \
		--mute \
		--no-osc \
		--loop \
		--vid=1 \
		--no-ytdl \
		--no-terminal \
		--really-quiet \
		--cursor-autohide=no \
		--player-operation-mode=cplayer \
		--no-input-default-bindings \
		--hwdec=auto-safe \
		--vo=gpu-next \
		--framedrop=vo \
		--no-sub \
		--stop-screensaver=no \
		$rotate \
		--input-conf="$keymapConf" 2>&1 >~/.wallpaper.log &
}

launch_page_xwinwrap() {
	# command detection using check_command
	check_command xwinwrap "xwinwrap (https://github.com/BYT0723/xwinwrap)" || return 1
	check_command surf "surf" || return 1

	local position=$1
	shift
	local filepath=$@
	xwinwrap -ov -g "$position" -- tabbed -w WID -g $(echo $position | sed -E 's/^([0-9]+x[0-9]+).*/\1/') -r 2 surf -e '' "$filepath" >~/.wallpaper.log 2>&1 &
}

get_screen_size() {
    xrandr | awk -F',' '{for(i=1;i<=NF;i++) if($i ~ /current/) print $i}' | awk '{print $2 $3 $4}'
}

launch_dynamic_wallpaper() {
    local type="$1"
    local position="$2"
    local rotate="$3"
    local filepath="$4"

    case "$type" in
    "video") launch_video_xwinwrap "$position" "$rotate" "$filepath" || return 1 ;;
    "page") launch_page_xwinwrap "$position" "$filepath" || return 1 ;;
    *) return 1 ;;
    esac

    NEW_WALLPAPER_PID="$!"
    kill -0 "$NEW_WALLPAPER_PID" 2>/dev/null || return 1
}

set_wallpaper_to_screen() {
    local filepath="$@"
    local Type=$(detect_file_type "$filepath")

    # run different commands according to the type
    case "$Type" in
    "video"|"page")
        local screen_size
        screen_size=$(get_screen_size) || return

        clean_latest
        launch_dynamic_wallpaper "$Type" "$screen_size+0+0" "${WALLPAPER_ROTATION:-}" "$filepath" || return

        echo "$NEW_WALLPAPER_PID" >"$wallpaper_full_pid"
        echo "$filepath|${WALLPAPER_ROTATION:-}" >"$wallpaper_full_latest"
        ;;
    "image")
        feh --no-xinerama --bg-scale "$filepath" || return
        clean_latest
        # write command to configuration
        echo "$filepath" >"$wallpaper_full_latest"
        ;;
    esac
}

# set wallpaper
set_wallpaper_to_monitor() {
    local monitor_index=${1}
    shift
    local filepath="$@"

    [ -z "$monitor_index" ] && return

    read monitor_index width height x y < <(get_monitor_info_by_index "$monitor_index")

    local Type=$(detect_file_type "$filepath")

    # run different commands according to the type
    case "$Type" in
    "video"|"page")
        clean_latest "$monitor_index"
        launch_dynamic_wallpaper "$Type" "${width}x${height}+${x}+${y}" "${WALLPAPER_ROTATION:-}" "$filepath" || return

        echo "$NEW_WALLPAPER_PID" >"${wallpaper_pid}_${monitor_index}"
        echo "$filepath|${WALLPAPER_ROTATION:-}" >"${wallpaper_latest}_${monitor_index}"
        ;;
    "image")
        # command detection
        check_command feh "feh" || return

        echo "$filepath" >"${wallpaper_latest}_${monitor_index}"

		# 开启 nullglob，保证通配符为空时不会报错
		shopt -s nullglob

		local wallpapers=()
		for f in "${wallpaper_latest}"_[0-9]*; do
			IFS='|' read -r w _ <"$f" || continue
			[[ $(detect_file_type "$w") == image ]] \
				&& wallpapers+=("$w") || wallpapers+=("$filepath")
		done

        feh --bg-scale --no-fehbg "${wallpapers[@]}" > ~/.wallpaper.log
        clean_latest "$monitor_index"
        ;;
    esac
}

# return random wallpaper filepath
random_wallpaper() {
    local depth=$(getConfig random_depth)
    local random_type=$(getConfig random_type)
    local dir=""
    local pattern=""

    case "$random_type" in
    "video")
        dir=$(getConfig random_video_dir)
        pattern=".*\.(mp4|avi|mkv)"
        ;;
    "image")
        dir=$(getConfig random_image_dir)
        pattern=".*\.(jpeg|jpg|png)"
        ;;
    *)
        error "Unknown random type: $random_type"
        return
        ;;
    esac

    # Use find_wallpapers to get all matching files
    local files
    if ! files=$(find_wallpapers "$dir" "$depth" "$pattern"); then
        # Error already printed by find_wallpapers
        return
    fi

    # Convert newline-separated list to array
    local file_array=()
    mapfile -t file_array <<< "$files"

    # Randomly select one file
    local count=${#file_array[@]}
    local random_index=$((RANDOM % count))
    echo "${file_array[$random_index]}"
}

select_wallpaper() {
	local dir tmp=$(mktemp)

	case "$(getConfig random_type)" in
	video) dir=$(getConfig random_video_dir) ;;
	image) dir=$(getConfig random_image_dir) ;;
	esac

	YAZI_CONFIG_HOME=$HOME/.config/yazi_wallpaper $TERM yazi "$dir" --chooser-file="$tmp"

	echo "$(cat $tmp)"
	rm -f "$tmp"
}

set_wallpaper() {
    local skip_select=false
    [ "$1" == "-s" ] && skip_select=true && shift
    local select_file="$@"

    # Get monitors list with caching
    local monitors_list
    monitors_list=$(xrandr --listactivemonitors 2>/dev/null)

    if [ $(echo "$monitors_list" | wc -l) = 2 ]; then
        select=$(echo "$monitors_list" | awk 'END{print $NF}')
    elif [[ $skip_select = true ]]; then
        select="ALL"
    else
        monitors="ALL\n"$(echo "$monitors_list" | awk 'NR>1 {print $NF}')"\nScreen"
        select=$(echo -e "$monitors" | bash $WORK_DIR/rofi/scripts/common_list.sh \
			-w 1000 \
			-F "JetBrains Mono Nerd Font 16" \
			"Wallpaper" "Select a monitor")
    fi
    [ -z "$select" ] && return

    # Video rotation prompt (only when landscape vs portrait mismatch)
    WALLPAPER_ROTATION=""
    if [[ $(detect_file_type "$select_file") == "video" ]] && command -v ffprobe >/dev/null 2>&1; then
        local vid_dim=$(get_video_dim "$select_file")
        if [ -n "$vid_dim" ]; then
            read vid_w vid_h <<< "$vid_dim"
            read mon_w mon_h <<< "$(get_monitor_dim "$select" "$monitors_list")"
            if orientation_mismatch "$mon_w" "$mon_h" "$vid_w" "$vid_h"; then
                WALLPAPER_ROTATION=$(preview_rotation "$select_file")
            fi
        fi
    fi

    [[ "$select" = "Screen" ]] && set_wallpaper_to_screen "$select_file" && return
    echo "$monitors_list" | awk 'NR>1 {sub(":","",$1); print $1,$NF}' | while read -r monitor_index monitor_name; do
        if [[ $select = "ALL" ]] || [[ $select = "$monitor_name" ]]; then
            set_wallpaper_to_monitor "$monitor_index" "$select_file"
        fi
    done
}

set_latest() {
	if [ -f "$wallpaper_full_latest" ]; then
		IFS='|' read -r fp rot < "$wallpaper_full_latest"
		WALLPAPER_ROTATION="$rot"
		set_wallpaper_to_screen "$fp" && return
	fi

	local files=()
	files=("${wallpaper_latest}"_[0-9]*)
	# 遍历每个匹配文件
	for f in "${files[@]}"; do
		local monitor_index=$(echo "$f" | awk -F '_' '{print $NF}')
		IFS='|' read -r fp rot < "$f"
		WALLPAPER_ROTATION="$rot"
		set_wallpaper_to_monitor "$monitor_index" "$fp" &
	done
}

# wallpaper launch_wallpaper
launch_wallpaper() {
	sleep $wallpaper_launch_delay

	# kill last daemon
	script=$(readlink -f "$0")
	pgrep -f "$script" | grep -vx "$$" | xargs -r kill

	set_latest

	while true; do
		sleep "$(($(getConfig duration) * 60))"
		[ "$(getConfig random)" -eq 1 ] && set_wallpaper "$(random_wallpaper)" true
	done
}

# 操作符
op=$1

case "$op" in
'-r' | '--run') launch_wallpaper ;;
'-s' | '--set')
	shift
	set_wallpaper "$@"
	;;
'-n' | '--next') set_wallpaper -s "$(random_wallpaper)" ;;
'-S' | '--select')
	select_file="$(select_wallpaper)"
	[ -n "$select_file" ] && set_wallpaper "$select_file"
	;;
'-h' | '--help') echo_help ;;
*)
	echo -e "\033[31mbad operator\033[0m"
	echo_help
	;;
esac

exit 0
