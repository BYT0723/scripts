#!/usr/bin/env /bin/bash

WORK_DIR=$(dirname "$(dirname "$0")")

source $WORK_DIR/utils/monitor.sh
source "$WORK_DIR/utils/notify.sh"

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
	echo "      -s | --set <path>      set wallpaper"
	echo "      -n | --next            random next wallpaper"
	echo "      -S | --select          use yazi select wallpaper to set"
}

clean_latest() {
	local monitor_index=$1

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
set_wallpaper_to_monitor() {
	local monitor_index=${1}
	shift
	local filepath="$@"

	[ -z "$monitor_index" ] && return

	read monitor_index width height x y < <(get_monitor_info_by_index "$monitor_index")

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
    		--hwdec=auto-safe \
    		--vo=gpu-next \
			--framedrop=vo \
			--no-sub \
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

# reutrn random wallpaper filepath
random_wallpaper() {
	local depth=$(getConfig random_depth)

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
		echo "$(find $dir -maxdepth $depth -type f -regextype posix-extended -regex ".*\.(mp4|avi|mkv)" | head -n $random | tail -n 1)"
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
		echo "$(find $dir -maxdepth $depth -type f -regextype posix-extended -regex ".*\.(jpeg|jpg|png)" | head -n $random | tail -n 1)"
		;;
	esac
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
	local select_file=${1}
	local skip_select=${2:false}

	if [ $(xrandr --listactivemonitors | wc -l) = 2 ]; then
		select_monitor_name=$(xrandr --listactivemonitors | awk 'END{print $NF}')
	elif [[ $skip_select = true ]]; then
		select_monitor_name="ALL"
	else
		monitors="ALL\n"$(xrandr --listactivemonitors | awk 'NR>1 {print $NF}')
		select_monitor_name=$(echo -e "$monitors" | bash $WORK_DIR/rofi/scripts/common_list.sh "Wallpaper" "Select a monitor")
	fi
	[ -z "$select_monitor_name" ] && return

	xrandr --listactivemonitors | awk 'NR>1 {sub(":","",$1); print $1,$NF}' | while read -r monitor_index monitor_name; do
		if [[ $select_monitor_name = "ALL" ]] || [[ $select_monitor_name = "$monitor_name" ]]; then
			set_wallpaper_to_monitor "$monitor_index" "$select_file"
		fi
	done
}

set_latest() {
	local files=()
	files=("${wallpaper_latest}"_[0-9]*)
	# 遍历每个匹配文件
	for f in "${files[@]}"; do
		local monitor_index=$(echo $f | awk -F '_' '{print $NF}')
		set_wallpaper_to_monitor "$monitor_index" "$(cat $f)" &
	done
}

# wallpaper launch_wallpaper
launch_wallpaper() {
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
	set_wallpaper $@
	;;
'-n' | '--next') set_wallpaper "$(random_wallpaper)" true ;;
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
