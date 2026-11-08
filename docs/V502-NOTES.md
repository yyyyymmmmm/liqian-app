# v5.0.2 交付说明：金额记账软件式表达（符号＋语义双色）

分支 `feat/v502-money-color`（基线 feat/v501-settings-ia），版本 5.0.2/52。
动因：用户 2026-11-08 原话——随礼收礼参考记账软件的 `+`/`−`，数字用
不同强调色；现版色调太接近、分不清。本版按用户新口径改版，取代旧
纪律「金额一律墨色、收送靠符号与小色点区分」（DESIGN.md 已同步改版
并注明日期）。

## 定版实现

### 1. Core 格式化单点（LiqianCore/LedgerMath）

- `signedMoney(cents:direction:)`：收礼 `+¥N`、随礼 `−¥N`（数学减号
  U+2212），千分位/非整两位与 fmtMoney 同口径；零金额中性 `¥0`。
- `signedMoneyAccessibility(cents:direction:)`：VoiceOver 读法
  「收 500 元」/「送 500 元」（方向词＋无符号读数），零金额也带方向。
- 新增单测 2 组（LedgerMathTests.testSignedMoney /
  testSignedMoneyAccessibility）：正负号、千分位、非整金额、零中性、
  读法。单测总数 158 → 160（以 CI 实测为准，见文末验收）。

### 2. 语义色令牌（Palette 主题令牌表＋DesignTokens.MoneyTone）

- 收色 `Palette.moneyReceived` ＝当前主题强调令牌（暖，随五主题走）。
- 送色「黛青」`Palette.moneyGiven`：主题令牌表新增 `moneyGiven` 字段，
  浅色四主题（白天/腾讯蓝/石墨/黄色）共用 `#14665A`，夜晚 `#4FB3A6`。
- 白事变体（降饱和，不入主题表、随深浅外观 dyn）：
  `moneyReceivedBai` 浅 `#8C4A3E` / 深 `#C08D81`；
  `moneyGivenBai` 浅 `#4C6D66` / 深 `#87A29B`。
- 解析收敛在 `MoneyTone`（方向×白事→颜色、零金额回墨）；组件
  `SignedMoneyText`（LiqianDesign/Components）是逐笔金额唯一呈现点：
  文本 signedMoney＋色 MoneyTone＋字阶 liqianMoney（暗色降字重）＋
  无障碍读法。各页禁止再自拼符号/自选金额色。

### 3. 对比度实测（WCAG 公式脚本实算；金额文字对 pageBG / surface）

| 令牌 | 白天 | 夜晚 | 腾讯蓝 | 石墨 | 黄色 |
|---|---|---|---|---|---|
| 收色（主题强调，既有值复核） | 6.68 / 7.03 | 5.45 / 4.88 | 5.89 / 6.54 | 6.45 / 7.10 | 4.71 / 4.92 |
| 送色 黛青（本版新增） | 6.48 / 6.82 | 7.36 / 6.60 | 6.15 / 6.82 | 6.20 / 6.82 | 6.53 / 6.82 |
| 白事收 降饱和（本版新增） | 6.31 / 6.64 | 6.51 / 5.83 | 5.98 / 6.64 | 6.03 / 6.64 | 6.35 / 6.64 |
| 白事送 降饱和（本版新增） | 5.41 / 5.70 | 6.78 / 6.07 | 5.13 / 5.70 | 5.18 / 5.70 | 5.45 / 5.70 |

- 全部 ≥4.5:1。本版新增色最低格 5.13（白事送浅值对腾讯蓝 pageBG）。
- 选色淘汰记录：`#0F766E`（Tailwind teal-700）最差 4.93、余量太薄，
  弃用，改 `#14665A`（最差 6.15）；白事送候选 `#557671` 仅 4.49
  不达标，弃用，改 `#4C6D66`。
- 收色沿用主题强调既有值（纪律定版：收＝主题强调令牌），其中夜晚
  surface 4.88、黄 pageBG 4.71 为全表最低两格、仍达标，本版未动主题
  强调值（动它会牵连全 App 强调面，不在本版范围）。

## 覆盖面清单（逐笔金额 → SignedMoneyText）

| 面 | 落点 | 备注 |
|---|---|---|
| 礼簿详情流水 | LedgerDetailView.recordRow | bai 按本簿 isBai |
| 人物详情收支流水 | PersonDetailView.timelineRow | 旧自拼 `+`/`-`（连字符）已收敛进组件 |
| 首页最近动态 | HomeView.recentCard | bai 按所属簿查 |
| 往来页备礼行 | PeopleView.prepRow | 待送出逐笔，方向随礼 → −黛青 |
| 备礼清单页行 | PeopleView.PrepListView.row | 同上；本页新增 ledgers 查询判白事 |
| 图表·点选读数行 | ChartsView 趋势卡读数行 | 收着 moneyReceived、送着 moneyGiven（原两数同为次色）；净保持墨 |
| 图表·选中月逐笔明细 | ChartsView 明细行 | 顺带统一（同卡逐笔呈现，避免同屏两套口径），字阶 .body |
| 图表·收/送系列色 | ChartsView givenColor | 石墨灰 42% → Palette.moneyGiven；趋势双柱、净额负柱、事由成对条、红事随礼、两处图例点全量跟随 |

## 边界执行（按定版，未过火）

- 汇总不着双色：总览 KPI、礼簿封面小计（LedgerCoverCard）、礼簿详情
  头部统计、人物头部合计与结论、首页待回卡与本月卡、往来人物行状态
  （待回/多随）、图表按年汇总行/年度总表/事由·人物聚合行——全部保持
  原墨/次色口径未动。图表内「点选读数行」按任务点名着双色，它是
  选中月的读数而非逐笔，这一条与汇总边界的取舍在此明示：只染趋势卡
  读数行一处，其余聚合读数行（按年/年度总表）未染。
- 礼谱 PDF 与全部导出（GiftBookPDF/Print/FamilyAlbum/ElectronicLibu）
  一行未动，PDF 内无彩色金额。
- 双色只染金额数字本身：背景/图标/按钮/方向签未动，底色仍中性。
- 白事：白事簿内逐笔走降饱和变体（组件 bai 参数）；图表红白卡的白事
  系列维持 v4.7 素蓝单色口径（baiPrimary＋透明阶），未套双色——那是
  「红白分开」的类别编码、不是收/送编码，留账待用户点名再议。

## 未覆盖留账

- 最近删除（TrashView）记录行：逐笔性质，但属恢复管理面，本版未动，
  仍 fmtMoney＋墨色；如需统一，一行换组件即可。
- LedgersView（v4.7 起无入口保留页）内的最近记录行：同上未动。
- 现场模式（SceneModeView）：全为本场总额/对账汇总口径，属汇总不染。
- 人情总览（StatsView）、年度报告、交接单、管家答复文本：聚合数与
  生成文本，非逐笔行，未动。
- 小组件：显示待回计数/总额（汇总），未动。

## 验收（实测）

- CI：run 42442084478 **success**（Build / Unit tests / 预签断言 /
  打包全绿）。
- 单测：**160 个、0 失败**（CI 日志 Executed 160 tests, with 0
  failures；基线 158＋本版新增 2 组，如数）。
- 解包验：App 与 Widget 的 Info.plist 均为 **5.0.2/52**；PlugIns
  只有 LiqianWidget.appex、**无 LiqianShare.appex**；CI 预签断言
  通过；App 二进制 strings 抽查 SignedMoneyText 符号在包内。
- IPA：~/workspace/your_files/liqian-v5.0.2/liqian-native-unsigned.ipa
  （3,568,063 字节）。

## 真机待验（不宣称已验）

1. 浅/深色（夜晚主题）各看一眼：往来列表、礼簿流水、人物流水的
   +朱砂 / −黛青是否一眼分明、黛青在深底是否够亮。
2. 五主题逐个切换：腾讯蓝主题下收色变蓝、送色仍黛青，蓝青相近时
   靠 +/− 符号兜底是否够分清（这是五主题里收/送色相最近的一组，
   重点看这一组）。
3. 白事簿：逐笔金额降饱和后是否够克制、不抢白事的素净。
4. 首页最近动态、备礼清单、图表读数行与选中月明细逐面核对符号与色。
5. VoiceOver：逐笔行读「收 X 元」/「送 X 元」，不读符号。
