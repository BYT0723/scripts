#!/bin/bash

# 图标
# $1 * [iconType]: toggle(开关) | active(状态)
# $2 * [targetType]: app(应用) | service(服务) | conf(配置)
# $3 * [target]
# $4 [confProperty]: regx
# $5 [confPropertyType]: bool | number
icon() {
    if [[ "$1" == "toggle" ]]; then
        icon=(" " " ")
    elif [[ "$1" == "active" ]]; then
        icon=(" " " ")
    fi

    if [[ "$2" == "app" ]]; then
        if [[ -n $(pgrep $3) ]]; then
            echo ${icon[1]}
        else
            echo ${icon[0]}
        fi

    elif [[ "$2" == "service" ]]; then
        if [[ "inactive" == $(systemctl status $3 | grep Active | awk '{print $2}') ]]; then
            echo ${icon[0]}
        else
            echo ${icon[1]}
        fi

    elif [[ "$2" == "conf" ]]; then
        if [[ -n $(cat ${confPath[$3]} | grep -E "^$4\s*=\s*$(typeToValue $5)") ]]; then
            echo ${icon[0]}
        else
            echo ${icon[1]}
        fi

    elif [[ "$2" == "cmd" ]]; then
        if [[ -n $(ps ax | grep "$3" | grep -v grep) ]]; then
            echo ${icon[1]}
        else
            echo ${icon[0]}
        fi
    fi
}

# get default value of type
typeToValue() {
    case "$1" in
    bool)
        echo false
        ;;
    number)
        echo 0
        ;;
    wallpaper_type)
        echo "image"
        ;;
    esac
}

# toggle application
toggleApplication() {
    if [[ -n $(pgrep $1) ]]; then
        killall $1
    else
        ${applicationCmd[$1]}
    fi
}

# toggle conf property
toggleConf() {
    if [[ -n $(cat ${confPath[$1]} | grep -E "^$2\s*=\s*$(typeToValue $3)") ]]; then
        case "$3" in
        bool)
            sed -i "s|^$2\s*=\s*false|$2\ =\ true|g" ${confPath[$1]}
            ;;
        number)
            sed -i "s|^$2\s*=\s*0|$2\ =\ 1|g" ${confPath[$1]}
            ;;
        wallpaper_type)
            sed -i "s|^$2\s*=\s*image|$2\ =\ video|g" ${confPath[$1]}
            ;;
        esac
    else
        case "$3" in
        bool)
            sed -i "s|^$2\s*=\s*true|$2\ =\ false|g" ${confPath[$1]}
            ;;
        number)
            sed -i "s|^$2\s*=\s*1|$2\ =\ 0|g" ${confPath[$1]}
            ;;
        wallpaper_type)
            sed -i "s|^$2\s*=\s*video|$2\ =\ image|g" ${confPath[$1]}
            ;;
        esac
    fi
}

getConfig() {
    echo $(cat ${confPath[$1]} | grep -E "^$2\s*=" | tail -n 1 | awk -F '=' '{print $2}' | grep -o "[^ ]\+\( \+[^ ]\+\)*")
}
