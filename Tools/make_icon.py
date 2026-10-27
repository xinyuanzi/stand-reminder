#!/usr/bin/env python3
"""生成 App 图标：Resources/AppIcon.icns（外加同名的 1024 PNG 备查）。

为什么用猫头鹰的**头部特写**而不是整只：
完整姿态里带着一把办公椅，缩到 16/32px 会变成一团灰糊。头部的眼睛和
喙在小尺寸下仍然是可辨认的形状，这是图标能成立的最低要求。

素材：Resources/frames/d/sit_raw.png（1024 白底原始帧）
输出：Resources/AppIcon.icns + Resources/AppIcon.png

用法：python3 Tools/make_icon.py
"""
import os
import shutil
import subprocess
import sys
import tempfile

from PIL import Image, ImageDraw

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from normalize import strip_background  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

SRC = os.path.join(ROOT, "Resources", "frames", "d", "sit_raw.png")
OUT_ICNS = os.path.join(ROOT, "Resources", "AppIcon.icns")
OUT_PNG = os.path.join(ROOT, "Resources", "AppIcon.png")

# 1024 画布上的头部特写（左右/上下都避开了椅背与扶手，改之前先跑一遍看边缘）
CROP = (360, 165, 730, 535)

# macOS 图标网格：内容区 824×824 居中，圆角约 185（Big Sur 之后的标准比例）
CANVAS = 1024
TILE_INSET = 100
TILE_RADIUS = 185
BG = (252, 244, 232, 255)     # 和提醒卡片同一个米色
EDGE = (233, 222, 203, 255)   # 极淡的描边，避免白底上糊成一块

# iconutil 需要的完整尺寸表：(文件名, 像素边长)
ICONSET = [
    ("icon_16x16.png", 16), ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32), ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128), ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256), ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512), ("icon_512x512@2x.png", 1024),
]


def build_master() -> Image.Image:
    owl = strip_background(Image.open(SRC).convert("RGBA")).crop(CROP)

    # 先把内容区（824×824）单独画好再贴进 1024 画布。
    # 直接在 1024 上画圆角矩形会让描边的外半像素越出网格，白底上留一圈淡边。
    tile_side = CANVAS - TILE_INSET * 2
    side = int(tile_side * 0.82)
    owl = owl.resize((side, side), Image.LANCZOS)

    tile = Image.new("RGBA", (tile_side, tile_side), (0, 0, 0, 0))
    ImageDraw.Draw(tile).rounded_rectangle(
        (2, 2, tile_side - 2, tile_side - 2),
        radius=TILE_RADIUS, fill=BG, outline=EDGE, width=3
    )
    tile.alpha_composite(owl, ((tile_side - side) // 2, (tile_side - side) // 2))

    mask = Image.new("L", (tile_side, tile_side), 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        (0, 0, tile_side - 1, tile_side - 1), radius=TILE_RADIUS, fill=255
    )
    tile.putalpha(Image.composite(tile.getchannel("A"),
                                  Image.new("L", (tile_side, tile_side), 0), mask))

    canvas = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))
    canvas.alpha_composite(tile, (TILE_INSET, TILE_INSET))
    return canvas


def main() -> None:
    master = build_master()
    master.save(OUT_PNG)

    tmp = tempfile.mkdtemp(prefix="AppIcon.")
    iconset = os.path.join(tmp, "AppIcon.iconset")
    os.makedirs(iconset)
    for name, px in ICONSET:
        subprocess.run(["sips", "-z", str(px), str(px), OUT_PNG,
                        "--out", os.path.join(iconset, name)],
                       check=True, stdout=subprocess.DEVNULL)
    subprocess.run(["iconutil", "-c", "icns", iconset, "-o", OUT_ICNS], check=True)
    shutil.rmtree(tmp, ignore_errors=True)

    print(f"✓ {OUT_ICNS}  ({os.path.getsize(OUT_ICNS) // 1024} KB)")
    print(f"✓ {OUT_PNG}")


if __name__ == "__main__":
    main()
