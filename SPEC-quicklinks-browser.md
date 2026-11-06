# Spec: quicklinks 浏览器历史/书签模式（`^`/`*`）

## Objective

`rofi/scripts/quicklinks-mode.sh` 新增两种前缀模式，对齐 Firefox Awesome Bar 习惯：

* `^` 历史模式：输入 `^` 后列表只剩历史行，继续输入本地过滤，选中打开。
* `*` 书签模式：输入 `*` 后列表只剩书签行，行为同上。
* 输入 `^foo` / `*foo` 直接回车（`RETV=2` 未选中行）：剥前缀后实时 SQL 找最佳命中打开，无命中回退默认搜索引擎（与现有 `@unknown` 语义一致）。

数据源：**仅系统默认浏览器**（跟随 `xdg-settings get default-web-browser` / `$BROWSER`），本期只实现 firefox；chromium 结构预留，后续再接线。

## Tech Stack

* bash（现有脚本风格：纯 bash + `jq` + `sqlite3`，零新依赖）。
* Firefox：`places.sqlite`（`moz_places` + `moz_bookmarks`），只读打开 `file:...?immutable=1`（浏览器运行时 WAL 加锁，实测 immutable 可读，查询 ~5ms）。
* Chromium（预留）：`History`（`urls` 表）+ `Bookmarks` JSON。

## Commands

```bash
bash tests/quicklinks-mode_test.sh   # 单测（含新增 history/bookmark 用例）
```

## Project Structure

```
rofi/scripts/quicklinks-mode.sh   → 新增 _history_list/_bookmark_list/_browser_detect，扩展 _list/_dispatch/_handle_input
tests/quicklinks-mode_test.sh     → 新增用例（mock sqlite3/xdg-settings）
SPEC-quicklinks-browser.md        → 本文件
```

## Code Style

沿用现有约定（见 `quicklinks-mode.sh`）：

* 行输出 `text\0icon\x1f<png>\x1finfo\x1f<id>`，多属性一律 `\x1f` 连接（第二个 `\0` 会截断 `ROFI_INFO`，回归测试已锁定）。
* `info` 新命名空间：`hist|<url>` / `bm|<url>`，与现有 link id / `new` / `new-searcher` 不碰撞。
* 历史预取：`WHERE visit_count>0 AND hidden=0 ORDER BY frecency DESC LIMIT 500`（取最常用）；`RETV=2` 最佳命中同样按 `frecency DESC` 取首条，语义一致。
* 显示格式：`^ <title> — <host>` / `* <title> — <host>`（host 后缀必须，用于消歧义 + 按域名过滤；空 title 回退 URL）。
* 无图标纯文本 fallback（miss/fail 与现有 links 一致）；`Alt+1/Alt+2` 编辑/删除守卫：`hist|*`/`bm|*` 的 info 直接 no-op。

示例行：

```bash
printf '%s\0icon\x1f%s\x1finfo\x1fhist|%s\n' "^ $title" "$ICON_CACHE_DIR/$host.png" "$url"
```

## Testing Strategy

* 沿用 `tests/quicklinks-mode_test.sh` 的 source+mock 模式：mock `sqlite3`（按调用参数返回 fixture）、mock `xdg-settings`。
* 用例：`_list` 含 `^`/`*` 行且格式正确；`RETV=1` + `info=hist|…` 触发 `xdg-open`；历史 info 走编辑/删除时 no-op；`RETV=2` `^foo` 命中打开、未命中回退默认引擎；profile 缺失/DB 缺失时零历史行零报错。
* `RETV=0 _main` 幂等、无 CONFIG 写回（历史/书签只读，不写 `quicklinks.json`）。

## Boundaries

* Always：只读浏览器 DB（immutable 或 tmp 拷贝，绝不写库）；缺 DB/缺 sqlite3 时静默降级（无行，不报错）；复用 favicon 缓存与 `_open_url`。
* Ask first：新增外部依赖；改动 `@`/links 现有行为。
* Never：提交 secrets；把历史 URL 写入任何持久文件/log；全量 dump（必须 `LIMIT`）。

## Success Criteria

1. 默认浏览器 firefox 下，rofi 输入 `^` 只剩历史行（frecency TOP500），输入 `*` 只剩书签行（全量，本机 169），行格式 `^ title — host`，可过滤选中打开。
2. `^foo` 直接回车打开 frecency 最佳历史命中；无命中走默认 searcher；`*foo` 同理走书签。
3. profile 通过 `profiles.ini`（`Default=1` + `IsRelative`）定位，无硬编码；切换默认浏览器到 chromium 时不崩（无 firefox 行或按预留提示）。
4. `bash tests/quicklinks-mode_test.sh` 全绿；`_list` 增量耗时 <200ms（sqlite 实测 ~5ms + 500 行 printf）。

## Open Questions

（已决策：Q1 历史预取用 frecency 最常用；Q2 显示必须带域名；Q3 chromium 留后续。）
