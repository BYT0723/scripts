# AGENTS.md

> 此文件记录所有脚本间的 source 依赖、函数调用关系和调用链。
> 每次修改脚本后需同步更新 (见下方 §编码准则.5)。

## Source 依赖图

```
dwm-launcher.sh ──sources──► utils/monitor.sh
dwm-status.sh ──sources──► dwm-status-tools.sh ──sources──► utils/weather.sh
                                                           utils/notify.sh
dwm-statuscmd.sh ──sources──► utils/notify.sh
colorscheme.sh ──sources──► utils/notify.sh

tools/lock.sh ──sources──► utils/notify.sh
              ◄──sourced by── rofi/powermenu/type-{1..6}/powermenu.sh
tools/wallpaper.sh ──sources──► utils/monitor.sh, utils/notify.sh
tools/screencast.sh ──sources──► utils/monitor.sh
tools/brightness.sh ──sources──► utils/notify.sh
tools/calendar.sh ──sources──► utils/notify.sh
tools/keyboard.sh ──sources──► utils/notify.sh
tools/volume.sh ──sources──► utils/notify.sh

tools/youtube/yt.sh ──sources──► tools/youtube/opus-webm.sh

rofi/scripts/quicklinks.sh  ──sources──► rofi/scripts/util.sh
rofi/scripts/module.sh      ──sources──► rofi/scripts/util.sh
rofi/scripts/wallpaper.sh   ──sources──► rofi/scripts/util.sh
rofi/scripts/notification.sh──sources──► rofi/scripts/util.sh
rofi/scripts/setting.sh     ──sources──► rofi/scripts/util.sh
rofi/scripts/system-tools.sh──sources──► rofi/scripts/util.sh
rofi/scripts/sing-box.sh    ──sources──► rofi/scripts/util.sh, utils/notify.sh

# 死代码 (未被任何脚本 source)
utils/print.sh   — number2icon() 无人调用
utils/shell-lib.sh — echo_note / is_float_term / init_tmux_cursor 无人调用
```

## 函数定义与调用关系

### utils/notify.sh → system-notify()
被以下脚本调用:
`brightness.sh` `calendar.sh` `keyboard.sh` `lock.sh` `volume.sh` `dwm-status-tools.sh` `dwm-statuscmd.sh` `sing-box.sh` `wallpaper.sh` `colorscheme.sh`

### utils/monitor.sh
| 函数 | 调用者 |
|------|--------|
| `is_portrait()` | dwm-launcher.sh (powermenu) |
| `get_monitor_info()` | wallpaper.sh (set_wallpaper_to_monitor) |
| `get_monitor_info_by_index()` | wallpaper.sh |
| `get_current_monitor()` | screencast.sh |

### utils/weather.sh
| 函数 | 调用者 |
|------|--------|
| `ipinfo-openMeteo()` | dwm-status-tools.sh (update_weather) |
| `weather-forecast()` | dwm-status-tools.sh |

### tools/lock.sh
| 函数 | 调用者 |
|------|--------|
| `_lock_before()` | lock() / suspend() → 所有 powermenu 脚本 |
| `_lock()` | lock() / suspend() → 所有 powermenu 脚本 / screen.sh(LOCKER) |
| `_lock_after()` | lock() / suspend() → 所有 powermenu 脚本 |
| `_screen_lock_loop()` | lock() / suspend() → 所有 powermenu 脚本 |
| `lock()` | screen.sh 的 LOCKER / `lock.sh lock` CLI |
| `suspend()` | `lock.sh suspend` CLI |

### rofi/scripts/util.sh
| 函数 | 调用者 |
|------|--------|
| `icon()` | module.sh, wallpaper.sh |
| `toggleApplication()` | module.sh |
| `toggleConf()` | wallpaper.sh |
| `getConfig()` | wallpaper.sh |
| `trim()` | quicklinks.sh |
| `is_url()` | quicklinks.sh |
| `get_default_browser_name()` | quicklinks.sh |
| `log()` | (deprecated: kcptun-sync.sh, trojan-sync.sh) |

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
    → udiskie &
    → lxpolkit &
    → setxkbmap ...
    → bash keyboard.sh &
    → bash wallpaper.sh &
    → bash dwm-status.sh &                  # 状态栏
    → bash screen.sh &                      # DPMS 守护 (调用 pactl 检测视频音频)
    → bash brightness.sh &
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
  → volume.sh / brightness.sh / keyboard.sh / screen.sh / ... (按模块)
```

### rofi 启动器链路
```
dwm-launcher.sh (快捷键)
  → source utils/monitor.sh (is_portrait 判断方向)
  → rofi -show drun          (应用启动)
  → rofi/scripts/powermenu_t2 (竖屏) / powermenu_t4 (横屏)  (电源菜单)
  → rofi/scripts/mpd.sh      (音乐控制)
  → rofi/scripts/module.sh   (模块管理)
  → rofi/scripts/screenshot.sh
  → rofi/scripts/screencast.sh
  → rofi/scripts/quicklinks.sh
  → rofi/scripts/emoji.sh
  → rofi/scripts/notification.sh
```

### 壁纸链路
```
wallpaper.sh → source utils/monitor.sh, utils/notify.sh
  ├─ feh (图片壁纸)
  ├─ mpv (视频壁纸) → xwinwrap
  └─ surf (网页壁纸) → tabbed → xwinwrap
```

## 配置文件
- `rofi/` 下各 type 目录的 `*.rasi` 文件
- `rofi/fonts/` 字体文件
- `rofi/colors/` `rofi/images/`
- `~/.config/dwm/colorscheme.json` — `colorscheme.sh` 的外部化主题配置 (light/dark)

## 已知问题
- `tools/calendar.sh:3` source 路径已修复为 `$(dirname "$0")/../utils/notify.sh`
- `tools/screen.sh:16` LOCKER 路径已改为 `$(dirname "$0")/lock.sh lock`，不再依赖 `$TOOLS_DIR`
- `tools/lock.sh` 的 `_screen_lock_loop` 在 xprintidle 缺失时有 fallback (sleep 30s 代替空闲检测)

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
