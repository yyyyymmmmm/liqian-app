# v5.9 施工片三：#1 自定义主题色 ＋ #2 换图标（feat/v59-appearance）

基线 feat/v581-quick-pack（v5.8.1/67），版本 5.9.0/69。
用户拍板口径：图标独立色＝红两款（朱砂红＋大厂红/京东红 #E1251B）、
蓝、黑、黄；主题预置强调色同理同套色单。

## #1 自定义主题

### 架构落点
- `AppTheme` 加第六位 `.custom`（LiqianDesign/Palette.swift）：五张人工
  令牌表零改动；custom 的整套令牌在查表时由派生引擎实时生成。
  colorScheme 恒浅色（自定义 v1 只做浅色一套，审计边界）。
- 基色存储：UserDefaults 键 `customThemeBaseHex`（hex 字符串），
  没存过回缺省朱砂——初次切到自定义等于从默认现状出发，不跳变。
- ContentView 根身份键在 custom 时拼入基色（`custom-<hex>`）：
  只换基色不换主题也要整树重挂、动态色即时重解析。
- 小组件读不到 App 主题（v5.1 既定边界）、礼谱 PDF/分享图卡永远朱砂
  定版——自定义色同理不进，NOTES 明示不假装支持。

### 派生算法（LiqianCore.CustomTheme，纯函数）
参照 Material 色阶派生思路：不裸用基色，先过护栏再取档。
- pageBG＝白天纸白 #FAF9F7 与基色 5% 混色（极淡染色，守 90% 中性）；
  surface＝纯白；ink/sub/line 复用白天中性阶（审计二选一取前者）。
- primary：基色保持色相/饱和度，只在明度轴处理——对 pageBG 与
  surface 均 ≥4.5:1 则**原样保留**；不达标则二分找最高达标明度
  （对比度对明度单调，48 次二分收敛）。朱砂/腾讯蓝/石墨灰/黑等
  本就达标的基色一分不动（单测钉死）。
- primaryFill＝primary 明度 ×0.85 再压一档（白字对比只增不减，
  另有循环兜底）；primaryTint＝primary 混白 88%。
- UI 诚实提示：基色被护栏调深时（isAdjusted），自定义区明示
  「已自动略调深；色点与图标仍是你选的原色」。

### 金额双色防撞（审计最硬约束）
收＝primary（随主题）、送＝黛青 #14665A（色相 ≈171°）。
规则：基色饱和度 ≥0.20 且与黛青色相夹角 <30°（绿/青系）→ 送色
自动切换备用「黛紫靛」#4F4699（色相 ≈246°，对白对比 ≈7.9:1；
与黛青夹角 ≈75°、与撞色窗右界 202° 亦有 ≈44°，换了不白换），
切换后同样过 ≥4.5:1 校验（ensureContrast 兜底压暗）。
低饱和基色（黑/灰）色相无意义、不触发——靠明度天然可分。
图表收/送系列与金额同源（同走 Palette 令牌），同规则自动生效；
白事双色是固定降饱和变体、不随主题（既有口径，不动）。
实算例：青绿 #1F9E8A（夹角 ≈1°）→ 备用；草绿 #2E9E5B（≈27°）→
备用；蓝 #007AFF（≈40°）、红、紫 → 维持黛青。

### 设置入口（AppearanceView「主题」页）
- 主题列表加「自定义」行（色点＝当前基色原色）。
- 选中自定义后出现「自定义强调色」区：预置色单点阵（朱砂红/
  大厂红/蓝/黑/黄＋夜晚/腾讯蓝/石墨灰/琥珀四个主题同色快捷项；
  白天同色即朱砂红不重复）＋系统 ColorPicker「自选颜色」行。
- ColorPicker 连续拖动只改草稿色（@State），停手 1.2 秒防抖或
  离开页面时才写存储——避免拖动中反复触发整 App 重挂打断取色；
  色单点选是离散动作、点即提交（与切主题同节奏）。

## #2 换图标

### 生产（scripts/make_alt_icons.py，可复现）
仓库无矢量源稿，走审计路线 (b)：对 1024 主图做覆盖率投影换色。
主图实测为纸白底（#FAF9F6）＋单色平涂礼结（#A62B1F，占比 ≈21.5%），
逐像素投影得覆盖率 t（底色 0、礼结 1、抗锯齿边居中；原图生成时的
彩色镶边被吸收为新色的正常边缘），新像素＝底色＋t×(新色−底色)，
白底与构图不动、明暗随 t 保留。primary 同色往返与原图 180 尺寸
平均差 0.155/255，近无损。依赖 Pillow＋numpy，仓库根目录执行：
`python3 scripts/make_alt_icons.py`。

### 变体清单（9 款，礼结色）
| 变体（alternateName） | 色 | 来源 |
|---|---|---|
| 默认（nil，走资源目录主图标） | 朱砂 #A62B1F | 白天主题同色 |
| AltIcon-night | #D96A5C | 夜晚主题同色 |
| AltIcon-tencentBlue | #0052D9 | 腾讯蓝主题同色 |
| AltIcon-graphite | #4E5969 | 灰色主题同色 |
| AltIcon-amber | #A16207 | 黄色主题同色 |
| AltIcon-jdRed | #E1251B | 独立色·大厂红 |
| AltIcon-appleBlue | #007AFF | 独立色·蓝 |
| AltIcon-black | #232323 | 独立色·黑 |
| AltIcon-brightYellow | #E8A20C | 独立色·黄 |

每款 @2x(120)/@3x(180) 两档 PNG 随 App 资源进包根目录；primary 的
同名文件仅作设置页缩略图（不在 plist 声明）。plist 声明写在
Project.swift 的 App target InfoPlist（CFBundleIcons：
CFBundlePrimaryIcon＋CFBundleAlternateIcons 8 键），键名与
AppIconVariant.alternateName 逐项一致。

### 设置与联动（AppearanceView「App 图标」区）
- 网格九款（缩略图＋色名＋当前打勾/描边），点选即经
  AppIconManager.apply 走 setAlternateIconName（completion 传 nil：
  不留框架回调，本项目有回调隔离前科，见 V551-NOTES）。
- 「图标跟随主题」开关（默认关）：开后切预置主题自动换同色图标；
  自定义主题按基色在九款里就近匹配（CustomTheme.nearestHex：
  色相夹角按饱和度加权＋明度/饱和度差）。手动点选图标会把跟随
  自动关掉（明确表态优先，避免下次切主题被覆盖）。
- 文案预期管理（区脚注）：白底不变只换礼结色；切换有系统弹窗；
  自定义色没有一模一样的图标、跟随时取最接近的一款。

## 不许动清单自查
问账全链（管线/提示词/AdvisorSession）、语音链与 AnalyzerFeeder、
金额与待回口径、礼谱生成：本片零改动（git diff 名单可核）。

## 验收（2026-11-08 回填）
- CI：run 42460572108 首跑单测 1 例期望误判挂（nearestHex 青绿
  用例，见下），修期望后 run 42460871464 全绿（构建/SwiftLint/
  单测/预签断言/打包全过）。
- 单测：267 个执行、0 失败（v5.8.1 基线 255＋CustomTheme 12 个）。
  首跑唯一失败＝testNearestHexPicksClosestVariant 的青绿用例：
  评分实算石墨 43 胜苹果蓝 55（无绿/青同色变体时按色相加权＋
  明度/饱和度差就近到石墨），原期望系人工误判，已改期望并加
  鲜艳蓝→苹果蓝用例钉死两种路径，公式未动。
- 解包验：liqian-native-unsigned.ipa 内 App 5.9.0/69、Widget
  5.9.0/69（双字面量实读）；PlugIns 仅 LiqianWidget.appex、
  无 LiqianShare.appex；AltIcon 9 款×@2x/@3x 共 18 个 PNG 全在
  App 包根目录；Info.plist CFBundleIcons 结构实读正确
  （CFBundlePrimaryIcon＋CFBundleAlternateIcons 恰 8 键、
  CFBundleIconFiles 逐项对齐）。
- 真机待验：设置里选自定义色全 App 即时变色、被调深时有提示；
  撞色基色（绿/青）下送礼金额变黛紫；逐款点选图标后桌面图标实际
  变更（系统弹窗为正常行为）；开跟随后切主题图标自动同色；
  小组件维持默认色对（既定边界，非缺陷）。

## 构建号口径
并行热修 v5.8.2（feat/v582-typewriter-fix）已先行交付并占用
构建号 68（5.8.2/68）；本片构建号顺延为 69（5.9.0/69，
短版本不变），避免同构建号双版本并存。合并两支时以
5.8.2/68 → 5.9.0/69 的递增序为准，无需再改。
