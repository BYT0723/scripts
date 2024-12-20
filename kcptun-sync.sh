#!/bin/bash

# sync kcptun and trojan configuration from remote server

# 基本所在路径
dir=$(dirname $0)
# 注册私钥邮箱
email="$(cat /etc/hostname)@syncer.com"
# 私钥路径
key_path="$dir/syncer"
# 服务器地址
host=byt0723.xyz
# 用户名
user=root
# 服务器ssh端口
port="29793"
# 服务器中torjan server配置路径
remote_server_config="/usr/local/kcptun/server-config.json"
# 服务器中ssh授权文件
remote_auth_path="/root/.ssh/authorized_keys"
# 本地trojan client配置路径
local_config="/etc/kcptun/config.json"
# service 路径
service_path="/etc/systemd/system/kcptun_client.service"
service_name=$(basename $service_path)

# 日志函数
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

# 检查本地配置文件写入权限
if [[ $UID != 0 ]]; then
	log ERROR "Need run with root user"
	exit 1
fi

# 如果私钥不存在，则生成
if [ ! -f "$key_path" ]; then
	# 在本地生成ssh public key
	echo "\n\n" | ssh-keygen -t rsa -b 2048 -C "$email" -f $key_path
fi

pk=$(cat "${key_path}.pub")
# 如果私钥不在远程服务器中,则托送上去
ssh $user@$host -p $port -i $key_path "\
if [ ! -d \"$(dirname $remote_auth_path)\" ] || [ ! -f \"$remote_auth_path\" ] || [ -z \"\$(grep \"$pk\" \"$remote_auth_path\")\" ]; then \
    mkdir -p \"$(dirname $remote_auth_path)\" && touch \"$remote_auth_path\" && echo \"$pk\" | tee -a \"$remote_auth_path\"; \
fi" >>/dev/null

# if [[ "$(curl -s -m 5 -o /dev/null -w '%{http_code}' -L 'https://www.google.com')" == "200" ]]; then
# 	log INFO "您的网络连接正常!!!"
# 	exit 0
# fi

server_config=$(ssh -p $port $user@$host -i $key_path "cat /usr/local/kcptun/server-config.json")

client_config=$(echo $server_config | jq --arg remote_host "$host" '{
  localaddr: ":\(.target | split(":")[1])",
  remoteaddr: "\($remote_host):\(.listen | split(":")[1])",
  key: .key,
  crypt: .crypt,
  mode: .mode,
  mtu: .mtu,
  sndwnd: .rcvwnd,
  rcvwnd: .sndwnd,
  datashard: .datashard,
  parityshard: .parityshard,
  dscp: .dscp,
  nocomp: .nocomp,
  quiet: .quiet,
  tcp: .tcp
} | del(.pprof)')

if [ ! -z "$client_config" ]; then
	>$local_config
	echo $client_config | jq >>$local_config
fi

if [ ! -z "$(command -v kcptun-client)" ]; then
	if [ ! -f "$service_path" ]; then
		log INFO "create kcptun client服务..."
		echo "[Unit]
Description=Kcptun Server Service
After=network.target

[Service]
Type=simple
ExecStart="$(command -v kcptun-client)" -c "$local_config"
Restart=on-failure
User=nobody
LimitNOFILE=4096

[Install]
WantedBy=multi-user.target" >>$service_path
		log INFO "enable $service_name服务..."
		systemctl enable $service_name 2>&1 >>/dev/null
		systemctl daemon-reload
		log INFO "start $service_name服务..."
		systemctl start $service_name
	else
		# 重启trojan
		log INFO "重启本地$service_name服务..."
		systemctl restart $service_name
	fi
fi

if [[ "$(systemctl is-active trojan)" == "active" ]]; then
	trojan_config=$(cat /etc/trojan/config.json)
	>/etc/trojan/config.json
	echo $trojan_config | jq --argjson local_port $(jq -r '(.localaddr | split(":")[1])' /etc/kcptun/config.json) '.remote_addr = "127.0.0.1" | .remote_port = $local_port' >>/etc/trojan/config.json

	log INFO "重启本地trojan服务..."
	systemctl restart trojan
fi

log INFO "[Done]"
