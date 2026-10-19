#!/usr/bin/env bash
# steam-workshop.sh 单元测试 (source + mock steamcmd/curl, 无网络/无弹窗)
# 运行: bash tests/steam-workshop_test.sh

SCRIPT="$HOME/.dwm/tools/steam-workshop.sh"
TEST_DIR=$(mktemp -d)
trap 'rm -rf "$TEST_DIR"' EXIT
export STEAM_LOGINUSERS="$TEST_DIR/loginusers.vdf"

FAIL=0
assert_cond() { # msg cond
    if eval "$2"; then
        echo "ok: $1"
    else
        echo "FAIL: $1"
        FAIL=1
    fi
}

# ---- fake bin: steamcmd + curl ----
FAKE_BIN="$TEST_DIR/bin"
mkdir -p "$FAKE_BIN"
cat >"$FAKE_BIN/steamcmd" <<'EOF'
#!/usr/bin/env bash
echo "$*" >>"${STEAMCMD_ARGS_LOG:-/dev/null}"
case "${STEAMCMD_MODE:-success}" in
success) mkdir -p "$STEAMCMD_OUTDIR/3810650535"; echo "Success. Downloaded item 3810650535 to \"$STEAMCMD_OUTDIR/3810650535\" (100 bytes)" ;;
auth) echo "ERROR! Download item 3810650535 failed (Access Denied)."; echo "ERROR: Invalid Password" ;;
error) echo "ERROR! Download item 3810650535 failed (Connection Timeout)." ;;
esac
EOF
chmod +x "$FAKE_BIN/steamcmd"
cat >"$FAKE_BIN/curl" <<'EOF'
#!/usr/bin/env bash
: >>"$CURL_CALLED"
case "$*" in
*GetPublishedFileDetails*)
    if [[ -n "${API_DYNAMIC:-}" ]]; then
        id=$(grep -o 'publishedfileids\[0\]=[0-9]*' <<<"$*" | grep -o '[0-9]*$')
        if [[ " ${DELETED_IDS:-} " == *" $id "* ]]; then result=9; else result=1; fi
        if [[ " ${UPDATED_IDS:-} " == *" $id "* ]]; then ts=9999999999; else ts=100; fi
        printf '{"response":{"result":1,"resultcount":1,"publishedfiledetails":[{"publishedfileid":"%s","result":%s,"consumer_app_id":431960,"time_updated":%s}]}}' "$id" "$result" "$ts"
    else
        cat "$CURL_API_FIXTURE"
    fi
    ;;
*appdetails*) cat "$CURL_APP_FIXTURE" ;;
*) cat "$CURL_FIXTURE" ;;
esac
EOF
chmod +x "$FAKE_BIN/curl"
export PATH="$FAKE_BIN:$PATH"
export CURL_CALLED="$TEST_DIR/curl.called" CURL_FIXTURE="$TEST_DIR/page.html"
export CURL_API_FIXTURE="$TEST_DIR/api.json" CURL_APP_FIXTURE="$TEST_DIR/app.json"

# shellcheck source=/dev/null
source "$SCRIPT"

# ---- fixtures ----
cat >"$TEST_DIR/page.html" <<'EOF'
<a class="btnv6_blue_hoverfade btn_medium" href="https://store.steampowered.com/app/431960?snr=x" data-appid="431960">
<div class="apphub_AppIcon"><img src="https://example.com/app.jpg"><div class="overlay"></div></div>
<div class="apphub_AppName ellipsis">Wallpaper Engine</div>
<div class="workshopItemTitle">Wavy grass</div>
EOF
cat >"$TEST_DIR/page-noapp.html" <<'EOF'
<html><body>no app here</body></html>
EOF
cat >"$TEST_DIR/page-gated.html" <<'EOF'
<div class="error_ctn">Sorry! An error was encountered while processing your request: You must be logged in to view this item.</div>
EOF
cat >"$TEST_DIR/api.json" <<'EOF'
{"response":{"result":1,"resultcount":1,"publishedfiledetails":[{"publishedfileid":"3812349759","result":1,"creator_app_id":431960,"consumer_app_id":431960,"title":"Gated Item"}]}}
EOF
cat >"$TEST_DIR/api-deleted.json" <<'EOF'
{"response":{"result":1,"resultcount":1,"publishedfiledetails":[{"publishedfileid":"999","result":9}]}}
EOF
cat >"$TEST_DIR/app.json" <<'EOF'
{"431960":{"success":true,"data":{"name":"Wallpaper Engine"}}}
EOF
cat >"$TEST_DIR/loginusers.vdf" <<'EOF'
"users"
{
	"76561198825777084"
	{
		"AccountName"		"0723wang"
		"PersonaName"		"Extension"
		"Timestamp"		"1791716170"
	}
	"76561198000000001"
	{
		"AccountName"		"second_user"
		"PersonaName"		"Second"
		"Timestamp"		"1690000000"
	}
}
EOF

# ---- parse_itemid ----
assert_cond "parse: workshop URL -> id" '[[ $(sw_parse_itemid "https://steamcommunity.com/sharedfiles/filedetails/?id=2858284176") == 2858284176 ]]'
assert_cond "parse: bare id" '[[ $(sw_parse_itemid "3810650535") == 3810650535 ]]'
assert_cond "parse: garbage fails" '! sw_parse_itemid "https://example.com/foo" >/dev/null'

# ---- resolve_appid ----
rm -f "$CURL_CALLED"
assert_cond "appid: &appid= param skips network" '[[ $(sw_resolve_appid "https://steamcommunity.com/profiles/1/myworkshopfiles/?appid=431960") == 431960 ]] && [[ ! -f $CURL_CALLED ]]'
assert_cond "appid: page data-appid" '[[ $(sw_resolve_appid "https://steamcommunity.com/sharedfiles/filedetails/?id=2858284176") == 431960 ]]'
export CURL_FIXTURE="$TEST_DIR/page-noapp.html"
assert_cond "appid: page without app fails" '! sw_resolve_appid "3810650535" >/dev/null'

# ---- item_info (同一页一次抓全: appid|app名|资源名) ----
export CURL_FIXTURE="$TEST_DIR/page.html"
assert_cond "info: appid|appname|title" '[[ $(sw_item_info "https://steamcommunity.com/sharedfiles/filedetails/?id=2858284176") == "431960|Wallpaper Engine|Wavy grass" ]]'
export CURL_FIXTURE="$TEST_DIR/page-noapp.html" CURL_API_FIXTURE="$TEST_DIR/api-deleted.json"
assert_cond "info: no app fails" '! sw_item_info "999" >/dev/null'
assert_cond "gated: login-gate detected" 'sw_page_gated "$(cat "$TEST_DIR/page-gated.html")"'
assert_cond "gated: normal page not gated" '! sw_page_gated "$(cat "$TEST_DIR/page.html")"'
export CURL_API_FIXTURE="$TEST_DIR/api.json" CURL_APP_FIXTURE="$TEST_DIR/app.json"
assert_cond "api: appid|appname|title" '[[ $(sw_api_info "3812349759") == "431960|Wallpaper Engine|Gated Item" ]]'
export CURL_API_FIXTURE="$TEST_DIR/api-deleted.json"
assert_cond "api: deleted item fails" '! sw_api_info "999" >/dev/null'
# ---- api_time (更新检查) ----
export API_DYNAMIC=1 UPDATED_IDS="111" DELETED_IDS="999"
assert_cond "api_time: appid|time_updated" '[[ $(sw_api_time "111") == "431960|9999999999" ]]'
assert_cond "api_time: old item timestamp" '[[ $(sw_api_time "222") == "431960|100" ]]'
assert_cond "api_time: deleted fails" '! sw_api_time "999" >/dev/null'
assert_cond "api_time: non-numeric fails" '! sw_api_time "abc" >/dev/null'
unset API_DYNAMIC UPDATED_IDS DELETED_IDS
export CURL_FIXTURE="$TEST_DIR/page-gated.html" CURL_API_FIXTURE="$TEST_DIR/api.json"
assert_cond "info: gated page falls back to api" '[[ $(sw_item_info "https://steamcommunity.com/sharedfiles/filedetails/?id=3812349759") == "431960|Wallpaper Engine|Gated Item" ]]'
export CURL_FIXTURE="$TEST_DIR/page-noapp.html" CURL_API_FIXTURE="$TEST_DIR/api-deleted.json"
assert_cond "info: deleted item fails" '! sw_item_info "999" >/dev/null'

# ---- list_users ----
mapfile -t _users < <(sw_list_users)
assert_cond "users: two entries" '[[ ${#_users[@]} -eq 2 ]]'
assert_cond "users: newest first" '[[ ${_users[0]} == "0723wang|Extension" ]]'
assert_cond "users: oldest last" '[[ ${_users[1]} == "second_user|Second" ]]'
export STEAM_LOGINUSERS="$TEST_DIR/nonexistent.vdf"
assert_cond "users: missing file fails" '! sw_list_users >/dev/null'

# ---- safe_app ----
assert_cond "safe_app: strips spaces" '[[ $(sw_safe_app "Wallpaper Engine" 431960) == "WallpaperEngine" ]]'
assert_cond "safe_app: empty falls back to appid" '[[ $(sw_safe_app "" 431960) == "431960" ]]'
assert_cond "safe_app: slash sanitized" '[[ $(sw_safe_app "A/B" 1) == "A_B" ]]'
assert_cond "safe_app: dots fall back to appid" '[[ $(sw_safe_app ".." 431960) == "431960" && $(sw_safe_app "." 431960) == "431960" ]]'

# ---- check_updates ----
UPROOT="$TEST_DIR/uproot"
mkdir -p "$UPROOT/WallpaperEngine_431960/111" "$UPROOT/WallpaperEngine_431960/222" \
  "$UPROOT/OtherApp_999999/333" "$UPROOT/LegacyName/444" "$UPROOT/431960/555" \
  "$UPROOT/junkdir/notanid" "$UPROOT/steamapps/workshop/content/431960/666"
touch -d '2001-01-01' "$UPROOT/WallpaperEngine_431960/111" "$UPROOT/LegacyName/444" \
  "$UPROOT/431960/555" "$UPROOT/steamapps/workshop/content/431960/666"
export API_DYNAMIC=1 UPDATED_IDS="111 444 555 666" DELETED_IDS="333"
_got=$(sw_check_updates "$UPROOT")
_exp="CURRENT|222|$UPROOT/WallpaperEngine_431960/222
SKIP|333|$UPROOT/OtherApp_999999/333|api-failed
UPDATE|431960|111|$UPROOT/WallpaperEngine_431960/111
UPDATE|431960|444|$UPROOT/LegacyName/444
UPDATE|431960|555|$UPROOT/431960/555
UPDATE|431960|666|$UPROOT/steamapps/workshop/content/431960/666"
assert_cond "check: full enumeration" '[[ "$_got" == "$_exp" ]]'
_got=$(sw_check_updates "$UPROOT" "WallpaperEngine_431960")
_exp="CURRENT|222|$UPROOT/WallpaperEngine_431960/222
UPDATE|431960|111|$UPROOT/WallpaperEngine_431960/111"
assert_cond "check: scope filter" '[[ "$_got" == "$_exp" ]]'
mkdir -p "$TEST_DIR/emptyroot"
assert_cond "check: empty root rc=1" '! sw_check_updates "$TEST_DIR/emptyroot" >/dev/null'
assert_cond "check: missing root rc=1" '! sw_check_updates "$TEST_DIR/nonexistent" >/dev/null'
unset API_DYNAMIC UPDATED_IDS DELETED_IDS
# ---- download ----
export STEAM_LOGINUSERS="$TEST_DIR/loginusers.vdf"
export STEAMCMD_OUTDIR="$TEST_DIR/real"
export STEAMCMD_ARGS_LOG="$TEST_DIR/steamcmd.args"
mkdir -p "$STEAMCMD_OUTDIR/3810650535"
export STEAMCMD_MODE=success
export STEAMCMD_INSTALL_DIR="$TEST_DIR/isolated"
rm -f "$STEAMCMD_ARGS_LOG"
_out=$(sw_download 431960 3810650535 anonymous "Wallpaper Engine")
assert_cond "download: success rc=0" '[[ $? -eq 0 ]]'
assert_cond "download: stdout is flat path with appid" '[[ $_out == "$STEAMCMD_INSTALL_DIR/WallpaperEngine_431960/3810650535" ]]'
assert_cond "download: flat dir exists" '[[ -d "$STEAMCMD_INSTALL_DIR/WallpaperEngine_431960/3810650535" ]]'
assert_cond "download: deep path moved away" '[[ ! -e "$STEAMCMD_OUTDIR/3810650535" ]]'
assert_cond "download: leaves no dir farm behind" '[[ ! -d $TEST_DIR/dl ]]'
assert_cond "download: passes force_install_dir" 'grep -Fq "+force_install_dir $STEAMCMD_INSTALL_DIR" "$STEAMCMD_ARGS_LOG"'
assert_cond "download: creates isolated dir" '[[ -d $STEAMCMD_INSTALL_DIR ]]'
_out2=$(sw_download 431960 3810650535 anonymous)
assert_cond "download: no appname falls back to appid" '[[ $_out2 == "$STEAMCMD_INSTALL_DIR/431960/3810650535" ]]'
export STEAMCMD_MODE=auth
assert_cond "download: auth failure rc=2" 'sw_download 431960 3810650535 someuser >/dev/null 2>&1; [[ $? -eq 2 ]]'
export STEAMCMD_MODE=error
assert_cond "download: other failure rc=1" 'sw_download 431960 3810650535 anonymous >/dev/null 2>&1; [[ $? -eq 1 ]]'
# compat + precedence + default
export STEAMCMD_MODE=success
rm -f "$STEAMCMD_ARGS_LOG"
sw_download 431960 notanid anonymous >/dev/null 2>&1
assert_cond "download: non-numeric itemid rejected without steamcmd" '[[ $? -eq 1 && ! -f $STEAMCMD_ARGS_LOG ]]'
rm -f "$STEAMCMD_ARGS_LOG"
sw_download notaid 3810650535 anonymous >/dev/null 2>&1
assert_cond "download: non-numeric appid rejected without steamcmd" '[[ $? -eq 1 && ! -f $STEAMCMD_ARGS_LOG ]]'
export STEAMCMD_MODE=success
export STEAM_WORKSHOP_DIR="$TEST_DIR/legacy-root"
unset STEAMCMD_INSTALL_DIR
rm -f "$STEAMCMD_ARGS_LOG"
sw_download 431960 3810650535 anonymous >/dev/null
assert_cond "download: STEAM_WORKSHOP_DIR compat" 'grep -Fq "+force_install_dir $STEAM_WORKSHOP_DIR" "$STEAMCMD_ARGS_LOG" && [[ -d $STEAM_WORKSHOP_DIR ]]'
export STEAMCMD_INSTALL_DIR="$TEST_DIR/preferred-root"
rm -f "$STEAMCMD_ARGS_LOG"
sw_download 431960 3810650535 anonymous >/dev/null
assert_cond "download: STEAMCMD_INSTALL_DIR wins" 'grep -Fq "+force_install_dir $STEAMCMD_INSTALL_DIR" "$STEAMCMD_ARGS_LOG"'
unset STEAMCMD_INSTALL_DIR STEAM_WORKSHOP_DIR
rm -f "$STEAMCMD_ARGS_LOG"
HOME="$TEST_DIR/fakehome" sw_download 431960 3810650535 anonymous >/dev/null
assert_cond "download: default is ~/Downloads/steamcmd" 'grep -Fq "+force_install_dir $TEST_DIR/fakehome/Downloads/steamcmd" "$STEAMCMD_ARGS_LOG" && [[ -d $TEST_DIR/fakehome/Downloads/steamcmd ]]'
export STEAMCMD_INSTALL_DIR="$TEST_DIR/isolated"

# ---- short_error ----
assert_cond "err: cached credentials" '[[ $(sw_short_error <<<"Loading Steam API...OK Cached credentials not found.") == "Cached credentials not found." ]]'
assert_cond "err: first ERROR line" '[[ $(sw_short_error <<<"foo ERROR (Invalid Password) bar") == "ERROR (Invalid Password) bar" ]]'
assert_cond "err: empty when nothing useful" '[[ -z $(sw_short_error <<<"nothing useful here") ]]'

exit $FAIL
