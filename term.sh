#!/bin/bash

# Termina Manager
# launch command in file config.h varialbe termcmd

Type=$1

# new different termina by $Type
case "$Type" in
float)
	st -i -g 110x30 -f "CaskaydiaCove Nerd Font:style=Regular:size=12" &
	;;
*)
	# st &
	alacritty &
	;;
esac
