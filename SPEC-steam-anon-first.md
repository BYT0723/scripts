# Spec: steam-workshop anonymous-first

> 状态：已实现（`feat/steam-anon-first`，Task 1+2+3）。三次测试文件全绿：
> steam-workshop 71 / auto 10 / rofi 26。

## Objective

`tools/steam-workshop.sh` 的 `sw_download` 当前对实名用户直接 `+login <user>`（无密码、依赖缓存），
缓存缺失即失败，逼用户每次去终端手登一次；且只要传了实名用户，即使公开条目也会建实名会话，
把 GUI Steam 顶下线（GUI 设了 `AutoLogin` 又抢回来，形成乒乓）。

改动目标：公开条目全程零登录；实名会话只在真正需要时（登录门/受限条目）建立。
调用方（rofi / auto / CLI）签名不变。

## Tech Stack

- bash（仓库纯 bash 风格，不引入新依赖，不用 python/jq 之外的新工具）
- steamcmd CLI（行为：`+login anonymous` / `+login <user> [password]`）
- 现有 mock 测试：`tests/steam-workshop_test.sh`（mock `steamcmd`/`curl` binary）

## Commands

```bash
bash tests/steam-workshop_test.sh       # 核心回归
bash tests/steam-workshop-auto_test.sh  # auto 编排回归
bash tests/rofi-steam-workshop_test.sh  # rofi 侧回归
bash -n tools/steam-workshop.sh rofi/scripts/steam-workshop.sh  # 语法检查
```

## Project Structure

```
tools/steam-workshop.sh        → sw_download 改 anonymous-first（唯一生产改动）
rofi/scripts/steam-workshop.sh → _go 公开条目跳过 _pick_user；handle_update 去掉 _pick_user、固定 anonymous
tests/steam-workshop_test.sh   → 追加用例（mock steamcmd 记录参数）
tests/rofi-steam-workshop_test.sh → 视现有结构追加 _go/handle_update 用例
```

## Code Style

沿用现有风格：小写 `local`、显式 `rc` 返回（0 成功 / 2 需登录 / 1 其他失败）、
`sw_short_error` 做人类可读错误。示例（示意，非最终代码）：

```bash
sw_download() {
    # user != anonymous 时：先 anonymous 试一次，认证类失败才 +login <user> 重试
    # （无密码参数，沿用旧行为靠缓存 key；失败则 rc=2，调用方按现有文案提示终端手登）
}
```

## Testing Strategy

沿用仓库现有 mock 框架（`tests/steam-workshop_test.sh` 的 `STEAMCMD_MODE`/`STEAMCMD_ARGS_LOG` 模式）：

1. `user=实名` + anonymous 成功 → 只调一次 steamcmd、参数为 anonymous、无 `+login <user>`、rc=0
2. anonymous 报认证类错误 + 实名成功 → 调两次，第二次带 `+login <user>`、rc=0
3. anonymous 报非认证错误（超时等）→ 不重试、rc=1（不浪费第二次时间）
4. `user=anonymous` → 行为与今天完全一致（现有用例覆盖）
5. rc=2 时调用方保持现有文案（提示终端 `steamcmd +login <user> +quit` 手登），不新增密码输入路径
6. 现有全部用例继续通过

## Boundaries

- Always: 不改函数签名（`sw_download appid itemid [user] [appname]` 不变）；rc 语义不变；`anonymous` 路径零行为变化
- Ask first: 若发现某类 431960 条目 anonymous 真下不了（与实测矛盾），停下来先确认再定 fallback 策略
- Never: 脚本内处理/存储密码（无 env 密码、无 rofi 密码框、不接 secret 后端——gated 条目走现有终端手登文案）；改 auto 脚本默认用户（它已经是 anonymous）；顺手重构无关代码

## Success Criteria

- [ ] 公开条目 `sw_download <appid> <item> <实名用户>` 不建实名会话（mock 断言参数无 `+login <user>`）
- [ ] 登录门条目走实名重试且成功时 rc=0
- [ ] 非认证失败不重试
- [ ] rofi 下载公开条目不再弹用户选择、不踢 GUI
- [ ] rofi 批量更新不再弹用户选择，gated 失败进 FAIL 名单正常上报
- [ ] 三个相关测试文件全绿
- [ ] AGENTS.md 函数表/调用链同步更新（`sw_download` 行为 + rofi `_go` 链路）

## Open Questions

（已清空：Q1 不要密码方案 / Q2 handle_update 默认 anonymous，均已定。）
