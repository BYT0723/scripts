#!/bin/bash

# loop dwm-status-refresh.sh to refresh statusBar
while true; do
	bash $(dirname $0)/dwm-status-refresh.sh
	# refresh interval
	sleep 2
done
