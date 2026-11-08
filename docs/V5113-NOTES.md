# v5.11.3 NOTES — 主 App 图标换新（谱框）

版本 5.11.3 / build 74。基线不变（不带 Share 扩展、CI 预签断言）。
本版只换包主图标＋品牌源留档，其余功能、问账、组件链零改动，页面零改动。

## 定版素材（用户在 Logo 横评线拍板，本版未做任何再设计）

新主图标 = Logo Generator「01-ledger-frame 谱框」：纸白 #F7F5F0 满幅、
墨框＋左侧装订线＋右下朱砂落款点。旧主图标（M2 礼结）退役。

留档（随本版入库）：
- `docs/brand/liji-appicon-1024.png` — 1024 主图（生成全套尺寸的唯一输入）
- `docs/brand/liji-appicon-1024.svg` — 带纸白底的图标矢量源
- `docs/brand/liji-mark.svg` — 裸标志（透明底）矢量源

## 接线方式（现行工程）

主图标走资源目录：`App/Resources/Assets.xcassets/AppIcon.appiconset`，
Info.plist 的 `CFBundlePrimaryIcon` 以名 "AppIcon" 引用（Project.swift），
`Contents.json` 是经典全尺寸声明（非单一 1024）。本次不改接线、不改
Contents.json，只按其现有声明替换全部 PNG。

生成脚本：`scripts/make_primary_icon.py`（本版新增）——读 Contents.json
逐项算像素尺寸，从 docs/brand 主图以 LANCZOS 等比缩放；1024 槽位字节
复制主图、不重编码。

## 全套尺寸清单（15 个文件，覆盖 Contents.json 全部 19 个槽位）

| 文件 | 像素 |
|---|---|
| Icon-App-1024x1024@1x.png | 1024×1024（与留档主图字节一致） |
| Icon-App-20x20@1x.png | 20×20 |
| Icon-App-20x20@2x.png | 40×40 |
| Icon-App-20x20@3x.png | 60×60 |
| Icon-App-29x29@1x.png | 29×29 |
| Icon-App-29x29@2x.png | 58×58 |
| Icon-App-29x29@3x.png | 87×87 |
| Icon-App-40x40@1x.png | 40×40 |
| Icon-App-40x40@2x.png | 80×80 |
| Icon-App-40x40@3x.png | 120×120 |
| Icon-App-60x60@2x.png | 120×120 |
| Icon-App-60x60@3x.png | 180×180 |
| Icon-App-76x76@1x.png | 76×76 |
| Icon-App-76x76@2x.png | 152×152 |
| Icon-App-83.5x83.5@2x.png | 167×167 |

（iphone/ipad 同尺寸槽位共用同名文件，故 19 槽位 = 15 文件。）

## 内页引用排查（本版只列位置、不动页面，等用户拍板）

1. **直接引用主图标资产：无。** 全仓 Swift 无 `Image("AppIcon")` /
   `UIImage(named: "AppIcon")`；我的页「关于礼记」只有动态版本号文字，
   无图标图；首开三页只有 SF Symbol。
2. **锁定页品牌块**（Sources/LiqianApp/AppLock.swift `coverMark`）：
   代码绘制的朱砂封面块＋竖排「礼簿」字，不用图标资产、也不是礼结图，
   与本次换图无冲突，不用动。
3. **启动屏仍是旧礼结**：`LaunchImage.imageset`（纸白底朱砂礼结，
   UILaunchScreen 在 Project.swift 以 UIImageName 引用）是独立资产、
   不是主图标资产，但冷启动时用户仍会看到已退役的礼结。要不要换成
   新谱框裸标志（docs/brand/liji-mark.svg），等用户拍板。
4. **外观页图标网格缩略图与实际不符**：AppearanceView 的图标网格
   缩略图全部取自 AltIcon-* 文件；其中「朱砂（默认）」一行显示的是
   旧礼结缩略图，但点它切回的桌面主图标已是新谱框图。

## ⚠️ 已知不一致（留用户决定，本版原样保留）

- v5.9 的 9 款换色礼结备用图标（AltIcon-night/tencentBlue/graphite/
  amber/jdRed/appleBlue/black/brightYellow ＋primary 缩略图，共 18 个
  PNG）与「图标跟随主题」机制**原样保留、零改动**：主图标已换谱框，
  备用仍是礼结，用户从外观页切到任意备用款，桌面会变回礼结造型。
- **脚本隐患**：`scripts/make_alt_icons.py` 以 appiconset 的 1024 主图
  为输入、按礼结几何（底色→礼结色投影）换色。主图现已换谱框，
  **今后切勿重跑该脚本**，会把备用图标算坏。本版未重跑，AltIcon
  文件经 git 核验零改动。

## 验收（回填）

- CI：（待回填）
- 单测：（待回填）
- 解包验：（待回填）

## 真机未验（待用户验）

- 桌面与设置里主图标换成新谱框图；
- 外观页备用图标仍可选旧礼结各色款（上述已知不一致）；
- 冷启动屏仍闪旧礼结（上述排查 3，未处理）。
