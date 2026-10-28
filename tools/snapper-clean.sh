#!/usr/bin/env bash
# snapper-clean.sh — 删除指定 snapper 配置的全部快照
# 用法: sudo ./snapper-clean.sh <config>

[ "$(id -u)" -ne 0 ] && echo "请使用 root 执行" >&2 && exit 1

command -v snapper >/dev/null || {
    echo "snapper 未安装" >&2
    exit 1
}

config_name="${1:-}"

if [ -z "$config_name" ]; then
    echo "用法: $0 <config>" >&2
    echo "可用 config:" >&2
    snapper list-configs >&2 || echo "(无法获取 config 列表)" >&2
    exit 1
fi

if ! list_output=$(snapper -c "$config_name" list 2>&1); then
    echo "获取快照列表失败 ($config_name):" >&2
    echo "$list_output" >&2
    exit 1
fi

# 只删纯数字且非 0 的: 0 是 current 本体, N* 是当前默认启动快照, 均不可删
ids=$(printf '%s\n' "$list_output" | awk 'NR>2 && $1 ~ /^[0-9]+$/ && $1 != 0 {print $1}')

[ -n "$ids" ] || {
    echo "config '$config_name' 无快照, 无需清理"
    exit 0
}

echo "$list_output"
echo "将删除 config '$config_name' 的快照:"
echo "$ids"
if printf '%s\n' "$list_output" | grep -qE '^[[:space:]]*[0-9]+\*'; then
    echo "(注: 带 * 的为当前默认启动快照, 不可删除, 已跳过)"
fi

read -r -p "确认删除? [y/N] " reply
case "$reply" in
[yY] | [yY][eE][sS]) ;;
*) echo "已取消"; exit 0 ;;
esac

# shellcheck disable=SC2086 -- $ids 分词传多个快照号
snapper -c "$config_name" delete $ids
