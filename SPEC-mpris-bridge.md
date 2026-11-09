# Spec: MPD 启动/停止时同步管理 MPRIS 桥（mpdris2-rs，经 systemd user service）

## Objective
`rofi/scripts/mpd.sh` 在 MPD 未运行时经 `systemctl --user start mpd.service`
拉起服务，并同步 `systemctl --user start mpdris2-rs.service` 确保 MPRIS 桥
（供支持 MPRIS 的客户端发现 MPD 的 D-Bus 代理）在运行。
`dwm-statuscmd.sh` 的状态栏 MPD 中键经
`systemctl --user stop mpdris2-rs.service mpd.service` 同步停掉两者
（先桥后 MPD），避免孤儿进程占着 MPRIS 名。

`mpdris2`（python 版）已移除，只支持 `mpdris2-rs`。
`mpdris2-rs.service` 为 `Type=dbus`（`BusName=org.mpris.MediaPlayer2.mpd`），
`start` 会等总线名就绪；`Wants/After mpd.service`，且 `start`/`stop` 均幂等，
故启动侧无需 `pgrep` 判重，后台 `( cmd & )` 拉起方式不再使用。

非目标：autostart 开机自启桥、`lock.sh` 锁屏暂停逻辑
（只 `mpc toggle`，MPRIS 状态由桥自动跟随，无需动）。

## Tech Stack
纯 bash；`systemctl --user start/stop`；通知沿用各文件现有通道
（mpd.sh 用 `notify-send`，与文件内 `"mpc not found"` 一致；
kill 路径不新增通知）。

## Commands
```bash
bash tests/mpris-bridge_test.sh
bash tests/mpd-cover_test.sh
```

## Project Structure
```
rofi/scripts/mpd.sh        → 启动路径：mpd 未就绪则 start mpd.service；随后 ensure 桥（未安装通知）
dwm-statuscmd.sh           → kill 路径：[$ST_MPD,$middle] stop 桥与 MPD（先桥后 MPD）
tests/mpris-bridge_test.sh → 测试：启动同步/已跑幂等/缺失通知/kill 四组断言（mock systemctl）
AGENTS.md                  → 同步 mpd.sh 行 + mock 隔离条目
```

## Code Style
匹配现有风格：`command -v mpdris2-rs >/dev/null 2>&1` 检测缺失；
`systemctl --user ... >/dev/null 2>&1` 静默；注释中文+根因。

## Testing Strategy
沿用 `tests/mpris-bridge_test.sh`（隔离 `HOME/XDG_CACHE_HOME` + mock ROFI_DIR
+ `FAKE_BIN` mock `mpc/systemctl/mpdris2-rs/notify-send`，`PATH` 前置）：
- S1：`mpd` 未就绪→`start mpd.service` 拉起成功，且 `start mpdris2-rs.service` 恰一次。
- S2：MPD 已就绪→不重复 `start mpd`，桥 `start` 照发（systemd 幂等）。
- S3：缺失 `mpdris2-rs` 时 `notify-send` 提示，且菜单逻辑继续（不 `exit 1`）。
- S4：kill 行为 `systemctl --user stop mpdris2-rs.service mpd.service`，
  不再含 `mpd --kill`/`pkill`；`eval` 用 mock 优先 PATH，不碰用户真服务。
回归跑 `mpd-cover_test.sh` 确保 mpd.sh 重构无破环。

## Boundaries
- Always: 最小 diff；新测试+回归测试全过；改动后同步 `AGENTS.md`
  （source/函数/调用链）；worktree 开发，不碰 `master`。
- Ask first: 把桥接入 autostart、新增配置项（如强制指定桥）。
- Never: 在 `master` 上开发/提交；kill 非桥进程；前台阻塞启动桥；
  为单次逻辑引入通用抽象。

## Success Criteria
1. `mpc status` 失败→`start mpd.service` 拉起成功后，`start mpdris2-rs.service`
   恰一次；MPD 已就绪则不重复 `start mpd`。
2. 缺失 `mpdris2-rs` 时 `notify-send` 提示安装，且后续菜单逻辑不受影响。
3. 状态栏 MPD 中键停 MPD 时桥同步消失；本来没跑则静默成功。
4. `tests/mpris-bridge_test.sh` + `tests/mpd-cover_test.sh` 全过；
   `AGENTS.md` 已同步。
