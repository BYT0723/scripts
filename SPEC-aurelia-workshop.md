# Spec: aurelia 优先下载 (tools/steam-workshop.sh)

## ASSUMPTIONS I'M MAKING

1. `sw_download <appid> <itemid> [user] [appname]` 函数签名、stdout（扁平落盘路径）、rc 语义（0=成功，2=需终端登录，1=其他失败）全部不变；调用方（`rofi/scripts/steam-workshop.sh`、`tools/steam-workshop-auto.sh` 经 `sw_run_updates`/`sw_sync_updates`）零改动。
2. aurelia 已在用户机登录（`aurelia account` 有会话）；未登录/会话失效视为 aurelia 失败，走 steamcmd fallback（不做预检，直接按失败处理）。
3. aurelia 落盘遵循标准 Steam 库布局 `<lib>/steamapps/workshop/content/<appid>/<itemid>`；库根枚举用 `aurelia libraries -j`（`.libraries[].path`），失败时回退 `aurelia config show -j` 的 `.steam_library_path`，再回退 `~/.local/share/Steam` 与 `~/.steam/steam`。
4. 单个 item 下载语义对齐 steamcmd：传 `--no-recurse`（collection 不展开）。
5. 实测：`aurelia workshop install --no-recurse <非法id>` 非零退出（rc=1，stderr `Error: no installable Workshop items resolved`）；成功时 rc=0。以下载后 `<appid>/<itemid>` 目录存在且非空作为成功判据，不解析 `--json` 进度流（避免进度行解析脆弱性）。

## Objective

`tools/steam-workshop.sh` 的 `sw_download` 在本机有 `aurelia` 时优先用
`aurelia workshop install` 下载，无 `aurelia` 时保持现有 `steamcmd` 路径；
aurelia 失败时自动 fallback 到 `steamcmd`（已由用户确认的三点：搬到扁平目录 /
失败则 fallback / 忽略 user）。

用户故事：已用 `aurelia login` 持久登录 Steam 的机器，不再依赖 steamcmd 的
缓存登录（`+login <user>` 无密码、常 `Invalid Password`），工坊壁纸下载成功率更高；
没装 aurelia 的机器行为与今天完全一致。

## Tech Stack

- bash（纯 bash，不新增依赖；aurelia 为可选外部二进制，缺失即走老路）
- 现有 mock 测试：`tests/steam-workshop_test.sh`（PATH 注入 fake `steamcmd`/`curl` binary）

## Commands

```bash
Test:  bash tests/steam-workshop_test.sh
Test:  bash tests/steam-workshop-auto_test.sh      # 回归：sw_run_updates/sw_sync_updates 编排
Test:  bash tests/rofi-steam-workshop_test.sh      # 回归：rofi 调用层
Lint:  bash -n tools/steam-workshop.sh             # 无 shellcheck 配置时至少做语法检查
```

## Project Structure

```
tools/steam-workshop.sh        → 唯一生产改动（新增 sw_aurelia_* helper + sw_download 分流）
tests/steam-workshop_test.sh   → 追加 aurelia 用例（fake aurelia binary）
rofi/scripts/steam-workshop.sh → 不动（sw_download 契约不变）
AGENTS.md                      → 同步 sw_download 函数表 + aurelia 链路说明
```

## Code Style

沿用文件现有风格：小写 `sw_` 前缀函数、`local` 声明、失败 `return 1`、stdout 只走最终路径。
driver 选择示例（风格，不是最終代码）：

```bash
if [[ "${STEAM_WORKSHOP_DRIVER:-auto}" == "auto" ]] && command -v aurelia >/dev/null 2>&1; then
    if sw_aurelia_download "$appid" "$itemid" "$appname"; then
        return 0
    fi
    # aurelia 失败 → 落到现有 steamcmd 逻辑
fi
```

## Testing Strategy

- 框架：现有 `tests/steam-workshop_test.sh` 的 assert_cond + fake bin 模式；PATH 注入 fake
  `aurelia`（记录参数、按 `AURELIA_MODE` 回放 success/fail、无输出目录模拟失败）。
- 新增用例：
  1. 有 aurelia + 成功 → 调了 `aurelia workshop install --no-recurse <itemid>`、stdout 为扁平路径、深路径（Steam 库内）已搬走、脚手架 `rmdir` 回收到 `content/<appid>` 为止；
  2. 无 aurelia（PATH 剔除）→ 行为与今天一致（调 steamcmd，现有断言全过）；
  3. aurelia 失败（rc≠0/无落盘）→ 自动 fallback steamcmd 且最终成功；
  4. aurelia 成功但 steamcmd 不应被调用（`STEAMCMD_ARGS_LOG` 不存在）；
  5. 非数字 appid/itemid → 两个 driver 都不调用；
  6. `STEAM_WORKSHOP_DRIVER=steamcmd` 强制老路（即使有 aurelia 也不调它）。
- 回归：`steam-workshop-auto_test.sh`、`rofi-steam-workshop_test.sh` 全过。

## Boundaries

- Always: 不改 `sw_download` 签名与 rc 语义；`anonymous` 路径零行为变化（无 aurelia 时与今天逐字节一致）；改后跑全部三个相关测试；同步 AGENTS.md。
- Ask first: 改扁平目录布局；新增除 aurelia 外的依赖；动 `sw_check_updates`/`acf` 逻辑。
- Never: 提交 secrets；动无关文件；在 `master` 上开发（本分支 `feat/aurelia-workshop`）；为单次使用抽新抽象。

## Success Criteria

- [ ] 有 aurelia 时 `sw_download 431960 <id> anonymous "Wallpaper Engine"` 经 aurelia 下载并返回 `<隔离根>/WallpaperEngine_431960/<id>`（mock 断言参数含 `workshop install --no-recurse <id>`）。
- [ ] 无 aurelia 时现有测试逐条通过（行为不变）。
- [ ] aurelia 失败时 fallback steamcmd 成功（mock `AURELIA_MODE=fail` + `STEAMCMD_MODE=success` → rc=0 且调了 steamcmd）。
- [ ] `STEAM_WORKSHOP_DRIVER=steamcmd` 时即使有 aurelia 也不调用它。
- [ ] 上述三测试文件全绿；`AGENTS.md` 函数表/调用链已同步。

## Open Questions

无（落盘语义/回退语义/user 参数三问已答复：搬到扁平目录、失败 fallback、忽略 user）。
已知 tradeoff（写入 spec 备查，不阻塞）：mv 会把文件搬出 Steam 库，已订阅该条目的
Steam 客户端下次校验可能重新下载；属用户已接受的代价，不做 cp 双写。

## Design Notes（实现时遵循，非契约）

- helper 拆分：`sw_aurelia_roots`（库根列表）→ `sw_aurelia_install`（调 aurelia，log 进 mktemp 文件便于排错）→ `sw_aurelia_find`（按 `<appid>/<itemid>` 在库根下定位）→ 复用现有扁平化/mv/prune 段落（抽成共用段或保持两份小重复，取改动最小者）。
- aurelia 路径忽略 `$user`；auth 失败归入 rc=1（沿用 steamcmd 外的“其他失败”，不编造 rc=2，除非 stderr 明确可判登录失效——实现时看证据，证据不足则统一 rc=1 并在 spec 留痕）。
- `--no-recurse` 固定带上；不传 `--json`（rc + 目录存在性即判据）。
