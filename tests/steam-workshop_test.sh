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
case "${STEAMCMD_MODE:-success}" in
success) echo "Success. Downloaded item 3810650535 to \"$STEAMCMD_OUTDIR/3810650535\" (100 bytes)" ;;
auth) echo "ERROR! Download item 3810650535 failed (Access Denied)."; echo "ERROR: Invalid Password" ;;
error) echo "ERROR! Download item 3810650535 failed (Connection Timeout)." ;;
esac
EOF
chmod +x "$FAKE_BIN/steamcmd"
cat >"$FAKE_BIN/curl" <<'EOF'
#!/usr/bin/env bash
: >>"$CURL_CALLED"
case "$*" in
*GetPublishedFileDetails*) cat "$CURL_API_FIXTURE" ;;
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
export CURL_FIXTURE="$TEST_DIR/page.html" CURL_API_FIXTURE="$TEST_DIR/api.json"
assert_cond "gated: login-gate detected" 'sw_page_gated "$(cat "$TEST_DIR/page-gated.html")"'
assert_cond "gated: normal page not gated" '! sw_page_gated "$(cat "$TEST_DIR/page.html")"'
export CURL_API_FIXTURE="$TEST_DIR/api.json" CURL_APP_FIXTURE="$TEST_DIR/app.json"
assert_cond "api: appid|appname|title" '[[ $(sw_api_info "3812349759") == "431960|Wallpaper Engine|Gated Item" ]]'
export CURL_API_FIXTURE="$TEST_DIR/api-deleted.json"
assert_cond "api: deleted item fails" '! sw_api_info "999" >/dev/null'
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

# ---- download ----
export STEAM_LOGINUSERS="$TEST_DIR/loginusers.vdf"
export STEAMCMD_OUTDIR="$TEST_DIR/real"
mkdir -p "$STEAMCMD_OUTDIR/3810650535"
export STEAMCMD_MODE=success
_out=$(sw_download 431960 3810650535 anonymous)
assert_cond "download: success rc=0" '[[ $? -eq 0 ]]'
assert_cond "download: stdout is real path" '[[ $_out == "$STEAMCMD_OUTDIR/3810650535" ]]'
assert_cond "download: leaves no dir farm behind" '[[ ! -d $TEST_DIR/dl ]]'
export STEAMCMD_MODE=auth
assert_cond "download: auth failure rc=2" 'sw_download 431960 3810650535 someuser >/dev/null 2>&1; [[ $? -eq 2 ]]'
export STEAMCMD_MODE=error
assert_cond "download: other failure rc=1" 'sw_download 431960 3810650535 anonymous >/dev/null 2>&1; [[ $? -eq 1 ]]'

exit $FAIL
