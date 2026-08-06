# Task Checklist: 壁纸 Monitor 持久组

## Task 1: wallpaper-lib.sh 组配置函数
- [x] group_names() — jq 列出 .groups 键
- [x] has_group(name) — 判断组存在
- [x] get_group_members(name) — jq 取 .groups.<name>.members[]
- [x] get_group_enabled(name) — .groups.<name>.enabled (默认 true)
- [x] is_group_member(monitor) — 是否属于任一启用组
- [x] Validation: bash -n 通过

## Task 2: get_group_dim + clean_target + list_text
- [x] get_group_dim(name) — 成员 get_monitor_info 求 bbox
- [x] get_monitor_dim 支持组名 → get_group_dim
- [x] get_monitor_list_text 追加组行
- [x] clean_target <type> <name> 封装清理逻辑
- [x] Validation: bash -n

## Task 3: wallpaper-render.sh set_wallpaper_to_group
- [x] 非 video/page → error
- [x] bbox → launch_dynamic_wallpaper
- [x] 写 _grp_<名> pid/latest
- [x] clean_latest → clean_target 替换
- [x] Validation: bash -n

## Task 4: wallpaper.sh 分发/daemon/set_latest
- [x] apply_wallpaper 组名 → set_wallpaper_to_group
- [x] 单屏属启用组 → error 拒绝
- [x] set_latest 恢复 _grp_*
- [x] launch_wallpaper 成员 skip
- [x] Validation: bash -n

## Task 5: lib-module.sh module_multi_rofi
- [x] module_multi_rofi() — -multi-select 多选 rofi
- [x] Validation: bash -n

## Task 6: rofi/scripts/wallpaper.sh 组管理
- [x] group 菜单项 + handle_group
- [x] 新建组 (多选+命名+互斥校验)
- [x] 编辑成员/启停 toggle/删除/Next
- [x] Validation: bash -n

## Task 7: 配置迁移 + AGENTS.md
- [x] AGENTS.md 更新 source 依赖图/函数表/调用链/死代码
- [x] Validation: bash -n 全绿
