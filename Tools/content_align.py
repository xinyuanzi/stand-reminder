#!/usr/bin/env python3
"""按「内容包围盒」对齐，而不是按椅子。

椅子对齐（chair_align.py）适用于大幅度换姿势的帧：椅子是唯一不动的参照物。
但**视线跟随帧和坐姿帧是同一个姿势**，只是瞳孔方向不同，
这时用整体轮廓对齐更准 —— 也能保证切帧时动物的头一样大。

视线帧如果按椅子对齐，头会小 11%，来回切就是「缩一下」，肉眼等于闪屏。

用法： content_align.py a sit gaze_left gaze_right gaze_up gaze_down
       （第一个参数是风格，第二个是参照姿态，其余是要对齐的姿态）
"""
import sys

import numpy as np
from PIL import Image

from add_up_frames import render
from normalize import strip_background
from paths import frame_raw, mascot_png


def bbox(im):
    a = np.asarray(im.convert("RGBA"))
    m = a[:, :, 3] > 24
    ys, xs = np.where(m)
    if len(xs) == 0:
        return None
    return int(xs.min()), int(ys.min()), int(xs.max()), int(ys.max())


def main():
    style = sys.argv[1]
    ref_pose = sys.argv[2]
    poses = sys.argv[3:]

    ref = Image.open(mascot_png(style, ref_pose)).convert("RGBA")
    rb = bbox(ref)
    rw, rh = ref.size
    ref_h = rb[3] - rb[1]
    ref_cx = (rb[0] + rb[2]) / 2
    ref_cy = (rb[1] + rb[3]) / 2
    print(f"参照 {ref_pose}: 内容 bbox={rb} 高={ref_h} 中心=({ref_cx:.0f},{ref_cy:.0f})")

    for pose in poses:
        raw = strip_background(
            Image.open(frame_raw(style, pose)).convert("RGBA"))
        cb = bbox(raw)
        if cb is None:
            print(f"{pose}: 找不到内容，跳过")
            continue
        raw_h = cb[3] - cb[1]
        raw_cx = (cb[0] + cb[2]) / 2
        raw_cy = (cb[1] + cb[3]) / 2

        # 让 raw 的内容高度映射成参照的内容高度 -> 窗口大小
        s = rh * raw_h / ref_h
        cx = raw_cx + s / 2 - ref_cx * s / rw
        cy = raw_cy + s / 2 - ref_cy * s / rh

        dst = mascot_png(style, pose)
        render(raw, (cx, cy), s, dst)

        out = bbox(Image.open(dst))
        print(f"{pose}: 内容高 {raw_h}→窗口 {s:.0f} 中心=({cx:.0f},{cy:.0f}) "
              f"-> 成品 bbox={out} 高={out[3] - out[1]}")


if __name__ == "__main__":
    main()
