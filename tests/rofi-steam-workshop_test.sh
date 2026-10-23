#!/usr/bin/env bash
# rofi/scripts/steam-workshop.sh 菜单改版回归测试 (awk 提取 handler + mock, 无 rofi/网络)
#   Download: 合法剪贴板直下 / 非法弹 input / 空 input 取消
#   Update: 空目录提示 / scope 取消 / 无更新 / 确认执行+删源 / 单条失败汇总 / 拒绝确认
#   Open: 建目录并 xdg-open
# 运行: bash tests/rofi-steam-workshop_test.sh

DWM="$HOME/.dwm"
TEST_DIR=$(mktemp -d)
trap 'rm -rf "$TEST_DIR"' EXIT
export HOME="$TEST_DIR/home"
mkdir -p "$HOME"

FAIL=0
check() { # desc cond
    if eval "$2"; then
        echo "ok: $1"
    else
        echo "FAIL: $1"
        FAIL=1
    fi
}

# ---- mock ----
NOTIFY_LOG="$TEST_DIR/notify.log"
: >"$NOTIFY_LOG"
system-notify() { printf '%s|%s|%s\n' "$1" "$2" "${3//$'\n'/\\n}" >>"$NOTIFY_LOG"; }
module_input() { echo CALLED >>"$TEST_DIR/input.called"; printf '%s' "${MODULE_INPUT_RET:-}"; }
module_sub_rofi() { echo CALLED >>"$TEST_DIR/sub.called"; printf '%s' "${MODULE_SUB_RET:-}"; }
module_confirm() { echo CALLED >>"$TEST_DIR/confirm.called"; [[ "${MODULE_CONFIRM_RET:-Yes}" == "Yes" ]]; }
_pick_user() { echo CALLED >>"$TEST_DIR/pick.called"; printf 'testuser'; }
_go() { printf 'GO:%s\n' "$1" >>"$TEST_DIR/go.log"; }
: >"$TEST_DIR/go.log"
xdg-open() { printf '%s\n' "$*" >>"$TEST_DIR/xdg.log"; }
reset_marks() { rm -f "$TEST_DIR"/input.called "$TEST_DIR"/sub.called "$TEST_DIR"/confirm.called "$TEST_DIR"/pick.called "$TEST_DIR"/go.log "$TEST_DIR"/dl.log "$TEST_DIR"/dlogo.log "$TEST_DIR"/check.log; : >"$NOTIFY_LOG"; }

source "$DWM/tools/steam-workshop.sh" # 真 sw_parse_itemid; sw_download/sw_check_updates 下面 mock
sw_check_updates() { printf 'CHECK:%s|%s\n' "$1" "$2" >>"$TEST_DIR/check.log"; printf '%s' "${SW_CHECK_RET:-}"; return "${SW_CHECK_RC:-0}"; }
sw_download() {
    printf 'DL:%s|%s|%s|%s\n' "$1" "$2" "$3" "$4" >>"$TEST_DIR/dl.log"
    if [[ "$2" == "${SW_DOWNLOAD_FAIL_ID:-__none__}" ]]; then return 1; fi
    printf '%s\n' "${SW_DOWNLOAD_OUT:-/new/path}"
    return 0
}

for fn in handle_download handle_update handle_open; do
    awk -v fn="$fn" '$0 == fn"() {"{f=1} f{print} f && /^\}$/{exit}' \
        "$DWM/rofi/scripts/steam-workshop.sh" >"$TEST_DIR/$fn.sh"
    eval "$(cat "$TEST_DIR/$fn.sh")"
done

VALID_URL="https://steamcommunity.com/sharedfiles/filedetails/?id=2858284176"

# ---- Download ----
reset_marks
CLIP_URL="$VALID_URL"
handle_download
check "download: 合法剪贴板直接下载" 'grep -q "GO:$VALID_URL" "$TEST_DIR/go.log"'
check "download: 合法剪贴板不弹 input" '[[ ! -f $TEST_DIR/input.called ]]'

reset_marks
CLIP_URL="hello not a url"
MODULE_INPUT_RET="$VALID_URL"
handle_download
check "download: 非法剪贴板弹 input 并下载输入" 'grep -q "GO:$VALID_URL" "$TEST_DIR/go.log" && [[ -f $TEST_DIR/input.called ]]'

reset_marks
CLIP_URL=""
MODULE_INPUT_RET=""
handle_download
check "download: input 为空直接返回" '[[ ! -s $TEST_DIR/go.log ]]'

reset_marks
CLIP_URL="3810650535"
handle_download
check "download: 纯数字剪贴板直下" 'grep -q "GO:3810650535" "$TEST_DIR/go.log"'

# ---- _go (真实函数 + mock 依赖; 公开条目跳选人/走 anonymous) ----
unset -f _go
awk -v fn="_go" '$0 == fn"() {"{f=1} f{print} f && /^\}$/{exit}' \
    "$DWM/rofi/scripts/steam-workshop.sh" >"$TEST_DIR/_go.sh"
eval "$(cat "$TEST_DIR/_go.sh")"
sw_item_info() { printf '%s' "${SW_INFO_RET:-}"; return "${SW_INFO_RC:-0}"; }
sw_fetch_page() { printf '%s' "${SW_PAGE_RET:-}"; }
sw_page_gated() { return "${SW_GATED_RC:-1}"; }
_download() { printf 'DLGO:%s|%s|%s|%s|%s\n' "$1" "$2" "$3" "$4" "$5" >>"$TEST_DIR/dlogo.log"; }

reset_marks
SW_INFO_RET="431960|Wallpaper Engine|Wavy grass"; SW_INFO_RC=0
_go "$VALID_URL"
check "go: 公开条目跳过选用户" '[[ ! -f $TEST_DIR/pick.called ]]'
check "go: 公开条目走 anonymous" 'grep -q "DLGO:431960|2858284176|anonymous|" "$TEST_DIR/dlogo.log"'

reset_marks
SW_INFO_RET=""; SW_INFO_RC=1; SW_PAGE_RET="gated"; SW_GATED_RC=0
MODULE_INPUT_RET="431960"
_go "$VALID_URL"
check "go: 手动 AppID 仍选用户" '[[ -f $TEST_DIR/pick.called ]]'
check "go: 手动 AppID 用所选用户下载" 'grep -q "DLGO:431960|2858284176|testuser|" "$TEST_DIR/dlogo.log"'

reset_marks
SW_INFO_RC=1; MODULE_INPUT_RET=""
_go "$VALID_URL"
check "go: AppID 为空直接返回" '[[ ! -s $TEST_DIR/dlogo.log ]] && [[ ! -f $TEST_DIR/pick.called ]]'
SW_INFO_RC=0

# ---- Update ----
export STEAMCMD_INSTALL_DIR="$TEST_DIR/empty-root"
reset_marks
handle_update
check "update: 空目录提示且不弹 scope" 'grep -q "No downloads yet" "$NOTIFY_LOG" && [[ ! -f $TEST_DIR/sub.called ]]'

mkdir -p "$TEST_DIR/uproot/WallpaperEngine_431960/111" "$TEST_DIR/uproot/steamapps/workshop/content/431960/666"
export STEAMCMD_INSTALL_DIR="$TEST_DIR/uproot"
reset_marks
MODULE_SUB_RET=""
handle_update
check "update: scope 取消直接返回" '[[ ! -f $TEST_DIR/check.log ]]'

reset_marks
MODULE_SUB_RET="All Apps"
SW_CHECK_RET="CURRENT|222|/x"$'\n'"SKIP|333|/y|api-failed"
SW_CHECK_RC=0
handle_update
wait
check "update: 无更新则提示且不确认不下载" 'grep -q "All up to date (1 skipped)" "$NOTIFY_LOG" && [[ ! -f $TEST_DIR/confirm.called ]] && [[ ! -f $TEST_DIR/dl.log ]]'
check "update: 检查前有 Checking 反馈" 'grep -q "Checking for updates" "$NOTIFY_LOG"'
check "update: 批量更新不弹用户选择" '[[ ! -f $TEST_DIR/pick.called ]]'

reset_marks
MODULE_SUB_RET="All Apps"
MODULE_CONFIRM_RET="Yes"
SW_CHECK_RET="UPDATE|431960|111|$TEST_DIR/uproot/WallpaperEngine_431960/111"$'\n'"UPDATE|431960|666|$TEST_DIR/uproot/steamapps/workshop/content/431960/666"
SW_CHECK_RC=0
SW_DOWNLOAD_OUT="$TEST_DIR/new-flat"
handle_update
wait
check "update: 逐条下载且 appname 正确派生" 'grep -q "DL:431960|111|anonymous|WallpaperEngine" "$TEST_DIR/dl.log" && grep -q "DL:431960|666|anonymous|431960" "$TEST_DIR/dl.log"'
check "update: 成功后删源目录" '[[ ! -e $TEST_DIR/uproot/WallpaperEngine_431960/111 && ! -e $TEST_DIR/uproot/steamapps/workshop/content/431960/666 ]]'
check "update: 汇总成功通知" 'grep -q "2 updated" "$NOTIFY_LOG"'
check "update: 成功通知带 id+名称" 'grep -q "WallpaperEngine_431960/111" "$NOTIFY_LOG" && grep -q "431960/666" "$NOTIFY_LOG"'
check "update: 开跑有 Updating 反馈" 'grep -q "Updating 2 item(s)" "$NOTIFY_LOG"'

mkdir -p "$TEST_DIR/uproot2/A_1/111" "$TEST_DIR/uproot2/A_1/222"
export STEAMCMD_INSTALL_DIR="$TEST_DIR/uproot2"
reset_marks
MODULE_SUB_RET="A_1"
MODULE_CONFIRM_RET="Yes"
SW_CHECK_RET="UPDATE|1|111|$TEST_DIR/uproot2/A_1/111"$'\n'"UPDATE|1|222|$TEST_DIR/uproot2/A_1/222"
SW_DOWNLOAD_FAIL_ID="222"
handle_update
wait
unset SW_DOWNLOAD_FAIL_ID
check "update: scope 透传给检查" 'grep -q "CHECK:$TEST_DIR/uproot2|A_1" "$TEST_DIR/check.log"'
check "update: 失败汇总含标签且成功源已删" 'grep -q "1 updated: A_1/111, 1 failed: A_1/222" "$NOTIFY_LOG" && [[ ! -e $TEST_DIR/uproot2/A_1/111 && -e $TEST_DIR/uproot2/A_1/222 ]]'
check "update: 失败通知带 id+名称" 'grep -q "A_1/111" "$NOTIFY_LOG" && grep -q "A_1/222" "$NOTIFY_LOG"'

reset_marks
MODULE_SUB_RET="All Apps"
SW_CHECK_RET="UPDATE|431960|111|/z"
SW_DOWNLOAD_OUT="$TEST_DIR/new-flat-noconfirm"
handle_update
wait
check "update: 免确认直接下载" '[[ -f $TEST_DIR/dl.log ]]'
check "update: 全程不弹确认" '[[ ! -f $TEST_DIR/confirm.called ]]'

# ---- Open ----
export STEAMCMD_INSTALL_DIR="$TEST_DIR/newroot"
reset_marks
rm -rf "$TEST_DIR/newroot" "$TEST_DIR/xdg.log"
handle_open
wait
check "open: 建目录并 xdg-open" '[[ -d $TEST_DIR/newroot ]] && grep -q "$TEST_DIR/newroot" "$TEST_DIR/xdg.log"'

exit $FAIL
