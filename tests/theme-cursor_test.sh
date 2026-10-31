#!/usr/bin/env bash
# theme.sh cursor 按 mode 覆盖回归测试 (get_cursor_config + set_dwm_theme/set_gtk_theme):
# 运行: bash tests/theme-cursor_test.sh
SCRIPT="$(dirname "$(dirname "$(readlink -f "$0")")")/tools/theme.sh"

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
mkdir -p "$HOME/.config/dwm" "$HOME/.local/state/dwm"
T_BIN="$T_HOME/bin"
mkdir -p "$T_BIN"
GSETTINGS_LOG="$T_HOME/gsettings.log"
printf '#!/usr/bin/env bash\necho "$@" >>"%s"\nexit 0\n' "$GSETTINGS_LOG" >"$T_BIN/gsettings"
chmod +x "$T_BIN/gsettings"
printf '#!/usr/bin/env bash\nexit 0\n' >"$T_BIN/pgrep"
chmod +x "$T_BIN/pgrep"
printf '#!/usr/bin/env bash\nexit 0\n' >"$T_BIN/pkill"
chmod +x "$T_BIN/pkill"
export PATH="$T_BIN:$PATH"
# grep/sed/jq/xrdb 用系统真实命令；pgrep/pkill/gsettings 已 mock

source "$SCRIPT"
system-notify() { :; } # 去 dunst 依赖
tool-notify() { :; }

write_conf() { printf '%s' "$1" >"$HOME/.config/dwm/theme.json"; }
reset_out() {
    rm -f "$HOME/.Xresources" "$HOME/.xsettingsd"
    rm -f "$HOME/.gtkrc-2.0" "$HOME/.config/gtk-3.0/settings.ini" "$HOME/.config/gtk-4.0/settings.ini"
    rm -f "$HOME/.local/state/dwm/current-theme" "$GSETTINGS_LOG"
    touch "$HOME/.Xresources"
}

# ---------- 场景 1: 无 mode cursor → 全局值 (旧行为) ----------
write_conf '{"cursor":{"theme":"G-Theme","size":28},"light":{"gtk":"T","icon":"I"},"dark":{"gtk":"T","icon":"I"}}'
check "s1 light theme 回退全局" '[ "$(get_cursor_config light theme)" = "G-Theme" ]'
check "s1 light size 回退全局" '[ "$(get_cursor_config light size)" = "28" ]'
check "s1 dark theme 回退全局" '[ "$(get_cursor_config dark theme)" = "G-Theme" ]'
reset_out
set_dwm_theme light
check "s1 Xresources theme=全局" 'grep -qx "Xcursor.theme: G-Theme" "$HOME/.Xresources"'
check "s1 Xresources size=全局" 'grep -qx "Xcursor.size: 28" "$HOME/.Xresources"'
set_gtk_theme light
check "s1 gtk3 theme=全局" 'grep -qx "gtk-cursor-theme-name=G-Theme" "$HOME/.config/gtk-3.0/settings.ini"'
check "s1 xsettingsd theme=全局" 'grep -qx "Gtk/CursorThemeName \"G-Theme\"" "$HOME/.xsettingsd"'
check "s1 gsettings theme=全局" 'grep -qx "set org.gnome.desktop.interface cursor-theme G-Theme" "$GSETTINGS_LOG"'

# ---------- 场景 2: mode 只配 theme → theme 取 mode，size 取全局 ----------
write_conf '{"cursor":{"theme":"G-Theme","size":28},"light":{"gtk":"T","icon":"I","cursor":{"theme":"L-Theme"}},"dark":{"gtk":"T","icon":"I"}}'
check "s2 light theme 取 mode" '[ "$(get_cursor_config light theme)" = "L-Theme" ]'
check "s2 light size 回退全局" '[ "$(get_cursor_config light size)" = "28" ]'
reset_out
set_dwm_theme light
check "s2 Xresources theme=mode" 'grep -qx "Xcursor.theme: L-Theme" "$HOME/.Xresources"'
check "s2 Xresources size=全局" 'grep -qx "Xcursor.size: 28" "$HOME/.Xresources"'
set_gtk_theme light
check "s2 gtk3 theme=mode" 'grep -qx "gtk-cursor-theme-name=L-Theme" "$HOME/.config/gtk-3.0/settings.ini"'
check "s2 gtk3 size=全局" 'grep -qx "gtk-cursor-theme-size=28" "$HOME/.config/gtk-3.0/settings.ini"'
check "s2 gsettings theme=mode" 'grep -qx "set org.gnome.desktop.interface cursor-theme L-Theme" "$GSETTINGS_LOG"'
check "s2 gsettings size=全局" 'grep -qx "set org.gnome.desktop.interface cursor-size 28" "$GSETTINGS_LOG"'

# ---------- 场景 3: mode 只配 size → 反之 ----------
write_conf '{"cursor":{"theme":"G-Theme","size":28},"light":{"gtk":"T","icon":"I"},"dark":{"gtk":"T","icon":"I","cursor":{"size":48}}}'
check "s3 dark theme 回退全局" '[ "$(get_cursor_config dark theme)" = "G-Theme" ]'
check "s3 dark size 取 mode" '[ "$(get_cursor_config dark size)" = "48" ]'
reset_out
set_dwm_theme dark
check "s3 Xresources theme=全局" 'grep -qx "Xcursor.theme: G-Theme" "$HOME/.Xresources"'
check "s3 Xresources size=mode" 'grep -qx "Xcursor.size: 48" "$HOME/.Xresources"'
set_gtk_theme dark
check "s3 xsettingsd size=mode" 'grep -qx "Gtk/CursorThemeSize 48" "$HOME/.xsettingsd"'

# ---------- 场景 4: mode 全配 → 全取 mode ----------
write_conf '{"cursor":{"theme":"G-Theme","size":28},"light":{"gtk":"T","icon":"I","cursor":{"theme":"L-Theme","size":20}},"dark":{"gtk":"T","icon":"I"}}'
check "s4 light theme 取 mode" '[ "$(get_cursor_config light theme)" = "L-Theme" ]'
check "s4 light size 取 mode" '[ "$(get_cursor_config light size)" = "20" ]'
reset_out
set_dwm_theme light
check "s4 Xresources theme=mode" 'grep -qx "Xcursor.theme: L-Theme" "$HOME/.Xresources"'
check "s4 Xresources size=mode" 'grep -qx "Xcursor.size: 20" "$HOME/.Xresources"'

# ---------- 场景 5: 全局+mode 全缺 → 不写光标行 ----------
write_conf '{"light":{"gtk":"T","icon":"I"},"dark":{"gtk":"T","icon":"I"}}'
check "s5 theme 为空" '[ -z "$(get_cursor_config light theme)" ]'
check "s5 size 为空" '[ -z "$(get_cursor_config light size)" ]'
reset_out
set_dwm_theme light
check "s5 Xresources 无光标行" '! grep -q "Xcursor" "$HOME/.Xresources"'
set_gtk_theme light
check "s5 gtk3 无光标行" '! grep -q "cursor" "$HOME/.config/gtk-3.0/settings.ini"'
check "s5 xsettingsd 无光标行" '! grep -q "Cursor" "$HOME/.xsettingsd"'

rm -rf "$T_HOME"
export HOME="$REAL_HOME"
[ "$fail" -eq 0 ] && echo "ALL PASS" || echo "SOME FAIL"
exit "$fail"
