# v4.7 交付说明（首页总览台 + 图表补全 + 打磨审计轮）

分支 `feat/v47-home-charts`（自 feat/v46-charts 顶端 c3f5412）：
- 8b30ba9 主体：基线去 Share + Core 聚合 + HomeView + ChartsView 补全
- d6813ab 打磨审计轮（清单 docs/V47-AUDIT.md）
- 本文件所在提交：验收记录

## 〇、基线决定（最重要）：本版不带 Share 扩展

- v4.6 真机裁决：完整包（带 Share）打不开、去分享恢复包可正常使用。
  本版按既定纪律把基线定在**不带 Share**，不等 App IDs 取证回来再赌。
- Project.swift：主 App 的 dependencies 摘掉 `.target(name: "LiqianShare")`
  （留注释）；LiqianShare 的 target 定义、源码、独立 Info.plist（仍
  4.6.0/46）全部保留休眠。
- **恢复方法**（将来根因确认后）：① Project.swift 主 App dependencies
  加回 `.target(name: "LiqianShare")`；② Share 的 Info.plist 字面量同步
  升到当版版本；③ CI 预签无需改动（已改动态遍历，见下）。
- CI 预签步 v4.7 改造：不再写死 appex 名单，改为遍历
  `PlugIns/*.appex` 逐个 ad-hoc 签名；断言集合 = 主 App 二进制 + 每个
  appex 的同名二进制，逐个验 LC_CODE_SIGNATURE 存在、entitlements
  含 application-groups 与组名，主 App 另验 icloud-services。
  以后增删扩展，签名与断言自动跟随。
- 解包验收已断言：**包内 PlugIns 只有 LiqianWidget.appex，
  没有 LiqianShare.appex**。
- 版本：Project.swift 的 MARKETING_VERSION/CURRENT_PROJECT_VERSION 与
  App、Widget 两份 Info.plist 字面量均为 4.7.0 / 47。

## 一、首页重规划：Tab 0 改为总览台 HomeView

新文件 Sources/LiqianApp/HomeView.swift，接替 LedgersView 成为 Tab 0
（ContentView 改一处调用，LedgersView 文件保留、无入口，见 backlog）。
全部数据走既有口径：AppSupport.snapshots 示例隔离、
待回 = LedgerMath 的 max(balance, 0)、fmtMoney 千分位。
自上而下：

1. **重要日子倒计时卡**：数据源与 Widget 完全同源——对
   ReminderDays 现算 nextDate（与 WidgetSummaryWriter.nextReminder
   同一判定：yearly 按今年/明年、once 按原日期，取最近未过者），
   显示名称 + 剩余天数（日历日差）+ 日期；0 天显示「就是今天」；
   无日子时整卡不渲染（不摆空卡）。
2. **待回礼卡**：待回总额 + 待回人数 + 待回降序前 3 人；点人物行
   经 ContentView 既有 personDeepLinkName 通道：先切往来 Tab、
   再由 PeopleView 既有 onChange 打开该人物——绑定由 ContentView
   传入（deepLinkPerson/tabSelection 两个 Binding），未新造通道。
   待回为 0 时显示「暂无待回礼」引导行而非空白。
3. **本月往来卡**：本月收/送/笔数（Calendar 年月键对 date 前缀），
   整卡点击切图表 Tab（tabSelection = 2），带 ScaleOnPress 按压反馈。
4. **快捷动作四枚**（全部接既有实现，逐一核过源码）：
   - 记一笔：RecordFormView，呈现口径与 ContentView 既有
     quickRecord 一致（默认收礼方向、空姓名）；
   - 批量录入：BatchEntryView，目标 = 日期最新非示例礼簿；
   - 拍礼簿：PhotoOCRView（Vision 识别 → OCRConfirmView 待确认流，
     既有入口原样复用，未新写管线），目标礼簿同上；
     无目标礼簿时两钮禁用 + 脚注提示先建礼簿；
     两者完成回执与礼簿详情页同口径（「共记 N 笔」/「共导入 N 笔
     收礼」），只把触发点从详情页扩到首页；
   - 问管家：AdvisorView（ContentView 工具栏既有入口的同一 View）。
5. **最近动态**：跨礼簿最近 8 笔（GiftRecord 按 createdAt 倒序），
   行含人物/方向签/金额/所属礼簿（标题+类型）/日期；点击经本页
   NavigationStack 的 NameRoute 进 PersonDetailView（与往来/图表
   页同一口径）。无记录时整区不渲染。
6. **我的礼簿分区**：礼簿列表能力完整下沉——LedgerCoverCard 行
   （封面/标题/日期场次/笔数/收送合计/白事素蓝）、点进行详情、
   左滑编辑/删除、删簿确认、删除进回收站（TrashStore 归档）、
   右下 FAB 新建礼簿（zoom 转场与旧页一致）、新建/编辑表单共用
   LedgerFormView sheet。
7. **空态**：无真实礼簿（含全新用户只有示例数据时）显示
   ContentUnavailableView（新建第一本礼簿 / 生成示例数据两出路），
   卡片区不渲染；示例生成提示文案已同步新 IA（「首页多了两本
   示例礼簿」，见审计 #9）。

## 二、图表页补全（ChartsView）

区块顺序：总览 → 收送趋势（月图+年汇总）→ **净额趋势** → 关系 →
**事由** → **红白** → 场合（钻取）→ 人物 → **金额段** → 待回 →
**年度总表**。新区块（除年度总表外）全部受范围三档控制，同口径：

1. **净额趋势**：月度净额（收−送）柱（正朱砂/负墨灰，零位基线）+
   累计净额折线，两图上下排（同图双层在负值区可读性差，分开）。
   累计为「窗口内自首月起算」，卡内脚注明示，全史净额看总览卡。
2. **事由分布**：LedgerMath.typeSummary（既有口径，与往来页/
   StatsView 同源）横向成对条：每种事由收（朱砂）/送（墨灰）两条
   + 下方明细行（收/送/笔数）。
3. **红白分开**：新聚合 kindSummary——判定复用 App 既有口径
   （ledgerType == LiqianConstants.baiType，与 Ledger.isBai 同一
   常量，未自创分类）；红事收/送、白事收/送四条成组条图（红事朱砂
   系、白事素蓝系）+ 明细行（收/送/净/笔数/场次，场次按礼簿去重）。
4. **金额段分布**：新聚合 amountBuckets——单笔金额五桶
   （<200 / 200–499 / 500–999 / 1000–1999 / ≥2000 元，分界按下界
   分值），横向条按笔数绘制、行尾标注「N 笔 · ¥X」双口径。
   只统计实际发生的往来（待送出不计，与全局口径一致）。
5. **年度总表**：新聚合 yearlyAggregates，逐年行：收/送/净额/
   笔数/场次 + 净额同比差额（与上一个有数据年份比）。**全范围**
   呈现（用 allSnapshots，不受范围切换影响），卡头注明。
6. **钻取**：场合 Top 明细行 → 对应礼簿 LedgerDetailView；
   关系明细行 → 该关系的人物列表（新私有视图 RelationPeopleList，
   按同口径快照过滤后 LedgerMath.people 聚合，行可再进人物详情）。
   图不再是死图；人物 Top 图条的钻取列入 backlog（审计 #17）。

**聚合下沉 LiqianCore**（LedgerMath.swift）：EntrySnapshot 新增
`ledgerID` 字段（默认 nil，向后兼容；GiftRecord.snapshot 已回填；
此前快照丢礼簿 ID，导致红白/场次类聚合在 App 层无从算起——这是
本版唯一的 Core 数据面改动）；新增 monthlyAggregates（月度收/送/
净额/累计净额）、amountBuckets、kindSummary、yearlyAggregates
四件，全部纯函数、与既有 summary/typeSummary 同源同口径。
**新单测** Tests/LiqianCoreTests/ChartsAggregationTests.swift 8 条：
月度净额与累计、待送出不计入、分桶边界（199.99/200/2000 元）、
红白分类与场次去重、年度同比差额（含跳年）、空集。

## 三、细节打磨审计轮（docs/V47-AUDIT.md）

逐屏走查七个维度（空态/触感/术语/间距/暗色/AI 态/键盘焦点），
共 17 项：**已修 12、backlog 5，如实列账未假装全修**。已修要点：
记一笔「账本」→「礼簿」3 处（每次记账可见，感知最强）、批量录入
焦点链（姓名回车直达金额）、四处触感补齐（问账答案到达/录音起停/
签名保存/分享图生成）、示例提示文案跟上新 IA、图表场合同名礼簿
图文明细对不上（数据正确性）、趋势卡年汇总与年度总表的范围标注、
提醒 chip 间距对齐令牌。Backlog 5 项含 StatsView 与图表 Tab 的
重复 IA（合并属改版式，超本轮边界）、LedgersView 死代码处置、
CSV 表头「账本」（格式契约优先的明确权衡）等，理由逐项写在
AUDIT 文档里。

## 交付验证（在 CI 产物上亲验，非本地构建）

- CI run **42407023147**（workflow_dispatch @ feat/v47-home-charts），
  结论 **success**（亲查 run 状态，非日志节选推断）。
- 单测：日志终行 `Executed 142 tests, with 0 failures` +
  `** TEST SUCCEEDED **`（v4.6 的 134 + 本版新 8 = 142，分毫不差）。
- 下载 artifact 解包亲验：
  - App Info.plist = **4.7.0 / 47**，Widget Info.plist = **4.7.0 / 47**；
  - PlugIns 目录**只有 LiqianWidget.appex，无 LiqianShare.appex**；
  - 本地解析两二进制 Mach-O 的 LC_CODE_SIGNATURE superblob：
    App 与 Widget 均带 ad-hoc 签名，entitlements blob 含
    application-groups 与 group.site.didichou.liqian，App 另含
    icloud-services（Widget 不含，符合其 entitlements 文件）。
- 产物：`~/workspace/your_files/liqian-v4.7/liqian-native-unsigned.ipa`
  （3,173,228 字节）。安装口径不变：SideStore 覆盖安装，数据不动。
- **打开预期（判断，非已验）**：本版包构成与 v4.6 去分享恢复包同
  一形态（同两 target、无 Share），且恢复包已被真机实证可打开，
  本版预期可打开；仍须真机确认，不得视为已验。

## 真机待验清单

1. 完整包 SideStore 覆盖安装后能正常打开（预期依据见上）。
2. 首页：倒计时卡天数与 Widget 显示一致；待回前三人点击落点
   （往来 Tab 对应人物详情）；本月卡点击落图表 Tab；快捷动作
   四入口（记一笔默认态、批量/OCR 目标礼簿是最新非示例簿、
   无礼簿时禁用态与提示、问管家打开）；最近动态点击进对人；
   礼簿行左滑编辑/删除与旧页手感一致。
3. 图表：净额趋势正负柱与折线读数、红白两组数字与礼簿实际对账、
   金额段笔数/金额、年度总表同比差额；钻取三路（场合→礼簿详情、
   关系→人物列表→人物详情、待回→人物详情）落点。
4. 打磨观感：问账答案触感、录音起停触感、签名/分享图保存触感、
   批量录入焦点链手感、首页本月卡按压反馈。
5. 小组件既有待验项沿袭 v4.5 清单（App Group 互通等），本版未动
   Widget 代码与口径。

## 遗留与下一步

- **Share 扩展根因仍未结**：等用户 SideStore → 设置 → App IDs 截图
  （site.didichou.liqian.share 是否注册、额度余量）。恢复方法已写
  在本文第〇节；若额度无问题仍打不开，备选走剪贴板 + 深链承接。
- backlog 5 项见 docs/V47-AUDIT.md，其中 StatsView/图表合并与
  LedgersView 去留建议随下版 IA 一起拍板。
- 上架线不变：等 v5 买断闭环。隐私政策与用户协议已由用户于
  2026-11-08 批准定稿（按 v4.5 所备版本），不再是待定项。
