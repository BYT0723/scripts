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
		if [[ -n $(cat ${confPath[$3]} | grep -E "^$4\s*=\s*$(typeToValue $5)") ]]; then
			echo ${icon[0]}
		else
			echo ${icon[1]}
		fi

	elif [[ "$2" == "cmd" ]]; then
		if [[ -n $(ps ax | grep "$3" | grep -v grep) ]]; then
			echo ${icon[1]}
		else
			echo ${icon[0]}
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
	wallpaper_type)
		echo "image"
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
	if [[ -n $(cat ${confPath[$1]} | grep -E "^$2\s*=\s*$(typeToValue $3)") ]]; then
		case "$3" in
		bool)
			sed -i "s|^$2\s*=\s*false|$2\ =\ true|g" ${confPath[$1]}
			;;
		number)
			sed -i "s|^$2\s*=\s*0|$2\ =\ 1|g" ${confPath[$1]}
			;;
		wallpaper_type)
			sed -i "s|^$2\s*=\s*image|$2\ =\ video|g" ${confPath[$1]}
			;;
		esac
	else
		case "$3" in
		bool)
			sed -i "s|^$2\s*=\s*true|$2\ =\ false|g" ${confPath[$1]}
			;;
		number)
			sed -i "s|^$2\s*=\s*1|$2\ =\ 0|g" ${confPath[$1]}
			;;
		wallpaper_type)
			sed -i "s|^$2\s*=\s*video|$2\ =\ image|g" ${confPath[$1]}
			;;
		esac
	fi
}

getConfig() {
	echo $(cat ${confPath[$1]} | grep -E "^$2\s*=" | tail -n 1 | awk -F '=' '{print $2}' | grep -o "[^ ]\+\( \+[^ ]\+\)*")
}

# 日志函数
# $1 level ERROR | WARN | INFO
# $2 message
log() {
	case "$1" in
	ERROR)
		echo -e "\033[30m\033[41m$(date +'%Y-%m-%d %H:%M:%S') [$1] ${@:2}\033[0m"
		;;
	WARN)
		echo -e "\033[30m\033[43m$(date +'%Y-%m-%d %H:%M:%S') [$1] ${@:2}\033[0m"
		;;
	INFO)
		echo -e "\033[30m\033[47m$(date +'%Y-%m-%d %H:%M:%S') [$1] ${@:2}\033[0m"
		;;
	*)
		echo -e "$(date +'%Y-%m-%d %H:%M:%S') [$1] ${@:2}"
		;;
	esac
}

# generate ssh key
# $1 private key path
# $2 comment
gen_sshkey() {
	# 如果私钥不存在，则生成
	if [ ! -f "$1" ]; then
		# 在本地生成ssh public key
		echo "\n\n" | ssh-keygen -t rsa -b 2048 -C "$2" -f $1
	fi
}

# first login ssh and set authorized_keys
# $1 host
# $2 user
# $3 port
# $4 key path
first_ssh_login() {
	pk=$(cat "$4.pub")
	case "$2" in
	root)
		remote_auth_path="/$2/.ssh/authorized_keys"
		;;
	*)
		remote_auth_path="/home/$2/.ssh/authorized_keys"
		;;
	esac
	# 如果私钥不在远程服务器中,则托送上去
	ssh -l $2 $1 -p $3 -i $key_path "\
if [ ! -d \"$(dirname $remote_auth_path)\" ] || [ ! -f \"$remote_auth_path\" ] || [ -z \"\$(grep \"$pk\" \"$remote_auth_path\")\" ]; then \
    mkdir -p \"$(dirname $remote_auth_path)\" && touch \"$remote_auth_path\" && echo \"$pk\" | tee -a \"$remote_auth_path\"; \
fi" >>/dev/null
}
