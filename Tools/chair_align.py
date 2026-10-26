#!/usr/bin/env python3
"""以办公椅为唯一锚点，把动作帧对齐到坐姿帧的机位。

为什么用椅子：它是两个镜头里唯一位置固定、形状不变的物体。
用椅子高度定缩放、用左边缘+顶边定平移，等价于恢复了机位，
切换帧时不会出现「镜头拉近/平移」的错觉。

注意：椅子宽度不可用 —— 它被猫挡住，量到的宽只是可见部分。

用法： chair_align.py a stand up punch1 punch2
       chair_align.py d stand up        # 新形象同样适用，只要坐姿帧里有那把椅子
"""
import sys

import numpy as np
from PIL import Image

from add_up_frames import render
from normalize import strip_background

LEFT_LIMIT = 0.60  # 只看左侧，避开身上的冷灰阴影


def chair_bbox(im):
    a = np.asarray(im.convert("RGBA")).astype(np.int16)
    r, g, b, al = a[:, :, 0], a[:, :, 1], a[:, :, 2], a[:, :, 3]
    lo = np.minimum(np.minimum(r, g), b)
    hi = np.maximum(np.maximum(r, g), b)
    m = (al > 150) & ((hi - lo) <= 18) & (b >= r) & (lo > 40) & (hi < 215)
    m[:, int(m.shape[1] * LEFT_LIMIT):] = False
    ys, xs = np.where(m)
    if len(xs) < 1000:
        return None
    return int(xs.min()), int(ys.min()), int(xs.max()), int(ys.max())


def main():
    style = sys.argv[1]
    # 参照用同一形象自己的坐姿帧：椅子是这一系列里唯一不动的物体，
    # 以它为锚点，走过去/站起来/出拳的帧才能共用同一个机位。
    ref_path = f"Resources/mascot_{style}_sit.png"
    ref = Image.open(ref_path)
    rb = chair_bbox(ref)
    if rb is None:
        print("参照帧找不到椅子")
        return
    rw, rh = ref.size
    ref_h = rb[3] - rb[1]
    print(f"参照椅子 bbox={rb} 高={ref_h}")

    for pose in sys.argv[2:]:
        raw = strip_background(
            Image.open(f"Resources/frames/{style}_{pose}_raw.png").convert("RGBA"))
        cb = chair_bbox(raw)
        if cb is None:
            print(f"{pose}: 找不到椅子，跳过")
            continue
        raw_h = cb[3] - cb[1]

        s = raw_h * rw / ref_h
        cx = cb[0] + s / 2 - rb[0] * s / rw
        cy = cb[1] + s / 2 - rb[1] * s / rw

        dst = f"Resources/mascot_{style}_{pose}.png"
        render(raw, (cx, cy), s, dst)
        print(f"{pose}: 椅子高 {raw_h}→窗口 {s:.0f} 中心=({cx:.0f},{cy:.0f}) -> {dst}")


if __name__ == "__main__":
    main()
