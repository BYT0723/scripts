# Spec: quicklinks 浏览器历史/书签模式（`^`/`*`）

## Objective

`rofi/scripts/quicklinks-mode.sh` 新增两种前缀模式，对齐 Firefox Awesome Bar 习惯：

* `^` 历史模式：主菜单仅留 `^ History` 入口行，输入 `^` 过滤到入口后回车下钻，
  子菜单只剩历史行，继续本地过滤，选中打开；`← Back` 首行返回主菜单。
* `*` 书签模式：同上（`* Bookmarks` 入口 → 书签子菜单）。
* `@` 搜索引擎不隔离：`@<name>` 提示行保留在主菜单（沿旧行为，输入 `@` 过滤展示）。
* 主菜单平时无 ^/* 明细行，避免污染普通查询的 rofi 过滤结果（行为隔离）。
* 输入 `^foo` / `*foo` 直接回车（`RETV=2` 未选中行）：剥前缀后实时 SQL 找最佳命中打开，
  无命中回退默认搜索引擎（与现有 `@unknown` 语义一致）；子菜单内裸词免前缀
  （`ROFI_DATA=hist|bm` 上下文自动补 `^`/`*`，显式前缀不受影响）。

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
rofi/scripts/quicklinks-mode.sh   → _list(主菜单)/_list_hist/_list_bm(子菜单)+_list_footer，
  _dispatch 下钻/返回，_handle_input 按 ROFI_DATA 补前缀
tests/quicklinks-mode_test.sh     → 用例（mock sqlite3/xdg-settings）
SPEC-quicklinks-browser.md        → 本文件
```

## Code Style

沿用现有约定（见 `quicklinks-mode.sh`）：

* 行输出 `text\0icon\x1f<png>\x1finfo\x1f<id>`，多属性一律 `\x1f` 连接（第二个 `\0` 会截断 `ROFI_INFO`，回归测试已锁定）。
* `info` 新命名空间：`hist|<url>` / `bm|<url>`，与现有 link id / `new` / `new-searcher` 不碰撞。
* 历史预取：`WHERE visit_count>0 AND hidden=0 ORDER BY frecency DESC LIMIT 500`（取最常用）；`RETV=2` 最佳命中同样按 `frecency DESC` 取首条，语义一致。
* 显示格式：`title — host`（子菜单上下文已明确类型，不带 `^`/`*` 前缀；host 后缀必须，用于消歧义 + 按域名过滤；空 title 回退 URL）。
* 无图标纯文本 fallback（miss/fail 与现有 links 一致）；`Alt+1/Alt+2` 编辑/删除守卫：`hist|*`/`bm|*` 的 info 直接 no-op。

示例行：

```bash
printf '%s\0icon\x1f%s\x1finfo\x1fhist|%s\n' "$title" "$ICON_CACHE_DIR/$host.png" "$url"
```

## Testing Strategy

* 沿用 `tests/quicklinks-mode_test.sh` 的 source+mock 模式：mock `sqlite3`（按调用参数返回 fixture）、mock `xdg-settings`。
* 用例：主菜单无 `hist|/bm|` 明细行（含两浏览入口 + `@` 提示 + `data main`）；
  `browse-hist/bm` 下钻输出对应子菜单（back 首行 + `data hist|bm`，rofi 收到输出原地刷新不退出）；
  `back` 返回主菜单；`RETV=1` + `info=hist|…` 触发 `xdg-open`；导航行走编辑/删除时 no-op；
  子菜单裸词按 `ROFI_DATA` 补前缀命中、`@` 显式直达不受影响；
  `RETV=2` `^foo` 命中打开、未命中回退默认引擎；profile 缺失/DB 缺失时子菜单仅 back 行零报错。
* `RETV=0/1 _main` 幂等、无 CONFIG 写回（历史/书签只读，不写 `quicklinks.json`；
  下钻/返回分支只输出列表，`_dispatch` 无输出分支才退出 rofi——man 语义“无输出即退出”）。

## Boundaries

* Always：只读浏览器 DB（immutable 或 tmp 拷贝，绝不写库）；缺 DB/缺 sqlite3 时静默降级（无行，不报错）；复用 favicon 缓存与 `_open_url`。
* Ask first：新增外部依赖；改动 `@`/links 现有行为。
* Never：提交 secrets；把历史 URL 写入任何持久文件/log；全量 dump（必须 `LIMIT`）。

## Success Criteria

1. 默认浏览器 firefox 下，rofi 主菜单仅 links + 两浏览入口 + `@` 提示（无 ^/* 明细行）；
   输入 `^` 过滤到 `^ History` 入口、回车下钻后只剩历史行（frecency TOP500），
   输入 `*` 同理只剩书签行（全量），行格式 `title — host`，可过滤选中打开，`← Back` 返回。
2. `^foo` 直接回车打开 frecency 最佳历史命中；无命中走默认 searcher；`*foo` 同理走书签。
3. profile 通过 `profiles.ini`（`Default=1` + `IsRelative`）定位，无硬编码；切换默认浏览器到 chromium 时不崩（无 firefox 行或按预留提示）。
4. `bash tests/quicklinks-mode_test.sh` 全绿；`_list` 增量耗时 <200ms（sqlite 实测 ~5ms + 500 行 printf）。

## Open Questions

（已决策：Q1 历史预取用 frecency 最常用；Q2 显示必须带域名；Q3 chromium 留后续。）
