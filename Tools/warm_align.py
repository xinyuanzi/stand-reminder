#!/usr/bin/env python3
"""用「暖色躯干宽度」对齐，专门处理爪子/翅膀会举过头顶或张开的新形象。

为什么不能用头顶宽度（group_align）：
    那个方法取包围盒顶部 14% 的一条量宽度当成"头顶"。
    一旦有翅膀举过头顶（伸懒腰）或向前伸（出拳），量到的是翅膀，
    算出来的缩放会偏大一倍，成品整体缩小、位置下坠。

为什么不能用椅子（chair_align）：
    圆胖形象站起来时会挡住椅子，椅子的可见高度只剩露出的扶手，同样失准。

所以改成：
1. 用暖色掩码把动物从灰色椅子和白底里分离出来
   （椅子是低饱和灰，动物是暖褐/奶油，r-b 差距明显）
2. 在躯干带（掩码下部 30%~60% 的行）取最大宽度当尺度基准 ——
   这一段落在肚子上，翅膀再高、伸得再远也干扰不到
3. 用掩码的整体中心做平移基准

用法： warm_align.py d sit blink yawn1 yawn2 scratch stand up punch1 punch2 sitdown
       （第一个是形象，第二个是参照姿态，其余是要对齐的姿态）
"""
import sys

import numpy as np
from PIL import Image

from add_up_frames import render
from normalize import strip_background
from paths import frame_raw, mascot_png

# 基准带的相对区间（相对暖色掩码高度，0 = 顶部）
# 取「脚底那一带」的宽度当尺度基准：
#   - 躯干中段会被横伸的翅膀污染（出拳帧直接偏小一圈）
#   - 头部会被举过头顶的翅膀污染
#   - 脚底带在所有姿势里都是身体最窄最稳的部分，翅膀伸得再远也碰不到
BASE_LO = 0.86
BASE_HI = 0.98


def warm_mask(im):
    a = np.asarray(im.convert("RGBA")).astype(np.int16)
    r, g, b, al = a[:, :, 0], a[:, :, 1], a[:, :, 2], a[:, :, 3]
    # 暖色：红明显高于蓝；再排掉阴影和灰椅子
    m = (al > 120) & ((r - b) > 18) & (r > 60)
    return m


def measure(im):
    m = warm_mask(im)
    ys, xs = np.where(m)
    if len(xs) < 500:
        return None
    y0, y1 = int(ys.min()), int(ys.max())
    h = max(1, y1 - y0)
    lo = y0 + int(h * BASE_LO)
    hi = y0 + int(h * BASE_HI)
    band = m[lo:hi, :]
    widths = []
    for row in range(band.shape[0]):
        xs_row = np.where(band[row])[0]
        if len(xs_row):
            widths.append(int(xs_row.max() - xs_row.min()))
    base = int(np.median(widths)) if widths else int(xs.max() - xs.min())
    return dict(base=base, cx=(xs.min() + xs.max()) / 2, bottom=y1,
                top=y0, h=h)


def main():
    style = sys.argv[1]
    ref_pose = sys.argv[2]
    poses = sys.argv[3:]

    ref = Image.open(mascot_png(style, ref_pose)).convert("RGBA")
    rm = measure(ref)
    if rm is None:
        print("参照帧找不到暖色躯干，放弃")
        return
    print(f"参照 {ref_pose}: 脚底宽={rm['base']} 脚底y={rm['bottom']} 中心x={rm['cx']:.0f}")
    rw, rh = ref.size

    for pose in poses:
        if pose == ref_pose:
            continue
        raw = strip_background(
            Image.open(frame_raw(style, pose)).convert("RGBA"))
        pm = measure(raw)
        if pm is None:
            print(f"{pose}: 找不到暖色躯干，跳过")
            continue
        s = rw * pm["base"] / rm["base"]
        # 竖向按脚底对齐，不按中心：按中心会让矮姿态悬空、高姿态下沉
        cx = pm["cx"] + s / 2 - rm["cx"] * s / rw
        cy = pm["bottom"] + s / 2 - rm["bottom"] * s / rh
        dst = mascot_png(style, pose)
        render(raw, (cx, cy), s, dst)

        out = Image.open(dst).convert("RGBA")
        om = measure(out)
        print(f"{pose}: 脚底宽 {pm['base']}→窗口 {s:.0f} -> 成品脚底宽={om['base']} "
              f"脚底y={om['bottom']} 高={om['h']}")


if __name__ == "__main__":
    main()
