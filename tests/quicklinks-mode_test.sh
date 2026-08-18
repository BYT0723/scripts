#!/usr/bin/env bash
# quicklinks-mode.sh 行为测试 (source + mock, 无 rofi 弹窗)
# 运行: bash tests/quicklinks-mode_test.sh

SCRIPT="$HOME/.dwm/rofi/scripts/quicklinks-mode.sh"
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

# ---- fixture (source 后覆盖, 脚本内 CONFIG 默认值在 source 时定义) ----
CONFIG="$TEST_DIR/quicklinks.json"
cat >"$CONFIG" <<'JSON'
{"links":[
  {"name":"GitHub","icon":"","url":"https://github.com","id":"id-1"},
  {"name":"Example","icon":"󰖟","url":"https://example.com","id":"id-2"}
]}
JSON

# ---- mock xdg-open / yad / rofi / notify-send ----
XDG_FAKE_LOG="$TEST_DIR/xdg.log"
FAKE_BIN="$TEST_DIR/bin"
mkdir -p "$FAKE_BIN"
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
	echo "\${MOCK_YAD_OUTPUT:-Edited Name|󰖟|https://edited.com}"
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
export PATH="$FAKE_BIN:$PATH"

# ---- Task 2: 列表输出 ----
_list >"$TEST_DIR/list.out"
printf '  GitHub\0info\x1fid-1\n󰖟 Example\0info\x1fid-2\n New (Add)\0info\x1fnew\n\0use-hot-keys\x1ftrue\n' >"$TEST_DIR/list.expected"
if cmp -s "$TEST_DIR/list.out" "$TEST_DIR/list.expected"; then
	echo "ok: _list 输出 (含 info 元数据, New 行底部, use-hot-keys)"
else
	echo "FAIL: _list 输出"
	echo "--- got ---"; xxd "$TEST_DIR/list.out" | head -10
	echo "--- want ---"; xxd "$TEST_DIR/list.expected" | head -10
	FAIL=1
fi

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
rm -f "$XDG_FAKE_LOG"
ROFI_RETV=2 _main "example.com/path"
sleep 0.3
assert_file_has "$XDG_FAKE_LOG" "OPEN:https://example.com/path" "RETV=2 URL 无协议 → 补 https"

rm -f "$XDG_FAKE_LOG"
ROFI_RETV=2 _main "https://already.com/x"
sleep 0.3
assert_file_has "$XDG_FAKE_LOG" "OPEN:https://already.com/x" "RETV=2 已有协议 → 原样打开"

rm -f "$XDG_FAKE_LOG"
ROFI_RETV=2 _main "hello world"
sleep 0.3
assert_file_has "$XDG_FAKE_LOG" "OPEN:https://www.google.com/search?q=hello world" "RETV=2 非 URL → 搜索引擎"

# ---- Task 4: 编辑 (RETV=10) ----
# 注意: 变量必须 export, _main 是函数(同进程), prefix 赋值不会传给嵌套的 yad 子进程
export MOCK_YAD_OUTPUT="Edited Name|󰖟|https://edited.com"
ROFI_RETV=10 ROFI_INFO=id-2 _main
wait
unset MOCK_YAD_OUTPUT
assert_eq "$(jq -r '.links[] | select(.id=="id-2") | .name' "$CONFIG")" "Edited Name" "编辑: name 更新"
assert_eq "$(jq -r '.links[] | select(.id=="id-2") | .url' "$CONFIG")" "https://edited.com" "编辑: url 更新"
assert_eq "$(jq -r '.links[] | select(.id=="id-2") | .id' "$CONFIG")" "id-2" "编辑: id 保留"
assert_eq "$(jq -r '.links[] | select(.id=="id-1") | .url' "$CONFIG")" "https://github.com" "编辑: 其他条目不变"
assert_eq "$(jq -r '.links | length' "$CONFIG")" "2" "编辑: 条数不变"

# 校验循环: 空 name → critical 通知 → 重开表单 → 第二次有效值写入
printf '|󰖟|https://x.com\nFixed Name|󰟖|https://fixed.com\n' >"$TEST_DIR/yad-seq"
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

export MOCK_YAD_OUTPUT="New Link|󰟖|https://newlink.example"
ROFI_RETV=1 ROFI_INFO=new _main
wait
unset MOCK_YAD_OUTPUT
assert_eq "$(jq -r '.links | length' "$CONFIG")" "2" "新增: 条数 +1"
assert_eq "$(jq -r '.links[-1].name' "$CONFIG")" "New Link" "新增: name 写入"
assert_eq "$(jq -r '.links[-1].url' "$CONFIG")" "https://newlink.example" "新增: url 写入"
assert_eq "$(jq -r '.links[-1].icon' "$CONFIG")" "󰟖" "新增: icon 写入"
assert_eq "$(jq -r '.links[-1].id != ""' "$CONFIG")" "true" "新增: id 非空"
assert_eq "$(jq -r '[.links[].id] | unique | length' "$CONFIG")" "2" "新增: id 唯一"

# 新增不依赖剪贴板 (xclip 无输出时流程正常)
cat >"$FAKE_BIN/xclip" <<'EOF'
#!/usr/bin/env bash
exit 1
EOF
export MOCK_YAD_OUTPUT="No Clip|󰖟|https://noclip.example"
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
