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

	local fps=$(getConfig render.video.fps)
	local fps_flag=""
	[ -n "$fps" ] && fps_flag="--vf=fps=$fps"

	xwinwrap -ov -g "$position" -- mpv -wid WID "$filepath" \
		$fps_flag \
		--no-config \
		--load-scripts=no \
		--no-keepaspect \
		--mute \
		--audio-client-name=wallpaper \
		--no-osc \
		--loop \
		--vid=1 \
		--no-ytdl \
		--no-terminal \
		--really-quiet \
		--video-sync=audio \
		--cursor-autohide=no \
		--player-operation-mode=cplayer \
		--no-input-default-bindings \
		--hwdec=auto-safe \
		--vo=gpu-next \
		--framedrop=vo \
		--no-sub \
		--stop-screensaver=no \
		--image-display-duration=inf \
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

launch_dynamic_wallpaper() {
	local type="$1"
	local position="$2"
	local rotate="$3"
	local filepath="$4"

	case "$type" in
	"video" | "image") launch_video_xwinwrap "$position" "$rotate" "$filepath" || return 1 ;;
	"page") launch_page_xwinwrap "$position" "$filepath" || return 1 ;;
	*) return 1 ;;
	esac

	NEW_WALLPAPER_PID="$!"
	kill -0 "$NEW_WALLPAPER_PID" 2>/dev/null || return 1
}

# 读取 latest 文件，若内容为 image 则输出路径，否则输出空
_feh_resolve() {
	local lf="$1"
	[ -f "$lf" ] || return 1
	local fp=$(head -1 "$lf" | cut -d'|' -f1)
	[ -n "$fp" ] && [ "$(detect_file_type "$fp")" = "image" ] && echo "$fp"
}

# 按 monitor 顺序收集图片路径，组 monitor 取组壁纸代，无图片用黑底占位，统一调 feh --bg-scale
_feh_refresh() {
	[ -f "$wallpaper_full_latest" ] && return
	local images=()
	while IFS= read -r mon; do
		local fp=""
		local grp=$(group_for_monitor "$mon")
		if [ -n "$grp" ] && [ "$(get_group_enabled "$grp")" = "true" ]; then
			local gs="${grp// /_}"
			fp=$(_feh_resolve "${wallpaper_latest}_grp_${gs}")
		fi
		[ -z "$fp" ] && fp=$(_feh_resolve "${wallpaper_latest}_$(get_monitor_info "$mon" 2>/dev/null | awk '{print $1}')")
		images+=("${fp:-$_FEH_BLACK}")
	done < <(xrandr --listactivemonitors 2>/dev/null | awk 'NR>1 {print $NF}')
	[ ${#images[@]} -gt 0 ] && feh --bg-scale "${images[@]}"
}

# 确保黑色占位图存在
_FEH_BLACK="${cache_wallpaper_dir}/.feh_black.png"
if [ ! -f "$_FEH_BLACK" ]; then
	base64 -d <<'EOF' >"$_FEH_BLACK"
iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAA
AABJRU5ErkJggg==
EOF
fi

set_wallpaper_to_screen() {
	local filepath="$@"
	local Type=$(detect_file_type "$filepath")

	# run different commands according to the type
	case "$Type" in
	"video" | "page")
		local screen_size
		screen_size=$(get_screen_size) || return

		clean_target "screen"
		launch_dynamic_wallpaper "$Type" "$screen_size+0+0" "${WALLPAPER_ROTATION:-}" "$filepath" || return

		echo "$NEW_WALLPAPER_PID" >"$wallpaper_full_pid"
		echo "$filepath|${WALLPAPER_ROTATION:-}" >"$wallpaper_full_latest"
		;;
	"image")
		feh --no-xinerama --bg-scale "$filepath" || return
		clean_target "screen"
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
	"video" | "page")
		clean_target "mon" "$monitor_index"
		launch_dynamic_wallpaper "$Type" "${width}x${height}+${x}+${y}" "${WALLPAPER_ROTATION:-}" "$filepath" || return

		echo "$NEW_WALLPAPER_PID" >"${wallpaper_pid}_${monitor_index}"
		echo "$filepath|${WALLPAPER_ROTATION:-}" >"${wallpaper_latest}_${monitor_index}"
		;;
	"image")
		clean_target "mon" "$monitor_index"
		echo "$filepath" >"${wallpaper_latest}_${monitor_index}"
		_feh_refresh
		;;
	esac
}

set_wallpaper_to_group() {
	local group="$1"
	shift
	local filepath="$@"

	local Type=$(detect_file_type "$filepath")

	local dims
	dims=$(get_group_dim "$group" 2>/dev/null) || return 1
	local w h x y
	read w h x y <<<"$dims"

	clean_target "grp" "$group"
	launch_dynamic_wallpaper "$Type" "${w}x${h}+${x}+${y}" "${WALLPAPER_ROTATION:-}" "$filepath" || return 1

	local gs="${group// /_}"
	echo "$NEW_WALLPAPER_PID" >"${wallpaper_pid}_grp_${gs}"
	echo "$filepath|${WALLPAPER_ROTATION:-}" >"${wallpaper_latest}_grp_${gs}"

	[ "$Type" = "image" ] && _feh_refresh
}
