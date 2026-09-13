#!/usr/bin/env bash
# theme.sh 亮度渐变回归测试 (Task 1 单元 + Task 2 集成):
# 运行: bash tests/theme-brightness_test.sh
SCRIPT="$HOME/.dwm/tools/theme.sh"

fail=0
check() { # desc cond
    if eval "$2"; then
        echo "PASS: $1"
    else
        echo "FAIL: $1"
        fail=1
    fi
}

source "$SCRIPT"

# ---------- _brightness_curve（线性直通，milliscale） ----------
check "curve 0→0" '[ "$(_brightness_curve 0)" = "0" ]'
check "curve 500→500" '[ "$(_brightness_curve 500)" = "500" ]'
check "curve 1000→1000" '[ "$(_brightness_curve 1000)" = "1000" ]'

# ---------- _brightness_at（纯插值） ----------
# dark=50 light=80 dur=3600
check "at t=0 →旧端点" '[ "$(_brightness_at 50 80 0 3600)" = "50" ]'
check "at t=dur →新端点" '[ "$(_brightness_at 50 80 3600 3600)" = "80" ]'
check "at 中点≈65" '[ "$(_brightness_at 50 80 1800 3600)" = "65" ]'
check "at duration=0 →新端点" '[ "$(_brightness_at 50 80 0 0)" = "80" ]'
check "at 越界钳制上" '[ "$(_brightness_at 50 80 7200 3600)" = "80" ]'
check "at 越界钳制下" '[ "$(_brightness_at 50 80 -5 3600)" = "50" ]'
check "at 反向 dusk 80→50 中点≈65" '[ "$(_brightness_at 80 50 1800 3600)" = "65" ]'
check "at 反向 t=0 →80" '[ "$(_brightness_at 80 50 0 3600)" = "80" ]'
check "at 反向 t=dur →50" '[ "$(_brightness_at 80 50 3600 3600)" = "50" ]'

# ---------- 窗口计算 ----------
# rise=10000 dawn=3600
check "dawn after 窗口" '[ "$(_dawn_window 10000 3600 after)" = "10000 13600" ]'
check "dawn center 窗口" '[ "$(_dawn_window 10000 3600 center)" = "8200 11800" ]'
check "dawn 非法anchor回退after" '[ "$(_dawn_window 10000 3600 bogus)" = "10000 13600" ]'
check "dawn duration=0 退化为点" '[ "$(_dawn_window 10000 0 after)" = "10000 10000" ]'
check "dusk after 窗口" '[ "$(_dusk_window 20000 3600 after)" = "20000 23600" ]'
check "dusk center 窗口" '[ "$(_dusk_window 20000 3600 center)" = "18200 21800" ]'
check "dusk 非法anchor回退after" '[ "$(_dusk_window 20000 3600 bogus)" = "20000 23600" ]'

# ---------- _theme_at（二值，锚点无关） ----------
check "theme rise前=dark" '[ "$(_theme_at 9999 10000 20000)" = "dark" ]'
check "theme rise整点=light" '[ "$(_theme_at 10000 10000 20000)" = "light" ]'
check "theme 白天=light" '[ "$(_theme_at 15000 10000 20000)" = "light" ]'
check "theme set整点=dark" '[ "$(_theme_at 20000 10000 20000)" = "dark" ]'
check "theme 夜晚=dark" '[ "$(_theme_at 25000 10000 20000)" = "dark" ]'

# ---------- _monitor_brightness_at（after 默认） ----------
# rise=10000 set=20000 dawn=dusk=3600 dark=50 light=80
check "after: rise前=dark端点" '[ "$(_monitor_brightness_at 9999 10000 20000 3600 3600 after 50 80)" = "50" ]'
check "after: rise整点=旧端点" '[ "$(_monitor_brightness_at 10000 10000 20000 3600 3600 after 50 80)" = "50" ]'
check "after: dawn中点≈65" '[ "$(_monitor_brightness_at 11800 10000 20000 3600 3600 after 50 80)" = "65" ]'
check "after: dawn结束=light端点" '[ "$(_monitor_brightness_at 13600 10000 20000 3600 3600 after 50 80)" = "80" ]'
check "after: 白天=light端点" '[ "$(_monitor_brightness_at 15000 10000 20000 3600 3600 after 50 80)" = "80" ]'
check "after: set整点=旧端点80" '[ "$(_monitor_brightness_at 20000 10000 20000 3600 3600 after 50 80)" = "80" ]'
check "after: dusk中点≈65" '[ "$(_monitor_brightness_at 21800 10000 20000 3600 3600 after 50 80)" = "65" ]'
check "after: dusk结束=dark端点" '[ "$(_monitor_brightness_at 23600 10000 20000 3600 3600 after 50 80)" = "50" ]'
check "after: 深夜=dark端点" '[ "$(_monitor_brightness_at 25000 10000 20000 3600 3600 after 50 80)" = "50" ]'

# ---------- _monitor_brightness_at（center） ----------
check "center: 窗口起点=dark端点" '[ "$(_monitor_brightness_at 8200 10000 20000 3600 3600 center 50 80)" = "50" ]'
check "center: rise整点≈中点65" '[ "$(_monitor_brightness_at 10000 10000 20000 3600 3600 center 50 80)" = "65" ]'
check "center: 窗口终点=light端点" '[ "$(_monitor_brightness_at 11800 10000 20000 3600 3600 center 50 80)" = "80" ]'
check "center: dusk起点=light端点" '[ "$(_monitor_brightness_at 18200 10000 20000 3600 3600 center 50 80)" = "80" ]'
check "center: set整点≈中点65" '[ "$(_monitor_brightness_at 20000 10000 20000 3600 3600 center 50 80)" = "65" ]'
check "center: dusk终点=dark端点" '[ "$(_monitor_brightness_at 21800 10000 20000 3600 3600 center 50 80)" = "50" ]'
check "center: 非法anchor回退after" '[ "$(_monitor_brightness_at 10000 10000 20000 3600 3600 bogus 50 80)" = "50" ]'

# ---------- duration=0 回退二值 ----------
check "duration=0 after dawn内直接新端点" '[ "$(_monitor_brightness_at 10000 10000 20000 0 0 after 50 80)" = "80" ]'

# ---------- 集成：apply_transition_brightness ----------
T_TMP=$(mktemp -d)
THEME_CONF="$T_TMP/theme.json"
cat >"$THEME_CONF" <<'EOF'
{"light": {"brightness": {"eDP": 80, "HDMI-A-0": 90}},
 "dark": {"brightness": {"eDP": 50, "HDMI-A-0": 40}}}
EOF
T_BIN="$T_TMP/bin"
mkdir -p "$T_BIN"
cat >"$T_BIN/xrandr" <<'EOF'
#!/usr/bin/env bash
if [ "$1" = "--listactivemonitors" ]; then
    printf '2\n 0: +*eDP 1920x1080+0+0 eDP\n 1: +HDMI-A-0 1920x1080+1920+0 HDMI-A-0\n'
fi
EOF
chmod +x "$T_BIN/xrandr"
export PATH="$T_BIN:$PATH"
SET_LOG="$T_TMP/set.log"

# 阶段一：当前值全 0，强制写入
read_brightness() { printf '0'; }
set_brightness() { printf '%s %s\n' "$1" "$2" >>"$SET_LOG"; }

RISE=100000; SET=200000; DUR=3600

: >"$SET_LOG"
apply_transition_brightness "$RISE" "$RISE" "$SET" "$DUR" "$DUR" after
check "apply after rise整点写旧端点" \
    'grep -q "^eDP 50$" "$SET_LOG" && grep -q "^HDMI-A-0 40$" "$SET_LOG"'

: >"$SET_LOG"
apply_transition_brightness $((RISE + 1800)) "$RISE" "$SET" "$DUR" "$DUR" after
check "apply after dawn中点写65/65" \
    'grep -q "^eDP 65$" "$SET_LOG" && grep -q "^HDMI-A-0 65$" "$SET_LOG"'

: >"$SET_LOG"
apply_transition_brightness $((RISE + 3600)) "$RISE" "$SET" "$DUR" "$DUR" after
check "apply after dawn结束写新端点" \
    'grep -q "^eDP 80$" "$SET_LOG" && grep -q "^HDMI-A-0 90$" "$SET_LOG"'

: >"$SET_LOG"
apply_transition_brightness "$RISE" "$RISE" "$SET" "$DUR" "$DUR" center
check "apply center rise整点写中点" \
    'grep -q "^eDP 65$" "$SET_LOG" && grep -q "^HDMI-A-0 65$" "$SET_LOG"'

: >"$SET_LOG"
apply_transition_brightness "$SET" "$RISE" "$SET" "$DUR" "$DUR" after
check "apply after set整点写旧端点80/90" \
    'grep -q "^eDP 80$" "$SET_LOG" && grep -q "^HDMI-A-0 90$" "$SET_LOG"'

# 阶段二：delta<1 跳过（eDP 当前值已是目标 65，只应写 HDMI-A-0）
read_brightness() { case "$1" in eDP) printf '65' ;; *) printf '0' ;; esac; }
: >"$SET_LOG"
apply_transition_brightness $((RISE + 1800)) "$RISE" "$SET" "$DUR" "$DUR" after
check "apply delta<1 跳过eDP只写HDMI" \
    '! grep -q "^eDP " "$SET_LOG" && grep -q "^HDMI-A-0 65$" "$SET_LOG"'

# 阶段三：读不到当前值时直接写
read_brightness() { printf ''; }
: >"$SET_LOG"
apply_transition_brightness "$RISE" "$RISE" "$SET" "$DUR" "$DUR" after
check "apply 读不到当前值直接写" \
    'grep -q "^eDP 50$" "$SET_LOG" && grep -q "^HDMI-A-0 40$" "$SET_LOG"'

# 阶段四：窗口外不写（手动/OSD 的不动）
read_brightness() { printf '0'; }
: >"$SET_LOG"
apply_transition_brightness 150000 "$RISE" "$SET" "$DUR" "$DUR" after
apply_transition_brightness 250000 "$RISE" "$SET" "$DUR" "$DUR" after
apply_transition_brightness 150000 "$RISE" "$SET" "$DUR" "$DUR" center
apply_transition_brightness 250000 "$RISE" "$SET" "$DUR" "$DUR" center
check "apply 窗口外零写入" '[ ! -s "$SET_LOG" ]'

# 阶段五：duration=0 的一侧按二值对齐端点
: >"$SET_LOG"
apply_transition_brightness 150000 "$RISE" "$SET" 0 0 after
check "apply duration=0 白天写light端点" \
    'grep -q "^eDP 80$" "$SET_LOG" && grep -q "^HDMI-A-0 90$" "$SET_LOG"'
: >"$SET_LOG"
apply_transition_brightness 250000 "$RISE" "$SET" 0 0 after
check "apply duration=0 夜晚写dark端点" \
    'grep -q "^eDP 50$" "$SET_LOG" && grep -q "^HDMI-A-0 40$" "$SET_LOG"'
: >"$SET_LOG"
apply_transition_brightness 150000 "$RISE" "$SET" 0 "$DUR" after
check "apply 仅dawn=0 白天写端点" \
    'grep -q "^eDP 80$" "$SET_LOG" && grep -q "^HDMI-A-0 90$" "$SET_LOG"'
: >"$SET_LOG"
apply_transition_brightness 250000 "$RISE" "$SET" 0 "$DUR" after
check "apply 仅dawn=0 夜晚窗口外不写" '[ ! -s "$SET_LOG" ]'
rm -rf "$T_TMP"

# ---------- 配置读取 fallback ----------
C_TMP=$(mktemp -d)
THEME_CONF="$C_TMP/theme.json"
echo '{}' >"$THEME_CONF"
check "配置缺失 dawn→60" '[ "$(_transition_minutes dawn_minutes)" = "60" ]'
check "配置缺失 anchor→after" '[ "$(_transition_anchor)" = "after" ]'
cat >"$THEME_CONF" <<'EOF'
{"auto": {"dawn_minutes": "abc", "dusk_minutes": -5, "transition_anchor": "bogus"}}
EOF
check "配置非法 dawn→60" '[ "$(_transition_minutes dawn_minutes)" = "60" ]'
check "配置非法 dusk→60" '[ "$(_transition_minutes dusk_minutes)" = "60" ]'
check "配置非法 anchor→after" '[ "$(_transition_anchor)" = "after" ]'
cat >"$THEME_CONF" <<'EOF'
{"auto": {"dawn_minutes": 0, "dusk_minutes": 30, "transition_anchor": "center"}}
EOF
check "配置 dawn=0 保留0（关闭渐变）" '[ "$(_transition_minutes dawn_minutes)" = "0" ]'
check "配置 dusk=30" '[ "$(_transition_minutes dusk_minutes)" = "30" ]'
check "配置 anchor=center" '[ "$(_transition_anchor)" = "center" ]'
rm -rf "$C_TMP"

# ---------- 单实例守卫 (跨进程争锁) ----------
F_TMP=$(mktemp -d)
F_LOCK="$F_TMP/daemon.lock"
check "singleton 首拿成功" '_auto_lock "$F_LOCK"'
exec 9>&-
(_auto_lock "$F_LOCK" || exit 1; sleep 3) &
HOLDER=$!
sleep 0.3
check "singleton 重入失败" '! _auto_lock "$F_LOCK"'
exec 9>&- 2>/dev/null
kill "$HOLDER" 2>/dev/null
wait "$HOLDER" 2>/dev/null
check "singleton 释放后可拿" '_auto_lock "$F_LOCK"'
exec 9>&-
rm -rf "$F_TMP"

# ---------- 手动切换不走插值 ----------
# _do_theme_change 无 nobright → 调 set_monitor_brightness (端点)；
# 有 nobright (daemon) → 不调，亮度由 apply_transition_brightness 负责
set_dwm_theme() { :; }; set_rofi_theme() { :; }; set_kitty_theme() { :; }
set_qt_theme() { :; }; set_gtk_theme() { :; }; set_fcitx5_theme() { :; }; set_dunst_theme() { :; }
xrdb() { :; }
M_TMP=$(mktemp -d)
SET_LOG="$M_TMP/set.log"
set_monitor_brightness() { printf 'endpoint %s\n' "$1" >>"$SET_LOG"; }
: >"$SET_LOG"
_do_theme_change light
check "手动切换走端点亮度" 'grep -q "^endpoint light$" "$SET_LOG"'
: >"$SET_LOG"
_do_theme_change light nobright
check "daemon 翻转不设端点亮度" '! grep -q "^endpoint " "$SET_LOG"'
rm -rf "$M_TMP"

exit $fail
