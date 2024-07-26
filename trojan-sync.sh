#!/bin/bash

# 基本所在路径
dir=$(dirname $0)
# 注册私钥邮箱
email="$(cat /etc/hostname)@syncer.com"
# 私钥路径
key_path="$dir/syncer"
# 服务器地址
server="root@byt0723.xyz"
# 服务器ssh端口
port="29793"
# 服务器中trojan client配置路径
remote_client_config="/root/config.json"
# 服务器中torjan server配置路径
remote_server_config="/usr/local/etc/trojan/config.json"
# 服务器中ssh授权文件
remote_auth_path="/root/.ssh/authorized_keys"
# 本地trojan client配置路径
local_config="/etc/trojan/config.json"

# 日志函数
log() {
	case "$1" in
	ERROR)
		echo -e "$(date +'%Y-%m-%d %H:%M:%S') \033[31m"[$1] ${@:2}"\033[0m"
		;;
	*)
		echo -e "$(date +'%Y-%m-%d %H:%M:%S') [$1] ${@:2}"
		;;
	esac
}

check_url() {
	echo $(curl -s -o /dev/null -w "%{http_code}" -L "$1")
}

# 检查本地配置文件写入权限
if [ ! -w "$local_config" ]; then
	log ERROR "您没有$local_config的写权限!!!"
	exit 1
fi

# 如果私钥不存在，则生成
if [ ! -f "$key_path" ]; then
	# 在本地生成ssh public key
	echo "\n\n" | ssh-keygen -t rsa -b 2048 -C "$email" -f $key_path
fi

pk=$(cat "${key_path}.pub")
# 如果私钥不在远程服务器中,则托送上去
ssh $server -p $port -i $key_path "\
if [ ! -d \"$(dirname $remote_auth_path)\" ] || [ ! -f \"$remote_auth_path\" ] || [ -z \"\$(grep \"$pk\" \"$remote_auth_path\")\" ]; then \
    mkdir -p \"$(dirname $remote_auth_path)\" && touch \"$remote_auth_path\" && echo \"$pk\" | tee -a \"$remote_auth_path\"; \
fi" >>/dev/null

if [[ "$(check_url 'https://www.google.com')" == "200" ]]; then
	log INFO "您的网络连接正常!!!"
	exit 0
fi

local_remote_port=$(grep -oP '"remote_port": \K\d+' $local_config)
if [[ -z "$local_remote_port" ]]; then
	log ERROR "无法获取本地trojan的remote_port"
	exit 1
fi

remote_local_port=$(ssh -p $port $server -i $key_path "grep -oP '\"local_port\": \\K\\d+' $remote_server_config")
if [[ -z "$remote_local_port" ]]; then
	log ERROR "无法获取远程trojan的local_port"
	exit 1
fi

if [[ "$local_remote_port" == "$remote_local_port" ]]; then
	log INFO "更新trojan接口..."
	echo -e "\015" | ssh -tt $server -p $port -i $key_path -q "trojan port >> /dev/null"
fi

# 更新远程Client Config文件
log INFO "更新远程trojan client config..."
echo "6" | ssh -tt $server -p $port -i $key_path -q '(trojan & sleep 1 && kill $!) >> /dev/null'

log INFO "远程端口为："$(ssh $server -p $port -i $key_path 'grep "remote_port" config.json | grep -oP "\d+"')

# 拉去最新的Config
log INFO "更新本地trojan client config..."
scp -P $port -i $key_path $server:$remote_client_config $local_config >>/dev/null

# 重启trojan
log INFO "重启本地trojan服务..."
systemctl restart trojan
log INFO "[Done]"
