#!/usr/bin/env python3
"""主图标全套尺寸生产脚本（v5.11.3）。

主图定版（Logo 横评拍板，01-ledger-frame 谱框）：纸白 #F7F5F0 满幅、
墨框＋左侧装订线＋右下朱砂落款点。源文件留档在 docs/brand/：
  - liji-appicon-1024.png（1024 主图，本脚本唯一输入）
  - liji-appicon-1024.svg / liji-mark.svg（矢量源）

本脚本只做一件事：把 1024 主图按 AppIcon.appiconset/Contents.json
的现有声明等比缩放（LANCZOS）到每个槽位的像素尺寸，文件名与声明
逐项一致；1024 槽位直接字节复制主图、不重编码。构图零改动。

注意：备用图标（AltIcon-*）已于 v5.11.4 整体取消，其生产脚本
make_alt_icons.py 随之删除，本脚本是图标资产的唯一生产入口。

用法（仓库根目录）：python3 scripts/make_primary_icon.py
依赖：Pillow。
"""

import json
import shutil
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
MASTER = ROOT / "docs/brand/liji-appicon-1024.png"
ICONSET = ROOT / "App/Resources/Assets.xcassets/AppIcon.appiconset"


def main() -> None:
    master = Image.open(MASTER)
    assert master.size == (1024, 1024), f"主图尺寸异常：{master.size}"
    contents = json.loads((ICONSET / "Contents.json").read_text())
    done = {}
    for entry in contents["images"]:
        filename = entry["filename"]
        if filename in done:
            continue
        size_pt = float(entry["size"].split("x")[0])
        scale = float(entry["scale"].rstrip("x"))
        px = round(size_pt * scale)
        out = ICONSET / filename
        if px == 1024:
            shutil.copyfile(MASTER, out)
        else:
            master.resize((px, px), Image.LANCZOS).save(out)
        done[filename] = px
        print(f"{filename}: {px}x{px}")
    print(f"共 {len(done)} 个文件")


if __name__ == "__main__":
    main()
