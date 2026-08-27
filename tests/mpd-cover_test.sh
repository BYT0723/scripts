#!/usr/bin/env bash
# mpd.sh fetch_cover 封面提取测试 (source + mock, 无 MPD/rofi)
# 运行: bash tests/mpd-cover_test.sh

SCRIPT="$HOME/.dwm/rofi/scripts/mpd.sh"
TEST_DIR=$(mktemp -d)
trap 'rm -rf "$TEST_DIR"' EXIT

FAIL=0
assert_eq() { # got want msg
    if [[ "$1" == "$2" ]]; then
        echo "ok: $3"
    else
        echo "FAIL: $3"
        echo "  got : $(printf '%q' "$1")"
        echo "  want: $(printf '%q' "$2")"
        FAIL=1
    fi
}
assert_cond() { # msg cond
    if eval "$2"; then
        echo "ok: $1"
    else
        echo "FAIL: $1"
        FAIL=1
    fi
}

# ---- 隔离 HOME + XDG_CACHE_HOME ----
export HOME="$TEST_DIR/home"
export XDG_CACHE_HOME="$TEST_DIR/cache"
mkdir -p "$HOME" "$XDG_CACHE_HOME"

# ---- 搭 mock ROFI_DIR 结构 (mpd.sh source util.sh/lib-module.sh 依赖 $0 所在目录) ----
MOCK_ROFI="$TEST_DIR/rofi"
mkdir -p "$MOCK_ROFI/scripts" "$MOCK_ROFI/applets/type-5"
cp "$SCRIPT" "$MOCK_ROFI/scripts/mpd.sh"

# mock util.sh (icon() 等, 空实现即可 — fetch_cover 不依赖)
cat >"$MOCK_ROFI/scripts/util.sh" <<'EOF'
icon() { echo ""; }
EOF

# mock lib-module.sh (module_loop 空实现, source 不触发 rofi)
cat >"$MOCK_ROFI/scripts/lib-module.sh" <<'EOF'
module_parse() { :; }
module_loop() { :; }
EOF

# mock rasi 文件 (module_loop 被 mock 后不再 grep)
cat >"$MOCK_ROFI/applets/type-5/style-2.rasi" <<'EOF'
* { USE_ICON = NO; }
EOF

FAKE_BIN="$TEST_DIR/bin"
mkdir -p "$FAKE_BIN"

# ---- mock nc: 序列文件驱动, 记录调用参数 ----
NC_LOG="$TEST_DIR/nc.log"
cat >"$FAKE_BIN/nc" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$NC_LOG"
if [[ -n "${MOCK_NC_SEQ_FILE:-}" && -s "$MOCK_NC_SEQ_FILE" ]]; then
    first=$(head -1 "$MOCK_NC_SEQ_FILE")
    tail -n +2 "$MOCK_NC_SEQ_FILE" >"$MOCK_NC_SEQ_FILE.tmp" && mv "$MOCK_NC_SEQ_FILE.tmp" "$MOCK_NC_SEQ_FILE"
else
    first="${MOCK_NC_RESP:-full}"
fi
case "$first" in
chunk1) printf 'OK MPD 0.24.0\nsize: 12\ntype: image/jpeg\nbinary: 4\nAAAA' ;;
chunk2) printf 'OK MPD 0.24.0\nsize: 12\ntype: image/jpeg\nbinary: 4\nBBBB' ;;
chunk3) printf 'OK MPD 0.24.0\nsize: 12\ntype: image/jpeg\nbinary: 4\nCCCC' ;;
full) printf 'OK MPD 0.24.0\nsize: 8\ntype: image/png\nbinary: 8\nPNGDATA!' ;;
noimg) printf 'OK MPD 0.24.0\nsize: 0\n' ;;
fail) printf 'OK MPD 0.24.0\n' ;;
*) printf 'OK MPD 0.24.0\n' ;;
esac
exit 0
EOF
chmod +x "$FAKE_BIN/nc"
export NC_LOG

# ---- mock mpc: 按参数返回 (mpd.sh source 时多次调用) ----
# 注意: shell 已剥离引号, $* 为空格连接的无引号参数
cat >"$FAKE_BIN/mpc" <<'EOF'
#!/usr/bin/env bash
case "$*" in
*"status %state%"*) echo "playing" ;;
*"status %repeat%"*) echo "on" ;;
*"status %random%"*) echo "on" ;;
*"-f %file% current"*) echo "${MOCK_MPC_FILE:-song.flac}" ;;
*"-f %title% current"*) echo "Title" ;;
*"-f %artist% current"*) echo "Artist" ;;
*"status %currenttime%/%totaltime%"*) echo "1:00/3:00 vol" ;;
*) echo "" ;;
esac
EOF
chmod +x "$FAKE_BIN/mpc"

export PATH="$FAKE_BIN:$PATH"

# ---- source mock 位置的 mpd.sh (末尾 module_loop 已被 mock) ----
source "$MOCK_ROFI/scripts/mpd.sh"

# ---- Task 1: 分块拼接 ----
printf 'chunk1\nchunk2\nchunk3\n' >"$TEST_DIR/nc-seq"
export MOCK_NC_SEQ_FILE="$TEST_DIR/nc-seq"
OUT="$TEST_DIR/cover.jpg"
fetch_cover "song.flac" "$OUT"
unset MOCK_NC_SEQ_FILE
assert_eq "$(cat "$OUT" 2>/dev/null)" "AAAABBBBCCCC" "分块: 3 chunk 拼接正确 (offset 递增)"
assert_eq "$(wc -c <"$OUT" 2>/dev/null)" "12" "分块: 拼接后 12 字节"

# ---- Task 2: 单块完整 ----
printf 'full\n' >"$TEST_DIR/nc-seq"
export MOCK_NC_SEQ_FILE="$TEST_DIR/nc-seq"
OUT2="$TEST_DIR/cover2.jpg"
fetch_cover "song.flac" "$OUT2" && rc=0 || rc=1
unset MOCK_NC_SEQ_FILE
assert_eq "$rc" "0" "单块: 成功返回 0"
assert_eq "$(cat "$OUT2" 2>/dev/null)" "PNGDATA!" "单块: 数据完整 (binary: 8)"

# ---- Task 3: 无内嵌封面 (size: 0) → 返回 1 ----
printf 'noimg\n' >"$TEST_DIR/nc-seq"
export MOCK_NC_SEQ_FILE="$TEST_DIR/nc-seq"
fetch_cover "song.flac" "$TEST_DIR/cover3.jpg" && rc=0 || rc=1
unset MOCK_NC_SEQ_FILE
assert_eq "$rc" "1" "无图: size:0 → 返回 1"
assert_cond "无图: 不产生输出文件" "[ ! -s \"\$TEST_DIR/cover3.jpg\" ]"

# ---- Task 4: 无 binary 行 (失败) → 返回 1 ----
printf 'fail\n' >"$TEST_DIR/nc-seq"
export MOCK_NC_SEQ_FILE="$TEST_DIR/nc-seq"
fetch_cover "song.flac" "$TEST_DIR/cover4.jpg" && rc=0 || rc=1
unset MOCK_NC_SEQ_FILE
assert_eq "$rc" "1" "失败: 无 binary → 返回 1"

# ---- Task 5: MPD_HOST/MPD_PORT 环境变量被使用 ----
: >"$NC_LOG"
printf 'full\n' >"$TEST_DIR/nc-seq"
export MOCK_NC_SEQ_FILE="$TEST_DIR/nc-seq" MPD_HOST="custom-host" MPD_PORT="7700"
fetch_cover "song.flac" "$TEST_DIR/cover5.jpg" >/dev/null 2>&1
unset MOCK_NC_SEQ_FILE MPD_HOST MPD_PORT
assert_cond "环境变量: nc 收到 custom-host" "grep -q 'custom-host' \"\$NC_LOG\""
assert_cond "环境变量: nc 收到 7700 端口" "grep -q '7700' \"\$NC_LOG\""

# ---- Task 6: 通道函数存在性 ----
assert_cond "通道: _mpd_readpicture 函数已定义" "declare -F _mpd_readpicture >/dev/null"

# ---- Task 7: cache 绑定歌曲 uri hash, 命中复用不重复拉取 ----
# mpd.sh source 时主流程已用 MOCK_MPC_FILE=song.flac 拉取过一次 (写入 cache)
NC_COUNT_FILE="$TEST_DIR/nc-count.txt"
: >"$NC_COUNT_FILE"
cat >"$FAKE_BIN/nc" <<'EOF'
#!/usr/bin/env bash
echo x >>"$NC_COUNT_FILE"
printf 'OK MPD 0.24.0\nsize: 8\ntype: image/jpeg\nbinary: 8\nPNGDATA!'
EOF
chmod +x "$FAKE_BIN/nc"
export NC_COUNT_FILE

# 预计算 song.flac 的 hash cache 文件 → 模拟已缓存
export MOCK_MPC_FILE="song.flac"
uri_hash=$(printf '%s' "song.flac" | cksum | cut -d' ' -f1)
cached="$XDG_CACHE_HOME/dwm/mpd-cover/mpd-cover-$uri_hash.jpg"
mkdir -p "$XDG_CACHE_HOME/dwm/mpd-cover"

# 场景 A: cache 不存在 → 拉取 (nc 调用 1 次) 并生成缓存文件
rm -f "$cached"
: >"$NC_COUNT_FILE"
# 重跑 source 触发主流程拉取
source "$MOCK_ROFI/scripts/mpd.sh" 2>/dev/null
assert_eq "$(wc -l <"$NC_COUNT_FILE")" "1" "cache 未命中: 拉取 1 次"
assert_cond "cache 未命中: 生成绑定 uri hash 的缓存文件" "[ -f \"$cached\" ]"

# 场景 B: cache 已存在 → 不拉取 (nc 调用 0 次)
: >"$NC_COUNT_FILE"
source "$MOCK_ROFI/scripts/mpd.sh" 2>/dev/null
assert_eq "$(wc -l <"$NC_COUNT_FILE")" "0" "cache 命中: 复用不重复拉取 (nc 0 次)"

# 场景 C: theme-str 防平铺要素 — 显式约束 imagebox 尺寸 (width/height/expand:false)
# 防平铺不绑定具体属性: 显式尺寸约束下 rofi 按给定尺寸绘制背景图
source "$MOCK_ROFI/scripts/mpd.sh" 2>/dev/null
ts="${MODULE_THEME_STR[0]:-}"
assert_cond "theme-str: 引用封面路径" "[[ \"\$ts\" == *\"\$cached\"* ]]"
assert_cond "theme-str: 显式尺寸约束防平铺 (width/height/expand:false)" \
    "[[ \"\$ts\" == *'width: 200px'* ]] && [[ \"\$ts\" == *'height: 200px'* ]] && [[ \"\$ts\" == *'expand: false'* ]]"

# 场景 D: 不同歌曲 → 不同 cache 文件 (hash 绑定)
MOCK_MPC_FILE_SAVE="$MOCK_MPC_FILE"
export MOCK_MPC_FILE="another/song.mp3"
source "$MOCK_ROFI/scripts/mpd.sh" 2>/dev/null
uri_hash2=$(printf '%s' "another/song.mp3" | cksum | cut -d' ' -f1)
assert_cond "不同歌曲: 生成独立 hash 缓存文件" "[ -f \"$XDG_CACHE_HOME/dwm/mpd-cover/mpd-cover-$uri_hash2.jpg\" ]"
MOCK_MPC_FILE="$MOCK_MPC_FILE_SAVE"

if ((FAIL)); then
    echo "== 有失败用例 =="
    exit 1
fi
echo "== 全部通过 =="
