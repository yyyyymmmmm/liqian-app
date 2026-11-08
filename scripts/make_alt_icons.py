#!/usr/bin/env python3
"""备用图标变体生产脚本（v5.9，审计 #2）。

原理：主图（1024×1024）是纸白底＋单色平涂礼结。把每个像素投影到
「底色→原礼结色」的直线方向上，得到覆盖率 t（0＝纯底色、1＝纯礼结，
抗锯齿边落在中间，生成时的彩色镶边也被吸收为正常边缘）；新像素＝
底色＋t×(新礼结色−底色)。白底与构图一分不动，只换礼结颜色，
明暗与边缘过渡随 t 保留（保亮度换色）。

输入：App/Resources/Assets.xcassets/AppIcon.appiconset/Icon-App-1024x1024@1x.png
输出：App/Resources/AltIcon-<name>@2x.png（120）与 @3x.png（180），
      随 App 资源进包根目录，供 Info.plist 的 CFBundleAlternateIcons
      声明与 setAlternateIconName 切换。
      primary 一款不在 plist 声明里（桌面默认走资源目录主图标），
      其文件只作设置页缩略图。

用法（仓库根目录）：python3 scripts/make_alt_icons.py
依赖：Pillow、numpy（pip install pillow numpy）。
变体清单 VARIANTS 是单一事实源，须与 Sources/LiqianApp/
AppIconManager.swift 的 AppIconVariant.knotHex 逐项一致。
"""

from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
MASTER = ROOT / "App/Resources/Assets.xcassets/AppIcon.appiconset/Icon-App-1024x1024@1x.png"
OUT_DIR = ROOT / "App/Resources"

# 主图实测双色（脚本对整图做过色值统计：底色占 ≈82%、礼结为单色平涂）
BG = np.array([250, 249, 246], dtype=np.float64)     # 纸白 #FAF9F6
KNOT = np.array([166, 43, 31], dtype=np.float64)     # 朱砂 #A62B1F

# 变体名（＝AppIconVariant rawValue）→ 礼结色 hex
VARIANTS = {
    "primary": 0xA62B1F,      # 朱砂（默认，仅生成缩略图文件）
    "night": 0xD96A5C,        # 夜晚主题同色
    "tencentBlue": 0x0052D9,  # 腾讯蓝主题同色
    "graphite": 0x4E5969,     # 灰色主题同色
    "amber": 0xA16207,        # 黄色主题同色
    "jdRed": 0xE1251B,        # 独立色：大厂红（京东红）
    "appleBlue": 0x007AFF,    # 独立色：蓝
    "black": 0x232323,        # 独立色：黑
    "brightYellow": 0xE8A20C,  # 独立色：黄
}

SIZES = {"@2x": 120, "@3x": 180}


def hex_to_rgb(value: int) -> np.ndarray:
    return np.array(
        [(value >> 16) & 0xFF, (value >> 8) & 0xFF, value & 0xFF],
        dtype=np.float64,
    )


def coverage_map(img: np.ndarray) -> np.ndarray:
    """逐像素覆盖率 t：像素在 底色→原礼结色 方向上的投影占比，
    钳制在 [-0.05, 1.05]（保留礼结内部的细微明暗起伏，底色噪点近零）。"""
    direction = KNOT - BG
    denom = float(direction @ direction)
    t = ((img - BG) @ direction) / denom
    return np.clip(t, -0.05, 1.05)


def recolor(t: np.ndarray, new_knot: np.ndarray) -> Image.Image:
    out = BG + t[..., None] * (new_knot - BG)
    out = np.clip(np.rint(out), 0, 255).astype(np.uint8)
    return Image.fromarray(out, mode="RGB")


def main() -> None:
    master = Image.open(MASTER).convert("RGB")
    assert master.size == (1024, 1024), f"主图尺寸异常：{master.size}"
    t = coverage_map(np.asarray(master, dtype=np.float64))
    knot_share = float(np.mean(t > 0.5))
    print(f"主图覆盖率统计：礼结占比 ≈ {knot_share:.1%}")
    for name, hex_value in VARIANTS.items():
        full = recolor(t, hex_to_rgb(hex_value))
        for suffix, size in SIZES.items():
            out = full.resize((size, size), Image.LANCZOS)
            path = OUT_DIR / f"AltIcon-{name}{suffix}.png"
            out.save(path, optimize=True)
            print(f"  {path.relative_to(ROOT)}  ({size}×{size}, 礼结 #{hex_value:06X})")
    print("完成：变体已生成到 App/Resources/（随资源进包）")


if __name__ == "__main__":
    main()
