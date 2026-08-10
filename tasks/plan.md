# Implementation Plan: Firefox 原生亮暗跟随（xsettingsd + portal 双通道）

## Overview
替换 tools/theme.sh 中基于 xdotool + Dark Reader 快捷键的 Firefox 主题切换方案（已证实失效：Dark Reader 快捷键为空串，xdotool 发空键）。改为双通道广播：
1. **xsettingsd 通道**：写 `~/.xsettingsd` 的 `Net/ThemeName` 并 HUP 重载 → GTK 应用（含 Firefox UI）即时刷新
2. **portal 通道**：`gsettings set org.gnome.desktop.interface color-scheme` → xdg-desktop-portal 广播 → Firefox content `prefers-color-scheme` 即时刷新

## Architecture Decisions
- **广播键名用 `Net/ThemeName`**：GDK 映射表 `gdk/x11/gdksettings.c:33`（`{"Net/ThemeName", "gtk-theme-name"}`）确认
- **portal 是 Firefox content scheme 的唯一决定者**：nsLookAndFeel.cpp `ComputeColorSchemeSetting()` 优先 portal `color-scheme`，且 `case 0 (default)` 硬映射为 light —— 仅广播 GTK 主题名不足以切换 Firefox content
- **Firefox 侧零配置**：`browser.theme.content-theme` 保持默认 2（System），不写 user.js 锁死
- **广播函数含自动拉起逻辑**：xsettingsd 未运行时自动启动；gsettings 失败时 system-notify 提示
- **旧方案整体删除**：`set_firefox_theme` + `_get_darkreader_shortcut` 及其 xdotool/jq/扩展依赖

## 验证结果
- [x] xsettingsd 安装并纳入 autostart（launch check 幂等）
- [x] set_gtk_theme 双通道工作（xsettingsd 广播 + gsettings 同步）
- [x] Firefox 运行中 apply dark → `matchMedia dark=true` 实时生效（无重启）
- [x] apply light → `dark=false` 实时生效
- [x] Firefox 重启后启动跟随（gsettings 持久 → portal 启动即报 dark）
- [x] 连续 apply 幂等（exit=0，单 xsettingsd 实例）
- [x] apply 退出码修复（auto 关闭时不再 exit 1）
- [x] AGENTS.md 同步（依赖图/启动链路/配置文件/已知问题/函数表）
- [x] Code review 修复：~/.xsettingsd 改用 _ensure_config_line（保留其他 XSETTINGS 键，不再整文件覆盖）；cs 三元表达式改 if/else；review 后复验通过
- [x] 架构收敛：按 review 意见将广播逻辑并入 set_gtk_theme（持久配置 + 运行时双通道广播同一职责），删除 set_gtk_broadcast

## Risks and Mitigations
| Risk | Impact | Mitigation |
|------|--------|------------|
| portal-gtk 未安装时 gsettings 无效果 | 中 | xsettingsd 通道仍工作（Firefox UI 层）；check 命令包含 dconf |
| Firefox 版本行为变化 | 中 | 以 FF153 实测为准；nsLookAndFeel 代码路径已验证 |
| libadwaita 应用（GTK4）不跟随 xsettingsd | 低 | 走 portal 通道，由 gsettings 驱动 |

## Open Questions
- 无（方向与取舍已确认并实施）
