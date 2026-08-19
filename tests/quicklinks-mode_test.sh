#!/usr/bin/env bash
# quicklinks-mode.sh 行为测试 (source + mock, 无 rofi 弹窗)
# 运行: bash tests/quicklinks-mode_test.sh

SCRIPT="$HOME/.dwm/rofi/scripts/quicklinks-mode.sh"
TEST_DIR=$(mktemp -d)
trap 'rm -rf "$TEST_DIR"' EXIT

# 注入隔离的 favicon 缓存目录 (source 前生效)
export ICON_CACHE_DIR="$TEST_DIR/icons"
mkdir -p "$ICON_CACHE_DIR"

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
assert_file_has() { # file content msg
	if grep -aqe "$2" "$1"; then
		echo "ok: $3"
	else
		echo "FAIL: $3 (file 不含 $2)"
		FAIL=1
	fi
}

# ---- source ----
source "$SCRIPT"

FAKE_BIN="$TEST_DIR/bin"
mkdir -p "$FAKE_BIN"

# ---- Task 1: _host_from_url ----
# _host_from_url 结果写 $_HOST 全局变量 (避免 $() 命令替换 fork — 性能优化)
_host_from_url "https://www.github.com/x"; assert_eq "$_HOST" "github.com" "host: strip www"
_host_from_url "https://github.com"; assert_eq "$_HOST" "github.com" "host: 无 www 原样"
_host_from_url "http://localhost:8080/path"; assert_eq "$_HOST" "localhost" "host: 端口剥除"
_host_from_url "https://translate.google.com/"; assert_eq "$_HOST" "translate.google.com" "host: 子域保留"
_host_from_url "not-a-url"; assert_eq "$_HOST" "not-a-url" "host: 非 URL 兜底"

rm -rf "$ICON_CACHE_DIR" && mkdir -p "$ICON_CACHE_DIR"

# ---- Task 2: _fetch_favicon 降级链 ----
# mock curl: MOCK_CURL_SEQ_FILE 每行一次调用 (ok=成功写入 -o 目标, 其他=失败); 无序列时默认失败
cat >"$FAKE_BIN/curl" <<'EOF'
#!/usr/bin/env bash
if [[ -n "${MOCK_CURL_SEQ_FILE:-}" && -s "$MOCK_CURL_SEQ_FILE" ]]; then
	first=$(head -1 "$MOCK_CURL_SEQ_FILE")
	tail -n +2 "$MOCK_CURL_SEQ_FILE" >"$MOCK_CURL_SEQ_FILE.tmp" && mv "$MOCK_CURL_SEQ_FILE.tmp" "$MOCK_CURL_SEQ_FILE"
	if [[ "$first" == "ok" ]]; then
		out=""
		while [[ $# -gt 0 ]]; do
			if [[ "$1" == "-o" ]]; then out="$2"; shift 2; else shift; fi
		done
		[[ -n "$out" ]] && printf 'FAKEIMG' >"$out"
		exit 0
	fi
	exit 1
fi
exit 1
EOF
# mock file: MOCK_FILE_MIME 控制 MIME 输出 (默认 image/png)
cat >"$FAKE_BIN/file" <<'EOF'
#!/usr/bin/env bash
echo "${MOCK_FILE_MIME:-image/png}"
EOF
chmod +x "$FAKE_BIN/curl" "$FAKE_BIN/file"
export PATH="$FAKE_BIN:$PATH"

rm -rf "$ICON_CACHE_DIR" && mkdir -p "$ICON_CACHE_DIR"
printf 'ok\n' >"$TEST_DIR/curl-seq"
export MOCK_CURL_SEQ_FILE="$TEST_DIR/curl-seq"
_fetch_favicon "github.com"
unset MOCK_CURL_SEQ_FILE
assert_eq "$([[ -f "$ICON_CACHE_DIR/github.com.png" ]] && echo yes)" "yes" "下载: 首源成功 → png 落盘"
assert_eq "$(wc -c <"$ICON_CACHE_DIR/github.com.png")" "7" "下载: 缓存内容落盘"

rm -f "$ICON_CACHE_DIR"/*
printf 'fail\nok\n' >"$TEST_DIR/curl-seq"
export MOCK_CURL_SEQ_FILE="$TEST_DIR/curl-seq"
_fetch_favicon "example.com"
unset MOCK_CURL_SEQ_FILE
assert_eq "$([[ -f "$ICON_CACHE_DIR/example.com.png" ]] && echo yes)" "yes" "下载: 首源失败降级次源 → png 落盘"

rm -f "$ICON_CACHE_DIR"/*
printf 'fail\nfail\nfail\n' >"$TEST_DIR/curl-seq"
export MOCK_CURL_SEQ_FILE="$TEST_DIR/curl-seq"
_fetch_favicon "nosite.com"
unset MOCK_CURL_SEQ_FILE
assert_eq "$([[ -f "$ICON_CACHE_DIR/nosite.com.png.fail" ]] && echo yes)" "yes" "下载: 三源全失败 → .fail 标记"
[[ -f "$ICON_CACHE_DIR/nosite.com.png" ]] && { echo "FAIL: 全失败不应有 png"; FAIL=1; } || echo "ok: 全失败无 png 残留"

# 下载内容非 image → file 校验拦截, 全源作废
rm -f "$ICON_CACHE_DIR"/*
printf 'ok\nok\nok\n' >"$TEST_DIR/curl-seq"
export MOCK_CURL_SEQ_FILE="$TEST_DIR/curl-seq" MOCK_FILE_MIME="text/html"
_fetch_favicon "badcontent.com"
unset MOCK_CURL_SEQ_FILE MOCK_FILE_MIME
assert_eq "$([[ -f "$ICON_CACHE_DIR/badcontent.com.png.fail" ]] && echo yes)" "yes" "下载: 内容非 image 全源作废 → .fail 标记"

rm -rf "$ICON_CACHE_DIR" && mkdir -p "$ICON_CACHE_DIR"

# ---- fixture (source 后覆盖, 脚本内 CONFIG 默认值在 source 时定义) ----
CONFIG="$TEST_DIR/quicklinks.json"
cat >"$CONFIG" <<'JSON'
{"links":[
  {"name":"GitHub","url":"https://github.com","id":"id-1"},
  {"name":"Example","url":"https://example.com","id":"id-2"}
]}
JSON

# ---- mock xdg-open / yad / rofi / notify-send ----
XDG_FAKE_LOG="$TEST_DIR/xdg.log"
cat >"$FAKE_BIN/xdg-open" <<EOF
#!/usr/bin/env bash
echo "OPEN:\$*" >> "$XDG_FAKE_LOG"
EOF
cat >"$FAKE_BIN/yad" <<EOF
#!/usr/bin/env bash
# 支持顺序输出序列 (MOCK_YAD_SEQ_FILE: 每行一次调用, 弹出第一行), 否则固定输出
if [[ -n "\$MOCK_YAD_SEQ_FILE" && -s "\$MOCK_YAD_SEQ_FILE" ]]; then
	first=\$(head -1 "\$MOCK_YAD_SEQ_FILE")
	tail -n +2 "\$MOCK_YAD_SEQ_FILE" > "\$MOCK_YAD_SEQ_FILE.tmp" && mv "\$MOCK_YAD_SEQ_FILE.tmp" "\$MOCK_YAD_SEQ_FILE"
	echo "\$first"
else
	echo "\${MOCK_YAD_OUTPUT:-Edited Name|https://edited.com}"
fi
EOF
cat >"$FAKE_BIN/rofi" <<EOF
#!/usr/bin/env bash
echo "\${MOCK_ROFI_OUTPUT:-No}"
EOF
cat >"$FAKE_BIN/notify-send" <<EOF
#!/usr/bin/env bash
echo "NOTIFY:\$*" >> "$XDG_FAKE_LOG"
EOF
chmod +x "$FAKE_BIN/xdg-open" "$FAKE_BIN/yad" "$FAKE_BIN/rofi" "$FAKE_BIN/notify-send"

# ---- Task 2: 列表输出 ----
_list >"$TEST_DIR/list.out"
printf 'GitHub\0info\x1fid-1\nExample\0info\x1fid-2\n New (Add)\0info\x1fnew\n\0use-hot-keys\x1ftrue\n' >"$TEST_DIR/list.expected"
if cmp -s "$TEST_DIR/list.out" "$TEST_DIR/list.expected"; then
	echo "ok: _list 输出 (含 info 元数据, New 行底部, use-hot-keys)"
else
	echo "FAIL: _list 输出"
	echo "--- got ---"; xxd "$TEST_DIR/list.out" | head -10
	echo "--- want ---"; xxd "$TEST_DIR/list.expected" | head -10
	FAIL=1
fi

# ---- Task 3: favicon 列表输出 ----
# hit: 缓存命中 → \0icon 图片属性 + \x1f 连接 info
# 注意: 多属性用 \x1f 连接 (rofi C 字符串解析, 第二个 \0 会截断 info → ROFI_INFO 丢失)
wait
rm -rf "$ICON_CACHE_DIR" && mkdir -p "$ICON_CACHE_DIR"
: >"$ICON_CACHE_DIR/github.com.png"
_list >"$TEST_DIR/list-hit.out"
printf 'GitHub\0icon\x1f%s\x1finfo\x1fid-1\nExample\0info\x1fid-2\n New (Add)\0info\x1fnew\n\0use-hot-keys\x1ftrue\n' "$ICON_CACHE_DIR/github.com.png" >"$TEST_DIR/list-hit.expected"
if cmp -s "$TEST_DIR/list-hit.out" "$TEST_DIR/list-hit.expected"; then
	echo "ok: _list hit → 图片属性, 行文本无字符 icon"
else
	echo "FAIL: _list hit 输出"
	echo "--- got ---"; xxd "$TEST_DIR/list-hit.out" | head -10
	echo "--- want ---"; xxd "$TEST_DIR/list-hit.expected" | head -10
	FAIL=1
fi
# 回归锁定: hit 行内属性必须 \x1f 连接 (第二 \0 会截断 info → ROFI_INFO 丢失)
# \0info 只应出现在 Example (miss) 与 New 行, 共 2 行; GitHub hit 行不得含
# 注意: 模式须单引号让 grep -P 解析 \x00 (bash $'\x00' 展开的字面 NUL 会截断模式); grep -a 对 NUL 文件不可靠
n=$(grep -Pac '\x00info' "$TEST_DIR/list-hit.out")
assert_eq "$n" "2" "hit 行属性以 \\x1f 连接 (\\0info 仅 miss/New 行, 共 2 行)"

# fail: .fail 标记 → 与 miss 相同 fallback 输出 (纯文本行)
wait
rm -rf "$ICON_CACHE_DIR" && mkdir -p "$ICON_CACHE_DIR"
: >"$ICON_CACHE_DIR/github.com.png.fail"
_list >"$TEST_DIR/list-fail.out"
printf 'GitHub\0info\x1fid-1\nExample\0info\x1fid-2\n New (Add)\0info\x1fnew\n\0use-hot-keys\x1ftrue\n' >"$TEST_DIR/list-fail.expected"
if cmp -s "$TEST_DIR/list-fail.out" "$TEST_DIR/list-fail.expected"; then
	echo "ok: _list fail → fallback 原样输出"
else
	echo "FAIL: _list fail 输出"
	echo "--- got ---"; xxd "$TEST_DIR/list-fail.out" | head -10
	echo "--- want ---"; xxd "$TEST_DIR/list-fail.expected" | head -10
	FAIL=1
fi

# 分隔符: name/url 含 | 不破坏字段解析
wait
rm -rf "$ICON_CACHE_DIR" && mkdir -p "$ICON_CACHE_DIR"
cat >"$CONFIG" <<'JSON'
{"links":[
  {"name":"A|B","url":"https://x.com/a|b","id":"id-pipe"}
]}
JSON
_list >"$TEST_DIR/list-pipe.out"
printf 'A|B\0info\x1fid-pipe\n New (Add)\0info\x1fnew\n\0use-hot-keys\x1ftrue\n' >"$TEST_DIR/list-pipe.expected"
if cmp -s "$TEST_DIR/list-pipe.out" "$TEST_DIR/list-pipe.expected"; then
	echo "ok: 分隔符: name/url 含 | 不破坏解析"
else
	echo "FAIL: 分隔符: name/url 含 | 解析"
	echo "--- got ---"; xxd "$TEST_DIR/list-pipe.out" | head -8
	echo "--- want ---"; xxd "$TEST_DIR/list-pipe.expected" | head -8
	FAIL=1
fi
wait
# 恢复原 fixture
cat >"$CONFIG" <<'JSON'
{"links":[
  {"name":"GitHub","url":"https://github.com","id":"id-1"},
  {"name":"Example","url":"https://example.com","id":"id-2"}
]}
JSON

# ---- Task 3: _ensure_icons ----
# 已缓存 (png/.fail) 的 host 不触发下载
wait
rm -rf "$ICON_CACHE_DIR" && mkdir -p "$ICON_CACHE_DIR"
_load
: >"$ICON_CACHE_DIR/github.com.png"
: >"$ICON_CACHE_DIR/example.com.png.fail"
printf 'ok\n' >"$TEST_DIR/curl-seq"
export MOCK_CURL_SEQ_FILE="$TEST_DIR/curl-seq"
_ensure_icons
wait
assert_eq "$(head -1 "$TEST_DIR/curl-seq")" "ok" "预取: 已缓存 host 不下载 (序列未消耗)"
unset MOCK_CURL_SEQ_FILE

# miss 的 host 触发后台下载 (example.com 预置 .fail 避免 mock 序列并发竞争)
wait
rm -rf "$ICON_CACHE_DIR" && mkdir -p "$ICON_CACHE_DIR"
: >"$ICON_CACHE_DIR/example.com.png.fail"
printf 'ok\n' >"$TEST_DIR/curl-seq"
export MOCK_CURL_SEQ_FILE="$TEST_DIR/curl-seq"
_ensure_icons
wait
assert_eq "$([[ -f "$ICON_CACHE_DIR/github.com.png" ]] && echo yes)" "yes" "预取: miss host 后台下载成功 → png 落盘"
assert_eq "$([[ -f "$ICON_CACHE_DIR/example.com.png.fail" ]] && echo yes)" "yes" "预取: 已 fail host 跳过不下载"
assert_eq "$(head -1 "$TEST_DIR/curl-seq" 2>/dev/null)" "" "预取: 序列耗尽 (仅下载 github.com)"
unset MOCK_CURL_SEQ_FILE

# 同域多链接去重: 只下载一次
wait
rm -rf "$ICON_CACHE_DIR" && mkdir -p "$ICON_CACHE_DIR"
cat >"$CONFIG" <<'JSON'
{"links":[
  {"name":"GH","url":"https://github.com","id":"id-g1"},
  {"name":"GH2","url":"https://github.com/other","id":"id-g2"}
]}
JSON
_load
printf 'ok\n' >"$TEST_DIR/curl-seq"
export MOCK_CURL_SEQ_FILE="$TEST_DIR/curl-seq"
_ensure_icons
wait
assert_eq "$([[ -f "$ICON_CACHE_DIR/github.com.png" ]] && echo yes)" "yes" "预取: 同域多链接只下载一次 → png 落盘"
assert_eq "$(head -1 "$TEST_DIR/curl-seq" 2>/dev/null)" "" "预取: 序列仅消耗一次"
unset MOCK_CURL_SEQ_FILE
cat >"$CONFIG" <<'JSON'
{"links":[
  {"name":"GitHub","url":"https://github.com","id":"id-1"},
  {"name":"Example","url":"https://example.com","id":"id-2"}
]}
JSON
wait

# ---- Task 2: 选中打开 (ROFI_INFO=id) ----
rm -f "$XDG_FAKE_LOG"
ROFI_RETV=1 ROFI_INFO=id-2 _main
sleep 0.3
assert_file_has "$XDG_FAKE_LOG" "OPEN:https://example.com" "RETV=1 + info=id-2 → xdg-open URL"

rm -f "$XDG_FAKE_LOG"
ROFI_RETV=1 ROFI_INFO=no-such-id _main
sleep 0.3
if [[ -s "$XDG_FAKE_LOG" ]]; then
	echo "FAIL: 未知 id 不应触发打开"; FAIL=1
else
	echo "ok: 未知 id 静默忽略"
fi

# ---- Task 3: 自定义输入 (RETV=2) ----
# 模拟真实 rofi: 输入作为脚本命令行参数传入 (子进程执行, 验证主入口参数转发)
rm -f "$XDG_FAKE_LOG"
ROFI_RETV=2 /bin/bash "$SCRIPT" "example.com/path"
sleep 0.3
assert_file_has "$XDG_FAKE_LOG" "OPEN:https://example.com/path" "RETV=2 URL 无协议 → 补 https"

rm -f "$XDG_FAKE_LOG"
ROFI_RETV=2 /bin/bash "$SCRIPT" "https://already.com/x"
sleep 0.3
assert_file_has "$XDG_FAKE_LOG" "OPEN:https://already.com/x" "RETV=2 已有协议 → 原样打开"

rm -f "$XDG_FAKE_LOG"
ROFI_RETV=2 /bin/bash "$SCRIPT" "hello world"
sleep 0.3
assert_file_has "$XDG_FAKE_LOG" "OPEN:https://www.google.com/search?q=hello world" "RETV=2 非 URL → 搜索引擎"

# ---- Task 4: 编辑 (RETV=10) ----
# 注意: 变量必须 export, _main 是函数(同进程), prefix 赋值不会传给嵌套的 yad 子进程
export MOCK_YAD_OUTPUT="Edited Name|https://edited.com"
ROFI_RETV=10 ROFI_INFO=id-2 _main
wait
unset MOCK_YAD_OUTPUT
assert_eq "$(jq -r '.links[] | select(.id=="id-2") | .name' "$CONFIG")" "Edited Name" "编辑: name 更新"
assert_eq "$(jq -r '.links[] | select(.id=="id-2") | .url' "$CONFIG")" "https://edited.com" "编辑: url 更新"
assert_eq "$(jq -r '.links[] | select(.id=="id-2") | .id' "$CONFIG")" "id-2" "编辑: id 保留"
assert_eq "$(jq -r '.links[] | select(.id=="id-1") | .url' "$CONFIG")" "https://github.com" "编辑: 其他条目不变"
assert_eq "$(jq -r '.links | length' "$CONFIG")" "2" "编辑: 条数不变"
assert_eq "$(jq -r 'any(.links[]?; has("icon"))' "$CONFIG")" "false" "编辑: icon 字段不写入"

# 校验循环: 空 name → critical 通知 → 重开表单 → 第二次有效值写入
printf '|https://x.com\nFixed Name|https://fixed.com\n' >"$TEST_DIR/yad-seq"
export MOCK_YAD_SEQ_FILE="$TEST_DIR/yad-seq"
rm -f "$XDG_FAKE_LOG"
ROFI_RETV=10 ROFI_INFO=id-1 _main
wait
unset MOCK_YAD_SEQ_FILE
assert_eq "$(jq -r '.links[] | select(.id=="id-1") | .name' "$CONFIG")" "Fixed Name" "编辑: 空 name 校验后重开表单并写入"
assert_eq "$(jq -r '.links[] | select(.id=="id-1") | .url' "$CONFIG")" "https://fixed.com" "编辑: 重开表单后的 url 写入"
assert_file_has "$XDG_FAKE_LOG" "-u critical" "编辑: 空 name 触发 critical 通知"

# ---- Task 4: 删除 (RETV=11) ----
export MOCK_ROFI_OUTPUT="No"
ROFI_RETV=11 ROFI_INFO=id-1 _main
wait
unset MOCK_ROFI_OUTPUT
assert_eq "$(jq -r '.links | length' "$CONFIG")" "2" "删除: 确认 No 不删除"

export MOCK_ROFI_OUTPUT="Yes"
ROFI_RETV=11 ROFI_INFO=id-1 _main
wait
unset MOCK_ROFI_OUTPUT
assert_eq "$(jq -r '.links | length' "$CONFIG")" "1" "删除: 确认 Yes 删除"
assert_eq "$(jq -r 'any(.links[]?; .id=="id-1")' "$CONFIG")" "false" "删除: id-1 已移除"
assert_eq "$(jq -r '.links[0].id' "$CONFIG")" "id-2" "删除: 其他条目保留"

# ---- Task 5: 新增 (info=new) ----
# mock xclip: 剪贴板预填源
cat >"$FAKE_BIN/xclip" <<EOF
#!/usr/bin/env bash
echo "https://clipboard.example/from-clip"
EOF
chmod +x "$FAKE_BIN/xclip"

export MOCK_YAD_OUTPUT="New Link|https://newlink.example"
ROFI_RETV=1 ROFI_INFO=new _main
wait
unset MOCK_YAD_OUTPUT
assert_eq "$(jq -r '.links | length' "$CONFIG")" "2" "新增: 条数 +1"
assert_eq "$(jq -r '.links[-1].name' "$CONFIG")" "New Link" "新增: name 写入"
assert_eq "$(jq -r '.links[-1].url' "$CONFIG")" "https://newlink.example" "新增: url 写入"
assert_eq "$(jq -r '.links[-1] | has("icon")' "$CONFIG")" "false" "新增: 无 icon 字段"
assert_eq "$(jq -r '.links[-1].id != ""' "$CONFIG")" "true" "新增: id 非空"
assert_eq "$(jq -r '[.links[].id] | unique | length' "$CONFIG")" "2" "新增: id 唯一"

# 新增不依赖剪贴板 (xclip 无输出时流程正常)
cat >"$FAKE_BIN/xclip" <<'EOF'
#!/usr/bin/env bash
exit 1
EOF
export MOCK_YAD_OUTPUT="No Clip|https://noclip.example"
ROFI_RETV=1 ROFI_INFO=new _main
wait
unset MOCK_YAD_OUTPUT
assert_eq "$(jq -r '.links | length' "$CONFIG")" "3" "新增: 无剪贴板仍可新增"

# ---- _ensure_ids 零写入 (id 齐全) ----
before=$(md5sum "$CONFIG" | cut -d' ' -f1)
ROFI_RETV=0 _main >/dev/null
after=$(md5sum "$CONFIG" | cut -d' ' -f1)
assert_eq "$before" "$after" "_ensure_ids: id 齐全时零写入"

if ((FAIL)); then
	echo "== 有失败用例 =="
	exit 1
fi
echo "== 全部通过 =="
