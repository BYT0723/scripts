# Spec: Steam Workshop 更新逻辑合一套 + rofi 免确认

## Objective
`tools/steam-workshop-auto.sh`（开机自动）与 `rofi/scripts/steam-workshop.sh handle_update()`（手动）
目前各写一套“检查→计数→跑更新→汇总”编排，只有最底层的 `sw_check_updates` /
`sw_run_updates` 共用。目标：抽一个公共编排函数，两边同调一套；
同时 rofi 侧删 `module_confirm`，检查出 UPDATE 直接下载并汇总通知（与 auto 一致）。

## Tech Stack
纯 bash；不新增依赖；沿用现有 `sw_check_updates` / `sw_run_updates` / `sw_download` /
`system-notify`。mock 式 shell 测试不变。

## Commands
```bash
bash tests/steam-workshop_test.sh        # 核心库守护
bash tests/steam-workshop-auto_test.sh   # auto 行为守护
bash tests/rofi-steam-workshop_test.sh   # rofi 行为（含改写后的免确认用例）
```

## Project Structure
```
tools/steam-workshop.sh          → 新增 sw_sync_updates()（唯一公共编排）
tools/steam-workshop-auto.sh     → main 改调 sw_sync_updates（锁/日志/静默策略保留）
rofi/scripts/steam-workshop.sh   → handle_update 改调 sw_sync_updates（选 scope/选用户/通知保留，删 module_confirm）
tests/rofi-steam-workshop_test.sh → “拒绝确认不下载”用例改写为“直接下载且不调 confirm”
AGENTS.md                        → 补 sw_sync_updates 函数表/调用链
```

## Code Style
新函数遵循现有注释头风格（一行用法 + 输入输出契约），示例：
```bash
sw_sync_updates() { # root user [scope...] → stdout "updates currents skips ok fail[ fids...]"; 无候选返回 1
```
调用方只留薄包装（通知/日志/锁/交互），计数分支不重复。`local` 逐行赋值
（不 `local x="$1" y="$x"` 同行）。

## Testing Strategy
TDD：先改 `tests/rofi-steam-workshop_test.sh`（免确认断言 + confirm 未调用断言），跑红；
实现 `sw_sync_updates` + 两处调用方改造后跑绿；三套测试全过。
auto 现有四场景（有更新/全 CURRENT/断网/锁被占/空根）保持原断言不变即守护统一无回归。

## Boundaries
- Always: 最小 diff；先读源码与测试；三套测试全过；`git diff --stat` 自查无无关文件；
  改后同步 `AGENTS.md`（§函数表/调用链）。
- Ask first: 改通知文案、改 scope 语义、新增依赖、改 `sw_download` 迁移规则。
- Never: 顺手重构相邻代码；动 `sw_download` acf 逻辑；在 `master` 上开发
 （本任务 worktree `~/Workspace/Worktrees/dwm-feat-steam-workshop-no-confirm`，
  分支 `feat/steam-workshop-no-confirm`）。

## 新函数契约（sw_sync_updates）
- 输入：`sw_sync_updates <root> [user] [scope...]`（scope 为空 = 全量；多个 scope 逐个检查合并）。
- 行為：逐 scope 调 `sw_check_updates`（失败的 scope 跳过）；无任何行 → 返回 1；
  统计 UPDATE/CURRENT/SKIP；UPDATE 行喂给 `sw_run_updates user`；只回显不 notify。
- 输出：stdout 一行 `updates currents skips ok fail[ fids...]`，返回 0。
- 调用方：
  - auto：`summary=$(sw_sync_updates "$AUTO_ROOT" anonymous "${appids[@]}") || {记skip日志; return 0}`；
    解析后记日志；`updates==0` 静默；否则汇总通知（ok/fail）。
  - rofi：后台子 shell 内
    `summary=$(sw_sync_updates "$root" "$user" ${scope:+"$scope"}) || {“No downloads yet”; return}`；
    `updates==0` → “All up to date”；否则 “Update done” 汇总。无 `module_confirm`。

## Success Criteria
1. `sw_check_updates`/`sw_run_updates` 的计数→运行→汇总编排只在 `sw_sync_updates` 内出现一份；
   `grep -n "grep -c '^UPDATE" tools/steam-workshop-auto.sh rofi/scripts/steam-workshop.sh` 无命中。
2. rofi 有 UPDATE 时无确认直接下载（`confirm.called` 不产生），汇总通知含 ok/fail。
3. auto 四场景行为不变（现有 `steam-workshop-auto_test.sh` 全过，无需改用例）。
4. 三套测试全过；`AGENTS.md` 已同步。

## Open Questions
- 无。方向已确认：合一套 + rofi 免确认，`_pick_user` 保留。
