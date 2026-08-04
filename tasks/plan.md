# Implementation Plan: rofi YouTube Downloader

## Overview
基于现有 `tools/youtube/yt.sh` + `rofi/scripts/lib-module.sh` 框架，做一个通过 rofi 菜单下载 YouTube 视频/音频的工具。

## Architecture

```
module.sh (注册表新条目)
  └─ rofi/scripts/yt-download.sh  (新脚本: source lib-module.sh + util.sh + notify.sh)
        ├─ 调用 tools/youtube/yt.sh  (重构: audio / video / raw 子命令)
        │     └─ source opus-webm.sh (extract_opus, 不变)
        └─ 缓存 ~/.local/state/dwm/cache/yt-history (历史记录)
```

## Key Decisions
- yt.sh 去掉 `--exec` 内嵌拼接，改为下载后统一 `extract_opus "$YT_DL_DIR"`（幂等）
- `$BROWSER` 加引号 + fallback `${BROWSER:-firefox}`
- `YT_DL_DIR` 环境变量可覆盖，默认 `~/Downloads/yt`
- 格式选择用 `yt-dlp -F` 输出 awk 解析
- 历史格式 `URL\tmode\t时间`，展示截断 40 字符
- 下载全部后台 `&`，system-notify 通知开始/完成/失败

## Task List

### Phase 1: Refactor yt.sh
- [ ] Task 1: 重构 tools/youtube/yt.sh（audio/video/raw 子命令）

### Phase 2: Core rofi Tool
- [ ] Task 2: 新建 rofi/scripts/yt-download.sh 核心流程

### Phase 3: Advanced Features
- [ ] Task 3: 剪贴板/-F 格式选择/历史记录/打开目录

### Phase 4: Integration
- [ ] Task 4: module.sh 注册 + AGENTS.md 更新

## Risks
| Risk | Mitigation |
|------|------------|
| -F 输出格式随 yt-dlp 版本变化 | awk 只依赖 ID EXT RESOLUTION 列位置 |
| 部分视频需 cookies | ${BROWSER:-firefox} fallback |
| xclip 不存在 | command -v 检查，缺失隐藏剪贴板项 |
