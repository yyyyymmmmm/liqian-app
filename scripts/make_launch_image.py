#!/usr/bin/env python3
"""启动图生产脚本（v5.11.4）。

启动屏版式不变（Project.swift 的 UILaunchScreen：LaunchBackground
纸白满屏＋LaunchImage 居中），只换图形本体：退役的旧礼结 → 新谱框
裸标志 docs/brand/liji-mark.svg（墨框 #262626＋左侧装订线＋右下朱砂
落款点 #A62B1F，几何以该 SVG 为单一事实源，本脚本不重绘）。

合成口径：
- 画布底色 #FAF9F6，与现行启动图实测底色及 LaunchBackground
  colorset 同值，换图后两者仍无缝（主图标的 #F7F5F0 是图标成品
  口径，不适用于启动屏这块 App 纸白）。
- 标志外框高度占画布 80.6%——与退役礼结在旧 @3x 图中的实测
  高度占比（319/396）一致，保证换图前后视觉分量不变。
- 标志在 SVG viewBox（100×100）中的外框（含描边）为
  x 21..79、y 15..85：高 70、宽 58、中心恰为 (50, 50)，
  故整幅 viewBox 按目标高度反推比例、居中粘贴即可，外框自然居中。

抗锯齿：先以目标 4 倍渲染再 LANCZOS 缩回。输出三档与 imageset 的
Contents.json 声明一致（132pt 的 1x/2x/3x = 132/264/396 px），
RGB PNG（同旧图，无 alpha）。

用法（仓库根目录）：python3 scripts/make_launch_image.py
依赖：Pillow、cairosvg。
"""

import io
import json
from pathlib import Path

import cairosvg
from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
MARK_SVG = ROOT / "docs/brand/liji-mark.svg"
IMAGESET = ROOT / "App/Resources/Assets.xcassets/LaunchImage.imageset"

PAPER = (250, 249, 246)  # #FAF9F6
BASE_PX = 132  # imageset 1x 像素边长（与退役图同规格）
HEIGHT_FRACTION = 319 / 396  # 退役礼结实测高度占比
MARK_HEIGHT_UNITS = 70.0  # 标志外框在 viewBox 中的高度（15..85）


def render_mark(viewbox_px: int) -> Image.Image:
    """把整个 100×100 viewBox 渲染为 viewbox_px 见方的透明图（4 倍超采样后缩回）。"""
    raw = cairosvg.svg2png(
        url=str(MARK_SVG),
        output_width=viewbox_px * 4,
        output_height=viewbox_px * 4,
    )
    img = Image.open(io.BytesIO(raw)).convert("RGBA")
    return img.resize((viewbox_px, viewbox_px), Image.LANCZOS)


def main() -> None:
    contents = json.loads((IMAGESET / "Contents.json").read_text())
    for entry in contents["images"]:
        scale = float(entry["scale"].rstrip("x"))
        size = round(BASE_PX * scale)
        # viewBox 边长：标志外框高 = viewbox 的 70%，须占画布 HEIGHT_FRACTION
        viewbox_px = round(size * HEIGHT_FRACTION * 100 / MARK_HEIGHT_UNITS)
        mark = render_mark(viewbox_px)
        canvas = Image.new("RGB", (size, size), PAPER)
        offset = (size - viewbox_px) // 2
        canvas.paste(mark, (offset, offset), mark)
        out = IMAGESET / entry["filename"]
        canvas.save(out)
        print(f"{entry['filename']}: {size}x{size}, viewBox {viewbox_px}px, offset {offset}")


if __name__ == "__main__":
    main()
