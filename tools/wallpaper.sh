#!/usr/bin/env /bin/bash

WORK_DIR=$(dirname "$(dirname "$0")")

#
# Focus: Do not use spaces in paths and filenames, unexpected consequences may occur
#

# wallpaper configuration file
conf="${XDG_CONFIG_HOME:-$HOME/.config}/dwm/wallpaper.conf"
cache_wallpaper_dir="$HOME/.cache/wallpaper"
mkdir -p "$cache_wallpaper_dir"
wallpaper_latest="$cache_wallpaper_dir/wallpaper_latest"
wallpaper_pid="$cache_wallpaper_dir/wallpaper_pid"

# Define the default configuration
declare -A config
config["random"]=0
config["random_type"]="image"
config["random_image_dir"]="~/Pictures"
config["random_video_dir"]="~/Videos"
config["random_depth"]=3
config["duration"]=30
cmd="feh --no-fehbg --bg-scale /usr/share/backgrounds/archlinux/small.png"

TERM=${TERMINAL:-"kitty --class float-term -o font_size=8 -o initial_window_width=160c -o initial_window_height=48c"}

source $WORK_DIR/utils/monitor.sh

# Get single configuration
getConfig() {
	if [ -f $conf ]; then
		res=$(cat $conf | grep -E "^$1\s*=" | tail -n 1 | awk -F '=' '{print $2}' | grep -o "[^ ]\+\( \+[^ ]\+\)*")
		if [ -z "$res" ]; then
			echo ${config[$1]}
		else
			echo $res
		fi
	else
		echo ${config[$1]}
	fi
}

error() {
	echo -e "\033[31m"$1"\033[0m"
}

# print help information
echo_help() {
	echo -e "Help Message"
	echo "      -r | --run             run wallpaper"
	echo ""
	echo "      -s | --set <path>      set wallpaper"
	echo ""
	echo "      -n | --next            random next wallpaper"
}

clean_latest() {
	local monitor_index=${1:-}

	# 开启 nullglob，保证通配符为空时不会报错
	shopt -s nullglob

	local files=()

	if [ -n "$monitor_index" ]; then
		files=("${wallpaper_pid}_${monitor_index}")
	else
		files=("${wallpaper_pid}"_*)
	fi

	# 遍历每个匹配文件
	for f in "${files[@]}"; do
		[ ! -f $f ] && continue

		pid=$(cat $f)
		[ ! -z "$pid" ] && kill $pid
		rm -f "$f"
	done
}

# set wallpaper
set_wallpaper() {
	local filepath=""
	local monitor_index=""

	# 解析短参数 -m
	while getopts "m:" opt; do
		case "$opt" in
		m) monitor_index="$OPTARG" ;;
		esac
	done

	shift $((OPTIND - 1)) # 剩下的参数就是 filepath
	filepath="$@"

	if [ -n "$monitor_index" ]; then
		read monitor_index width height x y < <(get_monitor_info_by_index "$monitor_index")
	else
		if [ $(xrandr --listactivemonitors | wc -l) = 2 ]; then
			select_monitor_name=$(xrandr --listactivemonitors | awk 'END{print $NF}')
		else
			select_monitor_name=$(xrandr --listactivemonitors | awk 'NR>1 {print $NF}' | bash $WORK_DIR/rofi/scripts/common_list.sh "Wallpaper" "Select a monitor")
			[ -z "$select_monitor_name" ] && return
		fi

		read monitor_index width height x y < <(get_monitor_info "$select_monitor_name")
	fi

	clean_latest $monitor_index

	baseFilename=$(basename "${filepath// /_}")

	# get file suffix
	Type="${baseFilename##*.}"

	# classify according to the suffix
	case "$Type" in
	'mp4' | mkv | avi)
		Type="video"
		;;
	jpg | jpeg | png)
		Type="image"
		;;
	html | htm)
		Type="page"
		;;
	*)
		Type="page"
		;;
	esac

	# run different commands according to the type
	case "$Type" in
	"video")
		# command detection
		if ! [[ -n $(command -v xwinwrap) ]]; then
			echo "set video to wallpaper need xwinwrap, install xwinwrap(https://github.com/BYT0723/xwinwrap) package"
			return
		fi
		if ! [[ -n $(command -v mpv) ]]; then
			echo "set video to wallpaper need mpv, install mpv package"
			return
		fi

		local keymapConf=$(getConfig video_keymap_conf)

		keymapConf=$(printf '%s\n' "$keymapConf" | envsubst)
		keymapConf="${keymapConf/#\~/$HOME}"

		xwinwrap -ov -g "${width}x${height}+${x}+${y}" -- mpv -wid WID "$filepath" \
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
			--cache \
			--framedrop=decoder \
			--vf=scale=2560:-1,fps=60 \
			--no-sub \
			--demuxer-max-bytes=256MiB \
			--demuxer-readahead-secs=20 \
			--input-conf=$keymapConf 2>&1 >~/.wallpaper.log &

		# 获取上一个命令的pid
		echo "$!" >"${wallpaper_pid}_${monitor_index}"

		# write command to configuration
		echo "$filepath" >"${wallpaper_latest}_${monitor_index}"

		;;
	"image")
		# command detection
		if ! [[ -n $(command -v feh) ]]; then
			echo "set image to wallpaper need feh, install feh package"
			return
		fi

		# write command to configuration
		echo "$filepath" >"${wallpaper_latest}_${monitor_index}"

		local wallpapers=()

		for f in "${wallpaper_latest}"_[0-9]*; do
			[ -f "$f" ] && read -r w < "$f" && wallpapers+=("$w")
		done

		feh --bg-scale --no-fehbg "${wallpapers[@]}" > ~/.wallpaper.log
		;;
	"page")
		# command detection
		if ! [[ -n $(command -v xwinwrap) ]]; then
			echo "set video to wallpaper need xwinwrap, install xwinwrap(https://github.com/BYT0723/xwinwrap) package"
			return
		fi
		if ! [[ -n $(command -v surf) ]]; then
			echo "set page to wallpaper need surf, install surf package"
			return
		fi

		xwinwrap -ov -g "${width}x${height}+${x}+${y}" -- tabbed -w WID -g $(echo $position | sed -E 's/^([0-9]+x[0-9]+).*/\1/') -r 2 surf -e '' $filepath 2>&1 >~/.wallpaper.log 2>&1 >~/.wallpaper.log &

		# 获取上一个命令的pid
		echo "$!" >"${wallpaper_pid}_${monitor_index}"

		echo "$filepath" >"${wallpaper_latest}_${monitor_index}"
		;;
	esac
}

# next random wallpaper
next_wallpaper() {
	clean_latest

	depth=$(getConfig random_depth)

	# run different command according to the `random_type` in the configuration
	case "$(getConfig random_type)" in
	"video")

		local dir=$(getConfig random_video_dir)

		# 展开环境变量
		dir=$(printf '%s\n' "$dir" | envsubst)
		dir="${dir/#\~/$HOME}"

		if [[ ! -d "$dir" ]]; then
			error "No target directory $dir"
			return
		fi

		len=$(find $dir -maxdepth $depth -type f -regextype posix-extended -regex ".*\.(mp4|avi|mkv)" | wc -l)

		if [ $len == 0 ]; then
			error "No target wallpaper found in "$dir
			return
		fi

		# Randomly get a video wallpaper
		random=$(($RANDOM % $len + 1))
		filename=$(find $dir -maxdepth $depth -type f -regextype posix-extended -regex ".*\.(mp4|avi|mkv)" | head -n $random | tail -n 1)

		local keymapConf=$(getConfig video_keymap_conf)
		keymapConf=$(printf '%s\n' "$keymapConf" | envsubst)
		keymapConf="${keymapConf/#\~/$HOME}"

		for name in $(xrandr --listactivemonitors | awk 'NR>1 {print $NF}'); do
			read index width height x y < <(get_monitor_info "$name")
			xwinwrap -ov -g "${width}x${height}+${x}+${y}" -- mpv -wid WID "$filename" \
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
				--cache \
				--framedrop=decoder \
				--vf=scale=2560:-1,fps=60 \
				--no-sub \
				--demuxer-max-bytes=256MiB \
				--demuxer-readahead-secs=20 \
				--input-conf=$keymapConf 2>&1 >~/.wallpaper.log &

			echo $! >"${wallpaper_pid}_${index}"
			echo $filename >"${wallpaper_latest}_${index}"
		done
		;;
	"image")
		local dir=$(getConfig random_image_dir)

		# 展开环境变量
		dir=$(printf '%s\n' "$dir" | envsubst)
		dir="${dir/#\~/$HOME}"

		if [[ ! -d "$dir" ]]; then
			error "No target directory $dir"
			return
		fi

		len=$(find $dir -maxdepth $depth -type f -regextype posix-extended -regex ".*\.(jpeg|jpg|png)" | wc -l)

		if [ $len == 0 ]; then
			error "No target wallpaper found in "$dir
			return
		fi

		# Randomly get a video wallpaper
		random=$(($RANDOM % $len + 1))
		filename=$(find $dir -maxdepth $depth -type f -regextype posix-extended -regex ".*\.(jpeg|jpg|png)" | head -n $random | tail -n 1)

		for name in $(xrandr --listactivemonitors | awk 'NR>1 {print $NF}'); do
			read index width height x y < <(get_monitor_info "$name")
			echo $filename >"${wallpaper_latest}_${index}"
		done

		feh --bg-scale --no-fehbg "$filename" >~/.wallpaper.log
		;;
	esac
}

select_wallpaper() {
	local dir file tmp=$(mktemp)

	case "$(getConfig random_type)" in
	video) dir=$(getConfig random_video_dir) ;;
	image) dir=$(getConfig random_image_dir) ;;
	esac

	$TERM yazi "$dir" --chooser-file="$tmp"
	[ -s "$tmp" ] && set_wallpaper "$(cat $tmp)"
	rm -f "$tmp"
}

set_latest() {
	local files=()
	files=("${wallpaper_latest}"_[0-9]*)
	# 遍历每个匹配文件
	for f in "${files[@]}"; do
		local monitor_index=$(echo $f | awk -F '_' '{print $NF}')
		set_wallpaper -m${monitor_index} "$(cat $f)" &
	done
}

# wallpaper launch_wallpaper
launch_wallpaper() {
	# kill last daemon
	if [[ "$$" != "$(pgrep -f $(basename $0))" ]]; then
		pgrep -f $(basename $0) | while read -r pid; do
			if [[ "$$" == "$pid" ]]; then
				continue
			else
				kill $pid
			fi
		done
	fi

	set_latest

	local duration=$(($(getConfig duration) * 60))
	while true; do
		sleep $duration
		if [ $(getConfig random) -eq 1 ]; then
			next_wallpaper
		fi

		# # 当cmd文件最后一次更改时间小于duration,使用新的cmdf
		# # FIX: 如果cmdf是脚本自己修改的如何判断呢？
		# local lastChangeDur=$(($(date +%s) - $(date -d $(stat -c %y "$conf") +%s)))
		# if [ $lastChangeDur -lt $duration ]; then
		# 	while [[ -n $(pgrep xwinwrap) ]]; do
		# 		killall xwinwrap
		# 		sleep 0.3
		# 	done
		# 	bash $cmdf
		# fi
	done
}

# 操作符
op=$1

case "$op" in
'-r' | '--run') launch_wallpaper ;;
'-s' | '--set')
	shift
	set_wallpaper $@
	;;
'-l' | '--last') set_latest ;;
'-n' | '--next') next_wallpaper ;;
'-S' | '--select') select_wallpaper ;;
'-h' | '--help') echo_help ;;
*)
	echo -e "\033[31mbad operator\033[0m"
	echo_help
	;;
esac

exit 0
