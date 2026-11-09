# Spec: MPD 启动/停止时同步管理 MPRIS 桥（mpdris2 / mpdris2-rs）

## Objective
`rofi/scripts/mpd.sh` 在 MPD 未运行时会执行 `mpd` 拉起服务，但 MPRIS 桥
（供浏览器/播放器小部件/媒体键发现 MPD 的 D-Bus 代理）不会跟着起来，
导致支持 MPRIS 的客户端找不到 MPD。目标：
1. mpd.sh 拉起 `mpd` 成功后，同步确保 MPRIS 桥在运行：本机有谁用谁
  （`mpdris2-rs` / `mpdris2` 任一），都没有则通知用户安装其一。
2. `dwm-statuscmd.sh` 的状态栏 MPD 中键（`mpd --kill`）停掉 MPD 时，
   同步杀掉桥进程，避免孤儿进程占着 MPRIS 名。
3. 已在运行的桥不重复拉起；kill 路径幂等（桥本来就没跑也不报错）。

非目标：autostart 开机自启桥、systemd user service 接管、`lock.sh`
锁屏暂停逻辑（只 `mpc toggle`，MPRIS 状态由桥自动跟随，无需动）。

## Tech Stack
纯 bash；沿用现有 `command -v` / `pgrep` / `pkill` / 后台 `( cmd & )` 模式；
通知沿用各文件现有通道（mpd.sh 用 `notify-send`，与文件内
`"mpc not found"` 一致；本次 kill 路径不新增通知）。

## Commands
```bash
bash tests/mpris-bridge_test.sh
bash tests/mpd-cover_test.sh
```

## Project Structure
```
rofi/scripts/mpd.sh        → 启动路径：mpd 拉起成功后 ensure 桥（已跑不重复；缺失通知）
dwm-statuscmd.sh           → kill 路径：[$ST_MPD,$middle] 追加杀桥（与 mpd --kill 同行）
tests/mpris-bridge_test.sh → 新测：启动/幂等/缺失通知/kill 四组断言（mock FAKE_BIN）
AGENTS.md                  → 同步 mpd.sh 行 + dwm-statuscmd kill 行 + 新增测试行
```

共享逻辑放置待定（见 Open Questions Q3）：候选 A 新建 `tools/mpd.sh`
供两处 source；候选 B 两处各内联 ~10 行小函数（零新文件）。

## Code Style
匹配现有风格：`command -v foo >/dev/null 2>&1` 检测；后台外部程序一律
`( cmd & )`（rofi script mode 下前台起常驻进程会卡住 rofi 等输出，
见 quicklinks `_open_url` 注释）；kill 用 `pkill -x <name> 2>/dev/null`
并恒返回 0（幂等、无进程不报错）；注释中文+根因，函数 `local` 逐行。

桥启动不传参：`mpdris2-rs -h` 默认读 `MPD_HOST`（或 `localhost:6600`），
与 mpd.sh 的 `MPD_HOST/MPD_PORT` 环境继承一致，零配置透传。
`mpdris2`（python 版）同样读 `MPD_HOST/MPD_PORT` 环境。

## Testing Strategy
TDD，新测试 `tests/mpris-bridge_test.sh` 仿 `tests/mpd-cover_test.sh`
结构（隔离 `HOME/XDG_CACHE_HOME` + mock ROFI_DIR + `FAKE_BIN`  mock
`mpc/mpd/pgrep/pkill/mpdris2-rs/mpdris2/notify-send`，`PATH` 前置）：
- RED：先写四组断言跑红（启动拉起 / 已跑不重复 / 双缺失通知 / kill 杀桥）。
- GREEN：实现后跑绿；回归跑 `mpd-cover_test.sh` 确保 mpd.sh 重构无破环。
- 覆盖：bridge 二进制名精确匹配（`mpdris2-rs` vs `mpdris2` 前缀陷阱：
  `pgrep -x` 精确匹配，不用 `-f` 子串）。

## Boundaries
- Always: 最小 diff；新测试+回归测试全过；改动后同步 `AGENTS.md`
  （source/函数/调用链）；worktree 开发，不碰 `master`
 （worktree `~/Workspace/Worktrees/dwm-feat-mpris-bridge`，
  分支 `feat/mpris-bridge`）。
- Ask first: 把桥接入 autostart、改用 systemd user service、新增配置项
  （如强制指定桥）、改 kill 为 `mpd --kill` 之外的停止方式。
- Never: 在 `master` 上开发/提交；kill 非桥进程；前台阻塞启动桥；
  为单次逻辑引入通用抽象。

## Success Criteria
1. `mpc status` 失败→`mpd` 拉起成功后，已安装的桥（任一）恰被启动一次；
   已在运行则零启动。
2. 双缺失时 `notify-send` 提示安装其一（文案见 Open Questions Q4），
   且 mpd.sh 后续菜单逻辑不受影响（不 `exit 1`）。
3. 状态栏 MPD 中键停 MPD 时桥进程同步消失；桥本来没跑则静默成功。
4. `tests/mpris-bridge_test.sh` + `tests/mpd-cover_test.sh` 全过；
   `AGENTS.md` 已同步。

## Open Questions（已定，2026-11-10）
- Q1 优先级 → `mpdris2-rs` 优先，回退 `mpdris2`。
- Q2 kill 粒度 → kill 路径无条件 `pkill -x` 两个名字（含用户手动起的桥）。
- Q3 共享位置 → B：两处各内联小函数，零新文件。
- Q4 缺失通知文案 → 英文：
  `neither mpdris2-rs nor mpdris2 found. Please install one of them`。
