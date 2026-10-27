#!/usr/bin/env python3
"""素材路径的唯一出处。

目录结构（2026-10-27 起按形象分目录）：

    Resources/
    ├── frames/{style}/{pose}_raw.png     AI 原始出图，1024×1024，白底，不入库
    └── mascots/{style}/{pose}.png        抠图对齐后的成品，512×512，透明

`style`：a 橘猫 / b 水獭 / c 小熊 / d 猫头鹰 / e 柴犬
`pose` ：sit / blink / yawn1 / yawn2 / scratch / stand / up / punch1 / punch2
         / flap1 / flap2 / sitdown / gaze_left / gaze_right / gaze_up / gaze_down

路径由本文件计算（基于 __file__，不依赖当前工作目录），
所以所有脚本都能在任何目录下执行，不再要求 `cd` 到项目根。
"""
import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RESOURCES = os.path.join(ROOT, "Resources")


def frame_raw(style: str, pose: str) -> str:
    """AI 原始出图：Resources/frames/{style}/{pose}_raw.png"""
    return os.path.join(RESOURCES, "frames", style, f"{pose}_raw.png")


def mascot_png(style: str, pose: str) -> str:
    """成品帧：Resources/mascots/{style}/{pose}.png"""
    return os.path.join(RESOURCES, "mascots", style, f"{pose}.png")


def ensure_parent(path: str) -> str:
    """写文件前建好父目录（新增形象时该目录还不存在）。"""
    parent = os.path.dirname(path)
    if parent:
        os.makedirs(parent, exist_ok=True)
    return path
