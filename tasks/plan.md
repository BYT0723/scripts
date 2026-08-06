# Implementation Plan: 壁纸 Monitor 持久组

## Overview
为壁纸系统引入 monitor 持久组：经 rofi 多选勾屏、持久化为 wallpaper.json 的显式成员名单，组名即目标（`-m <组> next`）。一个屏至多属于一个组（互斥）；组有 enabled 开关，禁用后 kill 组壁纸并让成员屏回归单屏 daemon 轮换；组仅支持 video/page，daemon 不轮换组（纯手动），set_latest 重启恢复。

## Architecture Decisions
- groups 数据结构：`"groups": { "<名>": { "enabled": bool, "members": [names] } }`，复用 `monitors[<组名>]` 作组自身配置（getConfig 零改动）。
- 成员互斥 + 组优先：rofi 创建/编辑时校验；launch_wallpaper 轮询跳过成员；手动单屏目标指向启用组成员拒。
- 组=跨屏 bbox 渲染：get_group_dim 求成员并集几何，video/page 用 xwinwrap 铺 WxH+X+Y；image 在组目标下直接报错。
- 启停持久化：enabled 写 json；禁用动作=enabled=false + kill 组进程 + 清 _grp_<名> 状态，成员随之恢复单屏轮换。

## 依赖图
```
wallpaper-lib.sh → wallpaper-render.sh → wallpaper.sh
                                        → rofi/scripts/wallpaper.sh
                → rofi/scripts/lib-module.sh → rofi/scripts/wallpaper.sh
                → wallpaper.json(迁移) + AGENTS.md
```

## Task List

### Phase 1: Foundation (lib)
- [ ] Task 1: wallpaper-lib.sh 组配置函数 (group_names, get_group_members, get_group_enabled, has_group, is_group_member)
- [ ] Task 2: get_group_dim, get_monitor_dim 扩展, get_monitor_list_text 追加组, clean_target 重构

### Checkpoint 1
- [ ] bash -n 全绿, 组函数单测通过

### Phase 2: Render + Dispatch
- [ ] Task 3: wallpaper-render.sh set_wallpaper_to_group
- [ ] Task 4: wallpaper.sh 分发/daemon 成员排除/set_latest 恢复

### Checkpoint 2
- [ ] 组壁纸手动 next/select 生效; daemon 不碰成员; 互斥拒绝生效

### Phase 3: Rofi UI
- [ ] Task 5: lib-module.sh module_multi_rofi
- [ ] Task 6: rofi/scripts/wallpaper.sh 组管理菜单 (新建/编辑/启停/删除/next)

### Checkpoint 3
- [ ] rofi 全流程可用

### Phase 4: 迁移 + 文档
- [ ] Task 7: 配置迁移 + AGENTS.md 更新

## Risks
| Risk | Impact | Mitigation |
|------|--------|------------|
| bbox 非零原点算错 | M | get_group_dim 用 x/y 求并集，单测覆盖 |
| clean_latest 破坏现有调用 | H | clean_target 平替全部调用点 |
| 状态文件冲突 | M | _grp_<名> 前缀隔离 |
