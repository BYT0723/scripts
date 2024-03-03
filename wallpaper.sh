#!/bin/bash

#
# Focus: Do not use spaces in paths and filenames, unexpected consequences may occur
#

# wallpaper configuration file
conf="$(dirname $0)/configs/wallpaper.conf"
cmdf="$(dirname $0)/configs/wallpaper-cmd.sh"

# Define the default configuration
declare -A config
config["random"]=0
config["random_type"]="image"
config["random_image_dir"]="~/Pictures"
config["random_video_dir"]="~/Videos"
config["random_depth"]=1
config["duration"]=30
cmd="feh --no-fehbg --bg-scale /usr/share/backgrounds/archlinux/small.png"

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

# set wallpaper
set_wallpaper() {
	if [ -z "$1" ]; then
		error "invalid wallpaper path"
		return
	fi

	args=("$@")        # 将所有参数存储到数组中
	arg="${args[@]:1}" # 获取从索引1开始的3个参数作为切片

	# kill existing xwinwrap
	if [[ -n $(pgrep xwinwrap) ]]; then
		killall xwinwrap
	fi

	# sleep for a short time to prevent killing the new xwinwrap
	sleep 0.3

	baseFilename=$(basename "${arg// /_}")

	# get file suffix
	Type="${baseFilename#*.}"

	# classify according to the suffix
	case "$Type" in
	'mp4' | mkv | avi)
		Type="video"
		;;
	jpg | png)
		Type="image"
		;;
	html | htm)
		Type="page"
		;;
	esac

	# run different commands according to the type
	case "$Type" in
	"video")
		# command detection
		if ! [[ -n $(command -v xwinwrap) ]]; then
			echo "set video to wallpaper need xwinwrap, install xwinwrap-git package"
			return
		fi
		if ! [[ -n $(command -v mpv) ]]; then
			echo "set video to wallpaper need mpv, install mpv package"
			return
		fi

		xwinwrap -d -ov -fs -- mpv -wid WID "$arg" --no-keepaspect --mute --no-osc --no-osd-bar --loop-file --cursor-autohide=no --player-operation-mode=cplayer --no-input-default-bindings --input-conf=$(getConfig video_keymap_conf) 2>&1 >~/.wallpaper.log
		# write command to configuration
		echo "xwinwrap -d -ov -fs -- mpv -wid WID \""$arg"\" --no-keepaspect --mute --no-osc --no-osd-bar --loop-file --cursor-autohide=no --player-operation-mode=cplayer --no-input-default-bindings --input-conf=$(getConfig video_keymap_conf) 2>&1 >~/.wallpaper.log" >$cmdf
		;;
	"image")
		# command detection
		if ! [[ -n $(command -v feh) ]]; then
			echo "set image to wallpaper need feh, install feh package"
			return
		fi

		feh --bg-scale --no-fehbg "$arg" >~/.wallpaper.log
		# write command to configuration
		echo "feh --bg-scale --no-fehbg '"$arg"' >~/.wallpaper.log" >$cmdf
		;;
	"page")

		# command detection
		if ! [[ -n $(command -v xwinwrap) ]]; then
			echo "set page to wallpaper need xwinwrap, install xwinwrap-git package"
			return
		fi
		if ! [[ -n $(command -v surf) ]]; then
			echo "set page to wallpaper need surf, install surf package"
			return
		fi

		# Start xwinwrap and tabbed
		size=$(xrandr --current | grep -o -E "current\s([0-9])+\sx\s[0-9]+" | awk '{print $2$3$4}')

		xwinwrap -d -ov -fs -- tabbed -w WID -g $size -r 2 surf -e '' $arg 2>&1 >~/.wallpaper.log 2>&1 >~/.wallpaper.log

		echo "xwinwrap -d -ov -fs -- tabbed -w WID -g $size -r 2 surf -e '' $arg 2>&1 >~/.wallpaper.log 2>&1 >~/.wallpaper.log" >$cmdf
		;;
	esac
}

# next random wallpaper
next_wallpaper() {
	if [[ -n $(pgrep xwinwrap) ]]; then
		killall xwinwrap
	fi

	sleep 0.3

	depth=$(getConfig random_depth)

	# run different command according to the `random_type` in the configuration
	case "$(getConfig random_type)" in
	"video")

		local dir=$(getConfig random_video_dir)

		if ! [ -d $dir ]; then
			error "No target directory "$dir
			return
		fi

		len=$(find $dir -type f -maxdepth $depth -regextype posix-extended -regex ".*\.(mp4|avi|mkv)" | wc -l)

		if [ $len == 0 ]; then
			error "No target wallpaper found in "$dir
			return
		fi

		# Randomly get a video wallpaper
		random=$(($RANDOM % $len + 1))
		filename=$(find $dir -type f -maxdepth $depth -regextype posix-extended -regex ".*\.(mp4|avi|mkv)" | head -n $random | tail -n 1)

		xwinwrap -d -ov -fs -- mpv -wid WID "$filename" --no-keepaspect --mute --no-osc --no-osd-bar --loop-file --cursor-autohide=no --player-operation-mode=cplayer --no-input-default-bindings --input-conf=$(getConfig video_keymap_conf) 2>&1 >~/.wallpaper.log
		echo "xwinwrap -d -ov -fs -- mpv -wid WID \""$filename"\" --no-keepaspect --mute --no-osc --no-osd-bar --loop-file --cursor-autohide=no --player-operation-mode=cplayer --no-input-default-bindings --input-conf=$(getConfig video_keymap_conf) 2>&1 >~/.wallpaper.log" >$cmdf
		;;
	"image")
		local dir=$(getConfig random_image_dir)

		if ! [ -d $dir ]; then
			error "No target directory "$dir
			return
		fi

		len=$(find $dir -type f -maxdepth $depth -regextype posix-extended -regex ".*\.(jpeg|jpg|png)" | wc -l)

		if [ $len == 0 ]; then
			error "No target wallpaper found in "$dir
			return
		fi

		# Randomly get a video wallpaper
		random=$(($RANDOM % $len + 1))
		filename=$(find $dir -type f -maxdepth $depth -regextype posix-extended -regex ".*\.(jpeg|jpg|png)" | head -n $random | tail -n 1)

		feh --bg-scale --no-fehbg "$filename" >~/.wallpaper.log
		echo "feh --bg-scale --no-fehbg '"$filename"' >~/.wallpaper.log" >$cmdf
		;;
	esac
}

# wallpaper launch_wallpaper
launch_wallpaper() {
	while true; do
		if [ $(getConfig random) -eq 1 ]; then
			next_wallpaper
		else
			if [ ! -f $cmdf ]; then
				$cmd
			else
				bash $cmdf
			fi
		fi
		if [ ! -z "$(pgrep -f wallpaper.sh)" ]; then
			break
		fi
		sleep $(($(getConfig duration) * 60))
	done
}

# 操作符
op=$1

case "$op" in
'-r' | '--run') launch_wallpaper ;;
'-s' | '--set') set_wallpaper $* ;;
'-n' | '--next') next_wallpaper ;;
'-h' | '--help') echo_help ;;
*)
	echo -e "\033[31mbad operator\033[0m"
	echo_help
	;;
esac

exit 0
