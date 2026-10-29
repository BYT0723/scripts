# Spec: web/scene 壁纸经 project.json 解析 preview 与入口 file

## Objective
`rofi/scripts/wallpaper.sh` 的 web/scene 选择器与 `tools/wallpaper.sh` 的随机/校验逻辑
目前硬编码 marker（web 只认 `index.html`，scene 只认 `scene.pkg|json`），与
Wallpaper Engine `project.json` 的真实契约脱节。实测反例：
- `3818900270/project.json`: `file=wallpaper.html`（`index.html` 不存在，现有逻辑永远选不上/校验拒绝）；
- `3497575235/project.json`: `file=scene.json` 但落盘只有 `scene.pkg`（`file` 字段不可直接拼接）。
目标：以 `project.json` 的 `preview` / `file` 字段为首要来源（带 fallback），
统一预览图与入口文件的解析，让选择器、yazi 校验、random 池三处同走一套 helper。

## ASSUMPTIONS I'M MAKING
1. `project.json` 存在即信任其 `title/preview/file/type` 四字段；缺失/损坏时回退现有行为（marker 文件名 + `preview.*` 轮询），不报错退出。
2. “web 门户”指渲染入口文件（传给 `xwallpaper --web` 的目录由其决定，校验看入口存在性），不是另起预览窗口。
3. 不改变 `xwallpaper` 调用契约（仍传目录），只改“目录是否合法 / 预览图取哪张”的判定。
4. scene 的 `file` 指向 `scene.json` 但落盘常为 `scene.pkg`，两者视为等价入口（任一存在即合法）。

## Tech Stack
纯 bash + jq（沿用现有）；不新增依赖；mock 式 shell 测试不变。

## Commands
```bash
bash tests/wallpaper-marker_test.sh        # 现有 marker/选择器守护（如有则跑，无则声明跳过）
bash tests/wallpaper-project-json_test.sh  # 新增：preview/file 解析契约（TDD 红→绿）
git diff --stat                            # 自查无无关文件
```

## Project Structure
```
tools/wallpaper-lib.sh      → 新增 project_preview() / project_entry()（唯一真实来源）
rofi/scripts/wallpaper.sh   → select_marker_wallpaper / select_yazi_directory 改调 helper
tools/wallpaper.sh          → random_web/scene 池枚举改走 helper（或放宽 find 模式 + helper 校验）
tests/wallpaper-project-json_test.sh → 新增契约测试
AGENTS.md                   → 补两函数表/调用链
```

## Code Style
helper 遵循现有注释头风格（一行用法 + 输入输出契约），示例：
```bash
project_preview() { # <dir> → 预览图绝对路径；无可用预览返回 1
project_entry() { # <dir> [web|scene] → 入口文件绝对路径；scene.json/pkg 互认；非法返回 1
```
`local` 逐行赋值（不 `local x="$1" y="$x"` 同行）。`detect_file_type` 的目录分支保持不动，
仅当新增 helper 需要时才复用。

## Testing Strategy
TDD：先写 `tests/wallpaper-project-json_test.sh` 覆盖以下契约，跑红；
实现 helper + 三处调用方改造后跑绿；现有 wallpaper 相关测试全过。
- preview：`preview` 字段存在且文件存在 → 返回 `$dir/$preview`；
  字段缺失/文件不存在 → 回退 `preview.gif/png/jpg/jpeg/webp` 首个存在者；
  都无 → 返回 1。
- entry(web)：`file` 字段存在且 `$dir/$file` 存在 → 返回它（含 `wallpaper.html` 反例）；
  否则回退 `index.html`；都无 → 返回 1。
- entry(scene)：`scene.json`/`scene.pkg` 任一存在即合法（`file` 字段与落盘名不一致时互认）；
  都无 → 返回 1。
- 选择器图标：有 `project.json` 的条目用 helper 结果，不再直拼 `$d/$preview`。
- yazi 校验：`wallpaper.html` 目录可通过；无入口目录仍拒绝。

## Boundaries
- Always: 最小 diff；先读源码与测试；新旧测试全过；`git diff --stat` 自查；
  改后同步 `AGENTS.md`（§函数表/调用链）。
- Ask first: 改 `xwallpaper` 传参（目录→文件）、改 random 池深度语义、新增依赖。
- Never: 顺手重构相邻代码；在 `master` 上开发
  （本任务 worktree `~/Workspace/Worktrees/dwm-feat-web-scene-project-json`，
  分支 `feat/web-scene-project-json`）。

## Success Criteria
1. `project_preview` / `project_entry` / `project_type` 在 `wallpaper-lib.sh` 定义，
   `find_project_dirs <dir> <depth> <type>` 枚举含 `project.json` 且 `type` 匹配的目录；
   三处调用方（selector/yazi/random）均经 helper 判定，不再有 `index\.html` 硬编码校验。
2. `3818900270`（`file=wallpaper.html`）可被选中且 yazi 校验通过；
   `3497575235`（`file=scene.json`/落盘`scene.pkg`）仍合法。
3. `preview` 字段缺失/损坏时回退 `preview.*` 行为不变，无预览时 selector 不崩（icon 为空）。
4. 新增契约测试 + 现有 wallpaper 测试全过；`AGENTS.md` 已同步。

## Open Questions
- 已确认（2026-10-29）：random 池走“含 project.json 的目录枚举 + `type` 字段过滤”，
  不再用 `find index.html / scene.pkg` 硬编码。`select_marker_wallpaper` 第三个参数
  由 find-regex 改为类型名（`web`/`scene`）。
- `detect_file_type` 的目录分支默认不动（marker 互认已够用）。
