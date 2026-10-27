#!/usr/bin/env python3
"""把 GifShot 抓到的帧序拼成 README 首屏 GIF。

为什么要专门一个脚本：
- 面板是透明背景（四周留了 28pt 给阴影），得先铺一层底色，
  否则 GIF 在半透明边缘会出黑边——必须先 paste 再合成，不能直接 convert。
- 100 帧原尺寸直接存 GIF 会有 10MB+。压到 460px 宽 + 128 色，肉眼基本无损。
- PIL 存 GIF 必须自己处理调色板，逐帧 ADAPTIVE 比全局单一调色板省一半体积。

用法：
    python3 Tools/make_hero_gif.py /tmp/gifshot docs/images/card-routine.gif
"""
import glob
import os
import sys

from PIL import Image, ImageDraw

WIDTH = 460
FPS = 10
COLORS = 128


def background(size):
    """浅色竖向渐变。和 app 的米色卡片不是一回事，这里要的是一个中性的桌面感。"""
    w, h = size
    top = (246, 247, 250)
    bottom = (228, 234, 242)
    bg = Image.new("RGB", (1, h))
    px = bg.load()
    for y in range(h):
        t = y / max(1, h - 1)
        px[0, y] = tuple(int(top[i] + (bottom[i] - top[i]) * t) for i in range(3))
    return bg.resize((w, h), Image.BILINEAR)


def main():
    src = sys.argv[1] if len(sys.argv) > 1 else "/tmp/gifshot"
    dst = sys.argv[2] if len(sys.argv) > 2 else "docs/images/card-routine.gif"

    paths = sorted(glob.glob(os.path.join(src, "*.png")))
    if not paths:
        sys.exit(f"没找到帧：{src}")

    first = Image.open(paths[0]).convert("RGBA")
    scale = WIDTH / first.width
    size = (WIDTH, round(first.height * scale))
    bg = background(size)

    frames = []
    for p in paths:
        im = Image.open(p).convert("RGBA").resize(size, Image.LANCZOS)
        # 先把 RGBA 贴到实底上再转 RGB。直接 convert("RGB") 会把透明像素按黑底算，
        # 卡片外面那圈阴影立刻变成脏灰边。
        canvas = bg.copy()
        canvas.paste(im, (0, 0), im)
        frames.append(canvas.convert("P", palette=Image.ADAPTIVE, colors=COLORS))

    os.makedirs(os.path.dirname(dst) or ".", exist_ok=True)
    frames[0].save(
        dst,
        save_all=True,
        append_images=frames[1:],
        duration=int(1000 / FPS),
        loop=0,
        optimize=True,
        disposal=1,
    )

    kb = os.path.getsize(dst) / 1024
    print(f"{dst}  {size[0]}×{size[1]}  {len(frames)} 帧  {len(frames)/FPS:.1f}s  {kb:.0f} KB")
    if kb > 4096:
        print("⚠️ 超过 4MB，考虑降 WIDTH 或 COLORS")


if __name__ == "__main__":
    main()
