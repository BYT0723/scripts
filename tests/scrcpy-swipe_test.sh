#!/usr/bin/env bash
# rofi/scripts/scrcpy.sh _swipe 横竖屏回归测试:
#   R1 竖屏 rotation=0 → 按自然尺寸滑动
#   R2 横屏 rotation=1 → w/h 交换后滑动 (旧代码发越界坐标被系统忽略)
#   R3 横屏 rotation=3 → 同 R2
#   R4 rotation=2 (倒竖屏) → 不交换
#   R5 dumpsys 为空/不可解析 → 回退 0 (竖屏行为, 兼容旧 mock)
#   R6 Override size 优先 + 横屏交换
#
# 背景: `wm size` 返回自然方向尺寸 (不随旋转变化), `input swipe`
# 坐标系随旋转变化。横屏时不交换 w/h 会发出 y 越界坐标
# (如 1080x2400 机器横屏发 y1=1800, 逻辑高度仅 1080) → 上划/下滑均失效。
# _swipe 每次调用都重查 wm size, 触发点本身是动态的, 病根在未处理旋转。
#
# 运行: bash tests/scrcpy-swipe_test.sh

REPO="$(cd "$(dirname "$0")/.." && pwd)"
SCRCPY_SH="$REPO/rofi/scripts/scrcpy.sh"
TEST_DIR=$(mktemp -d)
export TEST_DIR
export HOME="$TEST_DIR/home"
mkdir -p "$HOME/.config/dwm" "$HOME/.local/state/dwm"

BIN="$TEST_DIR/bin"
mkdir -p "$BIN"

cat >"$BIN/adb" <<'EOF'
#!/usr/bin/env bash
if [ "$1" = "-s" ]; then shift 2; fi
if [ "$1" = "shell" ]; then
    shift
    if [ "$1" = "wm" ]; then
        if [ -n "$ADB_OVERRIDE_SIZE" ]; then
            echo "Physical size: 1080x2400"
            echo "Override size: $ADB_OVERRIDE_SIZE"
        else
            echo "Physical size: 1080x2400"
        fi
        exit 0
    fi
    if [ "$1" = "dumpsys" ]; then
        [ -n "$ADB_DUMPSYS_EMPTY" ] && exit 0
        if [ -n "$ADB_DUMPSYS_RAW" ]; then
            printf '%s\n' "$ADB_DUMPSYS_RAW"
        else
            echo "    mCurrentRotation=${ADB_ROTATION:-0}"
        fi
        exit 0
    fi
    if [ "$1" = "input" ]; then
        echo "swipe $*" >>"$MOCK_LOG"
        exit 0
    fi
    if [ "$1" = "settings" ] || [ "$1" = "getprop" ]; then
        exit 0
    fi
fi
exit 0
EOF

chmod +x "$BIN"/*
export PATH="$BIN:$PATH"
export MOCK_LOG="$TEST_DIR/log"
: >"$MOCK_LOG"

module_parse() { :; }
module_loop() { return 1; }
export SCRCPY_NO_DISPATCH=1
# shellcheck disable=SC1090
source "$SCRCPY_SH" 2>/dev/null

fail=0
check() { # desc cond
    if eval "$2"; then
        echo "PASS: $1"
    else
        echo "FAIL: $1"
        fail=1
    fi
}
reset_state() {
    : >"$MOCK_LOG"
    unset ADB_ROTATION ADB_DUMPSYS_EMPTY ADB_DUMPSYS_RAW ADB_OVERRIDE_SIZE
}
last_swipe() { tail -n1 "$MOCK_LOG"; }

# ---- R1: 竖屏 ----
reset_state
export ADB_ROTATION=0
_swipe "emulator" up
check "R1 竖屏 up 按自然尺寸 (540 1800 540 600)" "[ \"\$(last_swipe)\" = 'swipe input swipe 540 1800 540 600 200' ]"

# ---- R2: 横屏 rotation=1 ----
reset_state
export ADB_ROTATION=1
_swipe "emulator" up
check "R2 横屏(1) up 交换 w/h (1200 810 1200 270)" "[ \"\$(last_swipe)\" = 'swipe input swipe 1200 810 1200 270 200' ]"
_swipe "emulator" down
check "R3 横屏(1) down 反向 (1200 270 1200 810)" "[ \"\$(last_swipe)\" = 'swipe input swipe 1200 270 1200 810 200' ]"

# ---- R3: 横屏 rotation=3 ----
reset_state
export ADB_ROTATION=3
_swipe "emulator" up
check "R4 横屏(3) up 同横屏(1)" "[ \"\$(last_swipe)\" = 'swipe input swipe 1200 810 1200 270 200' ]"

# ---- R4: rotation=2 不交换 ----
reset_state
export ADB_ROTATION=2
_swipe "emulator" up
check "R5 倒竖屏(2) 不交换" "[ \"\$(last_swipe)\" = 'swipe input swipe 540 1800 540 600 200' ]"

# ---- R5: dumpsys 失败回退 ----
reset_state
export ADB_DUMPSYS_EMPTY=1
_swipe "emulator" up
check "R6 dumpsys 为空回退竖屏坐标" "[ \"\$(last_swipe)\" = 'swipe input swipe 540 1800 540 600 200' ]"
check "R7 _display_rotation 空输出回 0" "[ \"\$(_display_rotation emulator)\" = '0' ]"

reset_state
export ADB_DUMPSYS_RAW="no rotation info here"
_swipe "emulator" up
check "R8 dumpsys 脏输出回退竖屏坐标" "[ \"\$(last_swipe)\" = 'swipe input swipe 540 1800 540 600 200' ]"

# ---- R6: Override + 横屏 ----
reset_state
export ADB_OVERRIDE_SIZE="1440x2560" ADB_ROTATION=1
_swipe "emulator" up
check "R9 Override 优先且横屏交换 (1280 1080 1280 360)" "[ \"\$(last_swipe)\" = 'swipe input swipe 1280 1080 1280 360 200' ]"

# ---- R7: _display_rotation 单测 ----
reset_state
export ADB_ROTATION=1
check "R10 _display_rotation 横屏回 1" "[ \"\$(_display_rotation emulator)\" = '1' ]"
export ADB_ROTATION=3
check "R11 _display_rotation 回 3" "[ \"\$(_display_rotation emulator)\" = '3' ]"

# ---- R8: 真机格式 (HyperOS: 空格形式 rotation + displayShape 静态段陷阱) ----
# 背景: 某机 dumpsys display 里 `displayShape{... rotation=0 ...}` 等静态段恒为 0,
# 当前值只在 `mOverrideDisplayInfo ... displayId 0` 行 (`rotation 1` / `, app W x H,`);
# 第一版 grep `rotation=[0-3]` 误命中静态段, 横屏恒判 0 (真机复现)。
LANDSCAPE_RAW='DisplayDeviceInfo{"xxx": 1200 x 2670, cutoutPathParserInfo={CutoutPathParserInfo{displayWidth=1200 displayHeight=2670 rotation={0}}}, touch INTERNAL, rotation 0, displayShape DisplayShape{ displayWidth=1200 displayHeight=2670 rotation=0 }}
    mCurrentOrientation=1
    mBaseDisplayInfo=DisplayInfo{"xxx", displayId 0, real 1200 x 2670, rotation 0, app 1200 x 2670}
    mOverrideDisplayInfo=DisplayInfo{"xxx", displayId 0, real 2670 x 1200, rotation 1, app 2670 x 1200, density 520}'
reset_state
export ADB_DUMPSYS_RAW="$LANDSCAPE_RAW"
check "R12 真机横屏格式判 1 (不受静态 rotation=0 干扰)" "[ \"\$(_display_rotation emulator)\" = '1' ]"
_swipe "emulator" up
check "R13 真机横屏 swipe 交换 (1200 810 1200 270)" "[ \"\$(last_swipe)\" = 'swipe input swipe 1200 810 1200 270 200' ]"

PORTRAIT_RAW='DisplayDeviceInfo{"xxx": 1200 x 2670, displayShape DisplayShape{ displayWidth=1200 displayHeight=2670 rotation=0 }}
    mCurrentOrientation=0
    mBaseDisplayInfo=DisplayInfo{"xxx", displayId 0, real 1200 x 2670, rotation 0, app 1200 x 2670}
    mOverrideDisplayInfo=DisplayInfo{"xxx", displayId 0, real 1200 x 2670, rotation 0, app 1200 x 2670, density 520}'
reset_state
export ADB_DUMPSYS_RAW="$PORTRAIT_RAW"
check "R14 真机竖屏格式判 0" "[ \"\$(_display_rotation emulator)\" = '0' ]"

ROT_ONLY_RAW='    mOverrideDisplayInfo=DisplayInfo{"xxx", displayId 0, real 2670 x 1200, rotation 3, density 520}
    mOverrideDisplayInfo=DisplayInfo{"scrcpy", displayId 25, real 1600 x 718, rotation 0, density 1}'
reset_state
export ADB_DUMPSYS_RAW="$ROT_ONLY_RAW"
check "R15 无 app 段时用 override rotation (3, 且不取虚拟屏 displayId 25)" "[ \"\$(_display_rotation emulator)\" = '3' ]"

# ---- B1-B4: 左边缘右滑返回 ----
reset_state
export ADB_ROTATION=0
_swipe "emulator" back
check "B1 竖屏 back 左边缘右滑 (54 1200 432 1200)" "[ \"\$(last_swipe)\" = 'swipe input swipe 54 1200 432 1200 200' ]"

reset_state
export ADB_ROTATION=1
_swipe "emulator" back
check "B2 横屏(1) back 交换 w/h (120 540 960 540)" "[ \"\$(last_swipe)\" = 'swipe input swipe 120 540 960 540 200' ]"

reset_state
export ADB_ROTATION=3
_swipe "emulator" back
check "B3 横屏(3) back 同横屏(1)" "[ \"\$(last_swipe)\" = 'swipe input swipe 120 540 960 540 200' ]"

reset_state
export ADB_OVERRIDE_SIZE="1440x2560" ADB_ROTATION=1
_swipe "emulator" back
check "B4 Override+横屏 back (128 720 1024 720)" "[ \"\$(last_swipe)\" = 'swipe input swipe 128 720 1024 720 200' ]"

rm -rf "$TEST_DIR"
exit $fail
