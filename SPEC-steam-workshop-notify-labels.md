# Spec: 更新汇总通知带 id+名称（本地标签，零新增网络）

## Objective
`handle_update`（rofi 手动）与 `steam-workshop-auto.sh`（开机自动）的汇总通知
目前只有计数 + 失败 id（如 `2 updated, 1 failed: 222`），用户不知道更新了啥。
目标：通知里列出每项 `父目录名/itemid`（如 `WallpaperEngine_431960/111`），
成功与失败都列。两边都要。不调新增 API（201essing: 检查阶段已逐条请求过，
标题解析会动核心契约，本次不用；纯本地路径拼接，零网络、即时）。

## Tech Stack
纯 bash；沿用 `sw_sync_updates` 公共编排；通知仍走 `system-notify`。

## Commands
```bash
bash tests/rofi-steam-workshop_test.sh
bash tests/steam-workshop-auto_test.sh
bash tests/steam-workshop_test.sh
```

## Project Structure
```
tools/steam-workshop.sh          → sw_sync_updates 输出追加明细行（首行契约不变）
tools/steam-workshop-auto.sh     → 汇总通知拼明细
rofi/scripts/steam-workshop.sh   → 汇总通知拼明细
tests/rofi-steam-workshop_test.sh → 新增标签断言
tests/steam-workshop-auto_test.sh → 新增标签断言
```

## Code Style
沿用现有注释头与 `local` 逐行风格；标签推导内联在编排层，调用方只做拼接。
明细过多时截断：最多列 10 项，余下记 `+N more`。

## Testing Strategy
TDD：先给两套测试加标签断言（跑红）→ 实现后跑绿；三套全过。
既有子串断言（如 `1 updated`）保持兼容——新文案保留该子串。

## Boundaries
- Always: 最小 diff；三套测试全过；同步 `AGENTS.md`（契约变化处）。
- Ask first: 改用 API 标题、改通知级别/文案结构、新增依赖。
- Never: 动 `sw_check_updates`/`sw_download`；在 `master` 上开发
 （worktree `~/Workspace/Worktrees/dwm-feat-steam-workshop-notify-labels`，
  分支 `feat/steam-workshop-notify-labels`）。

## 新契约（sw_sync_updates）
- 首行不变：`updates currents skips ok fail[ fids...]`（老解析 `read` 不动）。
- 追加明细行（仅当 updates>0）：每行 `OK|itemid|label` 或 `FAIL|itemid|label`，
  label = `$(basename $(dirname path))/itemid`（如 `WallpaperEngine_431960/111`；
  legacy 深路径即 `431960/666`）。ok 明细 = UPDATE 集 − 失败集。
- 调用方：取明细行拼通知，如
  `Update done\n2 updated: WallpaperEngine_431960/111, 431960/666`
  `Update done\n1 updated: A/111, 1 failed: A/222`
  auto 同理（`Auto update done` 前缀保留）。

## Success Criteria
1. 有更新时两边通知含每项 `label`（成功与失败各自列出；>10 项截断 `+N more`）。
2. 首行契约不变：auto 旧断言（`1 updated` 等子串）零修改通过。
3. 无更新/静默路径行为不变。
4. 三套测试全过；`AGENTS.md` 已同步。

## Open Questions
- 无。名称来源定为本地标签（目录名+id），两边都带。
