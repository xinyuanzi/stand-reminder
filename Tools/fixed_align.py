#!/usr/bin/env python3
"""固定取景对齐：**所有帧共用同一个裁切窗口与缩放比**，不做逐帧适配。

为什么需要第三个对齐工具（前两个是 chair_align / content_align）：

- chair_align：以椅子为锚，适合换姿势幅度大的帧。缺点是当动物把椅子挡住、
  只能量到露出的扶手时，会算出完全错误的缩放。
- content_align：以内容包围盒为锚，适合"同姿势只改局部"（视线、眨眼）。
  缺点是把逐帧的包围盒差异当成"该缩放"，于是 AI 画大一点就被缩回去 ——
  播放时表现为每帧体型都在微动，肉眼就是"抖"。

猫头鹰这批原始图有个好前提：**机位根本没动**。坐姿类九帧的暖色包围盒
逐像素一致（y=175..978），站立类也只差 3px。这种素材不需要逐帧对齐，
只需要一个固定窗口 —— 用 content_align 反而引入 1~3% 的尺寸抖动。

原则：**宁可发现某帧 AI 真的画大了然后重生成，也不让播放器替 AI 背锅。**
（punch2 就是这么被揪出来的：包围盒高 626 vs 其它 804，缩回去虽然能对齐，
但那是把"画错了"掩盖成"画对了"。）

用法：
    fixed_align.py d sit stand up flap1 flap2 sitdown
    （第一个参数是风格，第二个是参照姿态，其余是要输出的姿态）
"""
import sys

from PIL import Image

from add_up_frames import bbox, render
from normalize import strip_background
from paths import frame_raw, mascot_png


def main():
    style = sys.argv[1]
    ref_pose = sys.argv[2]
    poses = sys.argv[3:]

    ref_raw = strip_background(
        Image.open(frame_raw(style, ref_pose)).convert("RGBA"))
    rb = bbox(ref_raw)
    ref_png = Image.open(mascot_png(style, ref_pose)).convert("RGBA")
    pb = bbox(ref_png)

    # 只从参照帧反解一次窗口，之后所有帧照抄
    size = 512 * (rb[3] - rb[1]) / (pb[3] - pb[1])
    cx = (rb[0] + rb[2]) / 2
    cy = (rb[1] + rb[3]) / 2
    print(f"参照 {ref_pose}: raw bbox={rb} png bbox={pb}")
    print(f"固定窗口: 中心=({cx:.1f},{cy:.1f}) 边长={size:.1f}")

    for pose in poses:
        raw = strip_background(
            Image.open(frame_raw(style, pose)).convert("RGBA"))
        cb = bbox(raw)
        dst = mascot_png(style, pose)
        render(raw, (cx, cy), size, dst)

        out = bbox(Image.open(dst).convert("RGBA"))
        rh = cb[3] - cb[1]
        oh = out[3] - out[1]
        flag = ""
        if abs(rh - (rb[3] - rb[1])) > 24:
            flag = f"  ⚠️ 原始内容高 {rh} vs 参照 {rb[3] - rb[1]}，AI 画错尺寸，建议重生成"
        print(f"{pose}: raw 内容高={rh} -> 成品 bbox={out} 高={oh}{flag}")


if __name__ == "__main__":
    main()
