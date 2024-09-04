#!/bin/bash
st \
	-c bilichat-tui \
	-T bilichat \
	-f "CaskaydiaCove Nerd Font:style=Regular:size=10" \
	-g 45x45-0+400 \
	-e sh -c 'cd ~/Workspace/Github/bilibili_live_tui && go run main.go' &
