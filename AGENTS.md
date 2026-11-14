# AGENTS.md

> 此文件记录所有脚本间的 source 依赖、函数调用关系和调用链。
> 每次修改脚本后需同步更新 (见下方 §编码准则.5)。

## 目录

- [Source 依赖图](#source-依赖图)
- [函数定义与调用关系](#函数定义与调用关系)
- [调用链 (Call Chain)](#调用链-call-chain)
- [配置文件](#配置文件)
- [Rofi 模块注册表规范](#rofi-模块注册表规范)
- [已知问题](#已知问题)
- [编码准则](#编码准则)

## Source 依赖图

```
dwm-launcher.sh ──sources──► utils/monitor.sh
dwm-status.sh ──sources──► dwm-status-tools.sh ──sources──► dwm-status-print.sh
                                                           utils/weather.sh
                                                           utils/notify.sh
dwm-statuscmd.sh ──sources──► utils/notify.sh
autostart.sh ──sources──► utils/launch.sh
tools/theme.sh ──sources──► utils/notify.sh, utils/launch.sh, tools/monitor-brightness.sh
                ──requires─► xsettingsd, dconf (gsettings), curl (GTK/portal 双通道广播 / auto 日出日落)
                ──calls──► tools/wallpaper.sh --theme <mode> (后台, 主题翻转跟随换壁纸)
                ──calls──► utils/launch.sh launch restart snixembed (切主题重启 snixembed 重绘托盘图标, 见 restart_snixembed)
tools/monitor-brightness.sh ──sources──► 无外部脚本; ──sourced by── tools/theme.sh
utils/launch.sh ──sourced by── autostart.sh, tools/theme.sh; ──requires─► flock (/tmp/dwm-status/autostart-launch-<name>.{pid,lock})

tools/lock.sh ──sources──► utils/notify.sh; ──requires──► i3lock, pactl (静音/还原全部 sink), mpc, xset, xrandr (gamma 兜底)
              ◄──sourced by── rofi/powermenu/type-{1..6}/powermenu.sh
tools/screen.sh ──sources──► utils/notify.sh; ──requires─► xss-lock (extra), xrandr (gamma 预告); ──spawns──► xss-lock -n "/bin/bash <screen.sh> notifier" -- lock.sh lock (单一空闲权威); ──子命令──► `screen.sh notifier` (由 xss-lock -n 拉起: 锁屏前压暗, HUP/TERM 还原); ──调用──► xset s <锁屏-预告> <预告> + xset s noblank / xset s reset (音频抑制) / xset dpms 0 0 0
tools/wallpaper.sh ──sources──► utils/notify.sh, tools/wallpaper-lib.sh, tools/wallpaper-render.sh
tools/screencast.sh ──sources──► utils/monitor.sh
tools/brightness.sh ──sources──► utils/notify.sh
tools/calendar.sh ──sources──► utils/notify.sh
tools/keyboard.sh ──sources──► utils/notify.sh
tools/volume.sh ──sources──► utils/notify.sh
tools/touchpad.sh ──sources──► 无外部脚本
tools/avtool.sh ──sources──► 无外部脚本 (organize_av.sh + check_rescrape.sh 合并); ──requires─► curl, jq, rsync; organize 子命令查演员走 metatube 本地服务, check/identify 子命令走 Jellyfin API (识别逻辑:按文件名搜索并自动应用番号精确命中,check --fix 与 identify 共用 _identify_one)
utils/form.sh ──sources──► 无外部脚本; ──requires─► jq, yad (优先) / zenity (fallback); 环境变量 FORM_BACKEND/FORM_CSS/FORM_WIDTH/FORM_FONT (yad 字体)/FORM_TITLE (对话框标题)
utils/url.sh ──sources──► 无外部脚本
utils/string.sh ──sources──► 无外部脚本

dwm-windowhook.sh ──sources──► dwm-status-tools.sh (handle_refresh_mail 在后台子 shell 内延迟 source, 只取 update_mail; 顶层无 source, 不阻塞 dwm 同步调起)

tools/yt-dlp.sh ◄──sourced by── rofi/scripts/yt-dlp-wrapper.sh

tools/steam-workshop.sh ◄──sourced by── rofi/scripts/steam-workshop.sh, tools/steam-workshop-auto.sh

tools/steam-workshop-auto.sh ◄──autostart.sh 后台直起──► sw_sync_updates (flock 单实例 `/tmp/dwm-status/steam-workshop-auto.lock`, 日志 `~/.local/state/dwm/steam-workshop-auto.log`)

rofi/scripts/yt-dlp-wrapper.sh ──sources──► rofi/scripts/lib-module.sh, rofi/scripts/util.sh, utils/notify.sh, tools/yt-dlp.sh

rofi/scripts/quicklinks-mode.sh──sources──► utils/form.sh, utils/notify.sh, utils/url.sh, utils/string.sh, rofi/scripts/lib-module.sh (module_confirm, module_input); ──挂载于── rofi/launchers/type-3/launcher.sh (combi 模式 quicklinks modi)
rofi/scripts/steam-workshop.sh──sources──► rofi/scripts/lib-module.sh, rofi/scripts/util.sh, utils/notify.sh, tools/steam-workshop.sh; ──calls──► sw_download (STEAM_WORKSHOP_DRIVER=auto 时有 aurelia 优先 `aurelia workshop install --no-recurse`, 失败 fallback steamcmd +login <user>/+workshop_download_item, 后台子 shell + system-notify)
rofi/scripts/module.sh      ──sources──► rofi/scripts/lib-module.sh, rofi/scripts/util.sh
rofi/scripts/wallpaper.sh   ──sources──► rofi/scripts/util.sh, rofi/scripts/lib-module.sh, utils/notify.sh, tools/wallpaper-lib.sh, tools/wallpaper-render.sh
rofi/scripts/notification.sh──sources──► rofi/scripts/util.sh, rofi/scripts/lib-module.sh
rofi/scripts/sddm.sh       ──sources──► rofi/scripts/lib-module.sh, rofi/scripts/util.sh
rofi/scripts/screenshot.sh  ──sources──► rofi/scripts/lib-module.sh, rofi/scripts/util.sh
rofi/scripts/screencast.sh  ──sources──► rofi/scripts/lib-module.sh, rofi/scripts/util.sh, utils/monitor.sh
rofi/scripts/media-scraping.sh──sources──► rofi/scripts/lib-module.sh, rofi/scripts/util.sh, utils/notify.sh; ──manages──► docker.service (+ docker.socket) 生命周期 (Toggle 时自启/空闲自停)
rofi/scripts/mpd.sh         ──sources──► rofi/scripts/lib-module.sh, rofi/scripts/util.sh; ──requires─► MPD `readpicture` 协议 (nc / bash /dev/tcp, 环境变量 MPD_HOST/MPD_PORT 默认 localhost:6600), osdlyrics + busctl + setsid + pgrep (OSD 歌词开关: `org.osdlyrics.Config` 的 `General/display-mode-osd`); 封面缓存 `~/.cache/dwm/mpd-cover/mpd-cover-<uri-hash>.jpg` (按歌曲 uri cksum 绑定, 命中复用); ──generates──► `~/.config/systemd/user/mpdris2-rs.service.d/override.conf` (通知模板, 内容变了才 daemon-reload + restart)
rofi/scripts/sing-box.sh    ──sources──► rofi/scripts/lib-module.sh, rofi/scripts/util.sh, utils/notify.sh
rofi/scripts/scrcpy.sh    ──sources──► rofi/scripts/lib-module.sh, rofi/scripts/util.sh, utils/notify.sh
rofi/scripts/theme.sh──sources──► rofi/scripts/lib-module.sh, rofi/scripts/util.sh, tools/theme.sh
rofi/scripts/dunst-menu.sh──sources──► 无外部脚本 (dunst 的 dmenu 实现: stdin action/URL 行 → rofi applets/type-2/style-2 → stdout 原始行, `-format i` 序号回映射); ──invoked by── dunst (dunstrc `dmenu = ~/.dwm/rofi/scripts/dunst-menu.sh`)

# 死代码 (未被任何脚本 source)
utils/print.sh   — number2icon() 无人调用
utils/shell-lib.sh — echo_note / is_float_term / init_tmux_cursor 无人调用
```

## 函数定义与调用关系

### dwm-status-print.sh

| 函数        | 调用者                                                          |
| ----------- | --------------------------------------------------------------- |
| `print_battery()` | dwm-status.sh panes() (status2d 自绘电池: 端子/外框/内背景/电量四段 `^r^` 矩形, `^d^` 复位色 + `^fN^` 前移光标留间距) |

### utils/notify.sh → system-notify()

被以下脚本调用:
`brightness.sh` `calendar.sh` `keyboard.sh` `lock.sh` `volume.sh` `dwm-status-tools.sh` `dwm-statuscmd.sh` `sing-box.sh` `wallpaper.sh` `tools/theme.sh` `yt-dlp-wrapper.sh` `scrcpy.sh` (tool-notify)

### utils/monitor.sh

| 函数                          | 调用者                                  |
| ----------------------------- | --------------------------------------- |
| `is_portrait()`               | dwm-launcher.sh (powermenu)             |
| `get_monitor_info()`          | wallpaper.sh (set_wallpaper_to_monitor), wallpaper-lib.sh (get_group_dim), monitor.sh (get_monitor_info_by_index, get_current_monitor) — 单次 xrandr 调用解析 (原实现 3 次, get_group_dim 逐成员调用会倍增) |
| `get_monitor_info_by_index()` | wallpaper.sh                            |
| `get_current_monitor()`       | screencast.sh                           |

### utils/weather.sh

| 函数                 | 调用者                               |
| -------------------- | ------------------------------------ |
| `ipinfo-openMeteo()` | dwm-status-tools.sh (update_weather) |
| `weather-forecast()` | dwm-status-tools.sh                  |

### utils/form.sh

| 函数          | 调用者                             |
| ------------- | ---------------------------------- |
| `form_show()` | quicklinks-mode.sh (_edit_loop 表单录入) |

### utils/url.sh

| 函数         | 调用者                                     |
| ------------ | ------------------------------------------ |
| `is_url()`   | quicklinks-mode.sh (_handle_input) |
| `valid_url()`| quicklinks-mode.sh (_edit_loop 校验 / clipboard_url) |

### utils/string.sh

| 函数        | 调用者                                       |
| ----------- | -------------------------------------------- |
| `trim_str()`| quicklinks-mode.sh (_edit_loop / clipboard_url) |

### utils/launch.sh

> 应用启动/重启助手, 被 autostart.sh 与 tools/theme.sh 共用。以 `/tmp/dwm-status/autostart-launch-<name>.pid` 记录 pid, 同一 name 的"检查+启动"用 flock 保证原子, 后台子进程 `9>&-` 关闭锁 fd。`{ } 9>lock` 的重定向在块结束后由 bash 自动还原父 shell 的 FD 9 (故不与 theme.sh `_auto_lock` 的 FD 9 冲突)。

| 函数       | 调用者                                                                                          |
| ---------- | ----------------------------------------------------------------------------------------------- |
| `launch()` | autostart.sh (`check`/`restart` 各应用), tools/theme.sh `restart_snixembed` (切主题 `launch restart snixembed`) |

### rofi/scripts/quicklinks-mode.sh (rofi script mode)

| 函数               | 调用者                                                                 |
| ------------------ | ---------------------------------------------------------------------- |
| `_main()`          | 主入口 (按 ROFI_RETV 分派: 0=主菜单, 1=选中/下钻/返回, 2=自定义输入, 3/11=删除 (searcher\|* → _delete_searcher), 10=编辑 (searcher\|* → _edit_searcher)) |
| `_list()`          | _main (RETV=0 主菜单; _ensure_ids + _load + _ensure_icons (browser_hosts 恒空, 只预取 links/searcher) 后输出 links 行 (hit `name\0icon\x1f<png>\x1finfo\x1f<id>`, miss/fail 纯文本 `name\0info\x1f<id>`) + New/New Searcher 行 + `^ History`/`* Bookmarks` 浏览入口行 + searcher `@key (name)` 可选中行 (`@key (name)\0icon\x1f<png>\x1finfo\x1fsearcher|<key>`, 无 icon 时 `@key (name)\0info\x1fsearcher|<key>`; 缺 key 老数据回退 key=name) + `_list_footer main`; 主菜单无 ^/* 明细行, 避免污染普通查询过滤; hit 判定内联 `[[ -f ]]` 避免 `$()` fork) |
| `_list_hist()` / `_list_bm()` | _dispatch (RETV=1 info=browse-hist/bm; back 首行 + `_load_browser_rows` 历史/书签 `title — host\0info\x1fhist\|<url>` / `title — host\0info\x1fbm\|<url>` 行 (子菜单不带 ^/* 前缀) + `_list_footer hist|bm`; 有输出 → rofi 原地刷新不退出; 测试缝 `QUICKLINKS_NO_BROWSER` 非空时跳过浏览器行 (主菜单精确断言保持 hermetic)) |
| `_list_footer()`   | _list/_list_hist/_list_bm (输出 `\0data\x1f<main\|hist\|bm>` (经 ROFI_DATA 回传供 _handle_input 判上下文) + `\0use-hot-keys\x1ftrue`) |
| `_collect_host()`  | _ensure_icons (去重 + 跳过已 png/.fail, 未缓存 host 追加进 pending; 依赖调用者局部 seen/pending, bash 动态作用域) |
| `_ensure_icons()`  | _list/_list_hist/_list_bm (收集 links + searcher + `_browser_hosts` 的 host 去重 → 后台子 shell 分片并发下载, 每 8 个 wait 一轮防限流; 已 png/.fail 跳过; searcher 引擎域名经 `_host_from_url` 提取; stdout/stderr 重定向防 SIGPIPE; 主菜单 _browser_hosts 恒空, 不预取浏览器 host) |
| `_browser_detect()` | _list_hist/_list_bm (经 _load_browser_rows), _handle_input (`^`/`*` 分支; `xdg-settings get default-web-browser` 为主、`$BROWSER` 回退, 输出 `firefox\|<profile_dir>`, 非 firefox/不可用输出空 → 调用方零行降级) |
| `_ff_profile_dir()` | _browser_detect (解析 profiles.ini `Default=1` + `IsRelative`, 失败回退 `*.default-release` glob; 失败输出空) |
| `_ff_query()`      | _ff_history, _ff_bookmarks, _ff_best_match (`sqlite3 -separator \x1f "file:<db>?immutable=1"` 只读, 缺库/缺 sqlite3 时空输出返回 0 且无 stderr) |
| `_ff_history()`    | _load_browser_rows (frecency 降序 500 封顶, hidden/visit=0/非 http 过滤; 标题 SQL 层清洗换行/制表/\x1f — read 按行读, bash 层洗已太晚) |
| `_ff_bookmarks()`  | _load_browser_rows (type=1 join 全量, 书签 title 优先, 同上清洗) |
| `_ff_best_match()` | _handle_input (关键词 LIKE 转义后取 frecency 最佳 url, 无命中输出空) |
| `_load_browser_rows()` | _list_hist/_list_bm (检测串 → `_hist_rows`/`_bm_rows` 三元组 `title\x1furl\x1fhost` + `_browser_hosts`; 空标题回退 url) |
| `_print_browser_rows()` | _list_hist/_list_bm ($1=info 前缀 hist\|/bm\|, 其余=三元组; favicon 命中附加 icon 属性) |
| `_dispatch()`      | _main (RETV=1 透参; info=new → _new_link, new-searcher → _new_searcher, browse-hist/bm → _list_hist/_list_bm (有输出 → rofi 原地刷新), back → _list, `hist\|*`/`bm\|*` → _open_url 直接打开, `searcher\|*` → _select_searcher (自带 key 直搜, 无 key 异步 module_input 取词), 否则按 id 打开) |
| `_open_url()`      | _open_by_id, _handle_input, _dispatch (hist\|/bm\| 分支; xdg-open 后台执行, 外部程序必须 `( cmd & )` 否则 rofi 等待其输出; 空串守卫) |
| `_open_by_id()`    | _dispatch (jq 查 URL → _open_url)                                      |
| `_handle_input()`  | _main (RETV=2; 先按 ROFI_DATA 上下文补前缀 (hist/bm 子菜单内裸词自动补 `^`/`*`, 显式 ^/*/@ 不变); `^`/`*` 开头 → 剥前缀实时查历史/书签最佳命中并打开, 无关键词 no-op, 无命中/非 firefox 则整串(含前缀)落到下述搜索; is_url ? 补协议打开 : 搜索引擎搜索; 首 token `@key` 精确匹配(忽略大小写, key 优先+name 回退)命中 searcher → 用目标引擎, 未命中/无 @ → 默认 searcher[0], searcher 数组为空回退 SEARCH_ENGINE; 仅 `@key` 无搜索词不打开) |
| `_build_search_url()` | _handle_input (jq @uri 编码搜索词替换 `{key}`; 无 `{key}` 追加 url 末尾; bash 参数展开花括号须转义 `\{key\}`) |
| `_searcher_entry_by_key()` | _edit_searcher, _delete_searcher (key 优先+name 回退, 忽略大小写; 命中输出紧凑 JSON) |
| `_searcher_url_by_key()` | _select_searcher, _select_searcher_form, _handle_input (key 优先+name 回退, 忽略大小写; 未命中输出空) |
| `_interact_async()`| _edit_link, _delete_link, _new_link, _new_searcher, _edit_searcher, _delete_searcher, _select_searcher (后台子 shell 等 rofi 退出释放 grab 后执行命令 — script mode 下 rofi 存活期间 grab 键盘, 须先让 rofi 退出) |
| `_write_json()`    | _ensure_ids, _edit_form, _delete_form, _new_form, _new_searcher_form (jq 表达式原子写回 CONFIG: 唯一 tmp + mv, 避免并发写 .tmp 冲突) |
| `_edit_link()`     | _main (RETV=10; `hist\|*`/`bm\|*`/browse-*/back/searcher\|* 只读/导航/searcher no-op (searcher 走 _edit_searcher); 否则按 id 预填数据 → _interact_async _edit_form) |
| `_edit_form()`     | _interact_async (表单录入 + 按 id 替换写库, 保留 id)                   |
| `_delete_link()`   | _main (RETV=3/11; `hist\|*`/`bm\|*`/browse-*/back/searcher\|* 只读/导航/searcher no-op (searcher 走 _delete_searcher); 否则按 id 取名字 → _interact_async _delete_form) |
| `_delete_form()`   | _interact_async (module_confirm 确认后 jq 删除 + notify)               |
| `_edit_searcher()` | _main (RETV=10 searcher\|* 分支; 按 key 忽略大小写定位 (含 name 回退) → _interact_async _edit_searcher_form) |
| `_edit_searcher_loop()` | _new_searcher_form, _edit_searcher_form (searcher 专属三字段 Key/Name/URL 录入 + 非空/URL 校验循环; 白名单/判重由调用方单次判定) |
| `_edit_searcher_form()` | _interact_async (三字段录入 + 白名单 + key/name 各自忽略大小写撞名校验 (自身放行) + 按旧 key 忽略大小写替换写库, 保序) |
| `_delete_searcher()` | _main (RETV=3/11 searcher\|* 分支; 按 key 忽略大小写定位 (含 name 回退) → _interact_async _delete_searcher_form) |
| `_delete_searcher_form()` | _interact_async (module_confirm 确认后 jq 忽略大小写删除 + notify) |
| `_select_searcher()` | _dispatch (searcher\|* 分支; 一律 _interact_async _select_searcher_form (RETV=1 行文本不可解析); 有词搜索走 RETV=2) |
| `_select_searcher_form()` | _interact_async (module_input 取词, 取消/空词 no-op, 否则用该引擎搜索) |
| `_searcher_name_valid()` | _new_searcher_form, _edit_searcher_form (key 白名单 `^[A-Za-z0-9_-]+$`, searcher 专属; 判 key 用) |
| `_new_link()`      | _dispatch (info=new; → _interact_async _new_form)                      |
| `_new_form()`      | _interact_async (剪贴板 URL 预填 + 表单校验 + jq 追加; clipboard_url 须在此执行 — xclip 可能阻塞, 不能留在 rofi grab 存活期间) |
| `_new_searcher()`  | _dispatch (info=new-searcher; → _interact_async _new_searcher_form)    |
| `_new_searcher_form()` | _interact_async (三字段录入 + 白名单 + jq 追加 `{key,name,url}`; key 非法/撞名或 name 空/撞名 (各自忽略大小写) → critical notify 拒绝, 不写入) |
| `_edit_loop()`     | _edit_form, _new_form (links 两字段表单录入 + 校验循环; 第三参 url_label 自定义 URL 字段标签; searcher 走专属 `_edit_searcher_loop`) |
| `clipboard_url()`  | _new_form (剪贴板严格 URL 校验, 无效静默返回非 0)                      |
| `_gen_id()`        | _ensure_ids, _new_form (uuid 优先, base64 fallback)                    |
| `_ensure_ids()`    | _list (全部有 id 时零写入早退, 仅缺 id 时全量重生成)                    |
| `_load()`          | _list/_list_hist/_list_bm (构建 `_links` 四元组数组 `name|id|url|host`, host 一次性提取复用, 避免每次 fork python3) |
| `_host_from_url()` | _load (纯 bash 参数展开提取 hostname, 零子进程; 结果写 `$_HOST` 全局变量而非 stdout — 避免 `$()` 命令替换 fork, _load 循环每行一次约省 40ms/64 条) |
| `_fetch_favicon()` | _ensure_icons (① 页面 HTML 解析 link rel=icon 真实 favicon (优先标准 rel=icon 排除 apple-touch 白底大图), 相对路径拼接 host → ② 降级链 DuckDuckGo→Google s2→站内 /favicon.ico; curl 带浏览器 UA 防 429 限流 + 超时 + file MIME 校验 image/* + tmp/mv 原子写; 全失败写 .fail 标记) |
| `_dl_icon()`      | _fetch_favicon (curl 下载到文件 + file MIME 校验 image/*, 失败返回 1) |
| `_icon_href()`    | _fetch_favicon (从 HTML 提取 icon link 的 href, 第二参排除子串如 apple-touch) |

### dwm-windowhook.sh (dwm open/close 调起, env: ACTION/WID/CLASS/TITLE/TAGS/MON)

| 函数 | 调用者 |
| ---- | ------ |
| `handle_refresh_mail()` | windowhook_dispatch 经 WINDOWHOOK_RULES (后台子 shell source dwm-status-tools.sh 调 update_mail; 缺 mail.json/jq/curl 静默跳过) |
| `windowhook_dispatch()` | 主流程 (顶层, `WINDOWHOOK_NO_DISPATCH=1` 时跳过以便测试 source) / tests/windowhook_test.sh |

> 规则表一行三列 `"<action>|<trigger-spec>|<handler>"` (pipe 分隔,
> 首/末 `|` 切分, `cmd:` 里可含 `||`); action 精确预过滤 (`*` 通配) 与 trigger 是 AND;
> trigger-spec 两形式: `func:<名>` 调函数, `cmd:<条件>` eval;
> 加新事件 = 加一行 (+ 按需写函数), 不动分派循环。
> 分派语义: 顺序遍历、全命中全执行, `declare -F` 守卫缺失函数,
> 未知 spec 前缀一律 fail-closed 跳过, 恒返回 0。

### tools/lock.sh

| 函数                  | 调用者                                                       |
| --------------------- | ------------------------------------------------------------ |
| `_lock_before()`      | lock() / suspend() → 所有 powermenu 脚本 — 现取 mpd 快照并暂停; 逐 sink `pactl set-sink-mute 1` (记录 `muted_sinks`, 跳过本已静音的); STOP mpv/xwallpaper; 末尾 `_restore_gamma`。**不能用 amixer Master**: 它只作用于 ALSA 默认控制卡 (本机卡 3), 实际 sink 可能是 Fosi USB DAC (卡 1, 只有 PCM) / HDMI (卡 2) / `easyeffects_sink` → 锁屏后仍出声 |
| `_restore_gamma()`    | _lock_before — 所有活动输出 `xrandr --brightness 1.0` (幂等兜底): 压暗通知器被异常终止时防止停在暗屏; 本仓库不用 gamma 做亮度, 与 theme.sh 的硬件亮度插值互不干扰 |
| `_lock()`             | lock() / suspend() → 所有 powermenu 脚本 / screen.sh(LOCKER) — 先武装 `xset dpms 30 30 30` 再起 `i3lock -n` (DPMS 只在锁屏期存在, 每次输入自动重置计时, 故唤醒后 30s 再灭; 无需轮询)。**`-n` 不可删**: i3lock 默认 fork, 父进程立刻退出会让 `lock()` 的 `wait` 立即返回 → `_lock_after` 在锁屏期间执行 (静音/DPMS 被立刻还原, 表现为锁屏后照样出声) |
| `_lock_after()`       | lock() / suspend() → 所有 powermenu 脚本 — 只还原 `muted_sinks` 里本次静音的 sink (用户原本静音的不动), 恢复 mpd/xwallpaper, 末尾 `xset dpms 0 0 0` 收回 DPMS。**幂等** (`lock_restored` 守卫): 正常解锁与信号 trap 都会调, 重复执行会把 mpd 再 toggle 一次 |
| `lock()`              | screen.sh 的 LOCKER (经 xss-lock 调起, 阻塞到解锁) / `lock.sh lock` CLI — `_lock_before` 后挂 `trap '_lock_after' TERM INT HUP`, 正常解锁后 `trap -` 卸掉: `loginctl unlock-session`/外部 kill 不会走 `wait` 之后的还原, 靠 trap 兜底 (否则 sink 一直静音、xwallpaperd 停在 STOP) |
| `suspend()`           | `lock.sh suspend` CLI                                        |

> `_screen_lock_loop()` 已删除: DPMS 超时在锁屏期自身会因输入重置计时, 轮询 + `xdotool key Escape` 强制 standby 是多余的 (也是"唤醒 30s 又灭"体感的来源)。`xprintidle`/`xdotool` 不再是 lock.sh 依赖。

### tools/screen.sh

| 函数 | 调用者 |
| ---- | ------ |
| `_screensaver_start()` | daemon (启动 + 每轮 xss-lock 存活检查) — 清理残留 `xautolock`; 缺 `xss-lock` 且无存活实例 → 告警一次并返回 1; 否则 `xset s (600-预告) 预告` (预告=0 或越界退化为 `xset s 600 0`) + `xset s noblank` + `xset dpms 0 0 0` (解锁态不灭屏); 武装后 `pgrep -x i3lock \|\| xset s reset` (空闲计数归零: 否则 xss-lock 在长空闲中重生会立刻锁屏; 锁屏中绝不能 reset, 那等于强制解除 → xss-lock 杀 locker); 末尾 `_ensure_xss_lock` |
| `_ensure_xss_lock()` | _screensaver_start + **daemon 每轮** — 配置指纹 (`/tmp/dwm-status/screen-arm.fp`, 可被 `SCREEN_ARM_FILE` 覆盖) 与存活实例对账: 一致且存活 → 零操作; 变化/缺失 → 写指纹并拉起 `xss-lock -n "/bin/bash <self> notifier" -- lock.sh lock`; 重启前 `pkill` + 轮询 ≤2s 等旧实例退出 (否则新实例 `SetAttributes` 失败直接退出) |
| `_effective_warn()` | _screensaver_start, _ensure_xss_lock — 实际生效的预告秒数: `warn_seconds` 在 `(0, screen_saver_time)` 内才返回, 否则 0 (关闭预告) |
| `_rearm_deferred()` | _ensure_xss_lock — 不能重启 xss-lock 的两个状态: **锁屏中** (重启会让 xss-lock `exit_service` SIGTERM 掉 i3lock → 直接解锁) / **压暗中** (会杀掉 notifier, 本轮提示丢失); 推迟到状态结束后由 daemon 每轮补 |
| `_active_outputs()` | _set_screen_gamma, _notifier — 解析 `xrandr --query` 的 ` connected ` 行, 取带几何 (`WxH+X+Y`, 位置不固定故逐字段扫) 的输出名; connected 但未启用 (如未接线的 eDP) 与 disconnected 跳过 |
| `_set_screen_gamma()` | _notifier, _dim_stop — 对每个活动输出 `xrandr --output X --brightness <level>` (gamma 倍率, 不动硬件亮度) |
| `_dim_stop()` | _notifier 的 HUP/INT/TERM/EXIT trap — 幂等 (`_dim_done` 守卫): kill 驻留 `sleep`, 全部输出还原 `--brightness 1.0` |
| `_notifier()` | `screen.sh notifier` 子命令 (xss-lock -n 拉起, 独立进程) — 无 xrandr/无活动输出 → 直接返回 0 (绝不影响锁屏); 否则压暗 `dim_gamma`(0.4), `sleep 2147483647 & wait` 驻留 (前台 sleep 会把 trap 推迟到睡醒) |
| `_has_active_audio()` | _inhibit_poke — parec 采 sink.monitor 150ms → ffmpeg volumedetect, max_volume > -78 dB 视为有声 |
| `_inhibit_poke()` | daemon 每 `duration`(20s) — 已锁屏则跳过; 有声时 `xset s reset` 把空闲计数压回 0 (抑制不拆计时器, 解除后从 0 重新计时), 状态翻转时按 `SCREEN_DEBUG_NOTIFY` 通知 |
| `daemon()` | 主流程 (顶层分发 `daemon`; `SCREEN_NO_DAEMON=1` 时跳过以便测试 source) / tests/screen-lock_test.sh — 启动先 `_takeover`; 每轮: xss-lock 存活 → `_ensure_xss_lock` 对账 (补齐被推迟的重新武装), 缺失 → `_screensaver_start`; md5 变化时 `exec /bin/bash "$SELF" daemon` **原地重启 (pid 不变)**, 轮询间隔 `SCREEN_TICK`(默认 20s) 仅供测试缩短 |
| `_takeover()` | daemon 启动 — 单实例接管: `pgrep -f "$SELF"` 后按 `/proc/<pid>/cmdline` 只认 argv 恰为 `[/bin/bash, <self>]` 的旧 daemon (排除 `screen.sh notifier`), 且只杀**比自己早启动**的 (starttime 相同则比 pid, 避免两个新实例互杀); 保证热重启/双拉后只剩一个实例 |

> 顶层分发: `[ "${BASH_SOURCE[0]}" = "$0" ]` 时按 `$1` 走 `notifier` / `daemon` (默认)，被 source (测试) 时只加载函数。
> `xset s` 只是重设 timer (xserver `ProcSetScreenSaver` → `SetScreenSaverTimer`)，空闲判定仍基于 `LastEventTime`，故重复武装不会延长/缩短空闲时间 —— 这是“每次启动都对账”的前提。


### rofi/scripts/util.sh

| 函数           | 调用者                      |
| -------------- | --------------------------- |
| `icon()`       | lib-module.sh, wallpaper.sh |
| `toggleConf()` | wallpaper.sh                |
| `getConfig()`  | wallpaper.sh                |

### rofi/scripts/module.sh

| 函数                      | 调用者                                                      |
| ------------------------- | ----------------------------------------------------------- |
| `toggleApplication()`     | module.sh (handle_picom, handle_conky)                      |
| `handle_audio_output()`   | module.sh (pactl sink 切换子菜单 → notify-send)             |
| `handle_theme()`          | module.sh (Theme 子菜单 → rofi/scripts/theme.sh)            |
| `handle_yt_dlp_wrapper()` | module.sh (YT-DLP Wrapper → rofi/scripts/yt-dlp-wrapper.sh) |
| `handle_steam_workshop()` | module.sh (Steam Workshop → rofi/scripts/steam-workshop.sh) |
| `handle_xcolor()`         | module.sh (Color Picker → xcolor + xclip + dunstify)        |
| `handle_wallpaper()`      | module.sh (Wallpaper → rofi/scripts/wallpaper.sh)           |
| `handle_touchpad()`       | module.sh (Touch Pad → tools/touchpad.sh toggle)            |

### tools/touchpad.sh

| 函数      | 调用者                                 |
| --------- | -------------------------------------- |
| `status()` | module.sh (注册表 `toggle-raw` 图标状态) |
| `toggle()` | module.sh (handle_touchpad)            |

### rofi/scripts/lib-module.sh

外部 theme-str 数组 (追加在内置 `-theme-str` 之后、`-theme` 之前, 覆盖 rasi 定义, 可选不设):
`MODULE_THEME_STR`(主菜单 `_module_rofi`) / `MODULE_SUB_THEME_STR`(`module_sub_rofi`) / `MODULE_INPUT_THEME_STR`(`module_input`) / `MODULE_MULTI_THEME_STR`(`module_multi_rofi`); 展开经 `_module_theme_str_args` (nameref 数组 → `-theme-str` 参数对, 未设置零开销). 测试 `tests/lib-module_test.sh`.

| 函数                  | 调用者                                                                                                                                                                                                                                                                                               |
| --------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `module_parse()`      | module.sh, sddm.sh, screenshot.sh, media-scraping.sh, screencast.sh, theme.sh, yt-dlp-wrapper.sh, wallpaper.sh, scrcpy.sh, mpd.sh (读取注册表)                                                                                                                                                                          |
| `module_loop()`       | module.sh, sddm.sh, screenshot.sh, media-scraping.sh, screencast.sh, scrcpy.sh, wallpaper.sh (while 循环持续调用, ESC 退出), theme.sh, yt-dlp-wrapper.sh (主循环, 唯一入口) |
| `module_sub_rofi()`   | module.sh (handle_network, handle_bluetooth, handle_audio_output 的子菜单), sddm.sh (handle_set_theme, handle_set_config 的子菜单), scrcpy.sh (handle_lan_scan 的子菜单), wallpaper.sh (monitor_selection / handle_group 的子菜单), sing-box.sh (主菜单), yt-dlp-wrapper.sh (格式/清晰度子菜单) |
| `module_input()`      | yt-dlp-wrapper.sh (URL 输入框), wallpaper.sh (handle_group 组名输入), scrcpy.sh (handle_wireless_connect/pair 地址+码输入, handle_lan_scan 配对码输入经 _pair_with_addr)                                                                                                                                                                 |
| `module_multi_rofi()` | wallpaper.sh (handle_group 组成员多选)                                                                                                                                                                                                                                                               |
| `module_confirm()`   | quicklinks-mode.sh (_delete_link Alt+2 删除确认) |

### rofi/scripts/dunst-menu.sh

> 无函数 (线性脚本)。stdin 每行 `#<label> (<notification summary>) [<id>,<key>]`
> 或裸 URL; 选中后必须原样回传整行 (dunst 靠行尾 `[id,key]` 派发 action)。
> 显示为 `<label> <key>`: label 保留 (常是图标字形/动作名), key 裸跟在后面
> (不加括号), summary 丢弃; 空 label 只显示 key; 跨通知完全同名时补 ` #<id>`。
> 经 `rofi -dmenu -format i -no-custom` 的 0 基序号回映射; 空 stdin / ESC 均
> 静默退出 0。主题 `applets/type-2/style-2.rasi`, 运行时 theme-str 覆盖为
> 窗口 800px / `element{padding:20px 5px}` / `element-text{JetBrains Mono 12}`
> / inputbar 只留 `textbox-prompt-colon` (隐藏 entry)。回归测试 `tests/dunst-menu_test.sh`。

### rofi/scripts/media-scraping.sh (顶层 `while module_loop` + `MEDIA_SCRAPING_NO_DISPATCH=1` 测试缝)

| 函数            | 调用者                                                       |
| --------------- | ------------------------------------------------------------ |
| `_docker_service_active()` | _toggle / _docker_start / _docker_stop_if_idle / _is_running (`systemctl is-active --quiet docker.service`, daemon 存活的唯一判据) |
| `_docker_start()` | _toggle up 分支 (未运行 → `systemctl start docker.service` 单 unit 调用, Type=notify 返回即就绪无需轮询; **stderr 捕获进通知**, 失败 critical 并中止不调 `launch.sh up`; 成功 normal) |
| `_docker_stop_if_idle()` | _toggle down 分支 (`launch.sh down` 之后: service 仍 active 且**全局** `docker ps -q` 计数为 0 → `systemctl stop docker.socket` **单 unit** 调用; 停 socket 即连带停 service (`Requires=docker.socket`), 且避免"只停 service 时 socket 仍活着会被重触发"; 兜底再查 `_docker_service_active` 单独停 service。**一条 systemctl 只能带一个 unit**, 多 unit 会被 polkit 直接 Access denied, 见已知问题) |
| `_toggle()`     | media-scraping.sh (daemon 未运行时跳过 probe 直接走 up 分支; any running → down + `_docker_stop_if_idle`, 否则 `_docker_start` + up) |
| `_is_running()` | media-scraping.sh (Open 前检查容器状态, Toggle 图标状态检查) — 先 `_docker_service_active` 门禁: daemon 停着直接 rc=1 且不 spawn docker (不唤醒 socket, 也省掉每个菜单构建 ~10 次必然失败的调用) |

### rofi/scripts/mpd.sh

| 函数                | 调用者                                            |
| ------------------- | ------------------------------------------------- |
| `fetch_cover()`     | mpd.sh (主流程 else 分支: 拉取当前歌曲封面 → icon-cover 注入) |
| `_mpd_readpicture()` | fetch_cover (单次 readpicture 请求, nc 优先 /dev/tcp fallback) |
| `_cover_valid()`    | fetch_cover (成功校验), mpd.sh 主流程 (cache 命中校验) — 非空 + `file` MIME `image/*`; 空/损坏文件视为无效, 失败时 `rm -f` 删除避免残留空缓存 |
| `_ensure_mpris_bridge()` | mpd.sh 主流程 (MPD 就绪后按 `_mpris_override_action` 结果 `systemctl --user start\|restart mpdris2-rs.service` (Type=dbus 等总线名就绪, start 幂等); 未安装英文 notify 不中断; kill 侧在 `dwm-statuscmd.sh [$ST_MPD,$middle]` (`systemctl --user stop mpdris2-rs.service mpd.service`, 先桥后 MPD, 幂等)) |
| `_mpris_override_action()` | _ensure_mpris_bridge (通知模板 `MPDRIS2_NOTIFY_ARGS` 为 repo 源 → 生成 `$XDG_CONFIG_HOME/systemd/user/mpdris2-rs.service.d/override.conf`: `ExecStart=` 重置 + 完整 argv, `%` 转义为 `%%`、真实换行转 `\n`; 内容未变输出 `start` 零写入, 变化才写 + `daemon-reload` 并输出 `restart`; 写失败按未变处理不挡菜单) |
| `_have_mpris()` | _ensure_mpris_bridge, _notify_song (共用: `command -v mpdris2-rs` 检测桥是否安装) |
| `_notify_song()` | handle_play_pause/prev/next (有桥直接返回靠 MPRIS 通知, 无桥手动 notify-send 兜底, 避免无桥时切歌静默) |
| `_osd_running()` | _osd_on, handle_osd_lyrics (`pgrep -x osdlyrics`) |
| `_osd_on()` | mpd.sh 主流程 (菜单高亮索引 7), handle_osd_lyrics — 经 `busctl --user` 读 `General/display-mode-osd` (`b true`); 进程未运行直接返回 1, 不触发 Config 服务自动激活 |
| `_osd_set()` | handle_osd_lyrics — `busctl --user ... SetBool` 写 `General/display-mode-osd` (`true`/`false`) |
| `_osd_wait_daemon()` | handle_osd_lyrics 冷启动分支 — 轮询 `busctl --user status org.osdlyrics.Daemon` (100ms × ≤50, 实测 ~300ms), 等 Daemon 就绪后再写配置 |
| `handle_osd_lyrics()` | mpd.sh 注册表 `osd-lyrics` — 运行中翻转 OSD (应用留在托盘); 未运行先 `setsid -f osdlyrics`, 等 Daemon 就绪后再置 `true` (顺序不可反, 见已知问题); 未安装/调用失败走 notify |

> 封面注入: 用 rofi `icon` widget (`icon-cover`, `filename` + `size: 200` + `squared` 默认 true 强制 1:1 正方形) —
> 不能用 `imagebox`: 它不是真实 widget (rofi 静默当 `box`), `height` 属性被忽略 (box_get_desired_height 只累计 children),
> 无法保证 1:1。cache 按歌曲 uri cksum 命名放 `~/.cache/dwm/mpd-cover/`, 命中复用不重复拉取。
> 校验: 主流程 cache 命中判断 `_cover_valid` (不存在/空/损坏均视为 miss) → `rm -f` + 同步拉取 (`fetch_cover` 已优化 ~50ms, 原 `( ... & disown )` 后台异步已移除); 拉取失败回退 `rofi/images/flowers-2.png` 默认图 (透明背景 Nerd Font flowers 图标)。fetch_cover 失败同样删除输出, 不留空文件。

### rofi/scripts/scrcpy.sh (顶层包 main() + `SCRCPY_NO_DISPATCH=1` 测试缝, 抄 dwm-windowhook.sh 先例)

| 函数 | 调用者 |
| ---- | ------ |
| `_mdns_scan()` | handle_lan_scan (局域网 mDNS 发现, 输出 `name\|type\|addr`; `mdns check` 失败返回 1) |
| `_short_serial()` | _get_devices / handle_lan_scan (显示用短 id: 去 `adb-` 前缀和 `._adb-tls-connect._tcp` 后缀) |
| `_filter_dup_devices()` | main() (`_get_devices` 后过滤: 同一手机的手动 `ip:port` + 自动 `name._tcp` 两个 entry 按 `ro.serialno` 分组, 只留手动连的行; 拿不到序列号的不合并) |
| `_device_friendly_name()` | _get_devices (无线设备行), _connect_addr (成功通知) (`settings get global device_name` → `getprop ro.product.model` 回退, `timeout 3` 防挂, 拿不到返回空; 脚本内所有 adb 调用一律 `</dev/null`——adb 会偷读 `while read` 的 stdin 吞掉后面的行) |
| `_connect_addr()` | handle_lan_scan (connect 分支), handle_wireless_connect (`adb connect` + 通知 + `_connect`) |
| `_pair_with_addr()` | handle_lan_scan (pairing 分支, 跳过地址输入直问码), handle_wireless_pair (手动地址分支) (pair 成功后按同 IP 的 connect 广播直连 / 配对期间新出现的无线设备直起 (恰好一个才用) / 已在列表的同名设备直起 / 都没有才回退手动输入) |
| `handle_lan_scan()` | scrcpy.sh (`lan-scan` 注册表行 → 二级子菜单裸 `addr` (只列 pairing 广播, connect 对未配对设备鉴权必失败) → 配对码 → 同 IP 直连/已连直起/回退手动) |
| `main()` | 主流程 (顶层, `SCRCPY_NO_DISPATCH=1` 时跳过以便测试 source; `while` 循环持续交互, `_connect` 成功置 `_quit` 退出, ESC 退出) / tests/scrcpy-lan-scan_test.sh |
| `_build_menu()` | main() 每轮调用 (组菜单 + 派发 handler, 状态实时重建) |
| `_display_rotation()` | _swipe (只信 displayId 0 的 `mOverrideDisplayInfo` 行: `, app W x H,` 判宽高 → `rotation N` → 老格式兜底, 拿不到回 0; mBase/displayShape 是静态值不可信) |
| `_swipe()` | _watch_scrcpy_keys (单指滑动注入: `adb shell input swipe`, up/down 横向居中、纵向 25%~75%, back 左边缘 x 5%→40%/y 50%, 均 200ms; `wm size` 取 Override 优先, 每次按键现取以适配分辨率; `wm size` 是自然方向尺寸不随旋转变化, 经 `_display_rotation` 判 1/3 横屏时交换 w/h (否则横屏发 y 越界坐标被系统忽略); 无快捷键的 scrcpy 官方明确拒绝手势类 shortcut, 详见下) |
| `_watch_scrcpy_keys()` | _connect (后台 per-device 监听: 轮询 `xdotool search --all --onlyvisible --pid <scrcpy pid> --class scrcpy` 定位窗口 → `xev -id <wid>` 只收该窗口的 KeyPress/KeyRelease → 按顶部 `SCRCPY_KEYMAP` (默认 Up=下滑/Down=上滑/Left=返回) 匹配 xev 的 keysym 名 → `_swipe`; 窗口未聚焦时收不到事件, 故无需全局热键/手机端 App; 带 Ctrl/Alt/Super 的组合跳过 (state 掩码 `~0x13`, 让 Alt+方向 留给 scrcpy 音量); coproc `exec xev` + `read -t 2` 轮询 scrcpy pid 兜底退出; latch 抑制自动重复; pid 文件由监听自身写, 退出时仅当仍指向自己才删; `_disconnect` 按 `/tmp/scrcpy_keys_<serial>` 杀掉监听) |

> 短视频上下切换 + 左划返回: 起 scrcpy 后按 **Down = 下一个 / Up = 上一个 / Left = 返回 (左边缘右滑)** (键位在脚本顶部 `SCRCPY_KEYMAP` 映射表改, 如 `[Down]=up`)。实现要点:
> ① `xdotool search` 默认 `--any`(多条件 OR), 必须加 `--all` 否则 `--pid` 不生效会选到别的 scrcpy 窗口;
> ② `xev -id` 是对目标窗口**额外**选一份事件掩码, 不抢占事件(scrcpy 照常收到按键), 也不需要 XGrabKey;
> ③ 按键只在该窗口聚焦时送达, 天然限定作用域。scrcpy 出于可靠性拒绝把手势做成 shortcut(issue #4828), 故由启动脚本旁路 `adb input swipe` 注入。

### tools/theme.sh

| 函数                      | 调用者                                                                                                                                           |
| ------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------ |
| `_do_theme_change()`      | tools/theme.sh (apply / auto_daemon; 第二参 `nobright` 跳过一次性端点亮度) — daemon 翻转只切配色，亮度由每轮插值统一负责；手动 apply 保留端点亮度 (apply 后 auto 关闭)；末尾调 restart_snixembed (与 set_fcitx5_theme 同级) |
| `restart_snixembed()`     | _do_theme_change (切主题时若 PATH 有 snixembed 则 `launch restart snixembed`, 让它用新前景色重绘 symbolic 图标; 其余托盘程序 (nm-applet/pasystray/udiskie) 图标色来自 icon 主题, 由 set_gtk_theme 广播 `Net/IconThemeName` 后 GTK 即时重载, 无需重启) |
| `set_monitor_brightness()`| tools/theme.sh (_do_theme_change 非 nobright 路径, **同步**执行 — 后台化会让慢 job 用旧主题亮度覆盖新主题, 见下) — 逐 active monitor 读配置 `brightness.<monitor>` (per-monitor 独立), 缺失/非数字/>100 fallback 50, 经 set_brightness 分发 (eDP → brightnessctl, 其他 → ddcutil setvcp) |
| `_brightness_curve()`     | _brightness_at (插值曲线单点封装，milliscale cubic warp 两头快中间慢，起止约 2 倍速、中段约 0.5 倍速；太阳高度方案以后只换它) |
| `_brightness_at()`        | _monitor_brightness_at (经 _brightness_curve 缓动后 from→to 插值，duration≤0 取 to，elapsed 越界钳制) |
| `_transition_minutes()`   | auto_daemon (读 `auto.dawn/dusk_minutes`，缺失/非法→60，0=关闭渐变) |
| `_normalize_anchor()`    | _transition_anchor, _window_at, _monitor_brightness_at (锚点归一化: after/center/before, 非法→after; 三处复用, 单一真实来源) |
| `_transition_anchor()`    | auto_daemon (读 `auto.transition_anchor` after/center/before，非法→after) |
| `_dawn_window()` / `_dusk_window()` | _monitor_brightness_at (过渡窗口起止；after 事件后窗口 / center 对称窗口 / before 事件前窗口，非法 anchor 回退 after) |
| `_theme_at()`             | auto_daemon, _monitor_brightness_at (二值主题判定，锚点无关，配色始终在 rise/set 翻转) |
| `_monitor_brightness_at()` | apply_transition_brightness (单 monitor 目标亮度：窗口内插值，窗口外取端点，dusk 重叠优先) |
| `_should_apply_at()` | apply_transition_brightness (是否写亮度谓词：窗口内含终点，或 duration=0 侧的二值对齐；窗口外返回 1) |
| `apply_transition_brightness()` | auto_daemon (只在过渡窗口内写各 monitor 插值亮度，窗口外不动——手动/OSD 调的不抢回；duration=0 的侧按二值对齐端点；与硬件值差<1 跳过，读不到直接写) |
| `_auto_lock()`            | auto_daemon (flock 非阻塞单实例守卫，锁路径 `${THEME_LOCK:-/tmp/dwm-status/theme-auto.lock}`；autostart 直起的 daemon 无 pid 文件，重复 `auto on` 靠此不重入；flock 缺失时 fail-open) / `auto on` 的 flock 探针 (子 shell 内试拿即放，锁被占=已有实例→直接复用不 spawn，避免死 pid 覆盖 pid 文件) |
| `set_gtk_theme()`         | tools/theme.sh (_do_theme_change: 写 gtk2/3/4 持久配置 (主题/icon/光标 theme+size, 源 `theme.json:cursor` + `.<mode>.cursor` 覆盖) + 运行时双通道广播 — xsettingsd GTK 主题名 + `Gtk/CursorThemeName/Size` / gsettings color-scheme 同步 portal + `cursor-theme/size`) |
| `set_qt_theme()`          | tools/theme.sh (_do_theme_change: `QT_QPA_PLATFORMTHEME=qt6ct` 写 `~/.xprofile` (幂等替换 gtk3 残留) + qt6ct/qt5ct `style=kvantum` + icon 跟随 `theme.json:icon` + Kvantum 主题跟随 `theme.json:qt` (light `Orchis-solid` / dark `Orchis-solidDark`, 缺键直接返回不写) + `kvantummanager --set` 即时生效) |
| `_ensure_ini_key()`       | set_qt_theme (ini 版 `_ensure_config_line`: 按 `[section]` 归属写键, 缺节补节; qt6ct/qt5ct `Appearance` + Kvantum `General` 三处复用) |
| `get_auto_config()`       | tools/theme.sh (auto_daemon, auto on/off, apply)                                                                                                 |
| `get_cursor_config()`     | set_dwm_theme, set_gtk_theme (光标 theme/size 按 mode 覆盖: `.<mode>.cursor.<key>` 优先, 缺失回退全局 `.cursor.<key>`; 回归 `tests/theme-cursor_test.sh`) |
| `get_sun_times()`         | tools/theme.sh (auto_daemon), rofi/scripts/theme.sh (get_sun_message → MODULE_MESG 日出日落显示; 内置 `~/.local/state/dwm/cache/sun-times` 缓存) |
| `auto_daemon()`           | tools/theme.sh (auto 守护进程循环)                                                                                                               |

### tools/monitor-brightness.sh

| 函数                 | 调用者                                                                                                                       |
| -------------------- | ---------------------------------------------------------------------------------------------------------------------------- |
| `get_brightness()`   | toggle_monitor (xrandr --verbose 读 Brightness)                                                                              |
| `toggle_monitor()`   | 无 (未绑定快捷键; state 文件 `~/.local/state/dwm/status/monitor-<output>` 持久化原亮度, 开/关切换置黑/恢复)                  |
| `get_ddc_bus()`      | monitor_brightness (xrandr CONNECTOR_ID ↔ ddcutil drm_connector_id 匹配整数总线号, DP 走 aux 总线不能直接读 ddc symlink; 文件缓存 bus (`~/.local/state/dwm/ddc-bus-<output>`, key 为 active 输出集合) — 单次 detect 约 1.6s 占过渡 tick 主导开销, 集合变化/文件损坏即失效, 失败不写; 必须用文件而非内存: 调用方经 $() 子 shell 调用, 内存写会丢失)      |
| `monitor_brightness()`| read_brightness/set_brightness (eDP 分支之外) — ddcutil setvcp 10 硬件亮度 (value 省略时 getvcp 读当前值)                     |
| `read_brightness()`  | tools/theme.sh (apply_transition_brightness 每轮读当前值比对), rofi/scripts/theme.sh (handle_monitor_brightness 选单读取 / OK 后读实际亮度) — 单块显示器当前亮度百分比: eDP → brightnessctl -m, 其他 → monitor_brightness getvcp |
| `set_brightness()`    | tools/theme.sh (set_monitor_brightness, apply_transition_brightness), rofi/scripts/theme.sh (handle_monitor_brightness) — 单块显示器亮度: eDP → brightnessctl set, 其他 → monitor_brightness setvcp |

### rofi/scripts/theme.sh

| 函数                        | 调用者                                                                               |
| --------------------------- | ------------------------------------------------------------------------------------ |
| `handle_toggle()`           | theme.sh (→ `tools/theme.sh apply light\|dark` 翻转)                                 |
| `handle_auto()`             | theme.sh (→ `tools/theme.sh auto on/off`)                                            |
| `handle_monitor_brightness()` | theme.sh (注册表 → 循环连续调节多显示器: yad 滑块经 FIFO+后台 pid 实时预览, OK 保存 theme.json / 取消恢复, 调完回到 monitor 选择处 ESC 退出; 亮度读写复用 monitor-brightness.sh 的 read_brightness/set_brightness; eDP 逐值即时, DDC 走 `read -t 0.03` drain 丢弃积压只应用最新值) |
| `handle_dawn()` / `handle_dusk()` | theme.sh (注册表 → `_handle_offset unsigned` 改 `auto.dawn/dusk_minutes`，非负整数，改后重启 auto daemon) |
| `handle_anchor()`           | theme.sh (注册表 → select 直选 `auto.transition_anchor` (after/center/before)，改后重启 auto daemon) |
| `get_sun_message()`         | theme.sh (调 `get_sun_times` → 格式化 MODULE_MESG; 网络失败则 fallback 为无时间后缀) |

### tools/yt-dlp.sh

| 函数             | 调用者                                                                   |
| ---------------- | ------------------------------------------------------------------------ |
| `yt_download()`  | yt-dlp.sh (CLI: audio/video/raw) / yt-dlp-wrapper.sh (source 后直接调用) |
| `extract_opus()` | yt_download() (audio 模式) / yt-dlp.sh (定义/CLI extra)                  |

### tools/steam-workshop.sh (无 rofi 依赖, CLI: parse/appid/users/download)

| 函数                | 调用者                                                                 |
| ------------------- | ---------------------------------------------------------------------- |
| `sw_parse_itemid()` | steam-workshop.sh `_go` (URL/纯数字 → itemid, 失败 critical 退出)      |
| `sw_fetch_page()`     | sw_resolve_appid / sw_item_info (统一 curl 入口, 纯数字 ID 自动拼 URL) |
| `sw_parse_field()` / `sw_parse_appname()` / `sw_parse_title()` | sw_item_info (纯解析，见上) |
| `sw_page_gated()` | steam-workshop.sh `_go` (登录门检测，手输 AppID 提示语区分) |
| `sw_short_error()` | steam-workshop.sh `_download` (rc=2 时 notify 附真实错误行，不再只给通用指令) |
| `sw_resolve_appid()`| steam-workshop.sh `_go` 兼容入口 (先 `?appid=` 参数零网络, 后抓页面) |
| `sw_api_info()` | sw_item_info (免 key WebAPI `GetPublishedFileDetails` 取 appid+标题, store `appdetails` 取 app 名; 登录门条目可用, 需 jq) |
| `sw_item_info()`      | steam-workshop.sh `_go` (一次抓页返回 `appid\|app名\|资源名`; 页面无 appid → WebAPI 兜底 → 都失败才手输) |
| `sw_list_users()`   | steam-workshop.sh `_pick_user` (解析 loginusers.vdf `AccountName\|PersonaName`, Timestamp 倒序; 0→anonymous, 1→直用, N→rofi 选) |
| `sw_safe_app()`     | sw_download (app 名去空格/非法字符作扁平首层应用部分, `.`/`..`/空回退 appid, 仍非法回退 `unknown`) |
| `sw_aurelia_roots()` | sw_aurelia_find (Steam 库根列表: `aurelia libraries -j` → `config show -j` 的 steam_library_path → 默认 `~/.local/share/Steam`/`~/.steam/steam`; 无 aurelia/jq 返回 1) |
| `sw_aurelia_find()` | sw_aurelia_download (按 `<appid>/<itemid>` 在库根下定位首个有内容的落盘目录) |
| `sw_flatten_download()` | sw_download / sw_aurelia_download (深路径→扁平共用: `mv` 到 `<隔离根>/<safe>_<appid>/<itemid>` + `rmdir` 回收到 stopdir 为止 + 删 acf (仅 stopdir==隔离根的 steamcmd 路径); mv/mkdir 失败返回 1) |
| `sw_aurelia_download()` | sw_download (aurelia 路径: `workshop install --no-recurse <itemid>` → `sw_aurelia_find` 定位 → `sw_flatten_download` (stopdir=`content/<appid>`, 库内不 prune); user 忽略, 走 aurelia 自身会话; 任何失败返回 1 由调用方 fallback, 无 jq 亦视为失败) |
| `sw_download()`     | steam-workshop.sh `_download` / `handle_update` 循环 (driver: `STEAM_WORKSHOP_DRIVER=auto`(默认) 且有 aurelia 时优先 aurelia, 失败落回 steamcmd; `=steamcmd` 强制老路; 签名/stdout/rc 语义不变, 调用方零改动; steamcmd 分支: 隔离根 `STEAMCMD_INSTALL_DIR`(兼容 `STEAM_WORKSHOP_DIR`, 缺省 `~/Downloads/steam-workshop`) 经 `+force_install_dir` 写入, 自动 `mkdir -p`; 按传入 user 一次 `+login <user>` (缺省 anonymous); 成功后经 `sw_flatten_download` 搬扁平并返回扁平路径; 非数字 appid/itemid 直接 rc=1 (两个 driver 都不调); 2=认证失败提示终端登录, 1=其他失败; aurelia 失败输出暂存仅 steamcmd 也失败时打出, 成功路径 stderr 保持干净 — 见已知问题 `sw_run_updates 2>&1`) |
| `sw_api_time()`     | sw_check_updates (单条 GetPublishedFileDetails 取 `appid\|time_updated`, 需 jq) |
| `sw_check_updates()` | steam-workshop.sh `handle_update` / auto (scope 为空=全部, 完整目录名精确匹配, 纯数字/app 后缀解析为 appid 后同 app 的 flat+deep 一并纳入; 枚举 flat 新/老式 + legacy 深, 非数字叶跳过;逐条 `sw_api_time` 比 `mtime`, 输出 `UPDATE\|…/CURRENT\|…/SKIP\|…` 排序行; 无候选或根非法返回 1) |
| `_sw_dir_appid()` | sw_check_updates (目录名 → appid 唯一来源: 纯数字直接用, 取 `_<digits>` 后缀, 否则空) |
| `sw_run_updates()` | sw_sync_updates (stdin UPDATE 行逐条 `sw_download`+删源, stdout `ok fail[ fids...]`, 只回显不 notify) |
| `sw_sync_updates()` | steam-workshop.sh `handle_update` 后台子 shell / auto (公共编排: `root [user] [scope...]` 逐 scope 检查合并 → 计数 UPDATE/CURRENT/SKIP → UPDATE 行喂 `sw_run_updates`; stdout 首行 `updates currents skips ok fail[ fids...]` + 明细 `OK\|itemid\|label`/`FAIL\|itemid\|label` (label=`父目录名/itemid` 纯本地推导, 如 `WallpaperEngine_431960/111`), 无候选返回 1, 只回显不 notify) |
| `sw_label_list()` | `handle_update` 后台子 shell / auto (`[OK\|FAIL]` + stdin 明细行 → `label[, …]` 最多列 10, 余 `(+N more)`; 只回显) |
| `sw_result_msg()` | `handle_update` 后台子 shell / auto (`ok ok_labels fail fail_labels` → `N updated[: …][, M failed[: …]]` 汇总文案; 只回显) |

### rofi/scripts/yt-dlp-wrapper.sh

| 函数                 | 调用者                                               |
| -------------------- | ---------------------------------------------------- |
| `_download()`        | yt-dlp-wrapper.sh 各 handler (后台下载 + notify)     |
| `_format_download()` | yt-dlp-wrapper.sh (_pick_resolution / handle_format) |
| `_pick_resolution()` | yt-dlp-wrapper.sh (handle_video / handle_clipboard)  |
| `handle_audio()`     | yt-dlp-wrapper.sh (模块主菜单: 下载音频)             |
| `handle_video()`     | yt-dlp-wrapper.sh (模块主菜单: 下载视频)             |
| `handle_clipboard()` | yt-dlp-wrapper.sh (模块主菜单: 剪贴板链接直接下载)   |
| `handle_format()`    | yt-dlp-wrapper.sh (模块主菜单: -F 自定义格式)        |
| `handle_open()`      | yt-dlp-wrapper.sh (模块主菜单: 打开下载目录)         |

### rofi/scripts/steam-workshop.sh

| 函数                 | 调用者                                              |
| -------------------- | --------------------------------------------------- |
| `_pick_user()`       | steam-workshop.sh `_go` / `handle_update` (0 用户→anonymous, 1→直用, N→`module_sub_rofi` 选 `acc — pers`, ESC 返回 1) |
| `_download()`        | steam-workshop.sh `_go` (后台下载 + notify: 标题 `资源名 — App名`, appname 透传 sw_download 作扁平应用部分; 0→Done+`Open folder` action (notify-send -A, 点击 `xdg-open` 落盘路径), 2→critical 终端登录指令, 其他→critical rc) |
| `_go()`              | steam-workshop.sh handle_download (parse→info→user→download 全链; 始终 `_pick_user` 选用户后下载) |
| `handle_download()`  | steam-workshop.sh (剪贴板合法直下, 否则 `module_input` 预填剪贴板供输入, 空输入返回) |
| `handle_update()`    | steam-workshop.sh (scope 子菜单 All/各 app → `_pick_user` 选用户 (gated 条目失败进 FAIL 名单) → Checking 通知 → 后台子 shell 内 `sw_sync_updates`(无候选提示 No downloads yet → 0 条提示 up-to-date → 有更新直接 Updating 通知再跑下载, 无 `module_confirm`), 成功且路径变化删源, 汇总成功/失败 id) |
| `handle_open()`      | steam-workshop.sh (建隔离根(失败 critical)后 `xdg-open`) |

### rofi/scripts/wallpaper.sh

| 函数                          | 调用者                                                  |
| ----------------------------- | ------------------------------------------------------- |
| `monitor_selection()`         | wallpaper.sh (主入口: 选择 monitor/组)       |
| `handle_next()`               | wallpaper.sh (模块主菜单: 下一张; `( tools/wallpaper.sh -m ... next & )` 后台执行, rofi 立即重开) |
| `handle_select()`             | wallpaper.sh (模块主菜单: 选择文件; `random_type=web` 时走 `select_marker_wallpaper` rofi 图文选择, 否则 yazi) |
| `select_marker_wallpaper()`   | handle_select (web 分支: `find_project_dirs` 按 type 枚举目录 → `project.json:title` 标题 + `project_preview` 缩略图 → `rofi -dmenu -format i -show-icons` 按索引回映射目录; 末条为 yazi 目录入口 (map 值 `__YAZI__`, Enter 经 `select_yazi_directory` 选目录, Alt+1/2/3 落其上忽略重显); Alt+1 xdg-open / Alt+2 复制绝对路径(无换行) / Alt+3 `module_confirm` 后 `rm -rf`, 动作后循环重显(删除后回模块菜单), Enter 应用, ESC 返回) |
| `select_yazi_directory()`   | select_marker_wallpaper (末条 yazi 入口: 起始于主题目录 (`get_theme_dir`+`expand_path`, 缺失回退 `$HOME`), 文件输入归一到上层, 经 `project_entry` 验入口 (web 认 `file` 字段回退 `index.html`), 非法 critical 通知, 成功经 `tools/wallpaper.sh -m file` 应用; 成功返回 0, 取消/非法返回 1 由调用方继续循环) |
| `handle_random_switch()`      | wallpaper.sh (模块主菜单: 随机开关 toggle)              |
| `handle_random_type()`        | wallpaper.sh (模块主菜单: 类型三选一 selector image/video/web，状态行显示当前类型图标) |
| `handle_random_duration()`    | wallpaper.sh (模块主菜单: 设置轮换间隔)                 |
| `handle_random_images_path()` | wallpaper.sh (模块主菜单: 选择图片目录)                 |
| `handle_random_videos_path()` | wallpaper.sh (模块主菜单: 选择视频目录)                 |
| `handle_random_web_path()` | wallpaper.sh (模块主菜单: 选择网页壁纸目录 → `random_web_dir`) |
| `handle_random_images_path_dark()` | wallpaper.sh (模块主菜单: 选择深色图片目录 → `random_image_dir_dark`) |
| `handle_random_videos_path_dark()` | wallpaper.sh (模块主菜单: 选择深色视频目录 → `random_video_dir_dark`) |
| `handle_random_web_path_dark()` | wallpaper.sh (模块主菜单: 选择深色网页壁纸目录 → `random_web_dir_dark`) |
| `handle_fps()` | wallpaper.sh (模块主菜单: 设置视频帧率上限 → `video-render.fps`, 0=不限; setter 仅写入新值时返回 0, `&&` 串联 `reapply_video_wallpaper` 即时生效) |
| `handle_property()` | wallpaper.sh (模块主菜单: web 可调属性 — `prop_tunables` 优先 `--list-properties --labels` (name/type/value/label 四列, 旧 CLI 回退三列并补空 label) 中 slider+color+file+bool+combo 行; 单属性直接调 `_apply_property` 后回主菜单, 多属性 `while` 循环停留在选择层 (ESC 回主菜单, 复用 theme.sh handle_monitor_brightness 模式, 每轮末重取 tunables 使列表显示新值); 选择列表显示第四列本地化 label (缺失回退 `prop_label` 读 `<dir>/project.json:text`, 目录由 `prop_wall_dir` 从 state 解析; label 重名时附 ` (name)` 区分; display line → name 关联映射回查; color 值显示为 hex 纯表现层); property 菜单窗口 600px (函数内 local, 不影响主菜单); slider: `prop_range` 读 `<dir>/project.json:general.properties.<name>.min/max` (非法 fallback 0..100), FIFO + `yad --scale --print-partial` 逐值 `xwallpaper --set-property`; color: `prop_color_hex` 转初始色 + `yad --color`, set 前 `prop_hex_to_rgb` 转回 triple; file: `prop_pick_file` (与 image/video select 同样的 yazi 选择器, 起始于壁纸目录, 当前值存在时用其所在目录); bool: 一键翻转直接 set, 无对话框; combo: `prop_combo_options` 读 project.json options (对象数组用 value / 纯字符串数组用序号索引 / 数字 value 原样, 缺失回退 `module_input` 自由输入), rofi 显示 options label 全串 (label 碰撞才加 ` (value)` 区分) → set value (当前值标 ✓); color 经 `prop_commit_once` OK 单次应用 / 取消恢复原值, file 选中即单次 set / 取消恢复原值 (yad 无 partial, `--changed-action` 仅 CHK/CB/SW 有效); image/video 无 props 与 group/Screen (`-m` 无法寻址 -g 窗口) 通知返回) |
| `handle_property_reset()` | wallpaper.sh (模块主菜单 Reset Property + 多属性选择循环内 `󰜉 Reset to defaults` 行, 共用 `prop_reset`: 有 tunables 才 `module_confirm` 确认 → `xwallpaper --clear-properties -m` 回 project.json 默认, 成功/失败分别 notify; 循环内重置后重取 tunables 刷新列表) |
| `handle_group()`              | wallpaper.sh (模块主菜单: 组管理 — 新建/编辑/启停/删除) |

### tools/wallpaper-lib.sh

| 函数                         | 调用者                                                                                                                                                                                                       |
| ---------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `getConfig()`                | wallpaper.sh, wallpaper-lib.sh (内部)                                                                                                                                                                        |
| `get_theme_dir()`            | wallpaper.sh (random_wallpaper, select_wallpaper, theme_wallpaper) — 主题目录解析: light 用 base key, dark 用 `${base}_dark`, 为空 fallback base; theme 缺省经 `current_mode()` 读 current-theme |
| `current_mode()`             | wallpaper.sh (theme auto 解析、回写记忆) / wallpaper-lib.sh (get_theme_dir 缺省) — current-theme 归一化 light\|dark (缺失/非 dark 即 light); 与 theme.sh 的 `get_current_theme()` (原始值) 区分 |
| `get_last_wallpaper()`       | wallpaper.sh (theme_wallpaper 恢复记忆) — 读 `wallpaper-last.json` 中 `<target>.<mode>` 路径, 缺失/损坏输出空; mode 非 dark 按 light |
| `save_last_wallpaper()`      | wallpaper.sh (theme_wallpaper random 后、`-m next/select` 后、daemon 轮换后按 current-theme 回写) — jq 原子写回 (tmp+mv), 源缺失/损坏从 `{}` 重建 |
| `ensure_monitor_config()`    | rofi/scripts/wallpaper.sh (主入口选定 monitor 后初始化写入) — 遍历 `config` 数组写默认, 跳过 volume/fps (video-render 子对象默认) 与 random_depth (全局值) |
| `detect_file_type()`         | wallpaper.sh, wallpaper-render.sh — 目录一律 `page` (xwallpaper 已不支持 scene), 文件按扩展名 image/video/page |
| `get_video_dim()`            | wallpaper.sh (get_wallpaper_rotation) — 单次 ffprobe 合并取 dims+rotation (csv 第三列), 原两次独立调用省一半耗时                                                                                                                                                                        |
| `orientation_mismatch()`     | wallpaper.sh (get_wallpaper_rotation)                                                                                                                                                                        |
| `get_monitor_dim()`          | wallpaper.sh (get_wallpaper_rotation)                                                                                                                                                                        |
| `preview_rotation()`         | wallpaper.sh (get_wallpaper_rotation)                                                                                                                                                                        |
| `find_wallpapers()`          | wallpaper.sh (random_wallpaper image/video 池) — 入口经 `expand_path` 展开 `~`/`$VAR`, `~` 写法直接可用 |
| `project_type()`             | wallpaper-lib.sh (find_project_dirs 过滤内部) — `project.json:type` 小写输出，无文件/损坏/缺字段返回 1 |
| `project_preview()`          | rofi/scripts/wallpaper.sh (select_marker_wallpaper 图标) — `preview` 字段优先 (存在才用)，回退 `preview.gif/png/jpg/jpeg/webp`，都无返回 1 (icon 置空不崩) |
| `project_entry()`            | rofi/scripts/wallpaper.sh (select_yazi_directory 校验), wallpaper.sh (select_wallpaper web 校验) — `file` 字段优先 (存在才用，含 `wallpaper.html` 反例)；回退 `index.html`；scene 遗留目录视为非法；非法返回 1 |
| `find_project_dirs()`        | wallpaper.sh (random_wallpaper web 池), rofi/scripts/wallpaper.sh (select_marker_wallpaper) — 枚举含 `project.json` 且 `type` 匹配 (大小写无关) 的目录，无匹配/根非法返回 1 (同 find_wallpapers 契约)；裸 `index.html` (无 project.json) 视为非法 |
| `expand_path()`              | wallpaper-lib.sh (find_wallpapers, find_project_dirs, pick_config_dir 读侧), wallpaper.sh (select_wallpaper 起始目录) — `envsubst` ($HOME/任意$VAR) + 仅行首 `~`/`~/...` (`~other` 按字面保留); 默认值已用 `~` 写法 |
| `shrink_path()`              | wallpaper-lib.sh (pick_config_dir 存盘前) — `expand_path` 的逆操作, `$HOME` 前缀压缩为 `~` (HOME 外原样, `$HOME-other` 前缀陷阱不压缩, 空串非 0) |
| `handle_error()` / `error()` | wallpaper-lib.sh 内部, rofi/scripts/wallpaper.sh (handle_group)                                                                                                                                              |
| `xw_clear_group_members()`   | wallpaper-lib.sh (clean_group), wallpaper-render.sh (set_wallpaper_to_group) — 清 group 所有成员 monitor 独立窗口 (组与成员互斥); 以 `xwallpaper --list` active name 为准, 仅清实际存在的成员独立窗口 (已并入组、无独立窗口的成员自动跳过)                                                                                 |
| `clean_group()`              | rofi/scripts/wallpaper.sh (handle_group 禁用/重命名/删除/编辑成员 — 无后续同名 set, 需真清 grp_<组名> + 成员窗口)                                                                                                |
| `xw_set()`                   | wallpaper-lib.sh (xw_apply) — 视频分支按 confname 读 `.monitors["<monitor|组名|Screen>"]["video-render"]`: `volume>0` 传 `--volume N`, `volume=0`/缺省传 `--mute` (0 与 mute 等价), `fps>0` 才传 `--fps`; video-render 缺字段时回退脚本顶部 `config[volume]`/`config[fps]` 默认值; confname 默认同窗口名 target (group 场景由 render 层显式传组名, 见 render.sh) |
| `xw_clear()`                 | wallpaper-render.sh (set_wallpaper_to_monitor 清所属组窗口, set_wallpaper_to_group 经 xw_clear_group_members 清成员 monitor), wallpaper-lib.sh (clean_group, xw_clear_all_exclude_screen, xw_clear_screen_and_restore) |
| `xw_clear_keep()`            | wallpaper-lib.sh (xw_clear_all_exclude_screen) — xwallpaper clear --keep, 清窗口保留 last, 供 restore 恢复                                                                                                  |
| `xw_clear_all_exclude_screen()` | wallpaper-render.sh (set_wallpaper_to_screen) — 以 `xwallpaper --list` active name 为准清所有 monitor/group 窗口 (Screen 除外, 由 set 同名 reload 覆盖), monitor/group 用 --keep 保留 last (screen 清除后可 restore 恢复); 不再遍历 xrandr/config 枚举 (避免空打不存在 name)                                |
| `xw_clear_screen_and_restore()` | wallpaper-render.sh (set_wallpaper_to_monitor, set_wallpaper_to_group) — 仅当 `--list` 有 Screen 时才 clear Screen + `xwallpaper restore` 回退 last (否则早退, 不空打)                                                                     |
| `xw_apply()`                 | wallpaper-render.sh (set_wallpaper_to_screen/monitor/group) — 只发 set 命令, 不再写 latest 缓存 (状态由 xwallpaper 持久化); confname 默认同 target, group 由调用方显式传组名                                                                            |
| `get_screen_size()`          | wallpaper-render.sh, wallpaper-lib.sh (get_monitor_list_text)                                                                                                                                                |
| `get_monitor_list_text()`    | rofi/scripts/wallpaper.sh (monitor_selection)                                                                                                                                                                |
| `_json_path_for()`           | wallpaper-lib.sh (pick_config_dir, set_numeric_config 内部)                                                                                                                                                  |
| `pick_config_dir()`          | rofi/scripts/wallpaper.sh (handle_random_images_path[_dark], handle_random_videos_path[_dark]) — 读侧 `expand_path` 定 yazi 起始目录, 存盘前经 `shrink_path` 压缩 `$HOME` 为 `~` (可移植) |
| `set_numeric_config()`       | rofi/scripts/wallpaper.sh (handle_random_duration)                                                                                                                                      |
| `get_video_render_config()`  | wallpaper-lib.sh (set_video_render_config 内部), rofi/scripts/wallpaper.sh (fps 菜单 `cmd:` 状态显示) — 读 `.monitors["<monitor>"]["video-render"].<key>`, 缺失回退 `config[]` 默认 |
| `set_video_render_config()`  | rofi/scripts/wallpaper.sh (handle_fps) — rofi 输入整数校验 (`^[0-9]+$`, min 0) 后, 值未变早退 (无意义写回都省掉), jq (`tonumber`) 原子写回 `.monitors["<monitor>"]["video-render"].<key>`; 仅写入新值返回 0 |
| `has_group()`                | wallpaper.sh (apply_wallpaper), wallpaper-lib.sh (get_monitor_dim), rofi/scripts/wallpaper.sh (handle_group)                                                                                                 |
| `group_names()`              | wallpaper.sh (apply_wallpaper), wallpaper-lib.sh (is_group_member, group_for_monitor, get_monitor_list_text), rofi/scripts/wallpaper.sh (handle_group)                              |
| `get_group_members()`        | wallpaper.sh (apply_wallpaper), wallpaper-lib.sh (is_group_member, get_group_dim, xw_clear_group_members), wallpaper-render.sh (set_wallpaper_to_group 内部调 get_group_dim), rofi/scripts/wallpaper.sh (handle_group) |
| `get_group_enabled()`        | wallpaper.sh (launch_wallpaper daemon 枚举组), wallpaper-lib.sh (group_for_monitor, get_monitor_list_text), rofi/scripts/wallpaper.sh (handle_group)                                                          |
| `is_group_member()`          | wallpaper.sh (apply_wallpaper, launch_wallpaper daemon)                                                                                                                                                      |
| `group_for_monitor()`        | wallpaper.sh (apply_wallpaper), wallpaper-lib.sh (is_group_member), wallpaper-render.sh (set_wallpaper_to_monitor 内联), rofi/scripts/wallpaper.sh (handle_group)                                              |
| `get_group_dim()`            | wallpaper-lib.sh (get_monitor_dim, get_monitor_list_text), wallpaper-render.sh (set_wallpaper_to_group), wallpaper.sh (launch_wallpaper daemon)                                                             |

> `restore_latest_monitor_group()` 已删除: 由 xwallpaper `restore` 命令替代 (screen 清场时
> monitor/group 经 `clear --keep` 保留 last, 切回时统一重建)。`clean_latest()` 已删除 (死代码)。

### tools/wallpaper.sh

| 函数 | 调用者 |
| ---- | ------ |
| `random_wallpaper()` | wallpaper.sh (`-m next`, launch_wallpaper daemon, theme_wallpaper) — 经 `get_theme_dir` 按当前主题选目录 (第二参可显式传 light/dark); 按 `random_type` image/video/web 选池：image/video 为文件池 (`find_wallpapers` + pattern)，web 为含 `project.json` 且 `type` 匹配的目录池 (`find_project_dirs`)；`random_depth` 为全局值 (读顶层/`.defaults`, 缺省 3); 排除当前壁纸后随机抽取 |
| `ensure_xwallpaperd()` | wallpaper.sh (launch_wallpaper 经此拉起) — daemon 存活直接复用, 仅死亡/缺失才 pkill 清理 + 拉起 (热重启重跑 autostart 不杀 daemon, 窗口不销毁重建) |
| `select_wallpaper()` | wallpaper.sh (`-m select`) — 经 `get_theme_dir` 按当前主题定 yazi 起始目录 (入口 `expand_path` 展开, `~` 写法可用); web 选中目录经 `project_entry` 验入口后应用 |
| `theme_wallpaper()` | wallpaper.sh (`--theme [light\|dark\|auto]` CLI) / tools/theme.sh `_do_theme_change` (前台同步 hook, SIGHUP 前落盘) — 枚举 active monitors + enabled groups (skip 组员, 坏组跳过), Screen 激活时只切 Screen, 单 target 失败跳过整体恒返回 0; 先读 `wallpaper-last.json` 恢复该主题上次壁纸 (文件仍存在才用), 无记忆/文件已删才 random 并回写记忆; 当前已是目标时跳过 set (同名 set 即 reload, 白闪一次) |

### tools/wallpaper-render.sh

| 函数                         | 调用者                                                           |
| ---------------------------- | ---------------------------------------------------------------- |
| `set_wallpaper_to_screen()`  | wallpaper.sh (apply_wallpaper, set_latest), 内部调 xw_clear_all_exclude_screen 清空所有 monitor/group 壁纸窗口后整屏铺图 (Screen 自身由 set 同名 reload 覆盖, monitor/group 经 --keep 保留 last) |
| `set_wallpaper_to_monitor()` | wallpaper.sh (apply_wallpaper, set_latest), 内联检查所属组并清组窗口 (组与成员互斥, mon_name 自身靠同名 reload) + xw_clear_screen_and_restore (与 screen 互斥, 清除后 restore 回退 last) |
| `set_wallpaper_to_group()`   | wallpaper.sh (apply_wallpaper, set_latest), 内部调 xw_clear_group_members 清成员 monitor 独立窗口 (grp_<组名> 自身靠同名 reload) + xw_clear_screen_and_restore (与 screen 互斥, 清除后 restore 回退 last); 向 xw_apply 显式传组名为 confname (config 键用组名, 非窗口名 grp_<组名>) |
| `reapply_video_wallpaper()`  | rofi/scripts/wallpaper.sh (handle_fps 值改变后) — `xwallpaper --state` 按窗口名查 type, 仅 video 时 `xw_clear` + 经 `set_wallpaper_to_*` 重设同一文件 (mpv 仅创建时读 --fps, 同名 set reload 不生效; rotation 按 state 第 4 列透传); 非 video/无窗口 no-op |

## 调用链 (Call Chain)

### 锁屏/挂起链路

```
rofi powermenu (用户点击)
  → type-*/powermenu.sh (source lock.sh)
    → _lock_before()   # 现取 mpd 快照并暂停、按 sink 静音全部输出、暂停 mpv/xwallpaper 渲染
    → _lock()          # 武装锁屏期 DPMS (xset dpms 30 30 30) + 启动 i3lock, force standby
    → systemctl suspend  (仅 suspend)
    → wait             # 等待 i3lock 退出 (唤醒后输入 → DPMS 计时重置 → 30s 再灭)
    → _lock_after()    # 恢复音乐、只还原本次静音的 sink、恢复渲染; xset dpms 0 0 0 收回 DPMS

screen.sh (空闲链路, xss-lock 为唯一权威)
  → _screensaver_start()  # pkill 残留 xautolock; xset s 570 30; xset s noblank; xset dpms 0 0 0; _ensure_xss_lock
  → 570s 无输入 → X 屏保 ON → xss-lock -n 拉起 notifier → screen.sh notifier 压暗 (gamma 0.4)
  → 600s 无输入 → X 屏保 CYCLE → xss-lock 先 SIGTERM notifier (还原 1.0) 再拉起 LOCKER="lock.sh lock"
  → 期间任意键鼠 → 屏保 OFF → xss-lock SIGHUP notifier → 立即还原亮度, 计时归零
  → logind lock-session / 挂起前 → xss-lock 同样调起 LOCKER (锁在睡眠之前)
  → _inhibit_poke() (每 20s)  # 有声且未锁屏 → xset s reset (抑制=把空闲计数压回 0, 解除后重新计时)
```

### 窗口 hook 链路

```
dwm 窗口 open/close
  → dwm-windowhook.sh (env: ACTION/WID/CLASS/TITLE/TAGS/MON)
    → windowhook_dispatch() 按 WINDOWHOOK_RULES 顺序遍历
      → trigger 命中 → handler (耗时的一律后台 &, 如 update_mail 刷 mail-unread)
```

### 启动链路

```
DWM 启动
  → autostart.sh
    → picom &                          # launch(): 每 name 独立 flock 锁 (autostart-launch-<name>.lock) 保证
    → dunst &                          #   检查+启动原子, 重入时后者跳过; restart 轮询等旧进程退出 (≤2s)
    → xss-lock -- "lock.sh lock" &          # 空闲锁屏权威 (screen.sh 内拉起)
    → fcitx5 &
    → xsettingsd &                          # XSETTINGS 广播 (theme.sh set_gtk_theme 依赖)
    → udiskie &
    → lxpolkit &
    → setxkbmap ...
    → bash keyboard.sh &
    → bash wallpaper.sh &
    → bash steam-workshop-auto.sh 431960 &  # 工坊壁纸开机异步自动更新 (一次性, 只通知)
    → bash dwm-status.sh &                  # 状态栏
    → bash screen.sh &                      # 空闲锁屏链路 (xss-lock + 音频抑制, 有声不锁不灭)
    → bash brightness.sh &
    → bash tools/theme.sh auto &           # 自动主题切换 (auto=false 时立即退出)
```

### 状态栏链路

```
dwm-status.sh
  → source dwm-status-tools.sh, status-ids.sh
    → source utils/weather.sh, utils/notify.sh
  → panes() 拼接 ${ST_*_BYTE} + print_* 输出
    (顺序/分组/圆角归 dwm config.h 的 bar_left/bar_right; 空 block 只留
     id 字节, 由 dwm 的 bar_blocks 丢弃)
  → launch_daemon(update_*_daemon)
  → xsetroot -name "$status"

dwm-statuscmd.sh (状态栏点击)
  → volume.sh / brightness.sh / calendar.sh / mpd.sh / sing-box.sh / notification.sh / ... (按模块)
```

### rofi 启动器链路

```
dwm-launcher.sh (快捷键)
  → source utils/monitor.sh (is_portrait 判断方向)
  → rofi -show drun          (应用启动)
  → rofi/scripts/powermenu_t2 (竖屏) / powermenu_t4 (横屏)  (电源菜单)
  → rofi/scripts/mpd.sh      (音乐控制)
  → rofi/scripts/module.sh   (模块管理)
    → rofi/scripts/theme.sh (主题控制子菜单，由 module.sh handle_theme 调用)
    → rofi/scripts/yt-dlp-wrapper.sh (YT-DLP Wrapper，由 module.sh handle_yt_dlp_wrapper 调用)
    → rofi/scripts/steam-workshop.sh (Steam Workshop，由 module.sh handle_steam_workshop 调用)
    → rofi/scripts/wallpaper.sh (壁纸管理，由 module.sh handle_wallpaper 调用)
    → tools/touchpad.sh toggle (触控板开关，由 module.sh handle_touchpad 调用)
  → rofi/scripts/media-scraping.sh  (Media 启停子菜单，由 module.sh 调用)
  → rofi/scripts/screenshot.sh
  → rofi/scripts/screencast.sh
  → rofi/scripts/quicklinks-mode.sh (rofi -show quicklinks 外部脚本模式, ROFI_RETV 分派; 主菜单+历史/书签子菜单下钻/返回, ROFI_DATA 上下文; )
  → rofi/scripts/emoji.sh
  → rofi/scripts/notification.sh
```

### 自动主题切换链路

```
tools/theme.sh auto (守护进程)
  → get_sun_times() (ipinfo.io/loc + open-meteo daily=sunrise,sunset)
  → get_current_theme() (xrdb -query dwm.col_theme)
  → 日出/日落触发:
      → _do_theme_change("light"|"dark", nobright) (只切配色)
      → restart_snixembed() 经 launch restart 重启 snixembed (图标按新前景色重绘)
      → wallpaper.sh --theme <mode> 前台同步跟随换壁纸 (SIGHUP 前落盘, 失败不影响切换)
      → system-notify low
      → pkill -SIGHUP dwm → dwm restart → loadxrdb 重载配色
  → 每轮 (60s): apply_transition_brightness() 按 `auto.dawn/dusk_minutes` +
    `auto.transition_anchor` (after 默认 / center / before) 对各 monitor 线性插值设亮度
    (配色二值翻转，亮度渐变；锁屏期间两者都跳过)
  手动 apply 先 auto off 再切主题（防 daemon 间隙 tick 覆盖端点亮度）；
  auto off 附带 pkill 无 pid 文件的 daemon；daemon 启动 flock 单实例，不重入
```

### 壁纸状态 (latest) — 由 xwallpaper 持久化

当前壁纸状态已从脚本侧文件 (`~/.cache/wallpaper/wallpaper_latest_*`) 迁移至 xwallpaper
内部: 每次 `set` 时按窗口 name 持久化, daemon 启动自动恢复。脚本侧不再读写 latest 文件,
查询当前壁纸统一走 `xwallpaper --state` (输出 `name\ttype\tpath\trotation`; `--list` 仅输出名字)。

- xwallpaper 状态文件: `$XDG_STATE_HOME/xwallpaper/state` (fallback `~/.local/state/xwallpaper/state`)
- 行格式: `name\ttype\tpath\trotation\tgeom\tkeep`
  - `keep=0` — 当前窗口, daemon 启动恢复
  - `keep=1` — last 保留 (clear --keep 后), `xwallpaper restore` 恢复
- 脚本层 unique name: 实体 monitor 用 xrandr 名 (如 `eDP`), Group 用 `grp_<组名>`, 全屏用 `Screen`。
  `xw_set` 统一以 `-g <rect> --name <name>` 创建, xwallpaper 恢复时 name 命中当前 xrandr
  output 则重解析几何, 否则回退保存的 geom (grp_*/Screen)
- screen 互斥链: 铺全屏 → `xw_clear_all_exclude_screen` 对 monitor/group 走 `clear --keep` 保留 last
  (Screen 自身不清, 由 set 同名 reload 覆盖) →
  切回 monitor/group → `xw_clear_screen_and_restore` clear Screen 后 `xwallpaper restore` 回退
- **同名 set 即 reload, 手动 clear 目标窗口会留空窗黑屏**: xwallpaper `set` 对同名同类型窗口走
  `old->reload` (app.c:239), 不销毁重建。因此 `set_wallpaper_to_*` 只清**互斥对象**的窗口
  (monitor/group 互斥、与 screen 互斥), 不再清自身 target 窗口。`clean_group` 仅被 handle_group
  (禁用/重命名/删除/编辑成员, 无后续同名 set) 调用, 用于真清窗口。

> **规则**: 脚本侧任何读取/比对当前壁纸的逻辑, 用 `xwallpaper --state` 按 name 匹配。
> monitor 尚无配置时, `ensure_monitor_config()` 用脚本默认值（`config` 数组）初始化写入 `.monitors["<monitor>"]`（volume/fps 属 video-render 子对象默认, 不写入顶层）。

### 壁纸链路

```
wallpaper.sh → source utils/monitor.sh, utils/notify.sh
  ├─ 图（image） / 视频（video） / 网页（page） → xwallpaper 渲染 (全部 -g --name 窗口)
  ├─ monitor 组 → xwallpaper geom 窗口按 bbox 跨成员屏铺图/视频/网页
  │    ├─ 组名即目标 (config: groups.<组>), 脚本层 name 为 grp_<组名>
  │    ├─ rofi 多选创建/编辑/启停
  │    ├─ 成员互斥（一屏至多归一组）
  │    ├─ daemon 轮询对组成员 skip（手动 only）
  │    ├─ 主题色调: light 用 `random_image_dir/random_video_dir`, dark 用 `random_image_dir_dark/random_video_dir_dark`
  │    │   (dark 空 fallback light, 经 `get_theme_dir` 解析); 主题翻转经 `theme_wallpaper --theme` 跟随切换,
  │    │   daemon 轮换按 `current-theme` 实时选目录
  │    └─ launch_wallpaper 经 ensure_xwallpaperd 复用常驻 daemon (存活不重启, 仅死亡拉起), 启动时自动恢复 keep=0 状态
  └─ 状态: xwallpaper 持久化 (state 文件), daemon 重启自愈
```

## 配置文件

- `rofi/` 下各 type 目录的 `*.rasi` 文件
- `rofi/fonts/` 字体文件
- `rofi/colors/` `rofi/images/`
- `~/.config/dwm/quicklinks.json` — quicklinks 书签, `links` 数组元素含 `id`(uuid)、`name`、`url` (icon 字段已废弃移除); 顶层 `searcher` 数组存搜索引擎 `{name, url}`(name 为唯一键, url 用 `{key}` 占位搜索词, 可省略 → 追加 url 末尾), 自定义输入搜索默认用 `searcher[0]`, 支持 `@<name>` 首 token 指定引擎
- `~/.config/dwm/wallpaper.json` — 壁纸配置, 含 `monitors`(按屏/组名键)、`groups`(成员名单 + enabled 启停) + 可选顶层/`.defaults.random_depth` (全局搜索深度, 缺省 3, `find -maxdepth`); 每个 monitor/组可带可选 `video-render` 对象 `{volume, fps}`: `volume>0` 传 `--volume N` 播放音频, `volume=0`/缺省时传 `--mute` 静音 (0 与 mute 等价), `fps>0` 传 `--fps`; 随机类型 `random_type` ∈ image/video/web (rofi Type 三选一); web 随机池 `random_web_dir`/`random_web_dir_dark` (缺省 `~/.local/share/Steam/steamapps/workshop/content/431960`，池为其下所有 `index.html` 的上层目录); 主题色调目录: light 用 `random_image_dir`/`random_video_dir`, dark 用 `random_image_dir_dark`/`random_video_dir_dark` (缺失/空串 fallback light, rofi Wallpaper 菜单 Images Dark/Videos Dark 配置); 目录路径可写 `~`/`$HOME` 可移植形式 (读侧 `expand_path` 展开, rofi 选择存盘经 `shrink_path` 自动压缩 `$HOME` 为 `~`)
- `~/.local/state/dwm/wallpaper-last.json` — 壁纸主题记忆 (状态, 非配置): `{"<target>":{"light":"/path","dark":"/path"}}`, target = monitor 名/组名/Screen; 主题切换优先恢复记忆 (文件不存在回退 random), 手动 `next/select` 与 daemon 轮换按 `current-theme` 回写
- `~/.config/dwm/theme.json` — `tools/theme.sh` 的外部化主题配置，`"auto"` 含 `enabled`(默认 false)、`sun_rise_offset`(日出延迟分钟数)、`sun_set_offset`(日落延迟分钟数)、`dawn_minutes`/`dusk_minutes`(亮度过渡分钟数，默认 60，0=关闭渐变)、`transition_anchor`(过渡锚点 `after`(默认，事件后窗口) / `center`(对称窗口) / `before`(事件前窗口))，`"cursor"` 含 `theme`/`size`，`"dpi"` 为 Xft.dpi 值，`light`/`dark` 各自含 `colorscheme`(引用 `~/.config/dwm/colorschemes/` 下的颜色方案文件) 与可选 `brightness.<monitor>`(该模式的端点亮度，键为 xrandr 输出名，缺失/非数字/>100 fallback 50)，`qt` 为 Kvantum 主题名 (light `Orchis-solid` / dark `Orchis-solidDark`)
- `~/.xsettingsd` — `set_gtk_theme()` 维护 `Net/ThemeName`(当前 GTK 主题) + `Gtk/CursorThemeName/Size`(源 `theme.json:cursor`, 与 `Xcursor` 对齐, 缺失时 Firefox 回退到 `settings.ini/gsettings` 的 36), 保留其他 XSETTINGS 键, `pkill -HUP xsettingsd` 触发重载广播

## Rofi 模块注册表规范

`module_parse` 的 stdin 注册表采用 4 列 pipe 分隔格式:

```
key|icon|label|status
```

### 约定

- **key**: kebab-case，对应 `handle_<key>` 调度函数名（`-` 转 `_`）
- **icon**: Nerd Font 图标，始终非空（不含 sddm.sh 旧式空 icon）
- **label**: Title Case 纯名词短语，**不带括号解释**。括号仅用于并列子实体名如 `Hub (jellyfin)`。命名实体的官方写法优先（如 `sing-box` 而非 `SingBox`）
- **status**: `toggle` / `toggle-raw:<cmd>` / `active` / `active-svc` / `active:<svc>` / `cmd:<expr>` / `str:<text>` 或空
  - `toggle-raw:<cmd>` 把 `<cmd>` 的执行输出当作 toggle 图标索引（`util.sh icon() raw` 分支），适用于状态来自自定义命令的场景（如 `tools/touchpad.sh status`）
- status 的 `cmd:` 表达式在每次 menu build 时重新 eval；需引用脚本变量或命令结果（如 `$(getConfig ...)`）时，注册表 heredoc 必须加引号（`<<'MODULES'`），否则 parse 时展开会把旧值固化进表达式（见 wallpaper.sh random_type）

> **module_loop 返回约定**: ESC/取消返回 1，派发完成后固定返回 0（不受 handler 返回值影响）。需要持续交互的脚本用 `while module_loop; do :; done` 包一层（如 wallpaper.sh），单次即退的脚本直接调用。

### 示例

```
picom|󰋩|Picom|toggle
network|󰈀|Network|active:NetworkManager
sing-box||sing-box|active
calendar-lunar|󰃚|Lunar Calendar|
```

## 已知问题

按模块分组；每条记录现象、根因与修法，有回归测试的注明用例。新增条目前先找对应分组，不另起平铺列表。

### 状态栏（dwm-status*）

- **status writer 不再注入 pill 底色 (`^b`)**: `panes()` 原用 `new_pane()` 给每个 pane 组首 block 加 `^b$black^`, 理由是"让 pane 颜色跟随 xrdb 主题"。但 dwm 的 `SchemeStatus` bg = `col_black`, `loadxrdb()` 已用 `strncpy` **原地覆盖**为 xrdb 的 `dwm.col_black` (dwm.c), 且 SIGHUP restart 时 `autostart.sh` 会跑 `dwm-status.sh reboot` 让 writer 重读同一份 xrdb —— 两边同源同值, `^b` 纯属重复写入。现 `new_pane` 已删除, `panes()` 直接拼接 `${ST_*_BYTE}<text>` 且每块独占一行、按语义分组注释 (系统负载/未读/网络/天气/容器/录屏/代理/音频/电源时钟), 行序与 dwm 绘制顺序无关, 纯为阅读; 空 block 只留 id 字节, 由 dwm 的 `bar_blocks` 丢弃 (无可见文本)。绘制顺序/分组/圆角全由 dwm `config.h` 决定, 注册了但 config 未列的块 (如当前 volume) 直接不绘制。**注意** writer 侧若给空 block 加颜色码 (如 `^c...^`) 会使其"有可见文本"而不被丢弃, 故 `weather` 仍保留 `[ -n ]` 判断。回归测试 `tests/status-panes_test.sh`
- `tools/calendar.sh:3` source 路径已修复为 `$(dirname "$0")/../utils/notify.sh`

### MPD / MPRIS

- **mpd.sh fetch_cover 慢已修复**: 根因不是 MPD 网络往返而是客户端每 chunk 固定开销。① `nc -q1` 在 stdin EOF 后须等 1s 才退出，而 MPD 收 `close` 不主动断连 → 每块白白等 1s，readpicture chunk 上限 8192B，N 块 ≈ N 秒（实测 30KB 封面 4 块整函数 4102ms，改 `-q0` 后 88ms；1MB 封面 128 块会到 ~128s）。② `dd bs=1 skip=...` 逐字节跳过+拷贝，块内 skip 从文件头重来，累计 O(n²) 字节级 syscall（1MB 封面 128 块 ~6700 万次单字节 read），改 `iflag=skip_bytes,count_bytes bs=4096`（精确 seek + 块拷贝）。**单连接方案评估后放弃**: bash 无法可靠"恰好读 N 字节且把后续保留在流中"（read 缓冲与 fd 不同步、dd over-read 会吞掉下一响应 header、binary 块无长度外分隔标记），需 python/复杂协议解析，与仓库纯 bash 风格冲突，且 fetch 为低频场景（cache 按 uri 命中后不再拉），`-q0`+iflag 已把 4.1s→48ms，额外收益不足以抵风险。回归测试 `tests/mpd-cover_test.sh`
- **OSD Lyrics 开关 (mpd 菜单)**: osdlyrics 无 CLI, OSD 显隐由 Config D-Bus 服务 `org.osdlyrics.Config` 的 `General/display-mode-osd` 控制 (与托盘「桌面歌词模式」同一状态, 改后应用即时隐藏/重建窗口)。直接改 `~/.config/osdlyrics/osdlyrics.conf` 运行中不生效 (应用不监听文件); 菜单读状态先 `pgrep -x osdlyrics` 门禁, 避免查询时自动激活 Config daemon。关 OSD 只销毁窗口, 应用留在托盘。**冷启动顺序不可反**: 未运行时若先 `SetBool true` 再启动, 单独激活的 `ini_config.py` 会监听 `org.osdlyrics.Daemon`, Daemon 不存在时进程在 1s 保存定时器触发前退出 → `SetBool` 返回成功但值丢失, 表现为第一次 toggle 只启动应用、不显示歌词; 现改为先 `setsid -f osdlyrics`, 经 `_osd_wait_daemon` 等 Daemon 就绪 (~300ms) 后再写 true。回归测试 `tests/mpd-osd_test.sh` (mock busctl 按次数模拟 Daemon 就绪, 断言 SetBool 在启动之后)
- **source 含 `exit` 的脚本时 mock 缺工具会静默杀掉测试 shell**: `tests/mpris-bridge_test.sh` 初版只 mock 了桥相关命令，`mpc/systemctl` 等 mock 依赖的 `touch` 不在 PATH → mock 失败 → 被测脚本走 `exit 1` → 整个测试进程退出且零输出（`2>/dev/null` 把真错误也吞了）。修法：被测脚本外加窄 PATH 的场景 bin 时，把 mock/harness 间接依赖（`touch/rm/mkdir/dirname/head`）一并 link；且 `command -v` 会穿透到 `/usr/bin` 真二进制（如本机 `mpdris2-rs`），`chmod -x` 盖不住，必须用窄 PATH 隔离（`PATH="$SCEN_BIN" source ...`），kill 类 action 的 `eval` 同理用 mock 优先 PATH（防真 `systemctl` 动用户服务）。通知模板 drop-in 写入 `XDG_CONFIG_HOME`，测试须隔离该变量；`mpd-cover_test.sh` 亦 mock `systemctl/mpdris2-rs`，避免 source 时触碰真实用户服务。回归测试 `tests/mpris-bridge_test.sh`

### 锁屏 / 空闲（lock.sh, screen.sh）

- `tools/screen.sh:16` LOCKER 路径已改为 `$(dirname "$0")/lock.sh lock`，不再依赖 `$TOOLS_DIR`
- `tools/screen.sh` 的 `_has_active_audio()` 现改为**录默认输出判响度**（原 pw-dump 按 media.role/tlength 过滤流的方案已丢弃，总会遗漏播放流致误锁屏；`EXCLUDE_APPS`/`SCREEN_AUDIO_MODE`/`_jq_exclude_apps()`/pw-dump 双后端均已删除）：`parec --device "$(pactl get-default-sink).monitor"` 定长采 150ms (head -c 截断触发 SIGPIPE) → ffmpeg volumedetect → max_volume 超阈值即认为有活动音频。注意 **raw `pw-record` 解析不到本机 `*.monitor` 节点会静默回落到默认麦克风（录到输入而非输出），必须用走 pulse 层的 `parec`**；且 sink monitor 采的是 sink 音量衰减后的信号（本机 Fosi 30% 音量衰减约 25dB+），阈值取 -78 dB（真静音底约 -91 dB，静音时返回 none）
- **锁屏进程被 SIGTERM 时不还原已修复**: `lock()` 原来是 `_lock_before; _lock; wait; _lock_after`, 被 `loginctl unlock-session` 或外部 kill 掐掉时 `wait` 之后的还原不会执行 → sink 一直静音、`xwallpaperd` 停在 SIGSTOP (壁纸冻结)、DPMS 停在 30/30/30。现 `_lock_before` 后挂 `trap '_lock_after' TERM INT HUP`, 用 `lock_restored` 守卫保证幂等 (trap + 正常路径各调一次也只还原一遍, 不会重复 toggle mpd)。回归测试 `tests/lock-mute_test.sh` 场景 F (旧代码 F2/F3/F4/F5 FAIL)
- **锁屏后仍出声的第二个根因 (`wait` 被 i3lock fork 骗过)**: `lock()` 用 `_lock_before; _lock; wait; _lock_after` 表达"解锁后还原", 但 i3lock 默认 **fork** (父进程立即退出), 后台任务对应的进程瞬间结束 → `wait` 立即返回 → `_lock_after` 在**锁屏仍在进行时**就跑完: sink 静音被还原、DPMS 归零、mpd 恢复, 于是锁着屏照样出声。旧代码能工作纯粹是因为 `_screen_lock_loop` 轮询 `pgrep -x i3lock` 顺带把脚本拖到解锁; 该循环删除后回归暴露。修复: i3lock 加 `-n` (nofork), `wait` 才真正等到解锁 (副作用也符合 xss-lock "locker 不得 fork" 的要求)。实测: 锁屏 3s 后 4 个 sink 全 muted、DPMS 30/30/30、mpd paused; 解锁后恢复。回归测试 `tests/lock-mute_test.sh` 场景 E (模拟 i3lock fork, 旧代码 E1/E2/E3 FAIL)
- **锁屏后仍有声音已修复 (静音打错声卡)**: `_lock_before` 原用 `amixer set Master off`, 而 `amixer` 只作用于 ALSA 默认控制卡 (本机卡 3 内屏); 实际出声的 sink 由 module.sh 切换, 可能是 Fosi USB DAC (卡 1, **只有 PCM 控制, 没有 Master**)、HDMI (卡 2) 或 `easyeffects_sink` (虚拟) → 静音命令打空, 锁屏后照常出声。现改为 pulse 层逐 sink 静音 (`pactl list short sinks` + `pactl set-sink-mute <sink> 1`), 覆盖虚拟 sink 与任意硬件 sink; 记录 `muted_sinks` 只还原本次改过的。同时把 `mpd_status`/`volume_status` 快照从**脚本加载时**挪进 `_lock_before` —— powermenu 是先 source 再等用户点菜单, 顶层取值会拿到几分钟前的状态 (期间开始的播放暂停/静音不了)。回归测试 `tests/lock-mute_test.sh`
- **锁屏链路迁移到 xss-lock (单一空闲权威)**: 旧实现同时跑 3 个计时器 (X 屏保 `xset s 600 600`、X DPMS `900/1200/1800`、xautolock 自己的 10min 私有计数), 且**媒体抑制靠拆表** (`pkill xautolock` + `xset s off -dpms`, 恢复时重新 `xset s 600` + 重启 xautolock)。X 服务端的超时基于 `lastDeviceEventTime`, 重新武装时若已空闲超过超时就会**立即**激活 → 放视频/听歌一停就瞬间黑屏; 而 xautolock 重启后是全新 600s 计数, 于是黑屏但**未锁屏**长达 10 分钟 (安全漏洞)。现改为: `xset s 600 0` + `xset s noblank` + `xss-lock -- lock.sh lock` 作唯一权威 (顺带接管 logind `lock-session`/挂起前锁屏), 抑制改为周期性 `xset s reset` —— X 处理 `ScreenSaverReset` 时会把 `lastDeviceEventTime` 置为当前时间 (xorg `ProcForceScreenSaver`), 等价"抑制期间冻结、解除后从 0 重新计时", 与 GNOME mutter (idle inhibitor 视为 active) / KDE 2025 "inhibited/uninhibited 时重建 idle timeout" 的修复语义一致。灭屏与空闲解耦: 解锁态 `xset dpms 0 0 0`, 只由 `lock.sh _lock` 在锁屏时武装 `dpms 30 30 30` (i3lock(1) 推荐的 DPMS wrapper 形态), `_lock_after` 收回; `_screen_lock_loop`/`xprintidle`/`xdotool key Escape` 随之删除 (DPMS 自身会因输入重置计时)。音频轮询从 600s 降到 20s (旧值意味着视频开始后最多 10 分钟才抑制)。回归测试 `tests/screen-lock_test.sh`
- **锁屏 standby 后物理屏 1-2s 亮起（xwallpaper 视频壁纸持续 present 触发驱动 unblank）**：根因是 `xwallpaper --daemon` 的 libmpv（`vo=gpu`+`wid` 直绘）在 X DPMS off 后**持续 present 帧** → amdgpu 驱动把输出 dpms 恢复 On（sysfs 实测 2-3s 回弹，X 层 `xset q` 标志保持 Off/Standby 不变，eDP→HDMI→DP 依次亮）。与键盘幽灵输入、amdgpu REG_WAIT（7.x 回归，lts 6.18.46 无此）、TLP/GPU runtime PM（`control=on` 全程 active）均无关。修复双层：① xwallpaper（源码 `~/Workspace/Github/xwallpaper`）backend 层加 `set_paused` 回调（video → mpv pause），`xw_app_dpms_poll()`（`DPMSInfo` 查询，500ms 节流）在主循环检测电源模式，非 On 即暂停渲染；② `lock.sh _lock_before/_lock_after` 对 `xwallpaperd`（兼容保留 `xwallpaper` 单进程时代）进程 `pkill -STOP/-CONT` 双保险。验证：standby 12s sysfs dpms 全程 Off 不回弹。**注意**: client+daemon 拆分后常驻渲染进程名为 `xwallpaperd`，`-x xwallpaper` 精确匹配打不到 daemon，必须 STOP `xwallpaperd`，否则锁屏 `_screen_lock_loop` 会因 X 层 `xset q` 标志 stale（物理已亮、X 仍 Off）卡在 `! Monitor is On` 等待里，表现为灭一次→亮→再也不灭。
- **锁屏前压暗预告 (`xset s 570 30` + `xss-lock -n`)**: 旧行为是 10 分钟直接上锁, 读文档 (无输入/无音频) 时体感突兀。现 `xset s` 的 timeout = 锁屏时刻 − 预告, cycle = 预告: Xorg `dixSaveScreens()` 在第二次 `SCREEN_SAVER_ON` (即 `what == screenIsSaved`) 时改发 `SCREEN_SAVER_CYCLE`, 而 xss-lock 在 `On` 且 `cycle > 0` 时只启动 notifier、收到 `Cycle` 才启动 locker → **570s 压暗、600s 上锁, 锁屏时刻不变**。压暗走 `xrandr --brightness` (gamma 瞬时生效, 无硬件往返); 不能用 `brightnessctl`/`ddcutil` (DDC 单次 ~200ms, restore 被 SIGTERM 打断就会停在暗屏, 且与 `theme.sh` 的亮度插值抢同一硬件)。恢复固定 1.0, 另由 `lock.sh _lock_before` 兜底一次。notifier 由 xss-lock 直接 execv (不经 shell), 故必须写成 `/bin/bash <screen.sh> notifier`; 脚本内必须 `sleep … & wait` 驻留 (`前台 sleep` 会把 trap 推迟到睡醒)。回归测试 `tests/screen-dim_test.sh` + `tests/screen-lock_test.sh` A 组
- **改超时/参数后不生效已修复 (重新武装对账)**: 旧 `_screensaver_start` 只在 `xss-lock` 未运行时写 `xset s`, 于是改 `screen_saver_time` 后重启 daemon 也不会重新武装, notifier 参数同样锁死在旧进程里。现每次启动都写 `xset s` (幂等: X 只重设 timer, 空闲判定仍按 `LastEventTime` —— xserver `ProcSetScreenSaver` → `SetScreenSaverTimer`, 所以重复武装不会延长空闲时间), 并把 `<预告>|<锁屏>|<gamma>|<self>|<locker>` 指纹写 `/tmp/dwm-status/screen-arm.fp`; 仅指纹变化或进程缺失时重启 xss-lock, **锁屏中只写 xset、不重启** (下一轮再对齐), 重启前 `pkill` + 轮询 ≤2s 等旧实例退出 (新旧并存会让新实例 `SetAttributes` 失败直接退出)。测试用 `SCREEN_ARM_FILE` 隔离真实指纹。**推迟必须有重试**: 锁屏/压暗中不重启 xss-lock 的决策若只做一次, 解锁后会永久停在旧实例 (旧实例无 `-n`, 配合 `xset s 570 30` 会在 570s 直接上锁且不压暗) —— 真实踩到过一次; 现 daemon 每轮调 `_ensure_xss_lock` 对账, 由 `_rearm_deferred()` 判定 i3lock/notifier 两个状态。回归测试 `tests/screen-lock_test.sh` R/W 组
- **热重启后旧 screen.sh 没被 kill (双 daemon) 已修复**: `launch restart` 杀的是 `autostart-launch-screen.pid` 里的 pid, 而旧 `daemon()` 的 md5 自重启是 `/bin/bash "$SELF" &; exit 0` —— **换了 pid**, pid 文件随即指向死进程; 下次热重启 kill 空操作后拉起新实例, 旧实例继续跑 (实测 3535685 与 3553535 并存)。修复两层: ① 自重启改 `exec /bin/bash "$SELF" daemon` (pid 不变, launch 的记录始终有效); ② daemon 启动时 `_takeover` 杀掉更早启动的同 argv 实例 (`/proc/<pid>/cmdline` 过滤排除 `screen.sh notifier`; starttime 相同则比 pid, 避免互杀)。另修 `source "$(dirname "$0")/…"` → `$(dirname "${BASH_SOURCE[0]}")` (被 source 时 `$0` 是调用者, 路径会算错)。回归测试 `tests/screen-single-instance_test.sh`

### 主题 / 亮度 / 托盘（theme.sh, monitor-brightness.sh）

- `tools/theme.sh` 旧 Firefox 切换方案（`set_firefox_theme` + `_get_darkreader_shortcut`，xdotool 模拟 Dark Reader 快捷键）已删除：Dark Reader 的 `extension-settings.json` 快捷键实际为空串，jq 的 `//` 不兜底空串 → `xdotool key ""` 从未生效；且依赖 Firefox 窗口存在、/tmp 状态文件易漂移。现由 `set_gtk_theme()` 双通道替代
- **Firefox content 亮暗由 portal 决定而非 GTK**：Firefox 的 `prefers-color-scheme` 走 `nsLookAndFeel::ComputeColorSchemeSetting()` → xdg-desktop-portal 的 `color-scheme`（gsettings `org.gnome.desktop.interface color-scheme`），且 Firefox 将 portal 返回的 `0 (default)` 硬映射为 light（nsLookAndFeel.cpp case 0）。因此 `set_gtk_theme()` 必须同时写 gsettings（prefer-dark/prefer-light），仅广播 GTK 主题名不足以切换 Firefox content scheme
- `tools/theme.sh apply` 的退出码已修复：auto 关闭时末尾 `[ ... ]` 返回 1 导致 apply 成功但 exit 1，现显式 `exit 0`
- **"dark 主题却是 light 亮度"已修复**：根因 `_do_theme_change` 把 `set_monitor_brightness "$mode"` 放**后台** (`&`)，两次主题切换重叠时先启动但更慢的 job（DDC 单次 `setvcp` ~200ms、首次 `ddcutil detect` ~1.6s）在返回后才落盘，用旧主题亮度覆盖后启动的新主题；而 `apply_transition_brightness` 窗口外不写（故意不抢手动/OSD），错值便一直挂着不自愈。改为**同步**执行（后调用者最后写，值正确）。回归测试 `tests/theme-brightness_test.sh` "端点亮度同步写完"（mock 慢 job，旧代码后台化时返回即可见断言 FAIL）
- `tools/theme.sh auto_daemon` 挂起/锁屏问题已修复：原实现 `sleep $((next_switch - now))` 一次性睡到切换点，但 sleep 计时在挂起(休眠)期间暂停、唤醒后剩余秒数继续走 → 跨挂起的主题切换延迟数小时（例：23:00 睡 8h 到次日 7:00 切换点，挂起 9h 后 8:00 唤醒，sleep 还剩 8h，到 16:00 才重算）。现改为 60s 内轮询（`remain>60` 时 sleep 60，否则精确睡到点），每次醒来重算 desired，挂起唤醒后最多 60s 纠正。锁屏（i3lock）期间仍阻塞不切（避免与 dwm SIGHUP 重启竞态），解锁后下一轮立即重算切换。回归测试 `tests/theme_test.sh`（mock date/sleep/pgrep + 文件驱动时间推进，后台 daemon 无法感知环境变量变更，须用文件 mock 时间/锁屏状态）
- `tests/theme_test.sh` 必须 mock `xrandr/brightnessctl/ddcutil`：daemon 每轮调 `apply_transition_brightness` → 真 `xrandr --listactivemonitors` 在无显示环境可能枚举出幽灵 monitor（如 `DisplayPort-0`），进而 `read_brightness` 走 `ddcutil detect` 长时间 hang 住导致用例全挂；mock 后 loop 零 monitor 直接 no-op。另须 `export THEME_LOCK` 指向临时路径：flock 单实例守卫下测试 daemon 会与用户 live daemon 争锁秒退，全挂；回归测试 `tests/theme-brightness_test.sh`（纯函数单测 + mock xrandr/读写函数的 `apply_transition_brightness` 集成）
- `tests/theme_test.sh` 场景边界（B/C）必须先停旧 daemon、布好状态、清 log 后再起新实例：mock sleep 瞬时返回使 daemon 热循环，旧实例的在途迭代（持旧缓存/旧状态）会在清 log 后落盘 `theme_change`，误杀"…不切换"断言（负载高时必现；生产代码按读到的有效数据切换是正确的，属测试同步问题）。已修：`stop_daemon`/`start_daemon` 包场景 setup
- **theme auto daemon 死锁致整早未切 light 已修复 (三处)**: ① 长 sleep 继承 flock 锁 (FD 9)：开机 daemon 缓存缺失进 `sleep 1800`，期间 `auto off` 的 `pkill -f 'theme\.sh auto$'` 只杀父进程，孤儿 sleep 被 init 接管继续占锁 → 后续 daemon `_auto_lock` 永远失败秒退、主题永不切换。现 auto_daemon 内所有 `sleep` 及 `get_sun_times` 后台拉取子 shell 均 `9>&-` 关闭锁 FD。② 缓存缺失睡 1800：后台异步拉取几秒即写好缓存，daemon 却睡半小时才重算 → 改为 `sleep 30` 短轮询（`.fetching` 1 分钟锁防刷）。③ 拉取失败沿用上轮残留时间：`read sunrise...` 只在 `if times=$(...)` 成功分支执行，失败时循环外 `local` 变量保留旧值 → `[ -n ... ]` 照过、短重试成死代码（跨零点缓存过期后还会拿昨天日出时间 tight-loop 空转烧 CPU）→ 失败分支显式清空。回归测试场景 C（删缓存 → 断言 `sleep 30` 且无 `sleep 1800` → 手写缓存恢复切换）+ auto_daemon 内 sleep 全带 `9>&-` 静态守卫；另修 `auto on` 分支顶层 `local pid`（非函数内，每次报错，改 `pid=""`）
- **auto_daemon 脏数据防护已加固**: ① sun-times 读后数字校验 (非数字曾坍缩 epoch 0 → remain 恒负无 sleep 热循环 + desired 恒 dark → SIGHUP 风暴，现 sleep 30 跳过)。② fetch 落盘前校验 (坐标正则 + 三时间非空 + date 成功 + epoch 数字 + `ss>sr、sr2>ss` 时序；`date -d ""` 会静默返回当前时间，脏响应直接丢弃、不写缓存、不删 throttle 锁)。③ offset `^-?[0-9]+$` 校验 (非法→0；旧 `$((...))` 对 "abc" 静默 0、对 "08" 直接报错)。④ `auto.enabled` 三态：false/未知非空→退出，空 (瞬时不可读/缺 key)→sleep 10 重试不退出 (编辑器非原子写曾永久杀死 daemon)。⑤ i3lock 等待 loop 内重查 enabled (锁屏期间 auto off 生效，不补 stale 翻转)。⑥ SIGHUP 前校验 `current-theme == desired` (`_do_theme_change ""` early-return 时不重启)。回归测试 `tests/theme-autofix_test.sh` (D 脏缓存 / E enabled 缺失自愈 / F 脏 API / H 锁被占不 spawn；旧代码下 D1/D4/E1-3/F1-2/H2 均 FAIL)
- **auto_daemon 窗口外翻转不补亮度已修复**: `nobright` 翻转假设"亮度由插值负责"，但插值只在窗口内写——夜间启动 daemon / 挂起跨过窗口 / 锁屏延迟翻转等一切窗口外翻转，之后永久无人写亮度 (实测：dark 配 light 亮度整晚)。现翻转时复用 `_should_apply_at` 分流：窗口内 `nobright` (防闪端点)，窗口外带端点一次性写入。回归 `tests/theme-autofix_test.sh` I1 (窗口外带端点，旧代码 FAIL) / I2 (窗口内保持 nobright 防过度修正)
- **后台任务 flock FD 继承已全覆盖**: `_auto_lock` 注释的 `9>&-` 不变量此前只守了 auto_daemon 内 sleep，`_do_theme_change` 链的 `set_kitty_theme &` / wallpaper `( ... & )` / `fcitx5 -r &` / `xsettingsd &` 全继承 FD 9 —— 开机首次切换拉起的常驻 xsettingsd 会永久占锁致后续 daemon 秒退 (auto 假死)。现四处均加 `9>&-`，静态守卫 `tests/theme-autofix_test.sh` G1 (旧代码 FAIL)
- **托盘图标不跟随主题切换已修复（两处根因）**: ① **nm-applet / pasystray / udiskie**：图标色由 **icon 主题**决定（`Tela-manjaro-light` 深色图标 / `dark` 浅色图标），而 `set_gtk_theme` 只写 gtk settings.ini 的 `gtk-icon-theme-name`、**运行时没广播 `Net/IconThemeName`**；X11 下 GTK 以 XSETTINGS 优先于 settings.ini，故所有已启动 GTK 应用（含重启后）都卡在旧图标主题 → 亮主题下仍是浅色图标、看起来"不跟随"。修复：`set_gtk_theme` 增写 `~/.xsettingsd` 的 `Net/IconThemeName`（HUP xsettingsd 广播）+ `gsettings icon-theme` 同步；GTK 收到 XSETTINGS 变化后**即时重载图标，无需重启进程**（实测 nm-applet pid 不变，purest `#dfdfdf` ↔ `#505050`）。② **EasyEffects（snixembed 代理）**：EasyEffects 8.2.9 起发 `IconName`（`com.github.wwmm.easyeffects-symbolic`）而非 `IconPixmap`，snixembed 自 2020 起 IconName 优先（`set_icon_name`），靠 `GtkStatusIcon` 默认着色在轻量 X11 会话取到错误前景色 → 深底配深图标不可见。修复在 snixembed 自身：`set_icon_name` 用当前主题 style context 经 `IconInfo.load_symbolic_for_context` 自渲染（保留 SNI 规范鼓励的 IconName 优先），另修 `pixbuf_from_data` 的 `i += 3`→`i += 4`，`size_changed` 改连 `set_icon` 恢复尺寸自适应；代码在 `~/Workspace/Github/snixembed`。snixembed 前景色只在 `set_icon` 时取一次 → 切主题时由 `_do_theme_change` → `restart_snixembed`（`launch restart snixembed`）重启重绘；`launch()` 抽出 `utils/launch.sh` 供 autostart 与 theme.sh 共用。端到端 dark `#a5a6a9` ↔ light `#535355`。回归测试 `tests/theme-tray_test.sh`（restart_snixembed）+ `tests/autostart_test.sh`（改为 source `utils/launch.sh`）
- **rofi/scripts/theme.sh handle_monitor_brightness 保存值/退出码失效已修复**: 原实现 `coproc YAD` + `wait "$YAD_PID"` 取 yad 退出码区分 OK/取消, 但 bash 读完全部 coproc 输出后可能清理 `YAD_PID`（实测 wait 时已空 → 报错 status≠0 → 误走恢复分支）; 且 `while read` 最后一次 read 读到 EOF 时会把 `$value` **清空**, 循环外 `$value` 必空（OK 也空）。重构为 **FIFO + 后台 pid (`$!`, 稳定)**, 循环内用 `$last` 记录最终值; OK 后从硬件读取实际亮度（eDP brightnessctl / DDC getvcp）作为保存值, 读取失败回退 `$last`。回归测试 `tests/rofi-theme-monitor-brightness_test.sh`（awk 提取函数 + mock yad/xrandr/brightnessctl; 因脚本顶层 `module_loop` 阻塞无法整体 source）
- **DP 显示器 DDC 亮度控制失效已修复**: `get_ddc_bus()` 只接受 `ddcutil detect --brief` 中 `Display N` 有效条目, 丢弃 `Invalid display` 条目。但 DP 经 aux 总线时 detect 常误报 `This monitor does not support DDC/CI. (I2C slave address x37 is unresponsive.)`, 而同 bus 的 `getvcp/setvcp 10` 实际可用 (TRG JQ24F260L 实测) → bus 解析为空, 读写静默失败。现两遍取值: 优先有效条目, 无命中时回退同 `drm_connector_id` 的 Invalid 条目总线 (eDP 不受影响, 其读写短路走 brightnessctl)。回归测试 `tests/monitor-brightness_test.sh` 场景 D (旧代码 FAIL, 新代码 PASS)
- **DDC 显示器滑块拖动滞后已优化**：yad `--print-partial` 拖动时逐像素输出值, 原实现每个值都调 `ddcutil setvcp`（~200ms/次）, 大幅拖动会积压上百次调用排队, 松手后仍持续处理（实测 100 值 → ~20s）; eDP 的 `brightnessctl set` 即时无此问题。现循环按显示器类型分流: eDP 逐值即时应用, DDC 用内层 `read -t 0.03` 丢弃积压值、滑动暂停后只应用最新值（实测 100 值 → 1 次 setvcp, ~1s）。回归测试场景 C（mock ddcutil detect/setvcp + DisplayPort-0 monitor, 断言 setvcp 只调 1 次且为最新值）

### 壁纸（wallpaper*.sh, xwallpaper）

- **视频 rotation 元数据**：手机竖拍视频编码常为横屏 1920x1080 但带 display matrix rotation=-90/90 元数据（`ffprobe -show_entries stream_side_data=rotation`），实际显示为竖屏 1080x1920。`get_video_dim()` 必须读取该元数据并交换宽高，否则竖屏视频被误判为横屏——应用到竖屏 monitor（xrandr rotate left，如 `HDMI-A-0` 报告 `1080x1920`）时方向误判触发无谓的旋转预览。`preview_rotation()` 初始 `--video-rotate` 由硬编码 `90` 改为 `0`：mpv 的 `video-rotate` 是**叠加**在文件元数据之上的额外旋转（默认 `auto` 自动应用元数据，lavc 实测默认输出 1080x1920、`--video-rotate=90` 叠加后输出 1920x1080），硬编码 `90` 让带元数据旋转的视频初始画面变横屏，且 watch-later 无该行（`video-rotate=0` 为默认值 mpv 不写入）时 fallback 错误回到 `90`。xwallpaper 本机为 libmpv 内嵌版，`--rotate N` 直接映射 mpv `video-rotate`，与预览同引擎同语义，空 rotation 时不传 `--rotate` 由 mpv 自动旋转
- **壁纸 latest 状态已迁移至 xwallpaper**: 脚本侧 `wallpaper_latest_*` / `wallpaper_full_latest` 缓存文件
  删除, 由 xwallpaper 按 name 持久化 (`$XDG_STATE_HOME/xwallpaper/state`, `keep` 标志区分当前窗口/last)。
  脚本侧查询当前壁纸走 `xwallpaper --state`。`clear --keep` + `restore` 替代原 screen 清场保留/回退逻辑。
  **行为变化**: `clean_group` 后若铺 screen 再切回, 之前被普通 clear 的 target 仍可能被 restore 拉回
  (原实现会删缓存, 现普通 clear 删状态、仅 `--keep` 保留; 实际场景中 clean 后再铺 screen 极罕见, 可接受)。
- **rofi `next` 卡顿已修复**: 原 `xwallpaper` CLI 为单进程架构, 每次裸调用约 0.2s (X 连接+库加载), 一次 `next` 链路需串行 4-6 次 clear/restore/set (~1.5s)。原 `handle_next` 同步执行导致 rofi 要等 next 跑完才重开 (点 Next 后空白 1.5s)。修复两层: ① 脚本层 `handle_next` 改 `( tools/wallpaper.sh -m ... next & )` 后台执行, rofi 立即重开; ② xwallpaper 改为 **client+daemon 架构** (`xwallpaperd` 常驻, CLI 经 IPC 通信, 实测 `--list`/`--state`/`clear` 从 ~0.2s 降至 ~0.001s, group next 从 0.97s 降至 0.4s, 大图 set 从 0.6-1s 降至 0.16s)。另修复 `xwallpaper state` → `--state` 拼写 (3 处), 此前排除当前壁纸逻辑一直失效会重复抽同一张。
- **首次开机 HDMI 视频壁纸黑屏（swapchain 创建失败 → mpv 丢 video track）**：开机早期 GPU/GL（RADV/amdgpu Vulkan 栈）未就绪时，`vo=gpu` 的 swapchain 创建失败（`VK_ERROR_INITIALIZATION_FAILED`），mpv `write_video` 里 `vo_reconfig2<0` → `error_on_track` **禁用视频 track**（日志 `deselect track 0`/`Video: no video`）——窗口在、restore 显示 `ok`、只有音频在播、画面黑。**restore_pending 重试对此无效**（窗口 active 不算 pending）；**mpv 自身不重试**（reconfig 失败即禁 track）。为何 xwinwrap+mpv 无此问题：独立 mpv 进程启动晚（fork/exec/加载），建 swapchain 时 GPU 已就绪。修复（xwallpaper 已提交）：backend 加 `retry()` 回调（video 查 mpv `video` 属性，无视频则重新 `loadfile` 重建渲染路径），daemon 启动后 2 分钟窗口内 **0.5s 节拍**轮询，reload 间 **1.5s 防堆积**（`load_file` 统一记 `last_load_ms`，含首次 loadfile 防竞态），GPU 就绪后 ≤1.5s 出视频。诊断方法（临时）：`XW_DEBUG_DAEMON=1 xwallpaper --daemon` 手动启动，restore/自愈日志打 stderr，mpv 日志写 `/tmp/xw-mpv-<winid>.log` + IPC socket `/tmp/xw-mpv-<winid>.sock`（`get_property video` 查有无视频 track）
- **热重启后 autostart 重跑杀掉 xwallpaperd 多闪一次已修复**: dwm SIGHUP 重启会重跑 `autostart.sh` → `wallpaper.sh -r` 的 `launch_wallpaper` 曾无条件 `pkill xwallpaperd` 再起新实例 (窗口销毁重建闪一次, 叠加主题切换自身的 set 共两次)。现抽取 `ensure_xwallpaperd()`: `pgrep` 存活直接复用零操作, 仅死亡/缺失才清理拉起; bash 轮换实例仍按旧逻辑去重重启 (只重置计时器, 不碰窗口)。回归测试 `tests/wallpaper-restart_test.sh` (存活零 pkill/零启动 + 死亡拉起 + launch 体内无裸 pkill 静态守卫, 旧代码 FAIL)
- **主题切换壁纸闪两次已修复 (两处)**: ① `theme_wallpaper` 无幂等 — 当前已是目标仍同名 set (xwallpaper 同名即 reload) 白闪一次, 现以 `--state` path 比对, 相等跳过 (random 分支本就排除当前, 主要命中记忆恢复路径)。② `_do_theme_change` 壁纸 job 后台 `&` + 固定 `sleep 0.3` 后 SIGHUP, set (find+ffprobe+set 约 0.4-1s) 落在 dwm 重启之后成第二次闪烁, 现改前台同步 SIGHUP 前落盘 (恒返回 0, 失败不影响切换; 与端点亮度同步化同类修复)。回归测试 `tests/wallpaper-last_test.sh` 场景 6 (旧代码 FAIL) + `tests/wallpaper-theme_test.sh` hook 前台断言 (`&)` 静态守卫)

### rofi 菜单（module.sh, script mode）

- `module.sh handle_network` 已改用 `nmcli -t -f BARS,BAND,BSSID,SSID` 解析 WiFi 列表（条目形如 `▂▄▆█ [2.4 GHz] SSID`，无 SSID 的隐藏网络以 BSSID 兜底）：nmcli ≥1.58 在表格输出新增 BAND 列（且 RATE 两 token），旧 `substr+$8` 列位解析会把 RATE 的 "Mbit/s" 当信号条显示
- 隐藏网络无法仅凭 BSSID 连接（802.11 关联握手必须携带真实 SSID，NM 会报 `A 'wireless' setting with a valid SSID is required for hidden access points`）：`handle_network` 检测到选中项为 MAC 时弹 `module_input` 让用户输入真实 SSID，再 `nmcli device wifi connect <ssid> hidden yes bssid <BSSID>`
- **rofi script mode 多属性必须用 `\x1f` 连接**：正确格式 `text\0icon\x1f<v>\x1finfo\x1f<id>`（仅行文本后一个 `\0`）。曾错误写成 `text\0icon\x1f<v>\0info\x1f<id>`（两个 `\0`）导致选中无反应：rofi 按 C 字符串语义解析属性块（`dmenuscript_parse_entry_extras` 的 `g_strsplit` 遇 `\0` 截断），第二个 `\0` 之后的内容（含 info）不可见 → `ROFI_INFO` 不设置 → 静默返回。测试断言注意：`grep -a` 对含 NUL 文件匹配不可靠、`$'\x00'` bash 展开的字面 NUL 会截断 grep -P 模式，须用单引号模式 `'\x00info'` + `grep -P`
- **Media Scraping Toggle 不管 daemon 已修复 (两处失效)**: ① daemon 没起时 `docker compose up` 直接失败, 菜单看起来"点了没反应"; ② 关完最后一个容器后 daemon 继续常驻。现 Toggle 联动 `docker.service`: up 分支未运行则先 `systemctl start`, down 分支全局无活动容器则停 socket。**`docker.socket` 是 `ListenStream=/run/docker.sock` + `Triggers=docker.service`**, 只停 service 时本脚本菜单构建里的 `docker compose ps` (`_is_running` 每个 Toggle 行一次, 一轮最多 10 次) 会经 socket 把 daemon 立刻拉起来等于没停 → 停 socket 才是收尾动作。`_is_running` 先过 `_docker_service_active` 门禁 (daemon 停着直接 rc=1 不 spawn docker)。停止口径是**全局** `docker ps -q` 为 0 (其他 compose 项目还有容器在跑就不停 daemon)。回归测试 `tests/media-scraping-docker_test.sh` (A-G/S 组)
- **`systemctl` 一条只能带一个 unit (多 unit 被 polkit 直接拒)**: 首版 down 分支写成 `systemctl stop docker.service docker.socket`, 实机表现为 Toggle 关服务后收到 critical "停止失败" 且**没有任何 polkit 窗口**。实测: 多 unit 调用 `rc=4 Failed to enqueue jobs: Access denied`、0-7ms 返回、journal 里连 `polkit-agent-helper-1` 都不 spawn (不是"弹窗超时", 是 polkit 在 challenge 之前就回绝); 与 docker 无关 (`systemctl start getty@tty9 getty@tty11` 同样被拒), 同一上下文里单 unit 调用正常走 agent (`polkit-agent-helper-1` + pam 认证, 2-11s)。修法: 一条 `systemctl` 只带一个 unit; 停 socket `systemctl stop docker.socket` 单条即连带停 service (`Requires=docker.socket`, 实测两者一起 inactive), 反过来 `stop docker.service` 会警告 `Stopping 'docker.service', but its triggering units are still active: docker.socket`; 另加兜底 `_docker_service_active && systemctl stop docker.service`。同时 `2>/dev/null` 会把唯一线索吞掉, 现改为 `err=$(...)` 把 stderr 带进通知。回归测试 D2/D3/D5/D7/F2/F3/S5 (变异: 改回多 unit → D2/D3/S5 FAIL; 删兜底 → D7 FAIL; 吞 stderr → F3 FAIL)

### Steam Workshop

- **`sw_fetch_page` 同行 `local` 赋值恒空已修复**: `local in="$1" url="$in"` 中 bash 同行多赋值不按序可见, `url` 恒为空 → `curl ''` 恒返回空, 页面 AppID 解析全灭 (全靠 `sw_api_info` 兜底才没全崩; mock curl 忽略参数故单测从未抓住)。现改单行 `local url="$1"`; mock 记 curl 参数 + 断言 URL 透传/纯数字拼 URL (旧代码 FAIL)。另注意成熟内容条目 (如 3649839464) 匿名页面是内容门 (无 `data-appid`, 亦非登录门), 页面链天然失败, 走 API 兜底
- **同 appid 反复 `failed (Failure)` 真因是 acf 幽灵记录 (与账号无关)**: `sw_download` 把 content 搬到扁平目录后 `appworkshop_<appid>.acf` 残留 Installed/manifest 记录, 下次同 appid 下载 steamcmd 按 acf 校验已不存在的 content 文件 (content_log 实证 `CFileReader ... errno: 2 ... Missing game files` → 整单 Failure)。证据: 中毒根下 0723wang/anonymous 同错、干净根 3 次成功、同盘新根成功 (排除文件系统)。修复: 成功搬离后删该 acf (下次全量重下; 失败保留以便续传; `sw_check_updates` 不读 acf 无影响; appid 入口已校验纯数字+路径钉死隔离根)。回归: 预置 stale acf → 成功后消失/失败保留 (旧代码 FAIL)
- **aurelia fallback 噪声曾误删刚下载的扁平目录**: `sw_run_updates` 用 `out=$(sw_download ... 2>&1)` 合并 stderr 再与源路径比对 (`[[ $out != $path ]] && rm -rf`), aurelia 失败打到 stderr 的日志会污染 `out` 使比对恒不等 → 删掉刚落盘的扁平目录。修复: `sw_download` 内 aurelia 失败输出暂存 `aur_err`, 仅 steamcmd 也失败时才一并打出, 成功路径 stderr 保持干净。**不变量**: `sw_download` 成功时 stdout 必须恰为扁平路径、stderr 必须为空。回归测试 `tests/steam-workshop_test.sh` "run: deep source pruned after move" (旧代码 FAIL)

### 录屏 / 投屏（screencast.sh, scrcpy.sh）

- **录屏麦克风只有左声道已修复 (aux0 未上混)**: 本机 PCM2902 单声道 USB 声卡 (`s16le 1ch`) 的 PipeWire channel map 是 `aux0` 而非标准 `MONO`; `module-loopback` 把 `aux0` 混入立体声 `screencast_sink` 时只映射到 front-left, 右声道静音 (桌面 loopback 源是 `FL,FR` 故正常)。实测 `AUX0→stereo` 右声道 -91 dB, `MONO→stereo` 左右均 -21 dB; `remix=true` / `channels=2` 均无效。修复: `setup_virtual_devices` 检测默认源为 1ch 时给麦克风 loopback 追加 `channels=1 channel_map=mono`, 由 PipeWire 按 mono 上混到左右 (每声道约 -6 dB, 总能量守恒; 立体声源不降混)。测试缝 `SCREENCAST_NO_DISPATCH=1`, 回归测试 `tests/screencast-mic-mono_test.sh`
- **scrcpy 横屏时上下划失效已修复 (wm size 不跟旋转)**: `_swipe` 每次按键都重查 `wm size`, 触发点本身是动态的; 病根是 `wm size` 返回自然方向尺寸 (真机验证: 横屏时仍 `1200x2670`), 而 `input swipe` 坐标系随旋转变化, 不交换 w/h 会发 y 越界坐标被系统静默忽略。修复: 新增 `_display_rotation()`, 只信 `displayId 0` 的 `mOverrideDisplayInfo` 行 (`, app W x H,` 判宽高 → `rotation N` 空格形式 → 老格式 `mCurrentRotation=` 兜底); 曾误命中 `displayShape{... rotation=0 ...}` 等静态段致横屏恒判 0 (第一版在真机上复现)。回归测试 `tests/scrcpy-swipe_test.sh` R12-R15 锁真机格式 (第一版 R12/R13 FAIL)

## 编码准则

> 以下准则偏向谨慎，非关键任务可灵活判断。

### 1. 先想后写

**不要假设，不要隐藏困惑，给出取舍。**

动手之前:

- 明确说出你的假设。不确定就问。
- 如果有多种解读，全部列出来——不要默默选一种。
- 如果有更简单的方案，直接说。该推翻就推翻。
- 如果某处不清楚，停下来，说清困惑点，问。

### 2. 简洁至上

**最小化代码解决问题，不写推测性代码。**

- 不添加用户没要求的功能。
- 不为单次使用的代码创建抽象。
- 不添加用户没要求的"灵活性"或"可配置性"。
- 不处理不可能发生的错误场景。
- 如果写了 200 行实际只需要 50 行，重写。

自问："高级工程师会觉得这过度设计了吗？" 是的话就简化。

### 3. 精准修改

**只动必须动的，只清理自己弄乱的。**

编辑已有代码时:

- 不"优化"相邻代码、注释或格式。
- 不重构没坏的东西。
- 匹配已有风格，哪怕你有不同偏好。
- 如果发现无关的死代码，提一下——但不要删。

当你的改动产生孤儿代码时:

- 删除你的改动导致不再使用的导入/变量/函数。
- 不要删除已有的死代码，除非被要求。

测试标准: 每一行改动都应该能追溯到用户的需求。

### 4. 目标驱动

**定义成功标准，循环直到验证通过。**

把任务转化为可验证的目标:

- "加校验" → "先写非法输入测试，让它通过"
- "修 bug" → "先写复现测试，让它通过"
- "重构 X" → "确保测试前后都通过"

多步骤任务，先列出简要计划:

```
1. [步骤] → 验证: [检查项]
2. [步骤] → 验证: [检查项]
3. [步骤] → 验证: [检查项]
```

### 5. 依赖完整性

**每次修改脚本后，检查并更新本文档中的调用链和依赖关系。**

修改脚本时:

- 新增/删除 `source` 引用 → 更新 Source 依赖图
- 新增/删除函数 → 更新函数定义与调用关系表
- 改动调用链路 → 更新调用链
- 新增/移动脚本文件 → 更新所有相关条目

工作流程:

1. 修改前先读本文档了解当前依赖
2. 修改后对比 `git diff`，同步更新本文档
3. 确保文档变更与代码变更一致
