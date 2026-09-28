#!/usr/bin/env bash
# theme.sh Qt 切换回归测试 (set_qt_theme + _ensure_ini_key):
# 运行: bash tests/theme-qt_test.sh
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

# ---------- 隔离 HOME (THEME_CONF 在 source 时绑定, 必须先 export) ----------
REAL_HOME="$HOME"
T_HOME=$(mktemp -d)
export HOME="$T_HOME"
mkdir -p "$HOME/.config/dwm" "$HOME/.config/qt6ct" "$HOME/.config/Kvantum"
cp "$REAL_HOME/.config/dwm/theme.json" "$HOME/.config/dwm/theme.json"
T_BIN="$T_HOME/bin"
mkdir -p "$T_BIN"
KVSET_LOG="$T_HOME/kvset.log"
printf '#!/usr/bin/env bash\necho "$@" >>"%s"\n' "$KVSET_LOG" >"$T_BIN/kvantummanager"
chmod +x "$T_BIN/kvantummanager"
export PATH="$T_BIN:$PATH"

source "$SCRIPT"
system-notify() { :; } # 去 dunst 依赖 (只断言文件落盘, 不断言通知)

# ---------- _ensure_ini_key（单元） ----------
INI="$T_HOME/t.ini"
printf '[Appearance]\nstyle=fusion\n[Other]\nx=1\n' >"$INI"
_ensure_ini_key "$INI" Appearance style kvantum
check "ini 存在键则替换" 'grep -qx "style=kvantum" "$INI"'
_ensure_ini_key "$INI" Appearance icon_theme Tela-light
check "ini 缺键插到节后" '[ "$(sed -n "/^\\[Appearance\\]/,/^\\[/p" "$INI" | grep -c "^icon_theme=Tela-light$")" = "1" ]'
printf 'orphan=1\n' >"$INI"
_ensure_ini_key "$INI" Appearance style kvantum
check "ini 缺节则尾部补节" 'grep -qx "\[Appearance\]" "$INI" && grep -qx "style=kvantum" "$INI"'

# ---------- set_qt_theme light（集成） ----------
printf '# export QT_QPA_PLATFORMTHEME=gtk3\nexport QT_QPA_PLATFORMTHEME=gtk3\n' >"$HOME/.xprofile"
printf '[Appearance]\nstyle=fusion\nicon_theme=Tela-manjaro-dark\n' >"$HOME/.config/qt6ct/qt6ct.conf"
printf '[General]\ntheme=Orchis-solidDark\n' >"$HOME/.config/Kvantum/kvantum.kvconfig"
set_qt_theme light
check "xprofile gtk3→qt6ct (注释保留)" 'grep -qx "export QT_QPA_PLATFORMTHEME=qt6ct" "$HOME/.xprofile" && grep -qx "# export QT_QPA_PLATFORMTHEME=gtk3" "$HOME/.xprofile"'
check "qt6ct style=kvantum" 'grep -qx "style=kvantum" "$HOME/.config/qt6ct/qt6ct.conf"'
check "qt6ct icon 跟随 light" 'grep -qx "icon_theme=Tela-manjaro-light" "$HOME/.config/qt6ct/qt6ct.conf"'
check "qt5ct 自动创建" 'grep -qx "style=kvantum" "$HOME/.config/qt5ct/qt5ct.conf" && grep -qx "icon_theme=Tela-manjaro-light" "$HOME/.config/qt5ct/qt5ct.conf"'
check "kvantum 切 Orchis-solid" 'grep -qx "theme=Orchis-solid" "$HOME/.config/Kvantum/kvantum.kvconfig"'
check "kvantummanager --set 被调用" 'grep -qx -- "--set Orchis-solid" "$KVSET_LOG"'

# ---------- set_qt_theme dark ----------
set_qt_theme dark
check "kvantum 切 Orchis-solidDark" 'grep -qx "theme=Orchis-solidDark" "$HOME/.config/Kvantum/kvantum.kvconfig"'
check "qt6ct icon 跟随 dark" 'grep -qx "icon_theme=Tela-manjaro-dark" "$HOME/.config/qt6ct/qt6ct.conf"'

# ---------- 幂等 ----------
cp "$HOME/.xprofile" "$T_HOME/xp.before"
cp "$HOME/.config/qt6ct/qt6ct.conf" "$T_HOME/qt6ct.before"
set_qt_theme dark
check "重复执行无变化" 'diff -q "$T_HOME/xp.before" "$HOME/.xprofile" >/dev/null && diff -q "$T_HOME/qt6ct.before" "$HOME/.config/qt6ct/qt6ct.conf" >/dev/null'
check "键无重复行" '[ "$(grep -c "^style=" "$HOME/.config/qt6ct/qt6ct.conf")" = "1" ] && [ "$(grep -c "^icon_theme=" "$HOME/.config/qt6ct/qt6ct.conf")" = "1" ]'

# ---------- 缺 qt 键直接返回（无兜底） ----------
jq 'del(.light.qt, .dark.qt)' "$HOME/.config/dwm/theme.json" >"$T_HOME/noqt.json"
cp "$T_HOME/noqt.json" "$HOME/.config/dwm/theme.json"
printf 'export QT_QPA_PLATFORMTHEME=gtk3\n' >"$HOME/.xprofile"
printf '[Appearance]\nstyle=fusion\n' >"$HOME/.config/qt6ct/qt6ct.conf"
printf '[General]\ntheme=SENTINEL\n' >"$HOME/.config/Kvantum/kvantum.kvconfig"
: >"$KVSET_LOG"
set_qt_theme light
check "缺键不碰 xprofile" 'grep -qx "export QT_QPA_PLATFORMTHEME=gtk3" "$HOME/.xprofile"'
check "缺键不碰 qt6ct" 'grep -qx "style=fusion" "$HOME/.config/qt6ct/qt6ct.conf"'
check "缺键不碰 kvconfig" 'grep -qx "theme=SENTINEL" "$HOME/.config/Kvantum/kvantum.kvconfig"'
check "缺键不调 kvantummanager" '[ ! -s "$KVSET_LOG" ]'

rm -rf "$T_HOME"

exit $fail
