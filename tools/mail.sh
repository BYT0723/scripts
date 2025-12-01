#!/bin/bash

output=$(offlineimap -o >>/dev/null)
if [ ! -z "$output" ]; then
	notify-send -u critical -i mail-unread-symbolic "同步失败："$output
	exit 0
fi

if [ ! -z $(command -v notmuch) ]; then
	notmuch new
	unread=$(notmuch count tag:unread)
	if [ $unread -gt 0 ]; then
		notify-send -i mail-unread-symbolic "$(notmuch search --output=files tag:unread | cut -d/ -f5 | sort | uniq -c | awk '{print "[" $2 "] \t" $1 "封新邮件"}')"
	fi
fi
