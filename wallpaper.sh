#!/bin/bash

# wallpaper configuration file
conf="$(dirname $0)/configs/wallpaper.conf"

# Define the default configuration
declare -A config
config["random"]=0
config["random_type"]="image"
config["random_image_dir"]="~/Pictures"
config["random_video_dir"]="~/Videos"
config["random_depth"]=1
config["duration"]=30
config["cmd"]="feh --no-fehbg --bg-scale /usr/share/backgrounds/archlinux/small.png"

# Get single configuration
getConfig() {
    if [ -f $conf ]; then
        res=$(cat $conf | grep "^$1=" | tail -n 1 | awk -F '=' '{print $2}')
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

    # kill existing xwinwrap
    if [[ -n $(pgrep xwinwrap) ]]; then
        killall xwinwrap
    fi

    # sleep for a short time to prevent killing the new xwinwrap
    sleep 0.3

    # get file suffix
    Type=$(echo "${1#*.}")
    # classify according to the suffix
    case "$Type" in
    mp4 | mkv | avi)
        Type="video"
        ;;
    jpg | png)
        Type="image"
        ;;
    *)
        Type="video"
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

        nohup xwinwrap -ov -fs -- mpv -wid WID "$1" --mute --no-osc --no-osd-bar --loop-file --player-operation-mode=cplayer --no-input-default-bindings --input-conf=$(getConfig video_keymap_conf) >/dev/null 2>&1 &
        # write command to configuration
        sed -i "s|cmd=.\+|cmd=xwinwrap -ov -fs -- mpv -wid WID "$1" --mute --no-osc --no-osd-bar --loop-file --player-operation-mode=cplayer --no-input-default-bindings --input-conf=$(getConfig video_keymap_conf)|g" $conf
        ;;
    "image")
        # command detection
        if ! [[ -n $(command -v feh) ]]; then
            echo "set image to wallpaper need feh, install feh package"
            return
        fi

        feh --bg-scale --no-fehbg "$1"
        # write command to configuration
        sed -i "s|cmd=.\+|cmd=feh --no-fehbg --bg-scale "$1"|g" $conf
        ;;
    esac
}

# next random wallpaper
next_wallpaper() {
    if [[ -n $(pgrep xwinwrap) ]]; then
        killall xwinwrap
    fi

    sleep 0.3

    echo $(getConfig random_type)
    # run different command according to the `random_type` in the configuration
    case "$(getConfig random_type)" in
    "video")

        local dir=$(getConfig random_video_dir)

        if ! [ -d $dir ]; then
            error "No target directory "$dir
            return
        fi

        # The number of files in random_video_dir
        targets=($(find $dir -type f -maxdepth $(getConfig random_depth) -regextype posix-extended -regex ".*\.(mp4|avi|mkv)"))

        len=${#targets[*]}

        if [ $len == 0 ]; then
            error "No target wallpaper found in "$dir
            return
        fi
        # Randomly get a video wallpaper
        filename=${targets[$(($RANDOM % $len + 1))]}

        nohup xwinwrap -ov -fs -- mpv -wid WID "$filename" --mute --no-osc --no-osd-bar --loop-file --player-operation-mode=cplayer --no-input-default-bindings --input-conf=$(getConfig video_keymap_conf) >/dev/null 2>&1 &
        ;;
    "image")
        local dir=$(getConfig random_image_dir)

        if ! [ -d $dir ]; then
            error "No target directory "$dir
            return
        fi
        # The number of files in random_video_dir
        targets=($(find $dir -type f -maxdepth $(getConfig random_depth) -regextype posix-extended -regex ".*\.(jpeg|jpg|png)"))

        len=${#targets[*]}

        if [ $len == 0 ]; then
            error "No target wallpaper found in "$dir
            return
        fi
        # Randomly get a video wallpaper
        filename=${targets[$(($RANDOM % $len + 1))]}

        feh --bg-scale --no-fehbg $filename
        ;;
    esac
}

# wallpaper launch_wallpaper
launch_wallpaper() {
    while true; do
        cmd=$(getConfig cmd)
        if [ $(getConfig random) -eq 1 ]; then
            next_wallpaper
        else
            $cmd
        fi
        sleep $(($(getConfig duration) * 60))
    done
}

# 操作符
op=$1

case "$op" in
'-r' | '--run') launch_wallpaper ;;
'-s' | '--set') set_wallpaper $2 ;;
'-n' | '--next') next_wallpaper ;;
'-h' | '--help') echo_help ;;
*)
    echo -e "\033[31mbad operator\033[0m"
    echo_help
    ;;
esac

exit 0
