#!/usr/bin/env bash

echo_note() {
	local note=${1:-"$HOME/.note"}

	# command check
	[ -z "$(command -v lolcat)" ] && echo "echo_note need lolcat." && return

	# file exists check
	[ ! -f "$note" ] && return

	if command -v boxes >/dev/null; then
		grep '^\*' "$note" | cut -c3- | boxes -d parchment | lolcat -p 2 -S $RANDOM
	elif command -v cowsay >/dev/null; then
		grep '^\*' "$note" | cut -c3- | cowsay -f small -W "$(tput cols)" -n | lolcat -p 2 -S $RANDOM
	else
		grep '^\*' "$note" | cut -c3- | lolcat -p 2 -S $RANDOM
	fi
}

is_float_term() {
	# 判断当前窗口的class是否为"float-term"
	xprop -id "$WINDOWID" WM_CLASS 2>/dev/null | grep -q '"float-term"'
}

init_tmux_cursor() {
	# 在 tmux 内恢复光标样式
	if [[ "$TERM" == "screen"* || "$TERM" == "tmux"* ]]; then
		printf '\e[6 q' # insert mode / bar
	else
		printf '\e[5 q' # normal / block
	fi
}
