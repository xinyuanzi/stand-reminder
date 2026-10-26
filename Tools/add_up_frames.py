#!/usr/bin/env python3
"""把新生成的 up（伸懒腰）原始帧，按该形象既有取景归一化，并做尺寸对齐。

两步：
1. 从同形象一个已知 raw→png 配对反解出当初的裁切窗口；
2. 因为新图是重新生成的，主体大小未必与坐姿一致，再按「内容包围盒」把
   窗口等比缩放一次，让 up 与坐姿在 512 画布上的视觉尺寸对齐。
"""
import sys

from PIL import Image

from normalize import strip_background, clear_edges


def bbox(im, thr=12):
    w, h = im.size
    px = im.load()
    x0, y0, x1, y1 = w, h, 0, 0
    for y in range(h):
        for x in range(w):
            if px[x, y][3] > thr:
                if x < x0:
                    x0 = x
                if y < y0:
                    y0 = y
                if x > x1:
                    x1 = x
                if y > y1:
                    y1 = y
    return (x0, y0, x1 + 1, y1 + 1)


def content_extent(im):
    b = bbox(im)
    return max(b[2] - b[0], b[3] - b[1])


def solve_crop(style, ref_pose="yawn2"):
    raw = strip_background(
        Image.open(f"Resources/frames/{style}_{ref_pose}_raw.png").convert("RGBA"))
    rb = bbox(raw)
    png = Image.open(f"Resources/mascot_{style}_{ref_pose}.png").convert("RGBA")
    pb = bbox(png)
    sc = (rb[2] - rb[0]) / (pb[2] - pb[0])
    size = 512 * sc
    cx = rb[0] + (rb[2] - rb[0]) / 2
    cy = rb[1] + (rb[3] - rb[1]) / 2
    return raw, (cx, cy, size)


def render(up, center, size, dst):
    cx, cy = center
    box = Image.new("RGBA", (int(round(size)), int(round(size))), (0, 0, 0, 0))
    box.paste(up, (int(round(size / 2 - cx)), int(round(size / 2 - cy))))
    out = box.resize((512, 512), Image.LANCZOS)
    clear_edges(out)
    out.save(dst)
    return out


def main():
    styles = sys.argv[1:] or ["a", "b", "c"]
    for style in styles:
        _, (cx, cy, size) = solve_crop(style)
        up = strip_background(
            Image.open(f"Resources/frames/{style}_up_raw.png").convert("RGBA"))

        sit = Image.open(f"Resources/mascot_{style}_sit.png").convert("RGBA")
        target = content_extent(sit)

        # 第一次按基准窗口渲染，量出主体现有尺寸，再按比例放大窗口
        probe = render(up, (cx, cy), size, "/tmp/_probe.png")
        got = content_extent(probe)
        k = got / target
        size2 = size * k
        dst = f"Resources/mascot_{style}_up.png"
        out = render(up, (cx, cy), size2, dst)
        print(f"{style}: 窗口 {size:.0f}->{size2:.0f}（k={k:.3f}） "
              f"内容 {got}->{content_extent(out)} 目标={target} -> {dst}")


if __name__ == "__main__":
    main()
