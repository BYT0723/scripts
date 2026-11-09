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

通知模板（`--notification-summary` / `-body` 及其 `-paused` 变体）只认命令行参数，
上游没有配置文件。为让配置源留在 repo（`~/.config/systemd` 不在备份范围），
`mpd.sh` 以 `MPDRIS2_NOTIFY_ARGS` 数组为源，生成用户级 drop-in
`~/.config/systemd/user/mpdris2-rs.service.d/override.conf`；内容未变则不写、
不 `daemon-reload`，仅 `start`（幂等）；内容变化才重写、`daemon-reload` 并
`restart`（让新模板立即生效）。生成物是派生产物，不需要备份，恢复后由脚本重建。
`%` 是 systemd specifier，写入 unit 时统一转义为 `%%`（数组里仍写单 `%`）。

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
                              通知模板数组 + 生成/比对 drop-in（改了才 restart）
dwm-statuscmd.sh           → kill 路径：[$ST_MPD,$middle] stop 桥与 MPD（先桥后 MPD）
tests/mpris-bridge_test.sh → 测试：启动同步/drop-in 生成与幂等/缺失通知/kill（mock systemctl）
tests/mpd-cover_test.sh    → 补 systemctl/mpdris2-rs mock，避免 source 时触碰真实用户服务
AGENTS.md                  → 同步 mpd.sh 行 + mock 隔离条目
```

## Code Style
匹配现有风格：`command -v mpdris2-rs >/dev/null 2>&1` 检测缺失；
`systemctl --user ... >/dev/null 2>&1` 静默；注释中文+根因。

## Testing Strategy
沿用 `tests/mpris-bridge_test.sh`（隔离 `HOME/XDG_CONFIG_HOME/XDG_CACHE_HOME` + mock ROFI_DIR
+ `FAKE_BIN` mock `mpc/systemctl/mpdris2-rs/notify-send`，`PATH` 前置）：
- S1：`mpd` 未就绪→`start mpd.service` 拉起成功；首次生成 drop-in（`ExecStart=` 重置 +
  `%%state%%` / `%%title%%` 占位符），`daemon-reload` 后 `restart mpdris2-rs.service`。
- S2：模板未变→不重写、不 `daemon-reload`、不 `restart`，仅 `start`（幂等）。
- S3：缺失 `mpdris2-rs` 时 `notify-send` 提示，且菜单逻辑继续（不 `exit 1`）。
- S4：kill 行为 `systemctl --user stop mpdris2-rs.service mpd.service`，
  不再含 `mpd --kill`/`pkill`；`eval` 用 mock 优先 PATH，不碰用户真服务。
- S5：drop-in 内容漂移→重写 + `daemon-reload` + `restart`。
回归跑 `mpd-cover_test.sh`（补 systemctl/mpdris2-rs mock）确保 mpd.sh 重构无破环、
且测试不触碰真实 systemd 用户服务。

## Boundaries
- Always: 最小 diff；新测试+回归测试全过；改动后同步 `AGENTS.md`
  （source/函数/调用链）；worktree 开发，不碰 `master`。
- Ask first: 把桥接入 autostart、新增配置项（如强制指定桥）。
- Never: 在 `master` 上开发/提交；kill 非桥进程；前台阻塞启动桥；
  为单次逻辑引入通用抽象。

## Success Criteria
1. `mpc status` 失败→`start mpd.service` 拉起成功后，桥 drop-in 首次生成并
   `daemon-reload` + `restart`；模板未变时仅 `start`，不重复 `daemon-reload`/`restart`。
2. drop-in 含 `ExecStart=`（重置原值）+ 完整模板参数，`%` 已转义为 `%%`；
   修改数组后下次打开菜单即重写并 `restart` 生效。
3. 缺失 `mpdris2-rs` 时 `notify-send` 提示安装，且后续菜单逻辑不受影响。
4. 状态栏 MPD 中键停 MPD 时桥同步消失；本来没跑则静默成功。
5. `tests/mpris-bridge_test.sh` + `tests/mpd-cover_test.sh` 全过；
   `AGENTS.md` 已同步。
