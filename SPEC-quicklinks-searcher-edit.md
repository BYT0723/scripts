# Spec: quicklinks searcher 短 key + 编辑/删除 (Alt+1 / Alt+2)

## Objective
给 searcher 加短别名 `key`（`@key` 调用，显示 `@key (name)`），主菜单 searcher 行补齐与 links 对等的 `Alt+1` 编辑、`Alt+2` 删除，并明确 `Enter` 选中搜索行为。
现状：searcher 无短别名，只能 `@name` 调用（`Google Search` 这类长名难打）；行是 `@<name>` 可选中行（上一轮已改），`info=searcher|<name>`。
成功后：`key` 为 `@` 调用唯一键（白名单 `^[A-Za-z0-9_-]+$`，忽略大小写判重），`name` 仅展示（允许空格，但忽略大小写判重，两字段各自唯一）；行显示 `@key (name)`，`info=searcher|<key>`；`Alt+1` 改 key/name/URL，`Alt+2` 删除；`Enter`/自定义输入均走 `@key`（兼容老 `@name` 回退）。

## Tech Stack
- bash (`rofi/scripts/quicklinks-mode.sh`)，零新依赖
- 数据：`~/.config/dwm/quicklinks.json` 顶层 `.searcher[] = {key, name, url}`，`key` 为 `@` 调用唯一键（忽略大小写判重，白名单），`name` 仅展示（非空，忽略大小写判重；key 与 name 各自唯一），无 `id`；老数据缺 `key` 时默认拷贝 `name`（运行时回退 `key=name`，不自动改文件；编辑表单预填 `key` 为现有 `key` 或 `name`，保存时才写 `key`）

## Commands
- Test: `bash tests/quicklinks-mode_test.sh`
- Lint: 无（bash 脚本，靠测试守卫；改动前后跑上面单测）
- Dev: `ROFI_RETV=0 bash rofi/scripts/quicklinks-mode.sh` 看主菜单输出（需 `QUICKLINKS_NO_BROWSER=1` 隔离浏览器行）

## Project Structure
- `rofi/scripts/quicklinks-mode.sh` → 唯一实现文件（`_list` / `_dispatch` / `_main` / 新增 `_edit_searcher*` / `_delete_searcher*`）
- `tests/quicklinks-mode_test.sh` → 断言更新（Task 2b/2c 的 `nonselectable` 期望、`_list` 精确比对、新增 searcher 编辑/删除用例）
- `SPEC-quicklinks-searcher-edit.md`（本文件）→ 契约

## Code Style
沿用现有 links 路径写法，示例：
```bash
printf '@%s (%s)\0icon\x1f%s\x1finfo\x1fsearcher|%s\n' "$skey" "$sname" "$ICON_CACHE_DIR/$_HOST.png" "$skey"
# dispatch 剥前缀一次：
case "${ROFI_INFO:-}" in searcher\|*) key="${ROFI_INFO#searcher|}" ;;
# 查找先按 key (忽略大小写)，找不到再按 name 回退 (兼容老数据):
# jq '.searcher[]? | select((.key // .name) | ascii_downcase == ($k | ascii_downcase))'
```
- `info` 命名空间：`searcher|<key>`（与 `hist| / bm|` 同形，`#` 剥一次前缀；`key` 白名单 `^[A-Za-z0-9_-]+$`；`key` 与 `name` 各自忽略大小写唯一，`name` 可含空格；`|` 不在白名单内，既有脏数据仍可选中/删除，编辑时强制洗成合法 `key`）
- 多属性一律 `\x1f` 连接，行内只保留一个 `\0`（第二个 `\0` 会截断 `ROFI_INFO`，沿用 `_list` 注释的不变量）
- 只读/导航行守卫复用：`hist|* / bm|* / browse-* / back` 在 Alt+1/2 下 no-op，`searcher|*` 走新分支
- 字段约束（searcher 专属，links 不受影响）：`key` 白名单 + 忽略大小写唯一，`name` 非空 + 忽略大小写唯一（两字段各自判重）；`_new_searcher_form` / `_edit_searcher_form` 走 searcher 专属三字段循环（Key/Name/URL，不复用两字段 `_edit_loop`），`key` 非法/撞名或 `name` 为空/撞名 → critical 通知并重开表单，不写库
- `Enter` 选中 searcher（`_dispatch` 的 `searcher|*` 分支，需 `_main` 把 `"$@"` 透传给 `_dispatch`）：走 `_interact_async` 等 rofi 退出释放 grab 后 `module_input "Search @<key>"` 取词（RETV=1 时 rofi 只传行文本，不可解析 `$@` 取词；有词搜索走 RETV=2 自定义输入），取消/空词 no-op，否则用该引擎搜索；`RETV=2` 的 `@key word` 直搜按 key 解析（含 `name` 回退兼容老配置）；`@key` 无词仍 no-op
- 表单：links 沿用两字段 `_edit_loop`；searcher 用专属三字段循环（Key/Name/URL）+ `_interact_async` + `_write_json`（grab 释放后执行）

## Testing Strategy
- 沿用 `tests/quicklinks-mode_test.sh`（source + mock yad/rofi/xdg-open/curl/file，不弹真 rofi）
- 更新：行格式 `@key (name)` + `info\x1fsearcher|<key>`（含 icon 变体，`key` 缺失回退 `name`）；老 Task 2b/2c 期望同步
- 新增：
  1. `RETV=10 + INFO=searcher|<key>` → 三字段表单预填（Key/Name/URL），按旧 `key` 忽略大小写替换（保序）；新 `key` 非法/撞名（忽略大小写）→ critical 且不写；新 `name` 为空/撞名（忽略大小写）→ critical 且不写；`links` 不变
  2. `RETV=11 + INFO=searcher|<key>` → `No` 不删 / `Yes` 删除（按 `key` 忽略大小写定位），`links` 不变
  3. `RETV=1 + INFO=searcher|<key>`（Enter）：一律 `_interact_async` + `module_input` 取词后搜，取消/空词 no-op（行文本 `@key (name)` 不得被当搜索词）
  4. 守卫：`links` 的 Alt+1/2 不误伤 `.searcher`，反之亦然；`_new_searcher_form` 同为三字段 + 白名单/`key`/`name` 判重；`RETV=2` 的 `@key word` 按 key 解析（含 name 回退），`@key` 无词 no-op；`@` 输入过滤仅剩 `@key (name)` 行

## Boundaries
- Always: `_list` 精确输出经测试锁定；`_write_json` 原子写回；改动前后跑全量 `quicklinks-mode_test.sh`；`module_input` 调用走 `_interact_async`（等 rofi 退出释放 grab）
- Ask first: 再改 `.searcher` 数据结构；放宽 `key` 白名单（如需中文 key）
- Never: 把 `links[id]` 逻辑套到 searcher 上加 `id` 字段；删测试而不经确认；动 `hist|/bm|` 只读守卫语义

## Success Criteria
1. 主菜单行 `@key (name)` 可选中且带 `info=searcher|<key>`（有 icon 时 `\x1f` 连接 `icon`）；`@` 过滤仅剩 `@key` 行
2. `Alt+1` 三字段编辑，按旧 `key` 替换保序；`key` 非法/撞名拒绝，`name` 为空/撞名拒绝（`name` 可含空格，但不可重复）
3. `Alt+2` 在 searcher 行弹确认后删除，`links` 不受影响
4. `Enter` 在 searcher 行：一律弹 `module_input` 取词后搜，取消 no-op；`@key word` 走 RETV=2 自定义输入
5. `bash tests/quicklinks-mode_test.sh` 全绿

## Open Questions
1. ~~“重打 `_list` 留菜单”~~ → ~~有词直搜~~ → 已定：`Enter` 一律 `module_input` 取词（RETV=1 行文本不可解析）。
2. ~~`name` 允许重复~~ 已改：`key` 与 `name` 各自忽略大小写唯一（`name` 可含空格但不可重复）。
3. ~~老数据迁移~~ 已定：缺 `key` 默认拷贝 `name`（运行时回退，不自动改文件；编辑预填并在保存时写 `key`）。
4. ~~显示格式~~ 已定（用户提案）：`@key (name)`（如 `@g (Google)`，半角括号），`info=searcher|<key>`。
