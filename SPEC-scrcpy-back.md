# Spec: scrcpy 左边缘右滑返回

## Objective

给 `rofi/scripts/scrcpy.sh` 增加“返回”手势：scrcpy 窗口聚焦时按一个键，
触发 `adb shell input swipe` 从屏幕左边缘向右滑动，触发 Android 全面屏返回手势。
用户：竖屏刷短视频 + 日常操作时，不想伸手碰手机，用键盘完成返回。

用户故事：
- scrcpy 窗口聚焦，按 Left → 手机执行一次返回（等价手指从左边缘向右滑）。
- 横屏时同样可用（坐标系跟随旋转）。
- 不影响现有 Up/Down 上下滑动。

## Tech Stack

- bash（与现有脚本一致），`adb shell wm size / dumpsys display / input swipe`
- 测试：现有 `tests/scrcpy-swipe_test.sh` mock adb 模式

## Commands

```bash
bash tests/scrcpy-swipe_test.sh
bash tests/scrcpy-lan-scan_test.sh
bash -n rofi/scripts/scrcpy.sh
```

## Project Structure

```
rofi/scripts/scrcpy.sh      → SCRCPY_KEYMAP / _swipe / _watch_scrcpy_keys（本次改动点）
tests/scrcpy-swipe_test.sh  → _swipe 横竖屏回归（需追加 back 用例）
AGENTS.md                   → scrcpy 行需同步（_swipe 支持方向变化）
```

## Code Style

沿用现有 `_swipe` 风格：复用 `wm size` + `_display_rotation` 的 w/h 交换，
新增方向只加一个 `case` 分支，不另起函数。示例：

```bash
case "$dir" in
    up) y1=$((h * 3 / 4)); y2=$((h / 4)) ;;
    down) y1=$((h / 4)); y2=$((h * 3 / 4)) ;;
    back) x1=$((w / 20)); x2=$((w * 2 / 5)) ;;  # y 取 h/2，示意值
esac
```

命名：方向名用 `back`，map 键用 X11 keysym（`xmodmap -pke` 可查）。

## Testing Strategy

- 扩展 `tests/scrcpy-swipe_test.sh` mock adb（与现有 R1–R15 同模式）：
  - 竖屏 back 坐标断言
  - 横屏 rotation=1/3 下 back 坐标（验证 w/h 交换）
  - 非法方向仍返回非 0（现有 `*) return 1` 保持）
- 不做真机测试；`_display_rotation` 逻辑复用，不新增单测。

## Boundaries

- Always: 改前读 `scrcpy.sh` + `scrcpy-swipe_test.sh` 全文；改后跑上面三条命令；
  同步更新 `AGENTS.md` 的 scrcpy `_swipe` 行。
- Ask first: 换默认触发键（Left 以外）、改滑动时长/距离、加右边缘左滑。
- Never: 改 `SCRCPY_FLAGS` / 连接配对逻辑；提交 secrets；直接 push `master`；
  在 `~/.dwm` 主工作区开发（本次用 `~/Workspace/Worktrees/dwm-feat-scrcpy-back` +
  分支 `feat/scrcpy-back`）。

## Success Criteria

- [ ] scrcpy 聚焦时按 Left 触发一次左边缘→右滑动返回
- [ ] 竖屏 / 横屏(1/3) 坐标正确且无越界（横屏交换 w/h）
- [ ] Up/Down 行为不变，现有 R1–R15 全过，新增 back 用例全过
- [ ] `bash -n` 通过

## Open Questions

1. 触发键是否用 `Left`？（备选：`BackSpace` / `Escape` / 自定义）
2. 起止点是否按 `x1=w/20（5%）, x2=w*2/5（40%）, y=h/2, 时长 200ms`？边缘 5% 在
   全面屏手势区内是否足够小，要不要更贴边（如 2%）？
3. 是否同时需要“右边缘左滑返回”（右手习惯）？本次默认不做。

## ASSUMPTIONS I'M MAKING

1. 只做左边缘→右，不做右边缘→左。
2. 触发键默认 `Left`，即 `SCRCPY_KEYMAP[Left]=back`。
3. 滑动参数默认 `x1=5%w, x2=40%w, y=50%h, 200ms`，与现有 up/down 同级。
4. 横屏复用 `_display_rotation` 的 1/3 交换逻辑，不区分 1 和 3。
