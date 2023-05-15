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
        if [[ -n $(cat ${confPath[$3]} | grep $4 | grep $(typeToValue $5)) ]]; then
            echo ${icon[0]}
        else
            echo ${icon[1]}
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
    line=$(cat ${confPath[$1]} | grep $2 -n | awk -F ':' '{print $1}')
    if [[ -n $(cat ${confPath[$1]} | grep $2 | grep $(typeToValue $3)) ]]; then
        case "$3" in
        bool)
            sed -i $line' s/false/true/' ${confPath[$1]}
            ;;
        number)
            sed -i $line' s/0/1/' ${confPath[$1]}
            ;;
        esac
    else
        case "$3" in
        bool)
            sed -i $line' s/true/false/' ${confPath[$1]}
            ;;
        number)
            sed -i $line' s/1/0/' ${confPath[$1]}
            ;;
        esac
    fi
}
