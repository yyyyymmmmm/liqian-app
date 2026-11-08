# v5.11.4 NOTES — 图标体系收口（启动屏换新＋备用图标整体取消）

版本 5.11.4 / build 75。基线不变（不带 Share 扩展、CI 预签断言）。
本版三件事：启动图换谱框、备用图标整个取消、升级迁移兜底。
主图标谱框资产一像素未动；主题系统（含第六主题自定义色）、问账、
组件链、语音零改动；AnalyzerFeeder 零改动（diff 名单实查不在内）。

## 1. 启动屏换新：旧礼结 → 谱框裸标志

接线不变：Project.swift 的 UILaunchScreen 仍为
UIColorName=LaunchBackground ＋ UIImageName=LaunchImage，
LaunchBackground.colorset 未动，只换 imageset 里的三张图本体。

生产脚本：`scripts/make_launch_image.py`（本版新增）——以 cairosvg
渲染 `docs/brand/liji-mark.svg`（谱框裸标志：墨框 #262626＋左侧
装订线＋右下朱砂落款点 #A62B1F，几何以 SVG 为单一事实源，不重绘），
合成到纸白画布。口径：

- **底色 #FAF9F6**：与旧启动图实测底色及 LaunchBackground colorset
  同值，换图后图与背景仍无缝。主图标的 #F7F5F0 是图标成品口径，
  启动屏这块是 App 纸白，不混用。
- **视觉分量与旧图一致**：标志外框高度占画布 80.6%——与退役礼结在
  旧 @3x 图中的实测高度占比（319/396）相同；标志在 viewBox 中的
  外框为 x 21..79、y 15..85（高 70、中心恰为 (50,50)），整幅等比
  缩放居中粘贴，生成后实测三档均精确居中（@3x 中心 197.5,197.5）。
- **三档尺寸同旧规格**：132/264/396 px（132pt 的 1x/2x/3x），
  RGB PNG（同旧图，无 alpha）；4 倍超采样渲染后 LANCZOS 缩回抗锯齿。
- 生成后目检 @3x 成品：墨框＋装订线＋朱砂点无误。

## 2. 备用图标整个取消（用户拍板，不保留任何一款）

删除清单：

| 类别 | 内容 |
|---|---|
| 资产 | `App/Resources/AltIcon-*.png` 全部 18 个（9 款变体 ×@2x/@3x，含 primary 缩略图一对） |
| 生成脚本 | `scripts/make_alt_icons.py` |
| 切换封装 | `Sources/LiqianApp/AppIconManager.swift` 整文件（AppIconVariant 枚举＋AppIconManager） |
| plist 声明 | Project.swift 的 `CFBundleAlternateIcons`（8 键）及旧注释；CFBundleIcons 只剩主图标条目 |
| 外观页 | `iconSection` 整段（图标选择网格＋「图标跟随主题」Toggle）、`iconThumbnail`、`isActiveIcon`、`pickIcon`、`activeIconName` 状态、`@AppStorage iconFollowsTheme`；`selectTheme`/`commitBase` 内的跟随联动调用；连带文案一处（「色点与图标仍是你选的原色」→「色点仍是你选的原色」） |
| Core | `CustomTheme.nearestHex`——注释自明「图标联动用」，唯一调用方就是已删的 `AppIconVariant.variant(for:)`，随联动一并删除；自定义主题的令牌派生/对比度校正/黛青撞色逻辑一字未动 |
| 脚本注释 | `make_primary_icon.py` 中指向已删脚本的旧提示已改写 |

自定义主题（第六主题、换色派生本身）**不动**，只摘图标联动。

**「朱砂（默认）」缩略图图实不符**（v5.11.3 排查 4）：该缩略图取自
AltIcon-primary 文件、点选切回的却是新谱框主图标——图标网格已随
本版整段删除，此不一致随之消解，不再单独修。

## 3. 升级迁移兜底

落点：`Sources/LiqianApp/IconCleanup.swift` 的 `IconCleanup.run()`，
由 `LiqianAppDelegate.application(_:didFinishLaunchingWithOptions:)`
在启动最先调用（先于快捷菜单承接）：

- `UIApplication.shared.alternateIconName` 非空 →
  `setAlternateIconName(nil)` 复位主图标（completion 传 nil，
  沿用本项目「不给框架留回调」的既定口径）；
- 清除已下线的偏好键 `iconFollowsTheme`（standard defaults）。

幂等：复位后 alternateIconName 恒为 nil、键恒不存在，之后每次启动
只是两次空转检查。刻意不看 `supportsAlternateIcons`：声明删除后
该值可能为 false，但传 nil 复位在任何状态下都是合法调用，必须执行。

## 4. 测试增减明细

- **删除 1 个**：`CustomThemeTests.testNearestHexPicksClosestVariant`
  ——测的正是已删的 `CustomTheme.nearestHex`（图标联动就近匹配），
  随功能删除同步删除。
- 新增 0 个：迁移逻辑在 App target 的 UIKit 启动路径，LiqianCoreTests
  的覆盖面（LiqianCore）内无对应可测纯函数，不为凑数硬造。
- **总数 301 → 300**，CI 实测 0 失败（见下）。

## 验收（实测回填）

- CI：run 42530112696（workflow_dispatch @ feat/v5114-icon-cleanup），
  attempt 1 经 API 逐 attempt 实查 completed/success，job build-native
  全部步骤 success（无一失败/跳过异常）；日志实查「** BUILD
  SUCCEEDED **」「presign assertions passed (2 binaries)」。
- 单测：日志总计行「Executed 300 tests, with 0 failures」＋
  「** TEST SUCCEEDED **」（301 − 本版删除 1，与预期一致）。
- 解包验（IPA 4,081,358 字节）：App 与 Widget 的 Info.plist 均为
  5.11.4/75；App 的 CFBundleIcons 只剩 CFBundlePrimaryIcon，
  无 CFBundleAlternateIcons 键；全包 AltIcon 文件 0 个；
  PlugIns 仅 LiqianWidget.appex，无 LiqianShare.appex；
  Assets.car 内 LaunchImage 渲染条目在册（字符串命中 4 处）、
  无 alticon 字样。
- 主图标未动实证：包内 AppIcon60x60@2x 与 AppIcon76x76@2x~ipad
  经 CgBI 解码后——与 v5.11.3 包内同名文件逐像素比对 max diff = 0；
  与本仓 appiconset 生成图逐像素比对 max diff = 0。

## 真机未验（待用户验）

- 冷启动屏图形已换成新谱框（不再闪旧礼结）；
- 外观页已无「App 图标」区与「图标跟随主题」开关，主题与自定义色照旧；
- 若此前在旧版选过某款备用图标，升级后首次启动桌面自动回主图标
  （复位时系统可能弹一次图标变更提示，属系统行为、仅此一次）。
