#!/usr/bin/env python3
from __future__ import annotations
"""
詳細カードのアイコン領域の固定クロップ候補を試して、各画像で正しい色が
取れるかを検証する。+ 各クロップの平均彩度ピクセルの色相分布を出して、
バケット境界の調整に使う。
"""
import sys
from pathlib import Path
import colorsys
from collections import Counter
from PIL import Image, ImageOps, ImageDraw

REF_DIR = Path(__file__).resolve().parent.parent / "references"
OUT_DIR = REF_DIR / "_debug"
OUT_DIR.mkdir(exist_ok=True)

EXPECTED = {
    "IMG_1522.jpeg": "red",
    "IMG_1523.jpeg": "blue",
    "IMG_1524.jpeg": "yellow",
    "IMG_1525.jpeg": "green",
}

def hue_bucket(h_deg: float):
    if 0 <= h_deg < 22 or 338 <= h_deg <= 360: return "red"
    if 35 <= h_deg < 70:                        return "yellow"
    if 75 <= h_deg < 200:                       return "green"  # cyan も含める
    if 200 <= h_deg < 270:                      return "blue"
    return None

def hue_histogram(img: Image.Image):
    """高彩度ピクセルだけ集めた色相ヒストグラム（10°きざみ）"""
    px = img.load()
    w, h = img.size
    bins = Counter()
    n = 0
    bucket_counts = Counter()
    for y in range(h):
        for x in range(w):
            r, g, b = px[x,y]
            r, g, b = r/255, g/255, b/255
            mx = max(r,g,b); mn = min(r,g,b)
            v = mx
            s = 0 if v == 0 else (v-mn)/v
            if s < 0.30 or v < 0.20 or v > 0.97:
                continue
            n += 1
            hh = colorsys.rgb_to_hls(r,g,b)[0] * 360
            bins[int(hh // 10) * 10] += 1
            b_ = hue_bucket(hh)
            if b_:
                bucket_counts[b_] += 1
    return bins, bucket_counts, n

def crop_relative(img: Image.Image, box):
    W, H = img.size
    x0, y0, x1, y1 = box
    return img.crop((int(W*x0), int(H*y0), int(W*x1), int(H*y1)))

def annotate(path: Path, boxes_with_labels):
    img = Image.open(path)
    img = ImageOps.exif_transpose(img).convert("RGB")
    overlay = img.copy()
    d = ImageDraw.Draw(overlay)
    W, H = img.size
    colors = ["#ffff00", "#00ff00", "#ff8800"]
    for i, (label, box) in enumerate(boxes_with_labels):
        x0,y0,x1,y1 = box
        d.rectangle([int(W*x0), int(H*y0), int(W*x1), int(H*y1)],
                    outline=colors[i % len(colors)], width=12)
    overlay.thumbnail((600, 800))
    overlay.save(OUT_DIR / f"{path.stem}_test.png")

def main():
    paths = sorted(REF_DIR.glob("IMG_*.jpeg"))
    if not paths:
        print("no reference images found", file=sys.stderr); sys.exit(1)

    candidates = [
        ("L-mid-1", (0.07, 0.55, 0.20, 0.72)),
        ("L-mid-2", (0.10, 0.58, 0.22, 0.74)),
        ("L-mid-3", (0.13, 0.60, 0.25, 0.78)),
    ]

    for label, box in candidates:
        print(f"\n--- {label} rel={box} ---")
        for p in paths:
            img = Image.open(p)
            img = ImageOps.exif_transpose(img).convert("RGB")
            crop = crop_relative(img, box)
            crop.save(OUT_DIR / f"{p.stem}_{label}.png")
            bins, buckets, n = hue_histogram(crop)
            top_hues = bins.most_common(5)
            top_buckets = buckets.most_common()
            expected = EXPECTED[p.name]
            got = top_buckets[0][0] if top_buckets else "?"
            ok = "OK" if got == expected else "NG"
            print(f"  {p.name}  exp={expected:6s} got={got:7s} [{ok}] "
                  f"chrom={n:5d}  hues={top_hues}  buckets={dict(top_buckets)}")

    # 1セットのみ図示
    annotate(paths[0], [(c[0], c[1]) for c in candidates])
    print（f"\nオーバーレイ: {OUT_DIR}/IMG_1522_test.png  + 各クロップ画像 *_L-mid-*.png"）

if __name__ == "__main__":
    main()
