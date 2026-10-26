#!/usr/bin/env python3
"""把同一角色的一组动作用统一裁切窗口归一化，保证播放时不跳位。

输入 1024x1024 纯白背景原始帧，输出 512x512 透明 PNG。
所有帧共用同一个裁切矩形，因此保留相对位置与比例。
"""
import sys
from collections import deque

from PIL import Image, ImageFilter

# 在 1024 画布上的统一裁切窗口（已按所有帧的轮廓并集预留余量）
CROP = (24, 16, 1000, 992)


def is_bg(p):
    r, g, b, a = p
    if a == 0:
        return True
    lo, hi = min(r, g, b), max(r, g, b)
    return lo >= 205 and hi >= 218 and (hi - lo) <= 18


def strip_background(im):
    w, h = im.size
    px = im.load()
    vis = bytearray(w * h)
    q = deque()
    for x in range(w):
        for y in (0, h - 1):
            if is_bg(px[x, y]):
                vis[y * w + x] = 1
                q.append((x, y))
    for y in range(h):
        for x in (0, w - 1):
            if is_bg(px[x, y]) and not vis[y * w + x]:
                vis[y * w + x] = 1
                q.append((x, y))
    while q:
        x, y = q.popleft()
        px[x, y] = (0, 0, 0, 0)
        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            nx, ny = x + dx, y + dy
            if 0 <= nx < w and 0 <= ny < h and not vis[ny * w + nx] and is_bg(px[nx, ny]):
                vis[ny * w + nx] = 1
                q.append((nx, ny))
    im.putalpha(im.getchannel("A").filter(ImageFilter.GaussianBlur(0.6)))
    return im


def clear_edges(im, n=3):
    w, h = im.size
    px = im.load()
    for x in range(w):
        for y in range(n):
            px[x, y] = (0, 0, 0, 0)
            px[x, h - 1 - y] = (0, 0, 0, 0)
    for y in range(h):
        for x in range(n):
            px[x, y] = (0, 0, 0, 0)
            px[w - 1 - x, y] = (0, 0, 0, 0)


def normalize(src, dst, size=512):
    im = strip_background(Image.open(src).convert("RGBA"))
    im = im.crop(CROP)
    im = im.resize((size, size), Image.LANCZOS)
    clear_edges(im)
    im.save(dst)
    return dst


if __name__ == "__main__":
    for s, d in zip(sys.argv[1::2], sys.argv[2::2]):
        print(normalize(s, d))
