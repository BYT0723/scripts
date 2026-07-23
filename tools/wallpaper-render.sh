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
		--audio-client-name=wallpaper \
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
	"video" | "page")
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
	"video" | "page")
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
			[[ $(detect_file_type "$w") == image ]] &&
				wallpapers+=("$w") || wallpapers+=("$filepath")
		done

		feh --bg-scale --no-fehbg "${wallpapers[@]}" >~/.wallpaper.log
		clean_latest "$monitor_index"
		;;
	esac
}
