#!/bin/bash

#
# Focus: Do not use spaces in paths and filenames, unexpected consequences may occur
#

# wallpaper configuration file
conf="$(dirname $0)/configs/wallpaper.conf"
wallpaper_latest="$(dirname $0)/configs/wallpaper_latest"

# Define the default configuration
declare -A config
config["random"]=0
config["random_type"]="image"
config["random_image_dir"]="~/Pictures"
config["random_video_dir"]="~/Videos"
config["random_depth"]=1
config["duration"]=30
cmd="feh --no-fehbg --bg-scale /usr/share/backgrounds/archlinux/small.png"

cache_video_dir="$HOME/.cache/wallpapers/"
mkdir -p "$cache_video_dir"

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

clean_lastest() {
	# kill existing xwinwrap
	while [[ -n "$(pgrep xwinwrap)" ]]; do
		kill $(pgrep xwinwrap)
		sleep 0.3
	done
}

# set wallpaper
set_wallpaper() {
	if [ -z "$1" ]; then
		error "invalid wallpaper path"
		return
	fi

	args=("$@")        # 将所有参数存储到数组中
	arg="${args[@]:1}" # 获取从索引1开始的3个参数作为切片

	clean_lastest

	baseFilename=$(basename "${arg// /_}")

	# get file suffix
	Type="${baseFilename##*.}"

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

		nfname="$cache_video_dir"$(md5sum "$arg" | awk '{print $1}')".mp4"
		if [ ! -f "$nfname" ]; then
			notify-send "video wallpaper is being transcoding by ffmpeg ..."
			ffmpeg -i "$arg" -c:v libx264 -vf scale=$(xdpyinfo | grep dimensions | awk '{print $2}' | sed 's/x/:/') -crf 18 -preset veryfast -c:a aac $nfname
		fi

		xwinwrap -d -ov -fs -- mpv -wid WID "$nfname" \
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
			--demuxer-max-bytes=256MiB \
			--demuxer-readahead-secs=20 \
			--input-conf=$(getConfig video_keymap_conf) 2>&1 >~/.wallpaper.log
		# write command to configuration
		echo "$arg" >$wallpaper_latest
		;;
	"image")
		# command detection
		if ! [[ -n $(command -v feh) ]]; then
			echo "set image to wallpaper need feh, install feh package"
			return
		fi

		feh --bg-scale --no-fehbg "$arg" >~/.wallpaper.log
		# write command to configuration
		echo "$arg" >$wallpaper_latest
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

		echo "$args" >$wallpaper_latest
		;;
	esac
}

# next random wallpaper
next_wallpaper() {
	clean_lastest

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

		nfname="$cache_video_dir"$(md5sum "$filename" | awk '{print $1}')".mp4"
		if [ ! -f "$nfname" ]; then
			notify-send "video wallpaper is being transcoding by ffmpeg ..."
			ffmpeg -i "$filename" -c:v libx264 -vf scale=$(xdpyinfo | grep dimensions | awk '{print $2}' | sed 's/x/:/') -crf 18 -preset veryfast -c:a aac $nfname
		fi

		xwinwrap -d -ov -fs -- mpv -wid WID "$nfname" \
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
			--demuxer-max-bytes=256MiB \
			--demuxer-readahead-secs=20 \
			--input-conf=$(getConfig video_keymap_conf) 2>&1 >~/.wallpaper.log
		echo $filename >$wallpaper_latest
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
		echo $filename >$wallpaper_latest
		;;
	esac
}

# wallpaper launch_wallpaper
launch_wallpaper() {
	if [[ "$$" != "$(pgrep -f $(basename $0))" ]]; then
		pgrep -f $(basename $0) | while read -r pid; do
			if [[ "$$" == "$pid" ]]; then
				continue
			else
				kill $pid
			fi
		done
	fi

	clean_lastest
	# PERF: 将文件名获取网址存入cmdf中，使用脚本启动，这样启动不会做预备
	if [ -f $wallpaper_latest ]; then
		set_wallpaper -s "$(cat $wallpaper_latest)"
	else
		$cmd
	fi

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
'-s' | '--set') set_wallpaper $* ;;
'-n' | '--next') next_wallpaper ;;
'-h' | '--help') echo_help ;;
*)
	echo -e "\033[31mbad operator\033[0m"
	echo_help
	;;
esac

exit 0
