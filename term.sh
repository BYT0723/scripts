#!/bin/bash

# Termina Manager
# launch command in file config.h variable termcmd

Type=$1

# new different termina by $Type
case "$Type" in
float)
	# WINIT_X11_SCALE_FACTOR=1 alacritty --class float-term -o 'font.normal.family="CaskaydiaCove Nerd Font"' -o 'font.size=12'
	WINIT_X11_SCALE_FACTOR=1 alacritty --config-file $HOME/.config/alacritty/alacritty-float.toml &
	;;
*)
	WINIT_X11_SCALE_FACTOR=1 alacritty &
	;;
esac
