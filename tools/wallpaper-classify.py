#!/usr/bin/env python3
"""壁纸 light/dark 初筛 (B 规则: 暗像素占比).

暗部像素 (亮度 < --darkline) 占比 >= --frac 即判 dark, 否则 light。
图片经 PIL 直读, 视频抽 15% 处缩略图。目录本身是最终真相, 本脚本只给初筛建议。

用法:
    wallpaper-classify.py <dir|file> [...]          # 打印 verdict
    wallpaper-classify.py --move <dir> [...]        # 按 verdict 搬进 light//dark/ 子目录
    wallpaper-classify.py --darkline 100 --frac 0.5 <dir> [...]

依赖: python3 + PIL, 视频另需 ffmpeg/ffprobe。
"""

import argparse
import os
import shutil
import subprocess
import sys

try:
    from PIL import Image
except ImportError:
    sys.exit("need PIL: pip install pillow")

IMG_EXT = (".jpg", ".jpeg", ".png", ".webp", ".bmp")
VID_EXT = (".mp4", ".mkv", ".avi", ".webm")


def luminance_dark_frac(path, darkline):
    im = Image.open(path).convert("RGB")
    im.thumbnail((128, 128))
    # getdata 在 Pillow 14 移除, 有新 API 就用新的
    data = im.get_flattened_data() if hasattr(im, "get_flattened_data") else im.getdata()
    px = list(data)
    dark = sum(1 for r, g, b in px if 0.2126 * r + 0.7152 * g + 0.0722 * b < darkline)
    return dark / len(px)


def video_thumb(path, tmp):
    try:
        dur = float(
            subprocess.run(
                ["ffprobe", "-v", "error", "-show_entries", "format=duration",
                 "-of", "csv=p=0", path],
                capture_output=True, text=True,
            ).stdout.strip()
        )
    except ValueError:
        dur = 30
    r = subprocess.run(
        ["ffmpeg", "-v", "error", "-y", "-ss", str(dur * 0.15), "-i", path,
         "-frames:v", "1", "-vf", "scale=64:64", tmp]
    )
    return tmp if r.returncode == 0 and os.path.exists(tmp) else None


def classify(path, darkline, tmp):
    lo = path.lower()
    if lo.endswith(IMG_EXT):
        return luminance_dark_frac(path, darkline)
    if lo.endswith(VID_EXT):
        t = video_thumb(path, tmp)
        if t is None:
            return None
        return luminance_dark_frac(t, darkline)
    return None


def iter_media(targets):
    for t in targets:
        if os.path.isfile(t):
            yield t
        elif os.path.isdir(t):
            for dirpath, _, files in os.walk(t):
                for f in sorted(files):
                    p = os.path.join(dirpath, f)
                    if p.lower().endswith(IMG_EXT + VID_EXT):
                        yield p
        else:
            print(f"SKIP (not found): {t}", file=sys.stderr)


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("targets", nargs="+", help="dir or file to classify")
    ap.add_argument("--move", action="store_true",
                    help="move files into light//dark/ subdirs by verdict")
    ap.add_argument("--darkline", type=float, default=90, help="default: 90")
    ap.add_argument("--frac", type=float, default=0.60, help="default: 0.60")
    args = ap.parse_args()

    tmp = "/tmp/wallpaper-classify-thumb.jpg"
    for p in iter_media(args.targets):
        try:
            frac = classify(p, args.darkline, tmp)
        except Exception as e:  # noqa: BLE001 - report and continue
            print(f"ERR {p}: {e}", file=sys.stderr)
            continue
        if frac is None:
            print(f"SKIP {p}", file=sys.stderr)
            continue
        verdict = "dark" if frac >= args.frac else "light"
        if not args.move:
            print(f"{frac:.3f} {verdict} {p}")
            continue
        if os.path.basename(os.path.dirname(p)) in ("light", "dark"):
            print(f"SKIP (already sorted): {p}", file=sys.stderr)
            continue
        dst = os.path.join(os.path.dirname(p), verdict, os.path.basename(p))
        os.makedirs(os.path.dirname(dst), exist_ok=True)
        if os.path.exists(dst):
            print(f"SKIP (collision): {dst}", file=sys.stderr)
            continue
        shutil.move(p, dst)
        print(f"{frac:.3f} {verdict} {p} -> {dst}")


if __name__ == "__main__":
    main()
