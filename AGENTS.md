# AGENTS.md

> 此文件记录所有脚本间的 source 依赖、函数调用关系和调用链。
> 每次修改脚本后需同步更新 (见下方 §编码准则.5)。

## Source 依赖图

```
dwm-launcher.sh ──sources──► utils/monitor.sh
                ──windows subcmd──► rofi/scripts/windows-selector.sh (rofi -show window); ──requires─► wmctrl (窗口数统计)
dwm-status.sh ──sources──► dwm-status-tools.sh ──sources──► dwm-status-print.sh
                                                           utils/weather.sh
                                                           utils/notify.sh
dwm-statuscmd.sh ──sources──► utils/notify.sh
tools/theme.sh ──sources──► utils/notify.sh, tools/monitor-brightness.sh
                ──requires─► xsettingsd, dconf (gsettings), curl (GTK/portal 双通道广播 / auto 日出日落)
                ──calls──► tools/wallpaper.sh --theme <mode> (后台, 主题翻转跟随换壁纸)
tools/monitor-brightness.sh ──sources──► 无外部脚本; ──sourced by── tools/theme.sh

tools/lock.sh ──sources──► utils/notify.sh
              ◄──sourced by── rofi/powermenu/type-{1..6}/powermenu.sh
tools/wallpaper.sh ──sources──► utils/notify.sh, tools/wallpaper-lib.sh, tools/wallpaper-render.sh
tools/wallpaper-classify.py ──requires──► python3+PIL, ffmpeg/ffprobe (视频缩略图); 壁纸 light/dark 初筛 (B 规则暗像素占比), `--move` 按 verdict 搬进 light//dark/
tools/screencast.sh ──sources──► utils/monitor.sh
tools/brightness.sh ──sources──► utils/notify.sh
tools/calendar.sh ──sources──► utils/notify.sh
tools/keyboard.sh ──sources──► utils/notify.sh
tools/volume.sh ──sources──► utils/notify.sh
tools/touchpad.sh ──sources──► 无外部脚本
utils/form.sh ──sources──► 无外部脚本; ──requires─► jq, yad (优先) / zenity (fallback); 环境变量 FORM_BACKEND/FORM_CSS/FORM_WIDTH/FORM_FONT (yad 字体)/FORM_TITLE (对话框标题)
utils/url.sh ──sources──► 无外部脚本
utils/string.sh ──sources──► 无外部脚本

tools/yt-dlp.sh ◄──sourced by── rofi/scripts/yt-dlp-wrapper.sh

rofi/scripts/yt-dlp-wrapper.sh ──sources──► rofi/scripts/lib-module.sh, rofi/scripts/util.sh, utils/notify.sh, tools/yt-dlp.sh

rofi/scripts/quicklinks-mode.sh──sources──► utils/form.sh, utils/notify.sh, utils/url.sh, utils/string.sh, rofi/scripts/lib-module.sh (module_confirm); ──挂载于── rofi/launchers/type-3/launcher.sh (combi 模式 quicklinks modi)
rofi/scripts/module.sh      ──sources──► rofi/scripts/lib-module.sh, rofi/scripts/util.sh
rofi/scripts/wallpaper.sh   ──sources──► rofi/scripts/util.sh, rofi/scripts/lib-module.sh, tools/wallpaper-lib.sh
rofi/scripts/notification.sh──sources──► rofi/scripts/util.sh, rofi/scripts/lib-module.sh
rofi/scripts/sddm.sh       ──sources──► rofi/scripts/lib-module.sh, rofi/scripts/util.sh
rofi/scripts/screenshot.sh  ──sources──► rofi/scripts/lib-module.sh, rofi/scripts/util.sh
rofi/scripts/screencast.sh  ──sources──► rofi/scripts/lib-module.sh, rofi/scripts/util.sh, utils/monitor.sh
rofi/scripts/media-scraping.sh──sources──► rofi/scripts/lib-module.sh, rofi/scripts/util.sh
rofi/scripts/mpd.sh         ──sources──► rofi/scripts/lib-module.sh, rofi/scripts/util.sh; ──requires─► MPD `readpicture` 协议 (nc / bash /dev/tcp, 环境变量 MPD_HOST/MPD_PORT 默认 localhost:6600); 封面缓存 `~/.cache/dwm/mpd-cover/mpd-cover-<uri-hash>.jpg` (按歌曲 uri cksum 绑定, 命中复用)
rofi/scripts/sing-box.sh    ──sources──► rofi/scripts/lib-module.sh, rofi/scripts/util.sh, utils/notify.sh
rofi/scripts/scrcpy.sh    ──sources──► rofi/scripts/lib-module.sh, rofi/scripts/util.sh
rofi/scripts/theme.sh──sources──► rofi/scripts/lib-module.sh, rofi/scripts/util.sh, tools/theme.sh

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
`brightness.sh` `calendar.sh` `keyboard.sh` `lock.sh` `volume.sh` `dwm-status-tools.sh` `dwm-statuscmd.sh` `sing-box.sh` `wallpaper.sh` `tools/theme.sh` `yt-dlp-wrapper.sh`

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

### rofi/scripts/quicklinks-mode.sh (rofi script mode)

| 函数               | 调用者                                                                 |
| ------------------ | ---------------------------------------------------------------------- |
| `_main()`          | 主入口 (按 ROFI_RETV 分派: 0=列表, 1=选中, 2=自定义输入, 3/11=删除, 10=编辑) |
| `_list()`          | _main (RETV=0; _ensure_ids + _load + _ensure_icons 后输出; 缓存 hit 输出 `name\0icon\x1f<png>\x1finfo\x1f<id>`, miss/fail 输出纯文本 `name\0info\x1f<id>` + New 行 + New Searcher 行 + searcher @ 提示行 (`@<name>\0nonselectable\x1ftrue`, host 命中 favicon 缓存时追加 `\x1ficon\x1f<png>`; 输入 `@` 过滤仅剩这些行展示可用引擎, nonselectable 只展示不可选中, 不影响 RETV=2 自定义输入) + use-hot-keys; hit 判定内联 `[[ -f ]]` 避免 `$()` fork) |
| `_collect_host()`  | _ensure_icons (去重 + 跳过已 png/.fail, 未缓存 host 追加进 pending; 依赖调用者局部 seen/pending, bash 动态作用域) |
| `_ensure_icons()`  | _list (收集 links + searcher 的 host 去重 → 后台子 shell 分片并发下载, 每 8 个 wait 一轮防限流; 已 png/.fail 跳过; searcher 引擎域名经 `_host_from_url` 提取; stdout/stderr 重定向防 SIGPIPE) |
| `_dispatch()`      | _main (RETV=1; info=new → _new_link, info=new-searcher → _new_searcher, 否则按 id 打开) |
| `_open_url()`      | _open_by_id, _handle_input (xdg-open 后台执行, 外部程序必须 `( cmd & )` 否则 rofi 等待其输出) |
| `_open_by_id()`    | _dispatch (jq 查 URL → _open_url)                                      |
| `_handle_input()`  | _main (RETV=2; is_url ? 补协议打开 : 搜索引擎搜索; 首 token `@<name>` 精确匹配(忽略大小写)命中 searcher → 用目标引擎, 未命中/无 @ → 默认 searcher[0], searcher 数组为空回退 SEARCH_ENGINE; 仅 `@name` 无搜索词不打开) |
| `_build_search_url()` | _handle_input (jq @uri 编码搜索词替换 `{key}`; 无 `{key}` 追加 url 末尾; bash 参数展开花括号须转义 `\{key\}`) |
| `_searcher_url_by_name()` | _handle_input (jq ascii_downcase 忽略大小写精确匹配 searcher name → url, 未命中输出空) |
| `_interact_async()`| _edit_link, _delete_link, _new_link, _new_searcher (后台子 shell 等 rofi 退出释放 grab 后执行命令 — script mode 下 rofi 存活期间 grab 键盘, 须先让 rofi 退出) |
| `_write_json()`    | _ensure_ids, _edit_form, _delete_form, _new_form, _new_searcher_form (jq 表达式原子写回 CONFIG: 唯一 tmp + mv, 避免并发写 .tmp 冲突) |
| `_edit_link()`     | _main (RETV=10; 按 id 预填数据 → _interact_async _edit_form)           |
| `_edit_form()`     | _interact_async (表单录入 + 按 id 替换写库, 保留 id)                   |
| `_delete_link()`   | _main (RETV=3/11; 按 id 取名字 → _interact_async _delete_form)         |
| `_delete_form()`   | _interact_async (module_confirm 确认后 jq 删除 + notify)               |
| `_new_link()`      | _dispatch (info=new; → _interact_async _new_form)                      |
| `_new_form()`      | _interact_async (剪贴板 URL 预填 + 表单校验 + jq 追加; clipboard_url 须在此执行 — xclip 可能阻塞, 不能留在 rofi grab 存活期间) |
| `_new_searcher()`  | _dispatch (info=new-searcher; → _interact_async _new_searcher_form)    |
| `_new_searcher_form()` | _interact_async (复用 _edit_loop 表单 + jq 追加到 `.searcher`; name 忽略大小写重名 → critical notify 拒绝, 不写入) |
| `_edit_loop()`     | _edit_form, _new_form, _new_searcher_form (表单录入 + 校验循环; 仅 name/url 两字段; 第三参 url_label 自定义 URL 字段标签) |
| `clipboard_url()`  | _new_form (剪贴板严格 URL 校验, 无效静默返回非 0)                      |
| `_gen_id()`        | _ensure_ids, _new_form (uuid 优先, base64 fallback)                    |
| `_ensure_ids()`    | _list (全部有 id 时零写入早退, 仅缺 id 时全量重生成)                    |
| `_load()`          | _list (构建 `_links` 四元组数组 `name|id|url|host`, host 一次性提取复用, 避免每次 fork python3) |
| `_host_from_url()` | _load (纯 bash 参数展开提取 hostname, 零子进程; 结果写 `$_HOST` 全局变量而非 stdout — 避免 `$()` 命令替换 fork, _load 循环每行一次约省 40ms/64 条) |
| `_fetch_favicon()` | _ensure_icons (① 页面 HTML 解析 link rel=icon 真实 favicon (优先标准 rel=icon 排除 apple-touch 白底大图), 相对路径拼接 host → ② 降级链 DuckDuckGo→Google s2→站内 /favicon.ico; curl 带浏览器 UA 防 429 限流 + 超时 + file MIME 校验 image/* + tmp/mv 原子写; 全失败写 .fail 标记) |
| `_dl_icon()`      | _fetch_favicon (curl 下载到文件 + file MIME 校验 image/*, 失败返回 1) |
| `_icon_href()`    | _fetch_favicon (从 HTML 提取 icon link 的 href, 第二参排除子串如 apple-touch) |

### tools/lock.sh

| 函数                  | 调用者                                                       |
| --------------------- | ------------------------------------------------------------ |
| `_lock_before()`      | lock() / suspend() → 所有 powermenu 脚本                     |
| `_lock()`             | lock() / suspend() → 所有 powermenu 脚本 / screen.sh(LOCKER) |
| `_lock_after()`       | lock() / suspend() → 所有 powermenu 脚本                     |
| `_screen_lock_loop()` | lock() / suspend() → 所有 powermenu 脚本                     |
| `lock()`              | screen.sh 的 LOCKER / `lock.sh lock` CLI                     |
| `suspend()`           | `lock.sh suspend` CLI                                        |

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
| `module_sub_rofi()`   | module.sh (handle_network, handle_bluetooth, handle_audio_output 的子菜单), sddm.sh (handle_set_theme, handle_set_config 的子菜单), scrcpy.sh (handle_select_device 的子菜单), wallpaper.sh (monitor_selection / handle_group 的子菜单), sing-box.sh (主菜单), yt-dlp-wrapper.sh (格式/清晰度子菜单) |
| `module_input()`      | yt-dlp-wrapper.sh (URL 输入框), wallpaper.sh (handle_group 组名输入)                                                                                                                                                                                                                                 |
| `module_multi_rofi()` | wallpaper.sh (handle_group 组成员多选)                                                                                                                                                                                                                                                               |
| `module_confirm()`   | quicklinks-mode.sh (_delete_link Alt+2 删除确认) |

### rofi/scripts/media-scraping.sh

| 函数            | 调用者                                                       |
| --------------- | ------------------------------------------------------------ |
| `_toggle()`     | media-scraping.sh (启停 docker compose 服务)                 |
| `_is_running()` | media-scraping.sh (Open 前检查容器状态, Toggle 图标状态检查) |

### rofi/scripts/mpd.sh

| 函数                | 调用者                                            |
| ------------------- | ------------------------------------------------- |
| `fetch_cover()`     | mpd.sh (主流程 else 分支: 拉取当前歌曲封面 → icon-cover 注入) |
| `_mpd_readpicture()` | fetch_cover (单次 readpicture 请求, nc 优先 /dev/tcp fallback) |
| `_cover_valid()`    | fetch_cover (成功校验), mpd.sh 主流程 (cache 命中校验) — 非空 + `file` MIME `image/*`; 空/损坏文件视为无效, 失败时 `rm -f` 删除避免残留空缓存 |

> 封面注入: 用 rofi `icon` widget (`icon-cover`, `filename` + `size: 200` + `squared` 默认 true 强制 1:1 正方形) —
> 不能用 `imagebox`: 它不是真实 widget (rofi 静默当 `box`), `height` 属性被忽略 (box_get_desired_height 只累计 children),
> 无法保证 1:1。cache 按歌曲 uri cksum 命名放 `~/.cache/dwm/mpd-cover/`, 命中复用不重复拉取。
> 校验: 主流程 cache 命中判断 `_cover_valid` (不存在/空/损坏均视为 miss) → `rm -f` + 同步拉取 (`fetch_cover` 已优化 ~50ms, 原 `( ... & disown )` 后台异步已移除); 拉取失败回退 `rofi/images/flowers-2.png` 默认图 (透明背景 Nerd Font flowers 图标)。fetch_cover 失败同样删除输出, 不留空文件。

### theme.sh (tools/)

| 函数                      | 调用者                                                                                                                                           |
| ------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------ |
| `_do_theme_change()`      | tools/theme.sh (apply / auto_daemon; 第二参 `nobright` 跳过一次性端点亮度) — daemon 翻转只切配色，亮度由每轮插值统一负责；手动 apply 保留端点亮度 (apply 后 auto 关闭) |
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
| `set_gtk_theme()`         | tools/theme.sh (_do_theme_change: 写 gtk2/3/4 持久配置 (主题/icon/光标 theme+size, 源 `theme.json:cursor`) + 运行时双通道广播 — xsettingsd GTK 主题名 + `Gtk/CursorThemeName/Size` / gsettings color-scheme 同步 portal + `cursor-theme/size`) |
| `get_auto_config()`       | tools/theme.sh (auto_daemon, auto on/off, apply)                                                                                                 |
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

### rofi/scripts/wallpaper.sh

| 函数                          | 调用者                                                  |
| ----------------------------- | ------------------------------------------------------- |
| `monitor_selection()`         | wallpaper.sh (主入口: 选择 monitor/组)       |
| `handle_next()`               | wallpaper.sh (模块主菜单: 下一张; `( tools/wallpaper.sh -m ... next & )` 后台执行, rofi 立即重开) |
| `handle_select()`             | wallpaper.sh (模块主菜单: 选择文件)                     |
| `handle_random_switch()`      | wallpaper.sh (模块主菜单: 随机开关 toggle)              |
| `handle_random_type()`        | wallpaper.sh (模块主菜单: 类型切换 toggle)              |
| `handle_random_duration()`    | wallpaper.sh (模块主菜单: 设置轮换间隔)                 |
| `handle_random_depth()`       | wallpaper.sh (模块主菜单: 设置搜索深度)                 |
| `handle_random_images_path()` | wallpaper.sh (模块主菜单: 选择图片目录)                 |
| `handle_random_videos_path()` | wallpaper.sh (模块主菜单: 选择视频目录)                 |
| `handle_random_images_path_dark()` | wallpaper.sh (模块主菜单: 选择深色图片目录 → `random_image_dir_dark`) |
| `handle_random_videos_path_dark()` | wallpaper.sh (模块主菜单: 选择深色视频目录 → `random_video_dir_dark`) |
| `handle_group()`              | wallpaper.sh (模块主菜单: 组管理 — 新建/编辑/启停/删除) |

### tools/wallpaper-lib.sh

| 函数                         | 调用者                                                                                                                                                                                                       |
| ---------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `getConfig()`                | wallpaper.sh, wallpaper-lib.sh (内部)                                                                                                                                                                        |
| `get_theme_dir()`            | wallpaper.sh (random_wallpaper, select_wallpaper, theme_wallpaper) — 主题目录解析: light 用 base key, dark 用 `${base}_dark`, 为空 fallback base; theme 缺省读 current-theme |
| `ensure_monitor_config()`    | rofi/scripts/wallpaper.sh (主入口选定 monitor 后初始化写入) — 遍历 `config` 数组写默认, 跳过 volume/fps (video-render 子对象默认) |
| `detect_file_type()`         | wallpaper.sh, wallpaper-render.sh                                                                                                                                                                            |
| `get_video_dim()`            | wallpaper.sh (get_wallpaper_rotation) — 单次 ffprobe 合并取 dims+rotation (csv 第三列), 原两次独立调用省一半耗时                                                                                                                                                                        |
| `orientation_mismatch()`     | wallpaper.sh (get_wallpaper_rotation)                                                                                                                                                                        |
| `get_monitor_dim()`          | wallpaper.sh (get_wallpaper_rotation)                                                                                                                                                                        |
| `preview_rotation()`         | wallpaper.sh (get_wallpaper_rotation)                                                                                                                                                                        |
| `find_wallpapers()`          | wallpaper.sh (random_wallpaper)                                                                                                                                                                              |
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
| `pick_config_dir()`          | rofi/scripts/wallpaper.sh (handle_random_images_path[_dark], handle_random_videos_path[_dark])                                                                                                                             |
| `set_numeric_config()`       | rofi/scripts/wallpaper.sh (handle_random_duration, handle_random_depth)                                                                                                                                      |
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
| `random_wallpaper()` | wallpaper.sh (`-m next`, launch_wallpaper daemon, theme_wallpaper) — 经 `get_theme_dir` 按当前主题选目录 (第二参可显式传 light/dark); 排除当前壁纸后随机抽取 |
| `select_wallpaper()` | wallpaper.sh (`-m select`) — 经 `get_theme_dir` 按当前主题定 yazi 起始目录 |
| `theme_wallpaper()` | wallpaper.sh (`--theme [light\|dark\|auto]` CLI) / tools/theme.sh `_do_theme_change` (后台 hook) — 枚举 active monitors + enabled groups (skip 组员, 坏组跳过), Screen 激活时只切 Screen, 单 target 失败跳过整体恒返回 0 |

### tools/wallpaper-render.sh

| 函数                         | 调用者                                                           |
| ---------------------------- | ---------------------------------------------------------------- |
| `set_wallpaper_to_screen()`  | wallpaper.sh (apply_wallpaper, set_latest), 内部调 xw_clear_all_exclude_screen 清空所有 monitor/group 壁纸窗口后整屏铺图 (Screen 自身由 set 同名 reload 覆盖, monitor/group 经 --keep 保留 last) |
| `set_wallpaper_to_monitor()` | wallpaper.sh (apply_wallpaper, set_latest), 内联检查所属组并清组窗口 (组与成员互斥, mon_name 自身靠同名 reload) + xw_clear_screen_and_restore (与 screen 互斥, 清除后 restore 回退 last) |
| `set_wallpaper_to_group()`   | wallpaper.sh (apply_wallpaper, set_latest), 内部调 xw_clear_group_members 清成员 monitor 独立窗口 (grp_<组名> 自身靠同名 reload) + xw_clear_screen_and_restore (与 screen 互斥, 清除后 restore 回退 last); 向 xw_apply 显式传组名为 confname (config 键用组名, 非窗口名 grp_<组名>) |

## 调用链 (Call Chain)

### 锁屏/挂起链路

```
rofi powermenu (用户点击)
  → type-*/powermenu.sh (source lock.sh)
    → _lock_before()   # 暂停音乐、静音、暂停 mpv/xwallpaper 渲染
    → _lock()          # 启动 i3lock, xset dpms force standby
    → systemctl suspend  (仅 suspend)
    → _screen_lock_loop()  # 循环监控: 唤醒 → 空闲 → 重新 standby
    → wait             # 等待 i3lock 退出
    → _lock_after()    # 恢复音乐、音量、恢复 mpv/xwallpaper 渲染

screen.sh (DPMS 守护)
  → LOCKER="lock.sh lock"  # 由 xautolock 在超时后调用
```

### 启动链路

```
DWM 启动
  → autostart.sh
    → picom &                          # launch(): 每 name 独立 flock 锁 (autostart-launch-<name>.lock) 保证
    → dunst &                          #   检查+启动原子, 重入时后者跳过; restart 轮询等旧进程退出 (≤2s)
    → xautolock -locker "lock.sh lock" &    # 定时锁屏
    → fcitx5 &
    → xsettingsd &                          # XSETTINGS 广播 (theme.sh set_gtk_theme 依赖)
    → udiskie &
    → lxpolkit &
    → setxkbmap ...
    → bash keyboard.sh &
    → bash wallpaper.sh &
    → bash dwm-status.sh &                  # 状态栏
    → bash screen.sh &                      # DPMS 守护 (parec 录默认输出判响度, 有声不熄屏)
    → bash brightness.sh &
    → bash tools/theme.sh auto &           # 自动主题切换 (auto=false 时立即退出)
```

### 状态栏链路

```
dwm-status.sh
  → source dwm-status-tools.sh
    → source utils/weather.sh, utils/notify.sh
  → new_pane("...", print_*)
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
    → rofi/scripts/wallpaper.sh (壁纸管理，由 module.sh handle_wallpaper 调用)
    → tools/touchpad.sh toggle (触控板开关，由 module.sh handle_touchpad 调用)
  → rofi/scripts/media-scraping.sh  (Media 启停子菜单，由 module.sh 调用)
  → rofi/scripts/screenshot.sh
  → rofi/scripts/screencast.sh
  → rofi/scripts/quicklinks-mode.sh (rofi -show quicklinks 外部脚本模式, ROFI_RETV 分派; )
  → rofi/scripts/emoji.sh
  → rofi/scripts/notification.sh
  → windows (窗口切换: rofi/scripts/windows-selector.sh, rofi -show window)
```

### 自动主题切换链路

```
tools/theme.sh auto (守护进程)
  → get_sun_times() (ipinfo.io/loc + open-meteo daily=sunrise,sunset)
  → get_current_theme() (xrdb -query dwm.col_theme)
  → 日出/日落触发:
      → _do_theme_change("light"|"dark", nobright) (只切配色)
      → (wallpaper.sh --theme <mode> &) 后台跟随换壁纸 (失败不影响切换)
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
  │    └─ launch_wallpaper 启动 xwallpaper daemon, 启动时自动恢复 keep=0 状态
  └─ 状态: xwallpaper 持久化 (state 文件), daemon 重启自愈
```

## 配置文件

- `rofi/` 下各 type 目录的 `*.rasi` 文件
- `rofi/fonts/` 字体文件
- `rofi/colors/` `rofi/images/`
- `~/.config/dwm/quicklinks.json` — quicklinks 书签, `links` 数组元素含 `id`(uuid)、`name`、`url` (icon 字段已废弃移除); 顶层 `searcher` 数组存搜索引擎 `{name, url}`(name 为唯一键, url 用 `{key}` 占位搜索词, 可省略 → 追加 url 末尾), 自定义输入搜索默认用 `searcher[0]`, 支持 `@<name>` 首 token 指定引擎
- `~/.config/dwm/wallpaper.json` — 壁纸配置, 含 `monitors`(按屏/组名键)、`groups`(成员名单 + enabled 启停); 每个 monitor/组可带可选 `video-render` 对象 `{volume, fps}`: `volume>0` 传 `--volume N` 播放音频, `volume=0`/缺省时传 `--mute` 静音 (0 与 mute 等价), `fps>0` 传 `--fps`; 主题色调目录: light 用 `random_image_dir`/`random_video_dir`, dark 用 `random_image_dir_dark`/`random_video_dir_dark` (缺失/空串 fallback light, rofi Wallpaper 菜单 Images Dark/Videos Dark 配置)
- `~/.config/dwm/theme.json` — `tools/theme.sh` 的外部化主题配置，`"auto"` 含 `enabled`(默认 false)、`sun_rise_offset`(日出延迟分钟数)、`sun_set_offset`(日落延迟分钟数)、`dawn_minutes`/`dusk_minutes`(亮度过渡分钟数，默认 60，0=关闭渐变)、`transition_anchor`(过渡锚点 `after`(默认，事件后窗口) / `center`(对称窗口) / `before`(事件前窗口))，`"cursor"` 含 `theme`/`size`，`"dpi"` 为 Xft.dpi 值，`light`/`dark` 的 `colorscheme` 引用 `~/.config/dwm/colorschemes/` 下的颜色方案文件
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

- `tools/calendar.sh:3` source 路径已修复为 `$(dirname "$0")/../utils/notify.sh`
- **mpd.sh fetch_cover 慢已修复**: 根因不是 MPD 网络往返而是客户端每 chunk 固定开销。① `nc -q1` 在 stdin EOF 后须等 1s 才退出，而 MPD 收 `close` 不主动断连 → 每块白白等 1s，readpicture chunk 上限 8192B，N 块 ≈ N 秒（实测 30KB 封面 4 块整函数 4102ms，改 `-q0` 后 88ms；1MB 封面 128 块会到 ~128s）。② `dd bs=1 skip=...` 逐字节跳过+拷贝，块内 skip 从文件头重来，累计 O(n²) 字节级 syscall（1MB 封面 128 块 ~6700 万次单字节 read），改 `iflag=skip_bytes,count_bytes bs=4096`（精确 seek + 块拷贝）。**单连接方案评估后放弃**: bash 无法可靠"恰好读 N 字节且把后续保留在流中"（read 缓冲与 fd 不同步、dd over-read 会吞掉下一响应 header、binary 块无长度外分隔标记），需 python/复杂协议解析，与仓库纯 bash 风格冲突，且 fetch 为低频场景（cache 按 uri 命中后不再拉），`-q0`+iflag 已把 4.1s→48ms，额外收益不足以抵风险。回归测试 `tests/mpd-cover_test.sh`
- `tools/screen.sh:16` LOCKER 路径已改为 `$(dirname "$0")/lock.sh lock`，不再依赖 `$TOOLS_DIR`
- `tools/screen.sh` 的 `_has_active_audio()` 现改为**录默认输出判响度**（原 pw-dump 按 media.role/tlength 过滤流的方案已丢弃，总会遗漏播放流致误锁屏；`EXCLUDE_APPS`/`SCREEN_AUDIO_MODE`/`_jq_exclude_apps()`/pw-dump 双后端均已删除）：`parec --device "$(pactl get-default-sink).monitor"` 定长采 150ms (head -c 截断触发 SIGPIPE) → ffmpeg volumedetect → max_volume 超阈值即认为有活动音频。注意 **raw `pw-record` 解析不到本机 `*.monitor` 节点会静默回落到默认麦克风（录到输入而非输出），必须用走 pulse 层的 `parec`**；且 sink monitor 采的是 sink 音量衰减后的信号（本机 Fosi 30% 音量衰减约 25dB+），阈值取 -78 dB（真静音底约 -91 dB，静音时返回 none）
- `tools/lock.sh` 的 `_screen_lock_loop` 在 xprintidle 缺失时有 fallback (sleep 30s 代替空闲检测)
- `tools/theme.sh` 旧 Firefox 切换方案（`set_firefox_theme` + `_get_darkreader_shortcut`，xdotool 模拟 Dark Reader 快捷键）已删除：Dark Reader 的 `extension-settings.json` 快捷键实际为空串，jq 的 `//` 不兜底空串 → `xdotool key ""` 从未生效；且依赖 Firefox 窗口存在、/tmp 状态文件易漂移。现由 `set_gtk_theme()` 双通道替代
- **Firefox content 亮暗由 portal 决定而非 GTK**：Firefox 的 `prefers-color-scheme` 走 `nsLookAndFeel::ComputeColorSchemeSetting()` → xdg-desktop-portal 的 `color-scheme`（gsettings `org.gnome.desktop.interface color-scheme`），且 Firefox 将 portal 返回的 `0 (default)` 硬映射为 light（nsLookAndFeel.cpp case 0）。因此 `set_gtk_theme()` 必须同时写 gsettings（prefer-dark/prefer-light），仅广播 GTK 主题名不足以切换 Firefox content scheme
- `tools/theme.sh apply` 的退出码已修复：auto 关闭时末尾 `[ ... ]` 返回 1 导致 apply 成功但 exit 1，现显式 `exit 0`
- **"dark 主题却是 light 亮度"已修复**：根因 `_do_theme_change` 把 `set_monitor_brightness "$mode"` 放**后台** (`&`)，两次主题切换重叠时先启动但更慢的 job（DDC 单次 `setvcp` ~200ms、首次 `ddcutil detect` ~1.6s）在返回后才落盘，用旧主题亮度覆盖后启动的新主题；而 `apply_transition_brightness` 窗口外不写（故意不抢手动/OSD），错值便一直挂着不自愈。改为**同步**执行（后调用者最后写，值正确）。回归测试 `tests/theme-brightness_test.sh` "端点亮度同步写完"（mock 慢 job，旧代码后台化时返回即可见断言 FAIL）
- `tools/theme.sh auto_daemon` 挂起/锁屏问题已修复：原实现 `sleep $((next_switch - now))` 一次性睡到切换点，但 sleep 计时在挂起(休眠)期间暂停、唤醒后剩余秒数继续走 → 跨挂起的主题切换延迟数小时（例：23:00 睡 8h 到次日 7:00 切换点，挂起 9h 后 8:00 唤醒，sleep 还剩 8h，到 16:00 才重算）。现改为 60s 内轮询（`remain>60` 时 sleep 60，否则精确睡到点），每次醒来重算 desired，挂起唤醒后最多 60s 纠正。锁屏（i3lock）期间仍阻塞不切（避免与 dwm SIGHUP 重启竞态），解锁后下一轮立即重算切换。回归测试 `tests/theme_test.sh`（mock date/sleep/pgrep + 文件驱动时间推进，后台 daemon 无法感知环境变量变更，须用文件 mock 时间/锁屏状态）
- `tests/theme_test.sh` 必须 mock `xrandr/brightnessctl/ddcutil`：daemon 每轮调 `apply_transition_brightness` → 真 `xrandr --listactivemonitors` 在无显示环境可能枚举出幽灵 monitor（如 `DisplayPort-0`），进而 `read_brightness` 走 `ddcutil detect` 长时间 hang 住导致用例全挂；mock 后 loop 零 monitor 直接 no-op。另须 `export THEME_LOCK` 指向临时路径：flock 单实例守卫下测试 daemon 会与用户 live daemon 争锁秒退，全挂；回归测试 `tests/theme-brightness_test.sh`（纯函数单测 + mock xrandr/读写函数的 `apply_transition_brightness` 集成）
- `tests/theme_test.sh` 场景边界（B/C）必须先停旧 daemon、布好状态、清 log 后再起新实例：mock sleep 瞬时返回使 daemon 热循环，旧实例的在途迭代（持旧缓存/旧状态）会在清 log 后落盘 `theme_change`，误杀"…不切换"断言（负载高时必现；生产代码按读到的有效数据切换是正确的，属测试同步问题）。已修：`stop_daemon`/`start_daemon` 包场景 setup
- **theme auto daemon 死锁致整早未切 light 已修复 (三处)**: ① 长 sleep 继承 flock 锁 (FD 9)：开机 daemon 缓存缺失进 `sleep 1800`，期间 `auto off` 的 `pkill -f 'theme\.sh auto$'` 只杀父进程，孤儿 sleep 被 init 接管继续占锁 → 后续 daemon `_auto_lock` 永远失败秒退、主题永不切换。现 auto_daemon 内所有 `sleep` 及 `get_sun_times` 后台拉取子 shell 均 `9>&-` 关闭锁 FD。② 缓存缺失睡 1800：后台异步拉取几秒即写好缓存，daemon 却睡半小时才重算 → 改为 `sleep 30` 短轮询（`.fetching` 1 分钟锁防刷）。③ 拉取失败沿用上轮残留时间：`read sunrise...` 只在 `if times=$(...)` 成功分支执行，失败时循环外 `local` 变量保留旧值 → `[ -n ... ]` 照过、短重试成死代码（跨零点缓存过期后还会拿昨天日出时间 tight-loop 空转烧 CPU）→ 失败分支显式清空。回归测试场景 C（删缓存 → 断言 `sleep 30` 且无 `sleep 1800` → 手写缓存恢复切换）+ auto_daemon 内 sleep 全带 `9>&-` 静态守卫；另修 `auto on` 分支顶层 `local pid`（非函数内，每次报错，改 `pid=""`）
- `module.sh handle_network` 已改用 `nmcli -t -f BARS,BAND,BSSID,SSID` 解析 WiFi 列表（条目形如 `▂▄▆█ [2.4 GHz] SSID`，无 SSID 的隐藏网络以 BSSID 兜底）：nmcli ≥1.58 在表格输出新增 BAND 列（且 RATE 两 token），旧 `substr+$8` 列位解析会把 RATE 的 "Mbit/s" 当信号条显示
- 隐藏网络无法仅凭 BSSID 连接（802.11 关联握手必须携带真实 SSID，NM 会报 `A 'wireless' setting with a valid SSID is required for hidden access points`）：`handle_network` 检测到选中项为 MAC 时弹 `module_input` 让用户输入真实 SSID，再 `nmcli device wifi connect <ssid> hidden yes bssid <BSSID>`
- **rofi script mode 多属性必须用 `\x1f` 连接**：正确格式 `text\0icon\x1f<v>\x1finfo\x1f<id>`（仅行文本后一个 `\0`）。曾错误写成 `text\0icon\x1f<v>\0info\x1f<id>`（两个 `\0`）导致选中无反应：rofi 按 C 字符串语义解析属性块（`dmenuscript_parse_entry_extras` 的 `g_strsplit` 遇 `\0` 截断），第二个 `\0` 之后的内容（含 info）不可见 → `ROFI_INFO` 不设置 → 静默返回。测试断言注意：`grep -a` 对含 NUL 文件匹配不可靠、`$'\x00'` bash 展开的字面 NUL 会截断 grep -P 模式，须用单引号模式 `'\x00info'` + `grep -P`
- **视频 rotation 元数据**：手机竖拍视频编码常为横屏 1920x1080 但带 display matrix rotation=-90/90 元数据（`ffprobe -show_entries stream_side_data=rotation`），实际显示为竖屏 1080x1920。`get_video_dim()` 必须读取该元数据并交换宽高，否则竖屏视频被误判为横屏——应用到竖屏 monitor（xrandr rotate left，如 `HDMI-A-0` 报告 `1080x1920`）时方向误判触发无谓的旋转预览。`preview_rotation()` 初始 `--video-rotate` 由硬编码 `90` 改为 `0`：mpv 的 `video-rotate` 是**叠加**在文件元数据之上的额外旋转（默认 `auto` 自动应用元数据，lavc 实测默认输出 1080x1920、`--video-rotate=90` 叠加后输出 1920x1080），硬编码 `90` 让带元数据旋转的视频初始画面变横屏，且 watch-later 无该行（`video-rotate=0` 为默认值 mpv 不写入）时 fallback 错误回到 `90`。xwallpaper 本机为 libmpv 内嵌版，`--rotate N` 直接映射 mpv `video-rotate`，与预览同引擎同语义，空 rotation 时不传 `--rotate` 由 mpv 自动旋转
- **壁纸 latest 状态已迁移至 xwallpaper**: 脚本侧 `wallpaper_latest_*` / `wallpaper_full_latest` 缓存文件
  删除, 由 xwallpaper 按 name 持久化 (`$XDG_STATE_HOME/xwallpaper/state`, `keep` 标志区分当前窗口/last)。
  脚本侧查询当前壁纸走 `xwallpaper --state`。`clear --keep` + `restore` 替代原 screen 清场保留/回退逻辑。
  **行为变化**: `clean_group` 后若铺 screen 再切回, 之前被普通 clear 的 target 仍可能被 restore 拉回
  (原实现会删缓存, 现普通 clear 删状态、仅 `--keep` 保留; 实际场景中 clean 后再铺 screen 极罕见, 可接受)。
- **auto_daemon 脏数据防护已加固**: ① sun-times 读后数字校验 (非数字曾坍缩 epoch 0 → remain 恒负无 sleep 热循环 + desired 恒 dark → SIGHUP 风暴，现 sleep 30 跳过)。② fetch 落盘前校验 (坐标正则 + 三时间非空 + date 成功 + epoch 数字 + `ss>sr、sr2>ss` 时序；`date -d ""` 会静默返回当前时间，脏响应直接丢弃、不写缓存、不删 throttle 锁)。③ offset `^-?[0-9]+$` 校验 (非法→0；旧 `$((...))` 对 "abc" 静默 0、对 "08" 直接报错)。④ `auto.enabled` 三态：false/未知非空→退出，空 (瞬时不可读/缺 key)→sleep 10 重试不退出 (编辑器非原子写曾永久杀死 daemon)。⑤ i3lock 等待 loop 内重查 enabled (锁屏期间 auto off 生效，不补 stale 翻转)。⑥ SIGHUP 前校验 `current-theme == desired` (`_do_theme_change ""` early-return 时不重启)。回归测试 `tests/theme-autofix_test.sh` (D 脏缓存 / E enabled 缺失自愈 / F 脏 API / H 锁被占不 spawn；旧代码下 D1/D4/E1-3/F1-2/H2 均 FAIL)
- **后台任务 flock FD 继承已全覆盖**: `_auto_lock` 注释的 `9>&-` 不变量此前只守了 auto_daemon 内 sleep，`_do_theme_change` 链的 `set_kitty_theme &` / wallpaper `( ... & )` / `fcitx5 -r &` / `xsettingsd &` 全继承 FD 9 —— 开机首次切换拉起的常驻 xsettingsd 会永久占锁致后续 daemon 秒退 (auto 假死)。现四处均加 `9>&-`，静态守卫 `tests/theme-autofix_test.sh` G1 (旧代码 FAIL)
- **rofi `next` 卡顿已修复**: 原 `xwallpaper` CLI 为单进程架构, 每次裸调用约 0.2s (X 连接+库加载), 一次 `next` 链路需串行 4-6 次 clear/restore/set (~1.5s)。原 `handle_next` 同步执行导致 rofi 要等 next 跑完才重开 (点 Next 后空白 1.5s)。修复两层: ① 脚本层 `handle_next` 改 `( tools/wallpaper.sh -m ... next & )` 后台执行, rofi 立即重开; ② xwallpaper 改为 **client+daemon 架构** (`xwallpaperd` 常驻, CLI 经 IPC 通信, 实测 `--list`/`--state`/`clear` 从 ~0.2s 降至 ~0.001s, group next 从 0.97s 降至 0.4s, 大图 set 从 0.6-1s 降至 0.16s)。另修复 `xwallpaper state` → `--state` 拼写 (3 处), 此前排除当前壁纸逻辑一直失效会重复抽同一张。
- **锁屏 standby 后物理屏 1-2s 亮起（xwallpaper 视频壁纸持续 present 触发驱动 unblank）**：根因是 `xwallpaper --daemon` 的 libmpv（`vo=gpu`+`wid` 直绘）在 X DPMS off 后**持续 present 帧** → amdgpu 驱动把输出 dpms 恢复 On（sysfs 实测 2-3s 回弹，X 层 `xset q` 标志保持 Off/Standby 不变，eDP→HDMI→DP 依次亮）。与键盘幽灵输入、amdgpu REG_WAIT（7.x 回归，lts 6.18.46 无此）、TLP/GPU runtime PM（`control=on` 全程 active）均无关。修复双层：① xwallpaper（源码 `~/Workspace/Github/xwallpaper`）backend 层加 `set_paused` 回调（video → mpv pause），`xw_app_dpms_poll()`（`DPMSInfo` 查询，500ms 节流）在主循环检测电源模式，非 On 即暂停渲染；② `lock.sh _lock_before/_lock_after` 对 `xwallpaperd`（兼容保留 `xwallpaper` 单进程时代）进程 `pkill -STOP/-CONT` 双保险。验证：standby 12s sysfs dpms 全程 Off 不回弹。**注意**: client+daemon 拆分后常驻渲染进程名为 `xwallpaperd`，`-x xwallpaper` 精确匹配打不到 daemon，必须 STOP `xwallpaperd`，否则锁屏 `_screen_lock_loop` 会因 X 层 `xset q` 标志 stale（物理已亮、X 仍 Off）卡在 `! Monitor is On` 等待里，表现为灭一次→亮→再也不灭。
- **首次开机 HDMI 视频壁纸黑屏（swapchain 创建失败 → mpv 丢 video track）**：开机早期 GPU/GL（RADV/amdgpu Vulkan 栈）未就绪时，`vo=gpu` 的 swapchain 创建失败（`VK_ERROR_INITIALIZATION_FAILED`），mpv `write_video` 里 `vo_reconfig2<0` → `error_on_track` **禁用视频 track**（日志 `deselect track 0`/`Video: no video`）——窗口在、restore 显示 `ok`、只有音频在播、画面黑。**restore_pending 重试对此无效**（窗口 active 不算 pending）；**mpv 自身不重试**（reconfig 失败即禁 track）。为何 xwinwrap+mpv 无此问题：独立 mpv 进程启动晚（fork/exec/加载），建 swapchain 时 GPU 已就绪。修复（xwallpaper 已提交）：backend 加 `retry()` 回调（video 查 mpv `video` 属性，无视频则重新 `loadfile` 重建渲染路径），daemon 启动后 2 分钟窗口内 **0.5s 节拍**轮询，reload 间 **1.5s 防堆积**（`load_file` 统一记 `last_load_ms`，含首次 loadfile 防竞态），GPU 就绪后 ≤1.5s 出视频。诊断方法（临时）：`XW_DEBUG_DAEMON=1 xwallpaper --daemon` 手动启动，restore/自愈日志打 stderr，mpv 日志写 `/tmp/xw-mpv-<winid>.log` + IPC socket `/tmp/xw-mpv-<winid>.sock`（`get_property video` 查有无视频 track）
- **rofi/scripts/theme.sh handle_monitor_brightness 保存值/退出码失效已修复**: 原实现 `coproc YAD` + `wait "$YAD_PID"` 取 yad 退出码区分 OK/取消, 但 bash 读完全部 coproc 输出后可能清理 `YAD_PID`（实测 wait 时已空 → 报错 status≠0 → 误走恢复分支）; 且 `while read` 最后一次 read 读到 EOF 时会把 `$value` **清空**, 循环外 `$value` 必空（OK 也空）。重构为 **FIFO + 后台 pid (`$!`, 稳定)**, 循环内用 `$last` 记录最终值; OK 后从硬件读取实际亮度（eDP brightnessctl / DDC getvcp）作为保存值, 读取失败回退 `$last`。回归测试 `tests/rofi-theme-monitor-brightness_test.sh`（awk 提取函数 + mock yad/xrandr/brightnessctl; 因脚本顶层 `module_loop` 阻塞无法整体 source）
- **DP 显示器 DDC 亮度控制失效已修复**: `get_ddc_bus()` 只接受 `ddcutil detect --brief` 中 `Display N` 有效条目, 丢弃 `Invalid display` 条目。但 DP 经 aux 总线时 detect 常误报 `This monitor does not support DDC/CI. (I2C slave address x37 is unresponsive.)`, 而同 bus 的 `getvcp/setvcp 10` 实际可用 (TRG JQ24F260L 实测) → bus 解析为空, 读写静默失败。现两遍取值: 优先有效条目, 无命中时回退同 `drm_connector_id` 的 Invalid 条目总线 (eDP 不受影响, 其读写短路走 brightnessctl)。回归测试 `tests/monitor-brightness_test.sh` 场景 D (旧代码 FAIL, 新代码 PASS)
- **DDC 显示器滑块拖动滞后已优化**：yad `--print-partial` 拖动时逐像素输出值, 原实现每个值都调 `ddcutil setvcp`（~200ms/次）, 大幅拖动会积压上百次调用排队, 松手后仍持续处理（实测 100 值 → ~20s）; eDP 的 `brightnessctl set` 即时无此问题。现循环按显示器类型分流: eDP 逐值即时应用, DDC 用内层 `read -t 0.03` 丢弃积压值、滑动暂停后只应用最新值（实测 100 值 → 1 次 setvcp, ~1s）。回归测试场景 C（mock ddcutil detect/setvcp + DisplayPort-0 monitor, 断言 setvcp 只调 1 次且为最新值）

---

# 编码准则

> 以下准则偏向谨慎，非关键任务可灵活判断。

## 1. 先想后写

**不要假设，不要隐藏困惑，给出取舍。**

动手之前:

- 明确说出你的假设。不确定就问。
- 如果有多种解读，全部列出来——不要默默选一种。
- 如果有更简单的方案，直接说。该推翻就推翻。
- 如果某处不清楚，停下来，说清困惑点，问。

## 2. 简洁至上

**最小化代码解决问题，不写推测性代码。**

- 不添加用户没要求的功能。
- 不为单次使用的代码创建抽象。
- 不添加用户没要求的"灵活性"或"可配置性"。
- 不处理不可能发生的错误场景。
- 如果写了 200 行实际只需要 50 行，重写。

自问："高级工程师会觉得这过度设计了吗？" 是的话就简化。

## 3. 精准修改

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

## 4. 目标驱动

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

## 5. 依赖完整性

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
