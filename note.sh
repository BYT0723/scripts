#!/bin/bash

while true; do
	/bin/bash /home/walter/.dwm/clock.sh PLAN "$(grep '^[*=]' /home/walter/.note)"
	sleep 1800
done

exit 0
