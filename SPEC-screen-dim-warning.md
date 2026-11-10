# Spec: 锁屏前压暗提示（dim warning）

## Objective

当前链路在空闲 600 秒时直接拉起 i3lock，没有任何预告；读文档（无输入、无音频）时
体感是“突然要输密码”。本特性在锁屏**之前**用 gamma 把屏幕压暗一次作为提示：

- 空闲 **570 秒**：压暗（不锁屏，鼠标/键盘一动手就恢复）
- 空闲 **600 秒**：仍按原计划锁屏
- 整体策略不变：锁屏时刻依旧是“最后一次输入 + 10 分钟”，不延后、不取消

顺带修一个前置缺陷：`xset s` 目前只在 `xss-lock` 未运行时写入，导致改超时/改
notifier 后重启 daemon 也不生效。改成“每次启动都重新武装 + 配置变化时重启
xss-lock”，为后续 `rofi/scripts/module.sh` 的时长控制铺路。

非目标：

- 不做 rofi 时长控制（后续单独 spec）
- 不改硬件亮度（`brightnessctl` / `ddcutil`），只用 `xrandr --brightness`
- 不加通知音/弹窗（只用视觉压暗）
- 不改音频抑制逻辑（`_inhibit_poke` 保持不变）

## 行为时间线

| 空闲秒 | X 屏保事件 | xss-lock 动作 | 屏幕状态 |
| --- | --- | --- | --- |
| 570 | `ScreenSaverOn` | 启动 notifier（`screen.sh notifier`） | gamma 0.4（压暗） |
| 600 | `ScreenSaverCycle` | 先 SIGTERM notifier，再启动 locker | gamma 1.0 → i3lock |
| 任意输入 | `ScreenSaverOff` | SIGHUP notifier | gamma 1.0，计时归零 |

依据（已核对源码，非猜测）：

- Xorg `dixSaveScreens()`：第二次 `SCREEN_SAVER_ON` 时若 `what == screenIsSaved`
  会改发 `SCREEN_SAVER_CYCLE`；`os/WaitFor.c` 的定时器在 `ScreenSaverInterval > 0`
  时按该间隔再次触发。
- xss-lock 0.4.0：`ScreenSaverOn` 且 `cycle > 0` 且配置了 notifier → 启动 notifier；
  `ScreenSaverCycle` → 启动 locker；`ScreenSaverOff` → SIGHUP notifier；
  `start_child(&locker)` 会把 notifier 以 SIGTERM 杀掉（`locker.kill_first`）。

因此 `xset s 570 30` = 570 秒压暗、600 秒上锁，**锁屏时间不变**。

## Tech Stack

纯 bash，无新依赖。用到 `xrandr`（仓库现有依赖，`utils/monitor.sh` 已使用）、
`xss-lock 0.4.0` 的 `-n/--notifier`。

## Commands

```bash
bash -n tools/screen.sh tools/lock.sh
bash tests/screen-lock_test.sh
bash tests/screen-dim_test.sh
bash tests/lock-mute_test.sh
```

## Project Structure

```
tools/screen.sh          → daemon 武装链 + `notifier` 子命令（压暗/驻留/恢复）
tools/lock.sh            → _lock_before 增加 gamma 兜底恢复
tests/screen-dim_test.sh → 新增: notifier 子命令测试（执行态 + 降级）
tests/screen-lock_test.sh→ 更新断言 + 重新武装 R 组 / 边界 W 组
AGENTS.md                → 依赖图/函数表/已知问题同步
```

## Code Style

沿用仓库现有风格：`_` 前缀内部函数、中文注释解释“为什么”、常量放在文件顶部。

```bash
# 预告时段: 压暗后 xss-lock 会在 cycle 到点时启动 locker,
# 所以 xset s 的 timeout 是 (锁屏时刻 - 预告), cycle 是预告秒数。
warn_seconds=30
dim_gamma=0.4
```

## 实现要点

### 1. `screen.sh notifier`（子命令，非独立文件）

- 取活动输出：扫 `xrandr --query` 的 ` connected ` 行，逐字段找几何
  （`primary` 输出几何在 `$4`，普通在 `$3`）：
  `awk '/ connected / { for (i=2;i<=NF;i++) if ($i ~ /^[0-9]+x[0-9]+\+/) {print $1; break} }'`
- 压暗：逐输出 `xrandr --output "$o" --brightness "$dim_gamma"`
- `trap _dim_stop HUP INT TERM EXIT`：恢复为 **1.0**（本仓库不使用 gamma 做亮度，
  硬件亮度由 `brightnessctl`/`ddcutil` 管，故 1.0 是唯一正确基线）
- 驻留：`sleep 2147483647 & wait`（**不能前台 sleep**，否则 trap 推迟到睡醒）
- 降级：`xrandr` 缺失、无活动输出 → `return 0`，**绝不影响锁屏**
- 恢复幂等（`_dim_done` 守卫 + trap 里 kill 驻留 sleep，避免孤儿进程）
- 分发守卫：`[ "${BASH_SOURCE[0]}" = "$0" ]` 才按 `$1` 走 `notifier`/`daemon`，
  被 source（测试）时只加载函数

### 2. `tools/screen.sh` 的 daemon 部分

常量：

```bash
screen_saver_time=600   # 锁屏时刻（空闲秒）
warn_seconds=30         # 提前多少秒压暗（= xset cycle）
dim_gamma=0.4
```

武装：

```bash
# warn 越界/为 0 时退化为“无预告”（cycle=0），保持旧语义
if (( warn > 0 && warn < screen_saver_time )); then
    xset s $((screen_saver_time - warn)) "$warn"
else
    xset s "$screen_saver_time" 0
fi
```

xss-lock 启动参数：

```bash
xss-lock -n "/bin/bash $SELF notifier" -- "$LOCKER" lock
```

（xss-lock 用 `g_spawn` **直接 execv，不经 shell**，所以 notifier 必须是可执行 argv；
`screen.sh` 没有 +x，故用 `/bin/bash` 显式解释。不能用 `exec` 前缀。）

重新武装（本次一并修掉）：

- 计算指纹：`<warn>|<timeout>|<gamma>|<self>|<locker>`
- 指纹不变且 `xss-lock` 存活 → 零操作（热重启不重建，避免事件丢失）
- 指纹变化或进程缺失 → 重新写 `xset s`；**未锁屏**时 `pkill -x xss-lock` 后重启，
  写回指纹到 `/tmp/dwm-status/screen-arm.fp`（测试可用 `SCREEN_ARM_FILE` 覆盖）
- **锁屏中**（`pgrep -x i3lock`）只写 `xset s`，不重启 xss-lock，留到下一轮
- 重启前轮询 ≤2s 等旧实例退出（新旧并存会让新实例 `SetAttributes` 失败直接退出）
- 保留现有语义：`xset s noblank`、`xset dpms 0 0 0`、非锁屏才 `xset s reset`
- 缺 `xss-lock` 的告警/重试逻辑保持不变

### 3. `tools/lock.sh`

`_lock_before()` 末尾加兜底（幂等，只有 3 行）：

```bash
# gamma 兜底: notifier 被异常终止时可能停在暗屏, 锁屏/解锁都以 1.0 为准
xrandr --query 2>/dev/null | awk '…活动输出…' |
    while read -r _o; do xrandr --output "$_o" --brightness 1.0 2>/dev/null; done
```

## Testing Strategy

框架：仓库现有纯 bash 断言脚本（`check`/mock `$BIN` 模式），无新框架。

`tests/screen-dim_test.sh`（新）：

- 压暗：对每个活动输出各写一次 `--brightness 0.4`，且不碰未启用输出
- 恢复：SIGHUP / SIGTERM → 每个输出写回 `1.0`
- 幂等：EXIT trap 不重复写恢复
- 降级：`xrandr` 缺失 / 无活动输出 → 退出码 0 且无副作用
- 静态守卫：脚本不出现 `brightnessctl`/`ddcutil`；`sleep … &` + `wait` 驻留

`tests/screen-lock_test.sh`（更新 + 新增）：

- A 组：`xset s 570 30`、`xss-lock -n "/bin/bash … notifier" -- …`
- F 组：`_lock_before` 对活动输出写 `--brightness 1.0`
- R 组（重新武装）：指纹不变不重启 / 变化重启并重写 xset / 锁屏中不重启 / 进程缺失仍拉起
- W 组：`warn_seconds` 越界（0 / >= timeout）退化为 `xset s 600 0`
- 保留现有 A–J/G 全部断言（仅字面量更新）

`tests/lock-mute_test.sh`：补 `xrandr` mock，避免测试触碰真实 gamma。

手动验收（需真实会话）：

1. 重启 daemon → `xset q` 显示 `timeout: 570 cycle: 30`
2. 静置 9.5 分钟 → 屏幕变暗；动鼠标 → 立即恢复且 `xset q` 计时归零
3. 静置到 10 分钟 → 变暗后 30 秒锁屏，锁屏画面亮度正常
4. 解锁 → 亮度正常，无残留压暗

## Boundaries

- Always: 先写/改测试再改实现；每个改动跑 `bash -n` + 相关测试；同步 `AGENTS.md`
- Ask first: 新增依赖、调整 `warn_seconds`/`dim_gamma` 默认值
- Never: 提交 secrets；删改现有测试断言以“通过”；把硬件亮度混进本特性

## Success Criteria

1. 静置 9.5 分钟压暗、10 分钟锁屏；动键鼠在 1 个轮询周期内恢复亮度且不锁屏
2. 锁屏与解锁画面均为正常亮度，无“解锁后仍暗”的情况
3. 音频抑制路径不变：有声时既不压暗也不锁屏
4. `tests/screen-lock_test.sh`、`tests/screen-dim_test.sh` 全绿
5. 改 `warn_seconds`/`screen_saver_time` 后重启 daemon 即生效（不需手动 `xset`）

## 设计决定

### 单文件 + 子命令（最终决定）

`notifier` 不新增文件，而是 `screen.sh notifier` 子命令，由 xss-lock 以
`/bin/bash <self> notifier` 拉起。理由与代价：

1. **notifier 仍是独立进程**（xss-lock 直接 fork/execv），生命周期不受 daemon 影响；
   合并的只是“代码所在文件”，不是“进程”本身。
2. **信号路径干净**：没有中间 `sh -c`，`trap` 直接收到 xss-lock 的
   `SIGHUP`（用户活动）/`SIGTERM`（上锁前）；驻留用 `sleep … & wait`。
3. **可观测性**：`ps` 里会看到 `screen.sh notifier`，与 daemon 的 `screen.sh`
   参数不同，可直接区分。
4. **可测性**：`BASH_SOURCE[0] == $0` 守卫让 source 只加载函数；测试还能直接
   `bash screen.sh notifier` 跑执行态。
5. **代价**：`screen.sh` 由“文件级脚本”变成“函数 + 顶层分发”，daemon 热路径的
   改动面变大（本次已用测试覆盖：A–J/G 原断言 + R/W 新组）。

## Open Questions

已确认：`warn_seconds=30`、`dim_gamma=0.4`、gamma 基线固定恢复 `1.0`、
notifier 合并进 `tools/screen.sh`（子命令）。
