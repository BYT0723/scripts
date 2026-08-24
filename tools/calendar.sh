#/use/bin/env /bin/bash

source "$(dirname "$0")/../utils/notify.sh"

cal() {
    [ -z "$(command -v cal)" ] && system-notify normal "Tool Not Found" "please install cal" && return
    kitty \
        -T calendar \
        --class float-term \
        -o initial_window_width=67c \
        -o initial_window_height=36c \
        -e sh -c 'cal --color=always -sy | less -R'
}

ccal() {
    [ -z "$(command -v ccal)" ] && system-notify normal "Tool Not Found" "please install ccal" && return
    kitty \
        -T calendar-lunar \
        --class float-term \
        -o initial_window_width=70c \
        -o initial_window_height=36c \
        -e sh -c "ccal -u $(date +%Y) | less -R"
}

case "$1" in
lunar) ccal ;;
*) cal ;;
esac
