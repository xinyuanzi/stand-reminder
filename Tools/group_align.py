#!/usr/bin/env python3
"""没有办公椅的形象（B 水獭 / C 小熊），用「头顶宽度 + 落地点」对齐机位。

思路：
1. 先用基准帧（stand）和坐姿帧比较，解出一套归一化参数
   —— 头顶宽度决定缩放，内容包围盒的底边和水平中心决定平移；
2. 同一批派生帧共用这套参数。实测 AI 在同一基准上派生时相机是稳的
   （A 的四张派生图椅子高 818~824，误差 1%），所以共用参数即可。

用法： group_align.py b stand up punch1 punch2
      group_align.py b sitdown --solo
"""
import sys

import numpy as np
from PIL import Image

from add_up_frames import render
from normalize import strip_background
from paths import frame_raw, mascot_png

HEAD_BAND = 0.14  # 取内容包围盒顶部这么高的一条，量它的宽度 ≈ 头顶宽度


def measure(im):
    a = np.asarray(im.convert("RGBA")).astype(np.int16)
    al = a[:, :, 3]
    ys, xs = np.where(al > 150)
    if len(xs) == 0:
        return None
    x0, x1, y0, y1 = xs.min(), xs.max(), ys.min(), ys.max()
    band = int((y1 - y0) * HEAD_BAND) + 1
    sub = al[y0:y0 + band, :] > 150
    bxs = np.where(sub.any(axis=0))[0]
    head_w = int(bxs.max() - bxs.min()) if len(bxs) else int(x1 - x0)
    return dict(head=int(head_w), top=int(y0), bottom=int(y1),
                cx=(float(x0) + float(x1)) / 2)


def main():
    style = sys.argv[1]
    poses, i = [], 2
    opts = {}
    while i < len(sys.argv):
        a = sys.argv[i]
        if a.startswith("--"):
            opts[a] = float(sys.argv[i + 1])
            i += 2
        else:
            poses.append(a)
            i += 1

    def opt(name, default=None):
        return opts.get(name, default)

    ref = Image.open(mascot_png(style, "sit"))
    rm = measure(ref)
    ref_head = opt("--head", rm["head"])
    print(f"参照 sit: 头顶宽={ref_head} 底边={rm['bottom']} 中心x={rm['cx']:.0f}")

    base = strip_background(
        Image.open(frame_raw(style, poses[0])).convert("RGBA"))
    bm = measure(base)
    s = opt("--win", bm["head"] * 512.0 / ref_head)
    # 竖向锚点：默认对齐落地点；--top N 表示改为对齐头顶到画布 y=N
    # （站起来这类高个子必须用 --top，否则头会被圆形头像裁掉）
    top_target = opt("--top")
    cy = bm["bottom"] + s / 2 - rm["bottom"] * s / 512.0
    if top_target is not None:
        cy = bm["top"] + s / 2 - top_target * s / 512.0
    # 横向：默认对齐内容水平中心
    cx = bm["cx"] + s / 2 - rm["cx"] * s / 512.0
    print(f"{poses[0]}: 头顶宽={bm['head']} 窗口={s:.0f} 中心=({cx:.0f},{cy:.0f})")

    for pose in poses:
        raw = base if pose == poses[0] else strip_background(
            Image.open(frame_raw(style, pose)).convert("RGBA"))
        dst = mascot_png(style, pose)
        render(raw, (cx, cy), s, dst)
        print(f"  {pose} -> {dst}")


if __name__ == "__main__":
    main()
