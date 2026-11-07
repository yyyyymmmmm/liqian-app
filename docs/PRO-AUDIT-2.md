# 礼钱账本 · 第二轮审计（PRO-AUDIT-2）：整机视觉与结构审计＋功能 QA

审计日期：2026-11-07。范围：`Sources/` 全部视图的**视觉系统、页面结构与每个可见控件的真实行为/状态一致性**。
第一轮 PRO-AUDIT 只审代码层（令牌/术语/字阶），其条目本轮不重复；本轮审的是用户装机后真正看到的东西。
本报告只出结论与可落码规格，不改代码。

## 方法与证据（先声明，不凭感觉）

- **审计 skill**：p87 系列（design-review 六维加权评分＋Nielsen、design-qa 逐屏 PASS/WARN/FAIL 门禁、a11y-audit 的 P0 集、critique 的对抗式口径、gate 的「只报实测数字」纪律）＋ local-nielsen-heuristic（十项清单与 4/3/2/1 严重度标尺，含其 accessibility/data-viz 补充模块）。
**如实声明**：p87 套件的配套文件（workflows rubric、tokens、scripts/contrast.py、design-critic.md）未随 skill 文件夹安装（各目录内只有 SKILL.md），其脚本化门禁（accuracy_report、taste_audit）无法运行。本轮按 SKILL.md 正文载明的方法执行：六维权重（视觉层级/一致性/无障碍/可用性各 20%、响应式/性能各 10%）、逐屏门禁、P0 集（对比 4.5:1 正文 / 3:1 大字与组件、触摸目标、读屏名/角色）。对比度数字为对 Palette 实际 hex 值用 WCAG 相对亮度公式逐对实算（脚本计算，非目测），可复算。
- **对标基准**：Apple HIG 与 iOS 系统组件形态（ContentUnavailableView、List insetGrouped、系统字阶、prominent 按钮、系统分组背景）；Nielsen 十项；iOS「设置」与微信/支付宝「我的」页信息架构；微信记账本、随手记的金额字体与明细行形态（形态对照，凭公开常识）。
- **真机证据**：用户 2026-11-07 18:00–18:03 三张截图（我的页顶部、礼簿空状态、我的页下半部）。截图 1 做过像素级行扫描定界（1206×2622，3x），文中 pt 数均为实测换算。
- **代码证据**：全部主要视图通读（MeView/LedgersView/LedgerDetailView/RecordFormView/PeopleView/PersonDetailView/BatchEntryView/StatsView/AnnualReportView/TrashView/AISettingsView/QuickSentenceView/GreetingView/LibuExportView/LedgerFormView/AppLock/ContentView/Components/Palette/SampleData）。

**总判断（critique 口径，不 смяг）**：第一轮把「系统」修到了代码层，用户说「看起来没改」是对的——决定观感的三样东西一轮都没动：暖纸底（像素实测 (249,248,244)，与白卡并置就是一层黄）、衬线金额（每个数字都是宋体系 display 字）、自绘卡片堆（同一个白卡圆角矩形在全 App 重复十几次）。再加上「我的」页存在两个可复现的功能性错误（双 chevron、274pt 无来源空白）和示例数据状态不可信——这一轮的问题清单里，功能项比视觉项更靠前。

---

## 一、截图实证问题清单

严重度沿用 Nielsen 标尺：4 Critical / 3 Major / 2 Minor。类型：功能缺陷 / 视觉问题（功能项在第五部分有完整条目，此处只登记截图可见者）。

| # | 截图位置 | 问题 | 违反的基准 | 严重度 |
|---|---|---|---|---|
| S1 | 截图 3：统计、人情年度报告、最近删除、礼谱落款姓名、AI 智能助手共 5 行 | **每行两个 chevron**：行内一个（卡片右缘内侧）、卡片外一个被屏幕右缘裁切一半 | HIG：List 中 NavigationLink 的披露指示由系统唯一提供；自绘指示与系统指示并存是结构错误（成因见专项诊断二） | 3 |
| S2 | 截图 1：总览卡与待回礼卡之间 | **274pt 纯空白**（像素行扫描：总览卡止于 284pt、待回礼卡始于 558pt，中间无任何像素内容），分组内容被整体推到屏外 | Nielsen #8（信息密度失衡）；design-qa 布局门禁（成因见专项诊断一） | 3 |
| S3 | 截图 3：示例数据行副标题 vs 截图 2：首页「0 本」 | 副标题称「已生成示例数据，点按清除」，同一时段首页 0 本礼簿、总览 0 本 0 笔——**状态呈现互相矛盾**，用户无法信任任何一处（成因见专项诊断三） | Nielsen #1（系统状态可见性） | 3 |
| S4 | 截图 1＋2：全部金额（¥0 ×6） | 金额为衬线粗体 display 字（`liqianMoney` = serif），¥ 符与宋体数字混排，是「AI 中式风」最显眼的载体；大厂记账产品（微信记账本/随手记/支付宝账本）金额一律系统 sans＋等宽数字 | HIG Typography（系统字体层级）；大厂形态对照 | 3 |
| S5 | 截图 1＋2＋3：全页底色 | 暖纸底 #FAF9F6（实测像素 (249,248,244)）罩住每一页，白卡浮在「黄纸」上；与 iOS 系统分组底 #F2F2F7 的中性灰是两种世界 | 基准：背景用系统分组背景（定版见三.1） | 3 |
| S6 | 截图 2：空状态主行动 | 「新建第一本礼簿」是纯文字朱砂按钮，无填充、无按钮形，与同屏右上角系统玻璃 + 钮相比行动层级倒挂；HIG 与 ContentUnavailableView 惯例：空状态主行动用 prominent 样式 | HIG Buttons / ContentUnavailableView 结构（图标/标题/说明/主行动四分工） | 2 |
| S7 | 截图 2：空状态页顶部汇总卡 | 0 数据时仍展示「¥0/¥0/0 本」汇总卡，与下方空状态重复宣告「什么都没有」；空数据应隐藏仪表盘只留空状态（微信记账本空账本即如此） | Nielsen #8；大厂空状态形态对照 | 2 |
| S8 | 截图 1：待回礼空状态 | 「暂无待回礼记录」独占一张完整卡（82pt），且与总览卡同屏第二次呈现全零信息；空待回礼不值得一张卡（定版：降为分组脚注或整组隐藏，见三.3） | Nielsen #8 | 2 |
| S9 | 截图 1：首屏信息架构 | 874pt 首屏只有总览＋待回礼两张卡（外加 274pt 空白），全部功能入口都在屏外；「我的」页把虚荣统计置顶、功能下沉，与 iOS 设置/微信「我的」（入口列表即主体）相反 | 大厂「我的」页 IA 对照；Nielsen #8 | 2 |
| S10 | 截图 3：数据组图标着色 | 5 个导航行图标中，人情年度报告与 AI 智能助手用朱砂、其余用墨色，无规则（MeView.swift 中仅这两行传了 `iconColor: Palette.primary`）；同组图标着色必须单规则 | Nielsen #4（内部一致性） | 2 |
| S11 | 截图 3：分组标题 | 「数据」「AI 智能助手」为自绘 footnote 加粗灰字贴在纸面上，与 iOS insetGrouped 的 Section 头形态（位置、字色、与组卡的粘连关系）不同——组卡是自绘的，组头也是自绘的，整页没有一处是系统件 | HIG Lists（定版见三.3） | 2 |
| S12 | 截图 1＋2：大标题 | 导航大标题本身经代码核查为系统字阶渲染（全仓无一处给 navigationTitle 设衬线，见三.2），此条**不成立**，登记以正视听：用户感知的「衬线大标题」实际来自紧贴标题下方的衬线金额（S4）与卡片衬线标题 | —（澄清项） | — |

另有一项需真机复核（截图无法定性）：截图 3 中玻璃 Tab 栏压住 AI 组卡下缘——全页滚动截图的拼接位移与真机遮挡无法区分；真机滚到「我的」页底，确认「关于」卡末行不被 Tab 栏遮挡（List 在 TabView 下有自动安全区，预期正常）。

---

## 二、专项诊断（三个必查项，全部给代码级结论）

### 诊断一：「我的」页 274pt 空白——不是任何间距常量，是「拿 List 当画布」的结构病

**先排除法**（像素实测＋代码常量对账）：

- 总览卡实测高 106pt、待回礼卡实测高 82pt，与各自内容高度（统计三列＋脚注＋内边距 / 标题＋空文案＋内边距）逐项吻合——**两张卡自身尺寸都是对的**。
- 两行之间的全部代码间距：`asCardRow` 的 listRowInsets 上下各 spacingS=8（MeView.swift:508-515），合计 **16pt**。全仓最大间距令牌 spacingXL=32。**代码里不存在能产生 274pt 的常量**，padding、行高、空状态分支（pendingCard 空分支只是一行 Text，MeView.swift:163-165）全部排除。
- 像素行扫描确认空白区为纯纸色、无卡影无文字——不是「有内容没渲染出来」，是 List 布局本身留出的行间几何。

**结论**：空白由 List 的布局机制产生，根源是这一页的结构反模式——`List(.plain)` 被当作垂直画布：每行塞一张自带背景/描边/圆角的自绘卡（cardSurface），行背景清零（listRowBackground(.clear)）、分隔线全关，再把 NavigationLink 埋进卡里。在这个配置下，List 的行高完全依赖每行异形内容的自适应测量，系统自身的行几何（披露指示、行高估算与复用）与自绘卡的假设处处冲突——**同页的双 chevron 就是系统行几何强行介入的已证实例**（诊断二）。首帧 @Query 数据为空时，各组卡（尤其内含 NavigationLink 的行）高度测量时序最不可靠，空白恰好只出现在首屏前两行之间、下方分组（截图 3 滚动后）间距正常，与这一机制吻合。具体是哪一行的估算高度残留，需真机复现＋视图调试器才能钉死到行——但修法不依赖这一钉：**整页退出「List 画布」模式、改系统 insetGrouped 原生行**（规格见三.3），空白与双 chevron 同根同除。继续在现结构上调 padding 属于无效劳动。

责任代码：MeView.swift:66-87（List 结构）、:508-515（asCardRow）、:546-559（私有 cardSurface，全仓第三份卡面实现）。

### 诊断二：双 chevron——全仓只有「我的」页把 NavigationLink 放进 List，5 行全中

- `entryRow`（MeView.swift:470-505）自带一枚手绘 `chevron.right`（chevron 参数默认 true）。
- SwiftUI 的既定行为：**List 行内的 NavigationLink 会被系统自动附加一枚披露 chevron**，渲染在行（cell）的最右缘。
- 「我的」页的行不是卡片本身，而是被 `asCardRow` 包住的 List 行：行内边距 leading/trailing=16，卡片画在行内容区内。于是手绘 chevron 落在卡片右缘内侧，系统 chevron 落在行右缘——即卡片外、屏幕边缘，被裁切一半。与截图 3 五行的双箭头位置逐行吻合。
- **全仓交叉验证**：`NavigationLink` 在应用代码里只出现在两处——LedgersView（在 ScrollView＋LazyVStack 中，非 List，无系统 chevron，封面卡手绘 chevron 是唯一一枚，正常）与 MeView 的 5 处（MeView.swift:204 统计、:215 人情年度报告、:263 最近删除、:286 礼谱落款姓名、:342 AI 智能助手），与截图中出现双箭头的 5 行**一一对应**；同页 Button/ShareLink/Toggle 行（导出 CSV、导出备份、从备份恢复、示例数据、隐私锁）无此问题（截图 3 亦证实它们无箭头或单箭头都没有）。诊断闭合，无第二种解释。

### 诊断三：示例数据状态——先纠正预设：没有「存储的布尔标记」，但脱钩真实存在且可复现

- **标记的真实存法**：不存在 AppStorage 布尔。`MeView.hasSamples`（MeView.swift:386）每次渲染实时派生：`SampleData.hasSamples(ledgers:)` ＝ 账本数组中是否存在标题以「示例」开头的礼簿（SampleData.swift:12-14）。生成防重、清除范围（clearSamples，SampleData.swift:109-119）也全部靠这个**标题前缀**判定。
- **因此**：「标记存了、删簿后不复位」这一预设不成立——派生式没有可脱钩的存储态；且 MeView 与首页读同一 SwiftData 存储、同一条 @Query，同一时刻两处不可能不一致。
- **截图矛盾的成因链**（与时间戳吻合的唯一链）：18:00 两张截图（首页、我的顶部）均为 0 本 0 笔；18:03 我的页底部显示「已生成」。其间能翻转该副标题的唯一路径是生成动作本身（首页空状态的「生成示例数据」按钮，LedgersView.swift:265-268）。即大概率生成发生在两组截图之间、此后未再拍首页——状态在每个瞬间其实都自洽，**但用户全程没有得到一次明确确认**：从「我的」页入口生成有 alert，从首页/往来页入口生成只有整屏内容切换、无一句话回执；且全 App 没有任何一处持续呈现「示例数据存在中」的稳定指示（首页里示例簿与真实礼簿长得一模一样，只靠标题前缀肉眼分辨）。状态不可确认，等于状态不可信。
- **可稳定复现的真脱钩（本诊断的核心缺陷）**：示例身份＝标题前缀，而标题可自由编辑且无任何拦截（LedgerFormView.swift:95 编辑保存直接写回 title）。复现路径：生成示例 → 在礼簿详情里把「示例·表哥婚礼」改名为「表哥婚礼」→ 该簿从此对 hasSamples/clearSamples 双双隐形：副标题可能仍显示已生成（另一本还在），点「清除」清不掉它；两本都改名后副标题变回「生成两本示例礼簿」，再点生成会投放第二套示例（generate 的防重同样只认前缀，SampleData.swift:18-20），账本里出现四本示例类礼簿，其中两本永远清不掉。
- **连带污染**：所有汇总口径（首页汇总、我的总览、统计、年度报告）不区分示例与真实数据——生成示例后，我的总览立刻变成示例的 ¥7,200 级假数字。对记账产品，「数字可信」是底线，此条与改名脱钩同级处理（功能缺陷 F2/F13）。

定版修法（详见改造清单第 2 项）：示例身份改为生成时记录的账本 ID 集合（UserDefaults 存 [UUID 字符串]），hasSamples＝ID 集合与现存账本求交非空；清除按 ID 删；改名不脱钩；汇总口径默认排除示例账本，或在总览脚注明示「含示例数据」。

---

## 三、视觉系统三根问题的定版改造规格

与第一轮冲突处逐条标注及理由。

### 3.1 背景：paper 暖纸色退役，结构背景全走系统分组背景

**定版**：`Palette.paper`（#FAF9F6 / 深色 #171716）退出全部界面背景。

- 所有页面背景改 `Color(uiColor:.systemGroupedBackground)`（浅 #F2F2F7 / 深 #000000），卡面继续 `secondarySystemGroupedBackground`（现已映射，保持）。实现口径：List/Form 页删 `.scrollContentBackground(.hidden)`＋paper 背景，回归默认渲染；ScrollView 页背景换系统分组底。
- 白事连带：`baiPaper` #ECEEF0 / 深色 #14171A 同为手搓分组底，一并退役换系统分组底；`baiCard` 换 `secondarySystemGroupedBackground`；`baiInk/baiStone/baiLine` 分别映射 label/secondaryLabel/separator（与红事同法）。白事身份只由 `baiPrimary` 一个令牌承载（方向签、链接、按钮）。
- 深色模式连带：paper 深色 #171716（暖黑）随之消失，深色底为系统纯黑＋#1C1C1E 卡面——与 iOS 设置深色形态一致，不再有「暖黑」一说。
- **深色对比修复（与背景定版同批，实算值）**：现深色朱砂 #D96A5C 作填充＋白字 = **3.41:1**（caption2 方向签白字不达 AA 4.5）；深色素灰蓝 #93A1AD 作填充＋白字 = **2.64:1**（第一轮遗留，复算确认）。定版拆分填充令牌：
- 新增 `Palette.primaryFill` = dyn(#A62B1F, #A62B1F)：主按钮、方向签等一切「朱砂底＋白字」填充双模式共用浅色值，白字对比 7.03:1 ✓；`primary` 本体（dyn #A62B1F/#D96A5C）只作文字/图标强调（深色下对纯黑底 6.17:1 ✓）。
- 新增 `Palette.baiPrimaryFill` = dyn(#5B6770, #5F6B76)：白字对比浅 5.80:1 / 深 5.45:1 ✓；`baiPrimary` 本体只作文字/图标强调（深色 #93A1AD 对纯黑底 7.94:1 ✓）。
- 落点：DirectionTag（Components.swift:20）、LedgerCoverCard 小签与详情封面块、glassProminent 的 tint（详情/人物页底部主按钮如无法单独控填充色，则保持 tint=primary 并接受按钮大字 3:1 口径——17pt semibold 属 WCAG 大字，3.41 过大字 AA；签体 caption2 必须走 Fill 令牌，无豁免）。
- 与 PRO-AUDIT §3.3「paper 保留品牌令牌」冲突。理由：真机截图证明 #FAF9F6 的暖意在与白卡并置时清晰可辨（像素实测 (249,248,244)），且它就是用户点名的三根之一；第一轮保留它的论据是「产品的世界」，但世界感应由 moment（封面、印章、礼谱）承载，不由每一页的底色承载——底色是 chrome，chrome 用系统色是第一轮自己定下的结构色原则，paper 是这条原则最后一个例外，本轮收回。

### 3.2 字体：衬线退出全部 chrome，只许活在五个 moment

**定版**：

1. **金额去衬线**：`liqianMoney` 的衬线定义废止，金额改系统 sans：Font.system(语义字阶, weight:.semibold)＋`.monospacedDigit()`，三档沿用.title3/.title2/.largeTitle。落点（全量）：LedgersView 汇总/封面卡/最近往来、MeView 总览/待回礼、LedgerDetailView 统计与记录金额、PeopleView 行金额/备礼清单、PersonDetailView 合计/时间线、StatsView、AnnualReportView 页内统计、TrashView、BatchEntryView 大字金额（34pt 固定保留、字体改 sans semibold）、RecordFormView 金额显示与「¥」符（:331 的 liqianSerif(.title2) 一并改）、Widget 的计数与金额（LiqianWidget 自有字体定义同步）。
与 DESIGN v0.3「金额衬线三档」及第一轮 §4.2 映射冲突。理由：截图中每个 ¥0 都是宋体 display 字，这是「AI 中式风」在数字上的直接来源；HIG 与三家大厂记账产品金额无一用衬线。衬线的礼制感靠下方白名单的 moment 兑现，不靠每天看的金额。
2. **标题去衬线**：导航标题经核查本就是系统渲染（全仓无 navigationTitle 衬线设置），维持并立禁令——任何 liqianSerif 不得用于导航标题与页内标题。页内现存的衬线标题/数字逐处改 sans：AnnualReportView.swift:110 报告标题（.title3 衬线→.headline sans）、:163 与 StatsView.swift:133 排行序号（衬线→.subheadline sans medium、stone 色）、LedgerDetailView.swift:217/:240 统计值（属金额类，随第 1 条）、PersonDetailView.swift:182 合计值（同前）。
3. **衬线白名单（穷尽，此外全禁）**：
- 礼簿封面小签竖排事由字（Components.swift:143，15pt）与往来页搜索结果的迷你签（PeopleView.swift:213，12pt）；
- 印章印面字（Components.swift:199 SealStampView）与落印浮层；
- 锁定页品牌封面块竖排「礼簿」（AppLock.swift:73，24pt）；
- 年度报告**分享图卡**竖排题字与图卡金额（AnnualReportView.swift:326 及 AnnualReportCard 内 liqianMoneyFixed——静态成品，保留）；
- 礼谱 PDF 全部（GiftBookPDF serifFont，静态成品）；
- 改造清单第 6 项恢复的礼簿详情页头部封面满块题字（新 moment，竖排衬线）。
4. 字重纪律随行：页内标题.headline.weight(.bold) 的滥用（待回礼/备礼清单/各卡标题全 bold）在各页改版时顺带收敛为.headline（semibold）或系统 List 的 Section 头，不再逐卡自设标题（见 3.3）。

### 3.3 表面形态：逐页定版（自绘卡片 → 系统 List/组件）

总则：**设置型/列表型页面一律 List(.insetGrouped) 原生 Section 与行；卡片只许出现在仪表盘型页面（首页、报告页），且全 App 只保留一份卡面实现**（Components.liqianCardSurface，MeView 的 cardSurface 与 StatsView 的 statsCardSurface 两份私有副本删除）。空状态全量 ContentUnavailableView（见本节末）。

| 页 | 现状 | 定版 |
|---|---|---|
| 我的 MeView | List(.plain)＋asCardRow 自绘卡＋自绘组头＋私有 cardSurface | **整页重写为 List(.insetGrouped)**：总览＝首个 Section，内容为一行三列统计（HStack 置于原生行内，不套卡）；待回礼＝独立 Section（头「待回礼」），行＝原生 Button 行（人名＋朱砂金额），自动计算说明移入 Section **footer**（这正是 footer 的用途），空时整 Section 不渲染（S8 解决）；五组入口＝原生 Section＋NavigationLink 行，**手绘 chevron 全删**（系统唯一提供，S1 解决），图标着色单规则：全部 stone/ink，朱砂只留 AI 行一处也不留——统一 ink（S10 解决）；隐私锁＝原生 Toggle 行；关于＝Section（版本 LabeledContent 行）＋数据说明移入 footer；删 asCardRow/groupHeader/cardSurface 三件套（S2/S11 解决） |
| 首页 LedgersView | ScrollView＋LazyVStack 自绘卡（汇总卡、待回礼卡、年图卡、最近卡、封面卡） | 结构保留（仪表盘型，类支付宝首页），三项修正：① 0 数据时隐藏汇总卡与全部统计卡、只渲染 ContentUnavailableView（S7）；② 空状态主行动改 prominent 按钮样式（朱砂填充胶囊、白字，S6）；③ 全部卡面改走唯一 liqianCardSurface |
| 礼簿详情 LedgerDetailView | List(.plain)，头部统计自绘卡、记录为卡片行、底部玻璃双钮 | 记录区改 **List(.insetGrouped)** 原生行（人名＋方向签左、金额右，分隔线系统 hairline），swipeActions 保留；头部恢复**封面满块**（56×92，朱砂满底、竖排事由衬线＋印点，与列表小签同源放大版）＋右侧标题/日期，置于首个 Section 内——全 App 唯一满块（改造清单 6）；统计（收礼/随礼/人数）改原生 Section 三列行；删除礼簿＝末尾 Section 的 destructive 按钮行（原生形态）；底部玻璃双钮保留（iOS 26 原生件，本页唯一现代件，合格）；记录副标题的中点拼接串（LedgerDetailView.swift:302-306）随原生行改两行排布（首行人名＋签，次行 关系·方式·日期 用 footnote——注：原生行次行同样是拼接串问题，定版为「关系＋方式」与「日期」分列左右，不再四段一串） |
| 记一笔 RecordFormView | 系统 Form | 结构合格，保留。仅随 3.2 改金额字体、防重复提交（功能项 F3） |
| 往来 PeopleView | List(.plain)＋备礼卡＋人物卡片行 | 人物行改 List(.insetGrouped) 原生行（人名/副行左、差额/待回礼右），备礼清单改独立 Section 原生行；搜索维持系统.searchable（导航栏位）——DESIGN 附录「搜索下沉」是未实现承诺，二选一：本轮定版**删附录该条**，系统位即 HIG 标准位，不为时髦改 |
| 人物详情 PersonDetailView | ScrollView＋结论卡＋建议卡＋时间线卡片行 | 结论卡保留（本页的决策摘要，是有理由的一张卡，改唯一卡面实现）；时间线改**单张分组容器**：一张卡内 hairline 分隔的原生行列（不再每笔一张浮卡）；底部玻璃双钮保留；合计金额随 3.2 改 sans |
| 统计 StatsView | List(.plain)＋asCardRow＋私有 statsCardSurface（与 MeView 同病轻症） | 改 List(.insetGrouped)，四组各为 Section，排行行改原生 Button 行（系统不给 Button 行加 chevron，手绘一枚保留即可——注意与 NavigationLink 行规则区分：Button 行手绘 chevron 是唯一允许的手绘场景）；删私有卡面与 asCardRow |
| 最近删除 TrashView | List(.plain) 裸文字行（全 App 唯一无卡面的列表页，与其余页形态断裂） | 改 List(.insetGrouped) 原生行，与全 App 列表形态归一；恢复入口可见化（功能项 F8） |
| 年度报告 AnnualReportView | ScrollView＋五张卡 | 报告型页面，卡片保留但全改唯一卡面实现；页内标题/金额随 3.2；分享图卡为静态成品不动（衬线保留） |
| 批量补录 BatchEntryView | 系统 Form＋顶部汇总条 | 保留（Form 是系统件）；汇总条口径修功能项 F7 |
| 礼谱导出 LibuExportView | List(.insetGrouped) | **全 App 结构最合格的一页**，作其余页改版的参照，不动 |
| AI 设置/一句话/贺词/落款编辑 | Form / List(.insetGrouped) | 保留，仅背景随 3.1 |
| 锁定页 LockScreenView | 自绘品牌页 | 保留（品牌 moment）；封面块的白色高光渐变（AppLock.swift:66-72）与列表封面为同类拟物残留——DESIGN 例外登记只登记了封面块高光，此处为第二实例：定版**去掉高光**，纯朱砂＋竖排字足够 |

**空状态定版（全量 ContentUnavailableView）**：首页 ✓ 已是、最近删除 ✓ 已是；逐个改：礼簿详情空记录（LedgerDetailView.swift:230-245 自绘 VStack）、往来页空（PeopleView.swift:69-83 自绘 VStack）、年度报告空年（AnnualReportView.swift:70-74 裸 Text）、人物详情空（PersonDetailView.swift:66-70 裸 Text，实际近乎不可达，一并归一）。规格统一：Label（标题＋SF Symbol）/ description（一句人话）/ actions（主行动 prominent、次行动 plain），与首页现行实现同构。

---

## 四、逐屏 design-qa 结论（PASS / WARN / FAIL＋必修项）

门禁口径：FAIL＝存在影响任务正确性或平台规范硬伤的必修项；WARN＝可发布但有明确必修项；PASS＝无必修项（可有建议项）。

| 屏 | 结论 | 必修项（FAIL/WARN 的过门条件） |
|---|---|---|
| 首页（礼簿） | **WARN** | 0 数据隐藏汇总卡（S7）；空状态主行动改 prominent（S6）；卡面收敛唯一实现；金额改 sans（3.2） |
| 礼簿详情 | **WARN** | 封面满块按规格回归头部（第一轮 #6 的落点在此页、现完全缺失——「满块只留详情页」在整改后变成了满块无处存在，moment 被整体删除而非迁移）；记录行中点拼接串改分列（LedgerDetailView.swift:302）；空状态改 ContentUnavailableView |
| 记一笔 | **FAIL** | 保存防重复提交（F3：落印 1.05s 等待期内保存按钮仍可点、重复落库——记账正确性硬伤）；金额字体改 sans |
| 往来 | **WARN** | 空状态改 ContentUnavailableView；人物行/备礼行改 insetGrouped 原生行（3.3） |
| 人物详情 | **WARN** | 金额改 sans；时间线改单卡分组行；同名合并的已知限制在页内无任何提示（F12，至少在改造清单中登记处置） |
| 我的 | **FAIL** | 整页按 3.3 重写（双 chevron S1、274pt 空白 S2、组头/图标着色 S10/S11 同根于此）；示例状态按诊断三修（F2） |
| 批量补录（含大字模式） | **WARN** | 汇总条口径（F7）；大字模式只放大逐行录入模式、粘贴/AI 预览行只放大半行（BatchEntryView.swift:312/:471 的 bigMode 字号只作用于姓名行）——模式一致性必修：大字应作用于三种模式的编辑区与预览区 |
| 锁定页 | **PASS** | （建议项：去高光渐变，见 3.3；解锁失败后按钮文案不变、重试路径明确，无必修） |
| 统计 | **WARN** | 改 insetGrouped、删私有卡面（3.3）；关系分布图对 VoiceOver 无数据等价物（图中数值读屏不可达，补 accessibilityLabel 汇总句或数据列表） |
| 年度报告 | **WARN** | 分享图卡文案与内容对齐（F4）；生成失败反馈（F5） |
| 最近删除 | **WARN** | 恢复入口可见化（F8）；白事签色（F9）；改 insetGrouped（3.3） |

## 五、功能 QA：每个功能是否真的可用、状态是否可信

### 5.1 功能缺陷清单（与视觉问题分开列；严重度同前标尺）

| # | 功能 | 缺陷 | 代码证据 | 严重度 |
|---|---|---|---|---|
| F1 | 我的页导航行 | 双 chevron（系统指示＋手绘指示并存、系统一枚被裁切） | 诊断二（MeView.swift:204/215/263/286/342＋entryRow :488） | 3 |
| F2 | 示例数据 | 身份靠标题前缀识别：改名即脱钩——清除漏清、生成重复投放；且生成无统一回执、状态无稳定呈现点 | 诊断三（SampleData.swift:12-20、:109-119；LedgerFormView.swift:95；LedgersView.swift:265-268） | 3 |
| F3 | 记一笔保存 | 落印动画 1.05s 延迟关闭期间表单仍可交互、无防重入：连点「保存」重复落库 | RecordFormView.swift save()（insert 在前、Task.sleep 1050ms 后 dismiss，期间无 isSaving 守卫、按钮不禁用） | 3 |
| F4 | 年度报告分享 | 文案承诺与实现不符：入口与页内两处称「仅含汇总数据，不含个人明细」，图卡实际含往来第一位亲友的**姓名＋其往来总额** | MeView.swift:229 副标题；AnnualReportView.swift:238 页内文案 vs :271-285 makeShareImage 传 topName/topTotalCents、图卡 :313 渲染 | 3 |
| F5 | 分享图生成 | ImageRenderer 返回 nil 时静默无反馈：「分享这张图」不出现，用户以为按钮坏了 | AnnualReportView.swift:262-268（无 else 分支） | 2 |
| F6 | AI 设置状态 | ① 删除 API Key 后「启用 AI 功能」开关仍显示开（readiness 因无 Key 实际为不可用，开关与真实状态两张皮）② 保存 Key 只落钥匙串、无任何有效性校验，「已保存（尾号）」不等于可用，用户要到解析失败时才知道 Key 是错的 | AISettingsView.swift:41-49（删除分支不触 aiEnabled）、:79-87（saveKey 无校验调用） | 2 |
| F7 | 批量汇总条 | 「合计」把收礼＋随礼＋待送出全混算（与全 App「待送出不计入」口径相悖）；「最近：X」取无序 @Query 的 last，不保证是最近一笔 | BatchEntryView.swift:182-187（reduce 全量、mine.last）；:60 @Query 无 sort | 2 |
| F8 | 最近删除恢复 | 恢复/彻底删除仅左滑手势，行不可点、页内零说明——目标用户（中老年）大概率找不到恢复入口，「30 天内可恢复」的承诺在 UI 上不可达 | TrashView.swift:22-44（仅 swipeActions） | 3（对目标人群） |
| F9 | 最近删除行 | 记录行方向签写死 bai:false：白事礼簿的记录进最近删除后，收礼签显示朱砂而非素灰蓝 | TrashView.swift:101 | 2 |
| F10 | 小组件/快捷指令 | ① 0 本礼簿或隐私锁锁定中点击小组件：深链被 guard 静默吞掉，进 App 后毫无反应 ② 快捷指令标记只在 scenePhase 变 .active 与冷启动 .task 时消费，App 已在前台时运行快捷指令不立即弹表单 | ContentView.swift:117-122（presentQuickRecord 两个 guard 均 return 无反馈）、:82-104（消费点） | 2 |
| F11 | 记一笔（无礼簿路径） | 人物入口且无任何礼簿时，保存只震一下（errorTrigger）无文字原因——该路径实际近乎不可达（有人物必有账本），登记备查 | RecordFormView.swift:479-484 guard else 仅 errorTrigger | 2 |
| F12 | 人物聚合（已知限制） | 人物按**姓名**聚合：同名不同人（两个「王建国」）被合并为一人，差额/待回礼随之失真。属产品既定口径（Flutter 版沿用），但全 App 无任何提示，数据可信度边界应明示并登记为已知限制 | PersonDetailView.swift:33（person == name）；LedgerMath.people 按 name 分组 | 3（同名时） |
| F13 | 全部汇总口径 | 示例数据计入首页汇总、我的总览、统计与年度报告：生成示例后各处「累计」立刻是假数字，且无任何「含示例」标注 | MeView.swift:37-51、LedgersView.swift:20-30 均全量聚合； SampleData 与统计层无隔离 | 3 |
| F14 | 导出 CSV 行 | csvURL 生成前该行为 ShareLink 缺位＋0.5 透明度的静默禁用，无「正在生成」任何说明（通常瞬间完成，低频触发） | MeView.swift:330-352 | 2 |
| F15 | AI 引导 | 四处「AI 还没准备好」alert 只有「好」一个按钮，不给去设置的路径，用户被告知去「我的 → AI 智能助手」却要在 alert 关闭后自己找 | RecordFormView.swift:403、BatchEntryView.swift:170、GreetingView.swift:123、QuickSentenceView.swift:103 的 alert 形态一致 | 2 |

**复核通过、明确可用的功能**（逐项验过行为与状态来源，不是抽查）：新建/编辑礼簿（必填校验就地红字、自定义事由回退逻辑完整）；记一笔主流程（键盘合法性约束、人物联想、同名并列提示、保存并继续、落印反馈）；批量逐行录入（行级定位报错、空行跳过）；粘贴导入（失败行留在编辑器、部分成功当面说清——全 App 错误处理范式）；AI 解析预览（given 行拦截、uncertain 行明示、原始返回可查）；导出备份/覆盖恢复（计数对照的二次确认、Flutter 互通 id 映射）；CSV 导出（指纹变化自动重生成）；礼谱导出 sheet（落款回写、AI 谱序回退模板且明示、失败有文案）；贺词（复制反馈、候选清洗）；隐私锁（防叠弹、30 秒规则、无凭据设备不锁死）；待回礼自动规则（三处呈现口径一致：首页/我的/人物页同源 LedgerMath.people）；小组件数据写入（回前台刷新 App Group 汇总）。

### 5.2 逐功能可用性矩阵（回答「其他功能呢」）

| 功能 | 可用？ | 状态可信？ | 备注 |
|---|---|---|---|
| 新建礼簿 / 记一笔 / 编辑 | ✅ | ✅ | 除 F3 防重入、F11 边角路径 |
| 批量补录（逐行/粘贴/AI） | ✅ | ⚠️ | F7 汇总条口径 |
| 待回礼 / 备礼清单 | ✅ | ✅ | 三处同源同口径，本轮复核最扎实的一块 |
| 往来 / 人物详情 / 回礼参考 | ✅ | ⚠️ | F12 同名合并已知限制 |
| 统计 / 年度报告 | ✅ | ⚠️ | F4 分享承诺、F5 静默失败、F13 示例污染 |
| 导出礼谱（PDF） | ✅ | ✅ | 回退路径明示，结构最合格 |
| 备份 / 恢复 / CSV | ✅ | ✅ | F14 仅呈现小瑕 |
| 最近删除 | ✅ | ⚠️ | F8 入口不可见、F9 白事签色 |
| 示例数据 | ⚠️ | ❌ | F2 身份脱钩＋F13 污染统计——本轮唯一「状态不可信」评级 |
| AI（一句话/解析/贺词） | ✅ | ⚠️ | F6 开关两张皮＋Key 未校验、F15 引导死胡同 |
| 隐私锁 | ✅ | ✅ | 规则与实现一致 |
| 小组件 / 快捷指令 | ⚠️ | ⚠️ | F10 静默吞深链与前台消费时机 |

## 六、Nielsen 十项评分（核心流程：新建礼簿 → 记一笔 → 导出礼谱 → 回礼）

评分：Critical / Major / Minor / Good（方括号内为 Nielsen 编号）。

| # | 启发式 | 评级 | 发现 |
|---|---|---|---|
| 1 | 系统状态可见性 | **Major** | 反例集中在「静默」：CSV 行静默半透明（F14）、分享图静默失败（F5）、小组件深链静默吞（F10）、示例生成无统一回执（F2）；正例：批量实时汇总条、解析进度、生成中状态都在线 |
| 2 | 系统与现实匹配 | **Minor** | 礼簿/待回礼/备礼清单/落款等领域词经第一轮定版后贴合用户心智；残留口语报错三处：「姓名还没填」（RecordFormView.swift:477）、「先给礼簿起个名」（LedgerFormView.swift:88）、「礼谱没能生成出来，再试一次」（LibuExportView.swift:130）、批量页「AI 拿不准」（BatchEntryView.swift:434）——均属第一轮审校表外遗留 |
| 3 | 用户控制与自由 | **Major** | 记一笔保存窗口期不可控（F3）；覆盖恢复有确认但恢复后无回退（可接受，已确认）；批量逐行录入误点「取消」丢弃已填行、无确认（低频，Minor 级，合并记此） |
| 4 | 一致性与标准 | **Major** | 平台标准违反一处成例：双 chevron（F1）；内部不一致成组：卡面实现三份、空状态实现四种、List 风格两种（plain/insetGrouped）、图标着色双规则（S10）、衬线/无衬线角色混乱（3.2）。任务仍可完成，故不评 Critical |
| 5 | 错误预防 | **Major** | 正例强：金额键盘约束、AI 结果永不自动落库、覆盖恢复二次确认、同名并列预提示；反例决定评级：F3 重复落库、F2 示例身份可改名绕过——都是「防线建在可变数据上」 |
| 6 | 识别优于回忆 | **Major** | 最近删除恢复全靠手势记忆（F8）；示例状态要靠用户自己跨 Tab 对账（F2）；正例：人物联想、备礼清单、待回礼解释脚注都是识别式设计 |
| 7 | 灵活与效率 | **Good** | 保存并继续、批量三模式、快捷指令＋小组件直达、人物联想带入关系——加速器齐全且不打扰新手；唯一减项：AI 引导 alert 死胡同（F15） |
| 8 | 美学与极简 | **Major** | 三根问题（S4/S5/卡片堆）＋统计三处重复呈现（首页汇总、我的总览、统计页年度卡同一组数字出现三次）＋我的页首屏 274pt 空白与功能下沉并存（S2/S9） |
| 9 | 错误识别与恢复 | **Minor** | 批量/AI 的行级报错＋定版句族是全 App 范式级表现；减项全在静默型失败（F5/F11/F14）——错误处理两极分化：有文案的地方很好，没文案的地方假装没发生 |
| 10 | 帮助与文档 | **Minor** | 待回礼规则在三处都有就地说明，好；减项：恢复手势无说明（F8）、小组件/快捷指令无任何设置引导、Key 无有效性反馈（F6） |

**总计**：Critical 0 · Major 6（#1、#3、#4、#5、#6、#8）· Minor 3（#2、#9、#10）· Good 1（#7）。以流程可完成为界：没有 Critical，但 Major 密度说明这不是「再润色一轮」能解决的，必须按第八部分的结构项先行。

## 七、design-review 六维评分（加权）

| 维度 | 权重 | 分（/5） | 依据（一句） |
|---|---|---|---|
| 视觉层级 | 20% | 2 | 衬线金额＋卡片等权重复使一切都像标题，最重要的待回礼与虚荣总览同权呈现 |
| 一致性 | 20% | 2 | 三份卡面、四种空状态、两种 List、双 chevron——系统只剩令牌层还一致 |
| 无障碍 | 20% | 2 | 加分：Dynamic Type 已生效、44pt 目标成规、落印 Reduce Motion 降级；扣分：深色填充对比 3.41/2.64 两处 AA 失败（实算）、图表无读屏等价物、VoiceOver 标签仍稀疏 |
| 可用性 | 20% | 3 | 核心四流程全通、错误处理范式强；被 F1/F2/F3/F8 拉低 |
| 响应式 | 10% | 3 | Dynamic Type 大字号布局风险点第一轮已登记三处，未真机验证前不给更高（需真机复核项） |
| 性能 | 10% | 4 | 全量 @Query＋内存聚合在当前数据量级无压力；无卡顿证据 |
| **加权总分** | | **2.5 / 5** | 与第一轮 CLEAR 2.4 互为印证：代码层修完之后，整机分仍在 2.5——因为决定分数的结构层本轮才被审到 |

---

## 八、改造清单（按用户感知排序，直接作为下一轮实现依据）

规格粒度：组件名＋关键数值＋落点文件。顺序＝用户打开 App 的感知顺序：先「我的」页（错误最扎眼）、再状态可信、再三根视觉、最后一致性收尾。

| # | 改造项 | 规格 | 落点 | 风险 |
|---|---|---|---|---|
| 1 | **「我的」页整页重写** | 按 3.3 定版：List(.insetGrouped)；Section 序＝总览（单行三列统计）→待回礼（有数据才渲染，说明入 footer）→统计与报告→数据→AI 智能助手→隐私与安全→关于（版本 LabeledContent＋说明入 footer）；NavigationLink 行删 entryRow 手绘 chevron；图标统一 ink 色、frame 24；删 MeView 私有 asCardRow/groupHeader/cardSurface | MeView.swift 整文件重写（约 550 行）；HostNameEditView 不动 | 中：CSV/备份/恢复/示例/AI 五组行为逻辑平移勿改语义；重写后逐行对行为清单回归（5.1 复核通过项） |
| 2 | **示例数据可信化** | 身份改 ID 集合：`SampleData.generate` 返回两本 ID → 存 UserDefaults 键 `sampleLedgerIDs: [String]`；hasSamples＝集合 ∩ 现存账本 ID 非空（MeView.swift:386 改读此口径）；clear 按 ID 删簿及记录（不再按标题前缀）；generate 防重同口径；首页空状态与往来页空状态的生成按钮在成功后给 alert 回执（文案与 MeView 入口统一：「示例数据已生成」＋说明句）；**统计隔离**：MeView 总览、LedgersView 汇总、StatsView、AnnualReportView 的聚合默认排除 ID 集合内账本；若实现成本高，降级方案：总览卡脚注加「含示例数据」明示（二选一须落地一个） | SampleData.swift、MeView.swift、LedgersView.swift、PeopleView.swift、各统计聚合点 | 中：UserDefaults 与 SwiftData 双写一致性——以「集合∩现存」求交兜底，删簿后集合残留 ID 无害 |
| 3 | **记一笔防重复提交** | RecordFormView 加 `@State isSaving`：save() 首行 guard !isSaving 并置 true；保存按钮（toolbar confirmationAction）在 isSaving 时 .disabled(true)；saveAndContinue 分支在落印结束（1.05s）后复位；普通保存 dismiss 不需复位 | RecordFormView.swift save() 与 toolbar | 低 |
| 4 | **背景与填充色定版** | 按 3.1：paper/baiPaper/baiCard 退役 → systemGroupedBackground / secondarySystemGroupedBackground；baiInk/baiStone/baiLine 映射 label/secondaryLabel/separator；新增 primaryFill dyn(#A62B1F,#A62B1F)、baiPrimaryFill dyn(#5B6770,#5F6B76)；DirectionTag/封面签/印章填充换 Fill 令牌；各页删 scrollContentBackground(.hidden)＋paper 背景（保留白事页的 bai 条件分支改映射后同删）；DESIGN.md 色板章同步改写、删除「纸白底保留」例外登记 | Palette.swift；全部含 `.background(Palette.paper` 的视图（grep 约 10 文件）；GiftBookPDF 与分享图卡**不动**（静态成品的纸色是成品属性） | 中：深色模式全页需目视一轮；白事页改底后与 baiPrimary 的关系只剩元素级，目视确认礼制感不塌 |
| 5 | **金额与标题去衬线** | 按 3.2：liqianMoney 改为 sans semibold＋monospacedDigit 实现（API 名可保留、实现换血，调用点零改动是首选路径；若改名则全量替换约 30 处）；逐处改：RecordFormView.swift:331「¥」符、AnnualReportView.swift:110 标题、:163 与 StatsView.swift:133 排行序号；白名单五处（3.2 第 3 条）在 DESIGN.md 登记为穷尽清单，并加一条自查 grep：`liqianSerif` 在白名单文件外的引用应为 0 | Palette.swift（Font 扩展）、上述 4 个文件、LiqianWidget.swift | 低：纯字体替换；注意 .largeTitle 金额 minimumScaleFactor 等既有行为保留 |
| 6 | **封面满块回归详情页头部** | LedgerDetailView 头部 Section 改：左＝封面满块 56×92（朱砂 Fill 底、竖排事由 liqianSerifFixed 20、印点 7、圆角取同心公式：置于 cardCorner 18 容器内边距 12 时内圆角 6——按 20−12 口径取 8 并在代码注释写明）、右＝VStack（礼簿名 .headline、日期＋农历 .footnote 分段、收/随/人数三列统计紧凑行）；原 statsCard 删除；与列表小签（30×64）构成「小签在列表、满块在详情」的单一 moment 规则，写进 DESIGN.md 替代旧「封面块」条 | LedgerDetailView.swift 头部；Components.swift 可复用 SealStampView/签组件 | 低 |
| 7 | **空状态全量归一** | 四处改 ContentUnavailableView（规格见 3.3 末）：LedgerDetailView 空记录（actions：记一笔 prominent）、PeopleView 空往来（actions：生成示例数据 plain＋去礼簿记一笔）、AnnualReportView 空年、PersonDetailView 空（无 actions）；主行动 prominent 规格：朱砂 Fill 胶囊＋白字＋minHeight 44（首页 S6 同步） | LedgerDetailView.swift、PeopleView.swift、AnnualReportView.swift、PersonDetailView.swift、LedgersView.swift | 低 |
| 8 | **分享图卡口径对齐** | 文案改实（三处）：MeView 入口副标题与 AnnualReportView 页内说明改为「含往来第一位亲友的姓名与汇总，其余为年度汇总数据」；图卡保留姓名（分享对象为家人、用户主动生成，属明示后自愿）；makeShareImage 加失败分支：errorText 行「图卡生成失败，请重试」 | MeView.swift:229、AnnualReportView.swift:238、:262-268 | 低 |
| 9 | **最近删除可用化** | 行加 leading swipe「恢复」（tint primaryFill）；行加 contextMenu（恢复/彻底删除）；List 底部 Section footer：「左滑或长按一行可恢复或彻底删除。」；DirectionTag 的 bai 改按所属礼簿判定（TrashItem.ledger 快照 type 或 record 的 ledgerID 反查，取不到时按 item.ledger?.type == 白事 判断 record 行所属簿——实现时以 TrashStore 快照字段为准） | TrashView.swift | 低 |
| 10 | **AI 设置状态诚实化** | 删除 Key 分支同步 `aiEnabled = false`；保存 Key 后置状态行三态：未验证/验证中/已验证——保存后自动发一次最小 chatJSON 探活（system: 仅回复 OK），成功置「已验证」，失败置 message 为定版错误句＋「Key 已保存，但验证未通过」；开关行 footer 补一句「开关打开且 Key 验证通过，AI 功能才可用」 | AISettingsView.swift；DeepSeek.swift 复用现有 client | 中：探活产生一次极小额 API 调用，须在 footer 明示「保存时会自动验证一次 Key」 |
| 11 | **批量汇总条与大字一致性** | 汇总条改分方向：「已记 N 笔 · 收礼 ¥X · 随礼 ¥Y」（待送出单列或不计入并注明）；删「最近：X」或改按 date 最大取「最近日期」一笔并改文案为「最近一笔（按日期）」；bigMode 作用域补齐：粘贴/AI 模式的 TextEditor 字体（.system(size: 20)）与预览行全行同字号 | BatchEntryView.swift:176-200、paste/ai Sections | 低 |
| 12 | **一致性收尾包** | ① 卡面实现收敛：删 MeView/StatsView 私有卡面，全 App 只留 Components.liqianCardSurface（StatsView 随第 1 项同类改版时处理）② 残留口语报错四处改定版书面句（Nielsen #2 所列）③ AI 引导 alert 加「去设置」按钮（深链至 MeView 的 AI 行不可行时，改为关闭 alert 并切到「我的」Tab——实现口径：ContentView 监听 AIAccess 引导通知切 Tab，简化版可只改文案为明确路径＋按钮「知道了」并登记降级）④ StatsView 关系图与首页年图补 accessibilityLabel 汇总句 ⑤ DESIGN.md 附录清理：删「搜索下沉」条、锁定页高光例外随 3.3 落地后更新登记 | 各散点文件、docs/DESIGN.md | 低 |

**本轮不动**（明确排除，防范围蔓延）：礼谱 PDF 内部（静态成品，衬线/纸色/干支均为成品属性，第一轮已对齐 App 令牌）；小组件布局（仅随第 4/5 项同步底色与字体）；同名合并的数据模型（F12 需 schema 级处置——加人物实体或备注区分——单独立项，不在本轮）；iPad/分屏适配（无证据，不立项）。

**验收口径（下一轮交付时逐项对）**：截图复拍三处（我的页顶部应为 insetGrouped 形态、无双 chevron、无 274pt 空白）；深色模式复拍方向签（白字对 Fill 令牌）；改名复现路径重走（改示例簿名→副标题/清除/再生成三者一致）；记一笔连点保存只落一笔；生成示例后总览数字不变（隔离方案）或脚注明示（含示例方案）；VoiceOver 读统计图有汇总句。

---

## 附：整改落实记录（2026-11-07，同日执行）

执行口径：以本报告第八部分改造清单 12 项为准逐项落码；第一轮 PRO-AUDIT 定版
（术语/千分位/错误族/令牌梯队）未回退。DESIGN.md 已同步升版 v0.4。
复审数字为同一组 grep 口径的整改后实测。

| # | 改造项 | 状态 | 落实说明与复审数字 |
|---|---|---|---|
| 1 | 「我的」页整页重写 | ✅ 已落 | MeView 整文件重写为 List(.insetGrouped)：总览＝首个 Section 三列统计行＋计数入 footer；待回礼独立 Section（空时整组不渲染、说明入 footer）；五组入口为原生 NavigationLink/Button/ShareLink/Toggle 行；entryRow 手绘 chevron 删除（MeView 内 chevron 残留 0，系统披露箭头唯一）；图标统一 ink、frame 24；asCardRow/groupHeader/私有 cardSurface 三件套全删。行为逻辑（CSV 指纹重生成、备份导出、覆盖恢复二次确认、示例开关、AI 状态文案、隐私锁开关）平移未改语义 |
| 2 | 示例数据可信化 | ✅ 已落 | 身份改 ID 集合：generate 返回 Bool 并把两本 ID 存 UserDefaults 键 `sampleLedgerIDs`（不进备份）；hasSamples/clear/防重全按「存储集合 ∩ 现存账本」判定，改名不脱钩；旧版标题前缀生成的示例在 sampleIDs(ledgers:) 里一并认领 ID（旧示例同样可清、可隔离——取舍：靠标题认领仅对存量生效，新生成全走 ID）；首页/往来页生成按钮在 generate 返回 true 时弹「示例数据已生成」回执（文案与 MeView 入口统一）；统计隔离已落：MeView 总览、LedgersView 汇总/待回礼/年图/最近往来、StatsView、AnnualReportView 的聚合全部排除示例账本记录（未用降级脚注方案） |
| 3 | 记一笔防重复提交 | ✅ 已落 | RecordFormView 加 `@State isSaving`：save() 首行 guard、校验通过后置 true；保存/取消按钮在 isSaving 时 disabled；`.interactiveDismissDisabled(isSaving)` 禁手势退出；保存并继续分支在落印 1.05s 结束后复位，普通保存 dismiss 无需复位 |
| 4 | 背景与填充色定版 | ✅ 已落 | 新增 Palette.groupedBackground（systemGroupedBackground）与 primaryFill dyn(#A62B1F,#A62B1F)、baiPrimaryFill dyn(#5B6770,#5F6B76)；paper 退役出界面背景（视图引用残留仅 AnnualReportCard 静态图卡 1 处，属成品纸面）；baiPaper/baiCard/baiInk/baiStone/baiLine 全部重映射为系统分组底/次级面/label/secondaryLabel/separator，白事身份只剩 baiPrimary；DirectionTag、列表小签、详情封面满块、印章、往来迷你签填充全换 Fill 令牌；LaunchBackground.colorset 同步 #F2F2F7/#000000；含 `.background(Palette.paper` 的视图已全量改走 groupedBackground 或回归 List/Form 默认渲染（LibuExport/落款编辑/AI 设置/一句话/贺词删 scrollContentBackground+paper 背景） |
| 5 | 金额与标题去衬线 | ✅ 已落 | liqianMoney 内部换 sans semibold＋monospacedDigit（调用点零改动）；逐处改：RecordFormView「¥」符、AnnualReportView 报告标题（→.headline）与排行序号、StatsView 排行序号（→.subheadline.weight(.medium)）、LedgerDetailView 统计值与人数、PersonDetailView 合计值；批量大字金额 34pt 改 sans semibold 等宽；Widget 计数/金额改 sans。复审：`.liqianSerif(` 调用点 0；liqianSerifFixed 只剩白名单五 moment＋Palette 内图卡金额定义（封面签/印章/锁定页/图卡题字/详情满块/往来迷你签） |
| 6 | 封面满块回归详情页头部 | ✅ 已落 | LedgerDetailView 首个 Section 改头部行：左＝56×92 封面满块（primaryFill/baiPrimaryFill 满底、竖排 liqianSerifFixed 20、印点 7、圆角 8 按 20−12 同心口径并注释）、右＝礼簿名 .headline＋公历/农历分段＋收/随/人数三列紧凑统计；原 statsCard 删除；记录区改 insetGrouped 原生行（副行关系·方式与日期分列左右、备注单独一行），删除礼簿为末尾 Section 的 destructive 原生行；底部玻璃双钮保留 |
| 7 | 空状态全量归一 | ✅ 已落 | 四处改 ContentUnavailableView：礼簿详情空记录（actions：记一笔 borderedProminent＋Fill tint）、往来页空（actions：生成示例数据＋回执）、年度报告空年、人物详情空（无 actions）；首页 0 数据隐藏汇总卡（statRecords 为空时不渲染）、空状态主行动改 borderedProminent（primaryFill tint） |
| 8 | 分享图卡口径对齐 | ✅ 已落 | 按 F4 定版改文案（如实说明）：MeView 入口副标题与 AnnualReportView 页内说明统一为「含往来第一位亲友的姓名与汇总，其余为年度汇总数据」；图卡保留姓名；makeShareImage 加失败分支 errorText「图卡生成失败，请重试」（F5 同项落） |
| 9 | 最近删除可用化 | ✅ 已落 | TrashView 改 insetGrouped 原生行；leading swipe「恢复」（tint primaryFill、allowsFullSwipe）＋trailing 恢复/彻底删除保留；行加 contextMenu（恢复/彻底删除）；Section footer 加「左滑或长按一行可恢复或彻底删除。」；F9 白事签改按 item.ledgerID 反查现存礼簿 isBai（礼簿已恢复/不存在时回退 false） |
| 10 | AI 设置状态诚实化 | ✅ 已落 | 删除 Key 同步 aiEnabled=false；保存 Key 后自动探活一次（chatJSON 最小请求）：验证状态三态行（未验证/验证中/已验证/验证未通过，LabeledContent 呈现），失败时 message＝定版错误句＋「Key 已保存，但验证未通过」；开关行 footer 改「开关打开且 Key 验证通过，AI 功能才可用」，API Key 区 footer 明示「保存时会自动验证一次 Key（一次极小的接口调用）」 |
| 11 | 批量汇总条与大字一致性 | ✅ 已落 | 汇总条改分方向：「已记 N 笔 · 收礼 ¥X · 随礼 ¥Y」（待送出不计入随礼）；「最近：X」改按 date 最大取一笔、文案「最近一笔（按日期）」；bigMode 补齐粘贴/AI 模式：两个 TextEditor 大字时 .system(size: 20)、预览行（粘贴成功/失败、AI 三态）整行 .system(size: 17) |
| 12 | 一致性收尾包 | ✅ 已落 | ① 卡面收敛：MeView/StatsView 私有卡面已随第 1 项与 StatsView 改版删除，StatsView 改 insetGrouped 四 Section 原生行，全 App 卡面只剩 Components.liqianCardSurface 一份 ② 口语报错四处改书面句：「请填写姓名」「请填写礼簿名称，如…」「礼谱生成失败，请重试」「第 X 行未能确定，没有列进来…」 ③ AI 引导 alert 四处（记一笔/批量/一句话/贺词）加「去设置」按钮：发 liqianOpenAISettings 通知，ContentView 切到「我的」Tab（TabView 加 selection 绑定）——降级说明：设置页是「我的」内的二级页，通知只能切 Tab，进页后仍需点一行业（已按报告简化口径登记） ④ StatsView 关系图与首页年图补 accessibilityLabel 汇总句 ⑤ DESIGN.md 附录删「搜索下沉」条、锁定页高光已随第 3.3 定版去除（AppLock 封面块改 primaryFill 纯填充）、例外登记同步更新；F12 同名合并按已知产品限制未处理 |

**逐屏 WARN 必修项核对**：首页（S6/S7/卡面/金额 sans）✓；礼簿详情（满块/副行分列/空状态）✓；往来（空状态/insetGrouped）✓；人物详情（金额 sans/时间线单卡分组行/空状态）✓；批量（F7/大字三模式）✓；统计（insetGrouped/删私有卡面/图表读屏句）✓；年度报告（F4/F5）✓；最近删除（F8/F9/insetGrouped）✓；锁定页建议项（去高光）✓。

**本轮取舍登记**：
1. paper 令牌未从 Palette 删除——分享图卡（静态成品）的纸面仍引用它，令牌注释已改为「界面禁用、仅静态成品」；界面侧引用已清零（Widget 的 WPalette.paper 已改为系统分组底，仅保留同名）。
2. baiPaper/baiCard/baiInk/baiStone/baiLine 保留令牌名、重映射系统值（而非逐视图删引用）——效果与报告定版一致，且白事视图的 isBai 条件分支无需重写；后续若再审计可考虑直接删名。
3. 示例 ID 的存量认领走「标题前缀」兜底：新生成全走 ID；仅存量旧示例靠标题认领，若用户已把旧示例改过名则认领不到——该情形下它就是一本普通礼簿（数据无损，只是隔离/清除不再覆盖它）。
4. AI「去设置」只切 Tab 不直达设置页（见 12③）。

**真机验收清单（交付时逐项对，沿用报告验收口径）**：
- 截图复拍三处：我的页顶部应为 insetGrouped 形态、无双 chevron、无 274pt 空白；礼簿空状态主行动为朱砂填充按钮、0 数据无汇总卡；我的页滚到底，「关于」末行不被 Tab 栏遮挡。
- 深色模式复拍方向签与封面签：白字对 primaryFill/baiPrimaryFill（应明显比旧深色填充深）。
- 改名复现路径重走：生成示例 → 把示例簿改名 → 「我的」副标题仍显示已生成、点清除能清掉、再点生成不重复投放。
- 记一笔连点保存：落印动画期间狂点「保存」与下滑关 sheet，只落一笔。
- 生成示例后：首页汇总、我的总览、统计、年度报告数字不变（示例被隔离）；往来页仍能看到示例人物（演示面保留）。
- 白事礼簿全流程目视：详情页封面满块为素灰蓝、方向签素灰蓝、整页底色与红事同为系统分组底。
- VoiceOver：统计页关系分布图、首页年图能读出汇总句。
- AI 设置：删 Key 后开关自动关；填错 Key 保存后显示「验证未通过」而非「已保存」假象。
- 最近删除：左滑出行首即「恢复」、长按出行菜单、页脚有操作说明；白事记录的签为素灰蓝。
