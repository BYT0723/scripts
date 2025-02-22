#!/usr/bin/env bash

dir=$(dirname $0)

# Import Current Theme
type="$dir/rofi/applets/type-1"
style='style-2.rasi'
theme="$type/$style"

DIR="$(xdg-user-dir)/Screenshots"

time=$(date +%Y-%m-%d-%H-%M-%S)
geometry=$(xrandr | grep 'current' | head -n1 | cut -d',' -f2 | tr -d '[:blank:],current')
FILENAME="Screenshot_${time}_${geometry}.png"

if [[ ! -d "$DIR" ]]; then
	mkdir -p "$DIR"
fi

# Theme Elements
prompt='Screenshot'
mesg="  $DIR"

if [[ "$theme" == *'type-1'* ]]; then
	list_col='1'
	list_row='5'
	win_width='500px'
elif [[ "$theme" == *'type-3'* ]]; then
	list_col='1'
	list_row='5'
	win_width='120px'
elif [[ "$theme" == *'type-5'* ]]; then
	list_col='1'
	list_row='5'
	win_width='520px'
elif [[ ("$theme" == *'type-2'*) || ("$theme" == *'type-4'*) ]]; then
	list_col='5'
	list_row='1'
	win_width='670px'
fi

# Options
layout=$(cat ${theme} | grep 'USE_ICON' | cut -d'=' -f2)
if [[ "$layout" == 'NO' ]]; then
	option_1=" Capture Desktop"
	option_2=" Capture Area"
	option_3=" Capture Window"
	option_4=" Capture in 5s"
	option_5=" Capture in 10s"
else
	option_1=""
	option_2=""
	option_3=""
	option_4=""
	option_5=""
fi

# Rofi CMD
rofi_cmd() {
	rofi -theme-str "window {width: $win_width;}" \
		-theme-str "listview {columns: $list_col; lines: $list_row;}" \
		-theme-str 'textbox-prompt-colon {str: " ";}' \
		-dmenu \
		-p "$prompt" \
		-mesg "$mesg" \
		-markup-rows \
		-monitor -4 \
		-theme ${theme}
}

# Pass variables to rofi dmenu
run_rofi() {
	echo -e "$option_1\n$option_2\n$option_3\n$option_4\n$option_5" | rofi_cmd
}

# notify and view screenshot
notify_view() {
	notify_cmd_shot='notify-send -i gscreenshot -u low --replace-id=699'
	${notify_cmd_shot} "Copied to clipboard."
	feh ${DIR}/"$FILENAME"
	if [[ -e "$DIR/$FILENAME" ]]; then
		${notify_cmd_shot} "Screenshot Saved."
	else
		${notify_cmd_shot} "Screenshot Deleted."
	fi
}

# Copy screenshot to clipboard
copy_shot() {
	tee "$FILENAME" | xclip -selection clipboard -t image/png
}

# countdown
countdown() {
	for sec in $(seq $1 -1 1); do
		notify-send -i gscreenshot -t 1000 --replace-id=699 "Taking shot in : $sec"
		sleep 1
	done
}

# take shots
shotnow() {
	cd $DIR && sleep 0.5 && maim -u -f png | copy_shot
	notify_view
}

shot5() {
	countdown '5'
	sleep 1 && cd $DIR && maim -u -f png | copy_shot
	notify_view
}

shot10() {
	countdown '10'
	sleep 1 && cd $DIR && maim -u -f png | copy_shot
	notify_view
}

shotwin() {
	cd $DIR && maim -u -f png -i $(xdotool getactivewindow) | copy_shot
	notify_view
}

shotarea() {
	cd $DIR && maim -u -f png -s -b 2 -c 0.35,0.55,0.85,0.25 -l | copy_shot
	notify_view
}

# Execute Command
run_cmd() {
	if [[ "$1" == '--opt1' ]]; then
		shotnow
	elif [[ "$1" == '--opt2' ]]; then
		shotarea
	elif [[ "$1" == '--opt3' ]]; then
		shotwin
	elif [[ "$1" == '--opt4' ]]; then
		shot5
	elif [[ "$1" == '--opt5' ]]; then
		shot10
	fi
}

# Actions
chosen="$(run_rofi)"
case ${chosen} in
$option_1)
	run_cmd --opt1
	;;
$option_2)
	run_cmd --opt2
	;;
$option_3)
	run_cmd --opt3
	;;
$option_4)
	run_cmd --opt4
	;;
$option_5)
	run_cmd --opt5
	;;
esac
