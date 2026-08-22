#!/bin/bash

# URL 工具函数

# 宽松判断: 输入是否像 URL (接受无协议域名, 用于决定打开链接或搜索)
is_url() {
    [[ "$1" =~ ^https?:// ]] && return 0
    [[ "$1" =~ ^[a-zA-Z0-9.-]+\.[a-zA-Z]{2,} ]] && return 0
    return 1
}

# 严格校验: 仅 http/https, host 须为 localhost/IP/含点域名 (支持端口)
valid_url() {
    local u="$1" rest host port
    [[ "$u" =~ ^https?:// ]] || return 1
    rest="${u#*://}"
    [[ -z "$rest" ]] && return 1
    host="${rest%%/*}"
    port="${host#*:}"
    if [[ "$host" != "${port}" ]]; then
        [[ "$port" =~ ^[0-9]+$ ]] || return 1
        host="${host%%:*}"
    fi
    [[ -z "$host" ]] && return 1
    [[ "$host" == "localhost" ]] && return 0
    [[ "$host" =~ ^[0-9]+(\.[0-9]+){3}$ ]] && return 0
    [[ "$host" =~ ^[a-zA-Z0-9-]+(\.[a-zA-Z0-9-]+)+$ ]] && return 0
    return 1
}
