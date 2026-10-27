#!/usr/bin/env python3
"""生成 README 用的「形象全家福」横图 docs/images/mascots.png。

为什么要有这个脚本：这张图以前是手工拼的，每加一只形象就得重做一次，
而且换只手拼出来的圆底大小、格距、字号全不一样。现在把参数钉死在这里，
新增形象只要往 STYLES 里加一行再跑一遍。

布局参数是从四只版反解出来的（格距 300、圆直径 237、米色 251,244,233），
保持前后两版视觉一致。

形象一律按 **app 里的真实取景参数**贴：MascotCard 把 512 图塞进 112pt 框、
外面套 126pt 圆（比例 0.889），再乘各形象自己的 `mascotZoom` / `mascotOffset`。
这里用同一套数值换算成像素，图上看到的就是用户实际看到的 ——
不这么做的话，展示图的形象/圆比例偏大，柴犬这种宽体型的脚轮会被圆切掉，
而 app 里其实是完好的。

用法：
    /Library/Frameworks/Python.framework/Versions/3.14/bin/python3 Tools/make_mascots_sheet.py
"""
import os
import sys

from PIL import Image, ImageDraw, ImageFont, ImageChops

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from paths import ROOT, mascot_png  # noqa: E402

# ── 布局参数（改动前先跑一遍看看会不会挤） ──────────────────────────
CELL = 300          # 每格宽度，也是圆心间距
CIRCLE = 237        # 圆底直径
CIRCLE_CY = 184     # 圆心纵向位置
SHEET_H = 334       # 画布高
LABEL_CY = 316      # 标签文字中心 y
LABEL_SIZE = 17

BODY = 112          # MascotCard 里头像内容的边长（pt）
BODY_RATIO = BODY / 126.0   # 内容 / 圆 = 0.889

BG = (254, 254, 253)
BEIGE = (251, 244, 233)
INK = (72, 64, 56)
FONT = "/System/Library/Fonts/Hiragino Sans GB.ttc"

# ── 形象与标签 ────────────────────────────────────────────────────
# 顺序按解锁天数从早到晚。天数必须和 Sources/Habits.swift 的 `Unlocks.styles`
# 保持一致，否则图上的「N 天」会和设置页对不上。
# zoom / offset 跟 MascotCard.mascotZoom / mascotOffset 一一对应（单位 pt）。
STYLES = [
    ("c", "羊毛毡小熊", "默认", 1.00, (0, 0)),
    ("a", "毛绒橘猫", "5 天", 1.00, (0, 0)),
    ("d", "圆胖猫头鹰", "10 天", 1.30, (0, 2)),
    ("b", "水彩水獭", "15 天", 1.45, (2, -8)),
    ("e", "圆胖柴犬", "20 天", 1.00, (0, 0)),
]


def build() -> str:
    n = len(STYLES)
    width = CELL * n
    canvas = Image.new("RGB", (width, SHEET_H), BG)

    font = ImageFont.truetype(FONT, LABEL_SIZE, index=0)
    draw = ImageDraw.Draw(canvas)

    # 1pt 在展示图上等于多少像素，用来换算 mascotOffset
    pt = CIRCLE / 126.0

    for i, (style, name, unlock, zoom, offset) in enumerate(STYLES):
        cx = CELL * i + CELL // 2
        r = CIRCLE // 2
        box = [cx - r, CIRCLE_CY - r, cx + r, CIRCLE_CY + r]

        # 圆底 + 形象先合成到独立的 cell，再用圆的 alpha 一次性裁掉圆外部分。
        # 直接往 canvas 上贴会漏出圆心以外的脑袋和椅轮。
        cell = Image.new("RGBA", (width, SHEET_H), (0, 0, 0, 0))
        ImageDraw.Draw(cell).ellipse(box, fill=BEIGE + (255,))

        side = int(round(CIRCLE * BODY_RATIO * zoom))
        src = mascot_png(style, "sit")
        thumb = Image.open(src).convert("RGBA").resize((side, side), Image.LANCZOS)
        ox, oy = int(round(offset[0] * pt)), int(round(offset[1] * pt))
        cell.paste(thumb, (cx - side // 2 + ox, CIRCLE_CY - side // 2 + oy), thumb)

        mask = Image.new("L", (width, SHEET_H), 0)
        ImageDraw.Draw(mask).ellipse(box, fill=255)
        cell.putalpha(ImageChops.multiply(cell.getchannel("A"), mask))

        canvas.paste(cell, (0, 0), cell)

        text = f"{name} · {unlock}"
        draw.text((cx, LABEL_CY), text, font=font, fill=INK, anchor="mm")

    dst = os.path.join(ROOT, "docs", "images", "mascots.png")
    os.makedirs(os.path.dirname(dst), exist_ok=True)
    canvas.save(dst, optimize=True)
    return dst


if __name__ == "__main__":
    out = build()
    im = Image.open(out)
    print(f"wrote {out}  {im.width}×{im.height}  {os.path.getsize(out) // 1024} KB")
