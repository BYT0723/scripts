# rofi

application launcher of dwm

```bash
# 忽略colors.rasi修改 (launchers / powermenu / applets 各共享目录)
git update-index --skip-worktree rofi/launchers/*/shared/colors.rasi rofi/powermenu/*/shared/colors.rasi rofi/applets/*/shared/colors.rasi

# 恢复
git update-index --no-skip-worktree rofi/launchers/*/shared/colors.rasi rofi/powermenu/*/shared/colors.rasi rofi/applets/*/shared/colors.rasi

```
