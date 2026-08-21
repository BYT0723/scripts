# AGENTS.md

> 此文件记录所有脚本间的 source 依赖、函数调用关系和调用链。
> 每次修改脚本后需同步更新 (见下方 §编码准则.5)。

## Source 依赖图

```
dwm-launcher.sh ──sources──► utils/monitor.sh
dwm-status.sh ──sources──► dwm-status-tools.sh ──sources──► dwm-status-print.sh
                                                           utils/weather.sh
                                                           utils/notify.sh
dwm-statuscmd.sh ──sources──► utils/notify.sh
tools/theme.sh ──sources──► utils/notify.sh
                ──requires─► xsettingsd, dconf (gsettings), curl (GTK/portal 双通道广播 / auto 日出日落)

tools/lock.sh ──sources──► utils/notify.sh
              ◄──sourced by── rofi/powermenu/type-{1..6}/powermenu.sh
tools/wallpaper.sh ──sources──► utils/notify.sh, tools/wallpaper-lib.sh, tools/wallpaper-render.sh
tools/screencast.sh ──sources──► utils/monitor.sh
tools/brightness.sh ──sources──► utils/notify.sh
tools/calendar.sh ──sources──► utils/notify.sh
tools/keyboard.sh ──sources──► utils/notify.sh
tools/volume.sh ──sources──► utils/notify.sh
tools/touchpad.sh ──sources──► 无外部脚本
utils/form.sh ──sources──► 无外部脚本; ──requires─► jq, yad (优先) / zenity (fallback); 环境变量 FORM_BACKEND/FORM_CSS/FORM_WIDTH/FORM_FONT (yad 字体)
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
rofi/scripts/mpd.sh         ──sources──► rofi/scripts/lib-module.sh, rofi/scripts/util.sh
rofi/scripts/sing-box.sh    ──sources──► rofi/scripts/lib-module.sh, rofi/scripts/util.sh, utils/notify.sh
rofi/scripts/scrcpy.sh    ──sources──► rofi/scripts/lib-module.sh, rofi/scripts/util.sh
rofi/scripts/theme.sh──sources──► rofi/scripts/lib-module.sh, rofi/scripts/util.sh, tools/theme.sh

# 死代码 (未被任何脚本 source)
utils/print.sh   — number2icon() 无人调用
utils/shell-lib.sh — echo_note / is_float_term / init_tmux_cursor 无人调用
tools/wallpaper-lib.sh:clean_latest() — 已被 clean_target() 替代
```

## 函数定义与调用关系

### utils/notify.sh → system-notify()

被以下脚本调用:
`brightness.sh` `calendar.sh` `keyboard.sh` `lock.sh` `volume.sh` `dwm-status-tools.sh` `dwm-statuscmd.sh` `sing-box.sh` `wallpaper.sh` `tools/theme.sh` `yt-dlp-wrapper.sh`

### utils/monitor.sh

| 函数                          | 调用者                                  |
| ----------------------------- | --------------------------------------- |
| `is_portrait()`               | dwm-launcher.sh (powermenu)             |
| `get_monitor_info()`          | wallpaper.sh (set_wallpaper_to_monitor) |
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
| `_list()`          | _main (RETV=0; _ensure_ids + _load + _ensure_icons 后输出; 缓存 hit 输出 `name\0icon\x1f<png>\x1finfo\x1f<id>`, miss/fail 输出纯文本 `name\0info\x1f<id>` + New 行 + New Searcher 行 + use-hot-keys; hit 判定内联 `[[ -f ]]` 避免 `$()` fork) |
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
| `_fetch_favicon()` | _ensure_icons (降级链 DuckDuckGo→Google s2→站内 /favicon.ico; curl 超时 + file MIME 校验 image/* + tmp/mv 原子写; 全失败写 .fail 标记) |
| `_ensure_icons()`  | _list (收集 miss host 去重 → 后台子 shell 分片并发下载, 每 8 个 wait 一轮防限流; 已 png/.fail 跳过; stdout/stderr 重定向防 SIGPIPE) |

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

### theme.sh (tools/)

| 函数                 | 调用者                                                                                                                                           |
| -------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------ |
| `_do_theme_change()` | tools/theme.sh (apply / auto_daemon)                                                                                                             |
| `set_gtk_theme()`    | tools/theme.sh (_do_theme_change: 写 gtk2/3/4 持久配置 + 运行时双通道广播 — xsettingsd GTK 主题名 / gsettings color-scheme 同步 portal)                     |
| `get_auto_config()`  | tools/theme.sh (auto_daemon, auto on/off, apply)                                                                                                 |
| `get_sun_times()`    | tools/theme.sh (auto_daemon), rofi/scripts/theme.sh (get_sun_message → MODULE_MESG 日出日落显示; 内置 `~/.local/state/dwm/cache/sun-times` 缓存) |
| `auto_daemon()`      | tools/theme.sh (auto 守护进程循环)                                                                                                               |

### rofi/scripts/theme.sh

| 函数                | 调用者                                                                               |
| ------------------- | ------------------------------------------------------------------------------------ |
| `handle_toggle()`   | theme.sh (→ `tools/theme.sh apply light\|dark` 翻转)                                 |
| `handle_auto()`     | theme.sh (→ `tools/theme.sh auto on/off`)                                            |
| `get_sun_message()` | theme.sh (调 `get_sun_times` → 格式化 MODULE_MESG; 网络失败则 fallback 为无时间后缀) |

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
| `handle_next()`               | wallpaper.sh (模块主菜单: 下一张)                       |
| `handle_select()`             | wallpaper.sh (模块主菜单: 选择文件)                     |
| `handle_random_switch()`      | wallpaper.sh (模块主菜单: 随机开关 toggle)              |
| `handle_random_type()`        | wallpaper.sh (模块主菜单: 类型切换 toggle)              |
| `handle_random_duration()`    | wallpaper.sh (模块主菜单: 设置轮换间隔)                 |
| `handle_random_depth()`       | wallpaper.sh (模块主菜单: 设置搜索深度)                 |
| `handle_random_images_path()` | wallpaper.sh (模块主菜单: 选择图片目录)                 |
| `handle_random_videos_path()` | wallpaper.sh (模块主菜单: 选择视频目录)                 |
| `handle_group()`              | wallpaper.sh (模块主菜单: 组管理 — 新建/编辑/启停/删除) |

### tools/wallpaper-lib.sh

| 函数                         | 调用者                                                                                                                                                                                                       |
| ---------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `getConfig()`                | wallpaper.sh, wallpaper-lib.sh (内部)                                                                                                                                                                        |
| `ensure_monitor_config()`    | rofi/scripts/wallpaper.sh (主入口选定 monitor 后初始化写入)                                                                                                                                                  |
| `detect_file_type()`         | wallpaper.sh, wallpaper-render.sh                                                                                                                                                                            |
| `get_video_dim()`            | wallpaper.sh (get_wallpaper_rotation)                                                                                                                                                                        |
| `orientation_mismatch()`     | wallpaper.sh (get_wallpaper_rotation)                                                                                                                                                                        |
| `get_monitor_dim()`          | wallpaper.sh (get_wallpaper_rotation)                                                                                                                                                                        |
| `preview_rotation()`         | wallpaper.sh (get_wallpaper_rotation)                                                                                                                                                                        |
| `find_wallpapers()`          | wallpaper.sh (random_wallpaper)                                                                                                                                                                              |
| `check_command()`            | wallpaper-render.sh (launch_video_xwinwrap, launch_image_xwinwrap, launch_page_xwinwrap)                                                                                                                                            |
| `safe_kill_pidfile()`        | wallpaper-lib.sh (clean_latest, clean_target 内部)                                                                                                                                                           |
| `handle_error()` / `error()` | wallpaper-lib.sh 内部, rofi/scripts/wallpaper.sh (handle_group)                                                                                                                                              |
| `clean_latest()`             | 死代码 (已被 clean_target 替代)                                                                                                                                                                              |
| `clean_target()`             | wallpaper-render.sh (set_wallpaper_to_screen/monitor/group), rofi/scripts/wallpaper.sh (handle_group 禁用/删除/编辑成员)                                                                                     |
| `get_screen_size()`          | wallpaper-render.sh, wallpaper-lib.sh (get_monitor_list_text)                                                                                                                                                |
| `get_monitor_list_text()`    | rofi/scripts/wallpaper.sh (monitor_selection)                                                                                                                                                                |
| `_json_path_for()`           | wallpaper-lib.sh (pick_config_dir, set_numeric_config 内部)                                                                                                                                                  |
| `pick_config_dir()`          | rofi/scripts/wallpaper.sh (handle_random_images_path, handle_random_videos_path)                                                                                                                             |
| `set_numeric_config()`       | rofi/scripts/wallpaper.sh (handle_random_duration, handle_random_depth)                                                                                                                                      |
| `has_group()`                | wallpaper.sh (apply_wallpaper), wallpaper-lib.sh (get_monitor_dim), rofi/scripts/wallpaper.sh (handle_group)                                                                                                 |
| `group_names()`              | wallpaper.sh (apply_wallpaper, set_latest), wallpaper-lib.sh (is_group_member, clean_target, get_monitor_list_text), rofi/scripts/wallpaper.sh (handle_group)                                                |
| `get_group_members()`        | wallpaper.sh (apply_wallpaper), wallpaper-lib.sh (is_group_member, get_group_dim, clean_target), wallpaper-render.sh (set_wallpaper_to_group 内部调 get_group_dim), rofi/scripts/wallpaper.sh (handle_group) |
| `get_group_enabled()`        | wallpaper.sh (set_latest), wallpaper-lib.sh (is_group_member, clean_target), rofi/scripts/wallpaper.sh (handle_group)                                                                                        |
| `is_group_member()`          | wallpaper.sh (apply_wallpaper, launch_wallpaper daemon)                                                                                                                                                      |
| `group_for_monitor()`        | wallpaper.sh (apply_wallpaper), wallpaper-lib.sh (is_group_member, clean_target), rofi/scripts/wallpaper.sh (handle_group)                                                                                   |
| `get_group_dim()`            | wallpaper-lib.sh (get_monitor_dim, clean_target 内部 get_group_dim 输出 bbox), wallpaper-render.sh (set_wallpaper_to_group)                                                                                  |

### tools/wallpaper-render.sh

| 函数                         | 调用者                                                           |
| ---------------------------- | ---------------------------------------------------------------- |
| `launch_video_xwinwrap()`    | wallpaper-render.sh (launch_dynamic_wallpaper 内部)              |
| `launch_image_xwinwrap()`    | wallpaper-render.sh (launch_dynamic_wallpaper 内部)              |
| `launch_page_xwinwrap()`     | wallpaper-render.sh (launch_dynamic_wallpaper 内部)              |
| `launch_dynamic_wallpaper()` | wallpaper-render.sh (set_wallpaper_to_screen/monitor/group 内部) |
| `set_wallpaper_to_screen()`  | wallpaper.sh (apply_wallpaper, set_latest)                       |
| `set_wallpaper_to_monitor()` | wallpaper.sh (apply_wallpaper, set_latest)                       |
| `set_wallpaper_to_group()`   | wallpaper.sh (apply_wallpaper, set_latest)                       |

## 调用链 (Call Chain)

### 锁屏/挂起链路

```
rofi powermenu (用户点击)
  → type-*/powermenu.sh (source lock.sh)
    → _lock_before()   # 暂停音乐、静音
    → _lock()          # 启动 i3lock, xset dpms force standby
    → systemctl suspend  (仅 suspend)
    → _screen_lock_loop()  # 循环监控: 唤醒 → 空闲 → 重新 standby
    → wait             # 等待 i3lock 退出
    → _lock_after()    # 恢复音乐、音量

screen.sh (DPMS 守护)
  → LOCKER="lock.sh lock"  # 由 xautolock 在超时后调用
```

### 启动链路

```
DWM 启动
  → autostart.sh
    → picom &
    → dunst &
    → xautolock -locker "lock.sh lock" &    # 定时锁屏
    → fcitx5 &
    → xsettingsd &                          # XSETTINGS 广播 (theme.sh set_gtk_theme 依赖)
    → udiskie &
    → lxpolkit &
    → setxkbmap ...
    → bash keyboard.sh &
    → bash wallpaper.sh &
    → bash dwm-status.sh &                  # 状态栏
    → bash screen.sh &                      # DPMS 守护 (PipeWire 用 pw-dump 检测 node state, PA fallback 用 pactl)
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
```

### 自动主题切换链路

```
tools/theme.sh auto (守护进程)
  → get_sun_times() (ipinfo.io/loc + open-meteo daily=sunrise,sunset)
  → get_current_theme() (xrdb -query dwm.col_theme)
  → 日出/日落触发:
      → _do_theme_change("light"|"dark")
      → system-notify low
      → pkill -SIGHUP dwm → dwm restart → loadxrdb 重载配色
  手动 apply 会关闭 auto（自动调用 auto off）
```

### 壁纸状态缓存 (target → cache file)

`$monitor` 参数可能为以下三类值，对应不同缓存文件（存储内容均为 `filepath|rotation`）：

| 目标类型 | 示例值 | 缓存文件 | 写入者 |
|----------|--------|----------|--------|
| 实体显示器名 | `DP-0`, `HDMI-0` | `~/.cache/wallpaper/wallpaper_latest_<xrandr_index>` | `set_wallpaper_to_monitor()` |
| Group 名 | `landscape`, `portrait` | `~/.cache/wallpaper/wallpaper_latest_grp_<组名>` | `set_wallpaper_to_group()` |
| 全屏 | `Screen` | `~/.cache/wallpaper/wallpaper_latest_full` | `set_wallpaper_to_screen()` |

> **规则**: 任何读取/比对当前壁纸的逻辑，必须枚举以上三种目标类型，逐类命中对应缓存文件。monitor 尚无配置时，`ensure_monitor_config()` 用脚本默认值（`config` 数组）初始化写入 `.monitors["<monitor>"]`。

### 壁纸链路

```
wallpaper.sh → source utils/monitor.sh, utils/notify.sh
  ├─ 图（image） → feh (单屏/全屏/多屏) / nsxiv → xwinwrap (组)
  ├─ 视频（video）→ mpv → xwinwrap (单屏/全屏/组)
  ├─ 网页（page）→ surf → tabbed → xwinwrap (单屏/全屏/组)
  └─ monitor 组 → xwinwrap 按 bbox 跨成员屏铺图/视频/网页
       ├─ 组名即目标 -m <组> (config: groups.<组>)
       ├─ rofi 多选创建/编辑/启停
       ├─ 成员互斥（一屏至多归一组）
       ├─ daemon 轮询对组成员 skip（手动 only）
       └─ set_latest 恢复 _grp_<组> 状态
```

## 配置文件

- `rofi/` 下各 type 目录的 `*.rasi` 文件
- `rofi/fonts/` 字体文件
- `rofi/colors/` `rofi/images/`
- `~/.config/dwm/quicklinks.json` — quicklinks 书签, `links` 数组元素含 `id`(uuid)、`name`、`url` (icon 字段已废弃移除); 顶层 `searcher` 数组存搜索引擎 `{name, url}`(name 为唯一键, url 用 `{key}` 占位搜索词, 可省略 → 追加 url 末尾), 自定义输入搜索默认用 `searcher[0]`, 支持 `@<name>` 首 token 指定引擎
- `~/.config/dwm/wallpaper.json` — 壁纸配置, 含 `defaults`、`monitors`(按屏/组名键)、`groups`(成员名单 + enabled 启停)
- `~/.config/dwm/theme.json` — `tools/theme.sh` 的外部化主题配置，`"auto"` 含 `enabled`(默认 false)、`sun_rise_offset`(日出延迟分钟数)、`sun_set_offset`(日落延迟分钟数)，`"cursor"` 含 `theme`/`size`，`"dpi"` 为 Xft.dpi 值，`light`/`dark` 的 `colorscheme` 引用 `~/.config/dwm/colorschemes/` 下的颜色方案文件
- `~/.xsettingsd` — `set_gtk_theme()` 维护 `Net/ThemeName`(当前 GTK 主题) 行, 保留其他 XSETTINGS 键, `killall -HUP xsettingsd` 触发 XSETTINGS 重载广播

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
- `tools/screen.sh:16` LOCKER 路径已改为 `$(dirname "$0")/lock.sh lock`，不再依赖 `$TOOLS_DIR`
- `tools/lock.sh` 的 `_screen_lock_loop` 在 xprintidle 缺失时有 fallback (sleep 30s 代替空闲检测)
- `tools/theme.sh` 旧 Firefox 切换方案（`set_firefox_theme` + `_get_darkreader_shortcut`，xdotool 模拟 Dark Reader 快捷键）已删除：Dark Reader 的 `extension-settings.json` 快捷键实际为空串，jq 的 `//` 不兜底空串 → `xdotool key ""` 从未生效；且依赖 Firefox 窗口存在、/tmp 状态文件易漂移。现由 `set_gtk_theme()` 双通道替代
- **Firefox content 亮暗由 portal 决定而非 GTK**：Firefox 的 `prefers-color-scheme` 走 `nsLookAndFeel::ComputeColorSchemeSetting()` → xdg-desktop-portal 的 `color-scheme`（gsettings `org.gnome.desktop.interface color-scheme`），且 Firefox 将 portal 返回的 `0 (default)` 硬映射为 light（nsLookAndFeel.cpp case 0）。因此 `set_gtk_theme()` 必须同时写 gsettings（prefer-dark/prefer-light），仅广播 GTK 主题名不足以切换 Firefox content scheme
- `tools/theme.sh apply` 的退出码已修复：auto 关闭时末尾 `[ ... ]` 返回 1 导致 apply 成功但 exit 1，现显式 `exit 0`
- `module.sh handle_network` 已改用 `nmcli -t -f BARS,BAND,BSSID,SSID` 解析 WiFi 列表（条目形如 `▂▄▆█ [2.4 GHz] SSID`，无 SSID 的隐藏网络以 BSSID 兜底）：nmcli ≥1.58 在表格输出新增 BAND 列（且 RATE 两 token），旧 `substr+$8` 列位解析会把 RATE 的 "Mbit/s" 当信号条显示
- 隐藏网络无法仅凭 BSSID 连接（802.11 关联握手必须携带真实 SSID，NM 会报 `A 'wireless' setting with a valid SSID is required for hidden access points`）：`handle_network` 检测到选中项为 MAC 时弹 `module_input` 让用户输入真实 SSID，再 `nmcli device wifi connect <ssid> hidden yes bssid <BSSID>`
- **rofi script mode 多属性必须用 `\x1f` 连接**：正确格式 `text\0icon\x1f<v>\x1finfo\x1f<id>`（仅行文本后一个 `\0`）。曾错误写成 `text\0icon\x1f<v>\0info\x1f<id>`（两个 `\0`）导致选中无反应：rofi 按 C 字符串语义解析属性块（`dmenuscript_parse_entry_extras` 的 `g_strsplit` 遇 `\0` 截断），第二个 `\0` 之后的内容（含 info）不可见 → `ROFI_INFO` 不设置 → 静默返回。测试断言注意：`grep -a` 对含 NUL 文件匹配不可靠、`$'\x00'` bash 展开的字面 NUL 会截断 grep -P 模式，须用单引号模式 `'\x00info'` + `grep -P`

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
