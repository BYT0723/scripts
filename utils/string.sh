#!/bin/bash

# 字符串工具函数

# trim 首尾空白
trim_str() {
    local s="$1"
    s="${s#"${s%%[![:space:]]*}"}"
    s="${s%"${s##*[![:space:]]}"}"
    printf '%s' "$s"
}
