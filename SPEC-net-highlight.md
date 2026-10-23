# Spec: net-highlight 5M

## Objective
`dwm-status-print.sh:print_speed` 上行 >=2MiB/s、下行 >=5MiB/s 时各自变黄提醒，低于阈值保持现有白色。用户确认值：上2下5。

## Tech Stack
bash, dwm status2d `^c$color^`，现有 `yellow/white` 变量（`dwm-status-tools.sh` 定义）。

## Commands
- 语法检查： `bash -n dwm-status-print.sh`
- 功能验证： mock `$network_traffic_path` + source 后调用 `print_speed`，断言输出含 `^c$yellow^`
- Lint： 仓库无统一 lint，有 shellcheck 则跑单文件，无则声明跳过

## Project Structure
- `dwm-status-print.sh`： `print_speed()` 唯一改动点
- spec 本文件： `SPEC-net-highlight.md`（分支内，用完可删）

## Code Style
照抄现有 `print_cpu/print_mem` 模式：
```bash
local fg="$white"; (( rx >= 5242880 )) && fg="$yellow"
printf "^c$fg^..."
```
上/下行各自独立设色，不整行统一变色。阈值：上行 `2*1048576=2097152`，下行 `5*1048576=5242880` 字节字面量+注释。

## Testing Strategy
无单测框架，bash 手工验证：
1. rx=tx=0 → 无 `yellow`
2. rx=6MiB/s → 下行段含 `yellow`，上行段不含
3. tx=3MiB/s → 上行段含 `yellow`，下行段不含
4. rx=4.9MiB/s + tx=1.9MiB/s → 均白色（边界）

## Boundaries
- Always: 只改 `print_speed`，`git diff` 无关文件为零；`AGENTS.md` 无新增函数/source 则不更新
- Ask first: 阈值改成上下行不对称、加 red 等级、改 `human_speed` 单位
- Never: 动 `update_traffic_daemon` 采样逻辑；提交 secrets；直接 push master

## Success Criteria
- `tx>=2097152` 上行段输出以 `^c#ffff00^`（yellow）开头
- `rx>=5242880` 下行段输出以 `^c#ffff00^`（yellow）开头
- 低于阈值输出颜色不变（white）
- `bash -n` 通过

## Open Questions
- 无（已确认：上2下5对称否→不对称，颜色只要 yellow）
