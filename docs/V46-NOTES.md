# v4.6 说明（4.6.0 / 46）

分支 feat/v46-charts，两笔提交：v4.6 主体 + 质感审计调整。

## 交付验证（2026-11-08）

- CI：GitHub Actions run 42405345048（workflow_dispatch @ feat/v46-charts）
  结论 success；首跑 42405225838 红于 BarMark position 写法，修后复跑绿。
- 单测：LiqianCoreTests 共 134 条、0 失败（v4.5 的 132＋新增
  AppGroupResolverTests 2 条）。
- 预签断言：CI 日志含 "presign assertions passed"。
- 解包实测（本地 Mach-O 解析）：App/Widget/Share 三 target 均
  4.6.0 (46)；三二进制均带 LC_CODE_SIGNATURE 且可提取 entitlements
  blob——App 含 application-groups＋aps-environment＋icloud 两键，
  两 appex 含 application-groups，组名 group.site.didichou.liqian 在位；
  Share 扩展在包（PlugIns/LiqianShare.appex）。
- 产物：~/workspace/your_files/liqian-v4.6/liqian-native-unsigned.ipa

## 一、四栏导航

ContentView 三 Tab 改四 Tab：**首页（0）/ 往来（1）/ 图表（2）/ 我的（3）**。

- 首页＝原 LedgersView 原样承接（礼簿列表、示例隔离、新建/记一笔入口不变），
  仅 Tab 标题「礼簿」→「首页」、图标 book.closed → house.fill。
- tabSelection 全量赋值点核对（grep 全仓只有 ContentView 持有）：
  - `liqianOpenAISettings` 通知：2 → **3**（「我的」新索引；2 现为图表）✅ 已改
  - checkShareImport → 0（首页）不变；人物深链 → 1（往来）不变；
    checkShortcutPending → 1 不变；小组件 quick-record 走 presentQuickRecord
    弹表单、不切 Tab，不变。
- 单测为 LiqianCore 纯函数层，不涉及 Tab，无断言需改。

## 二、图表页（ChartsView.swift，本版主菜）

入口：「图表」Tab，自带 NavigationStack。数据口径与全 App 统计完全一致
（AppSupport.snapshots + SampleData 示例隔离；随礼只计已送出；待回 =
LedgerMath.people 的 max(balance, 0)；金额 LedgerMath.fmtMoney）。

**时间范围**：顶部滑块式三档——全部 / 近 12 个月 / 自然年（自然年档附年份
菜单，列数据中出现过的年份）；切换后全部区块按同一口径刷新。

自上而下六个区块：
1. **总览卡组**：累计收、累计送、净往来（收−送）、待回礼（金额＋人数）、
   往来人数、场次（礼簿数），2×3 财务摘要排版，金额入场滚动（见质感审计 4）。
2. **收送趋势**：按月双柱（收＝朱砂、送＝墨灰），窗口为最近 12 个月
   （自然年档为该年 12 个月，缺月补零保轴连续）；柱组上方标**月合计**
   （逐柱精确值会互撞 24 个标签，改由月合计＋按年汇总＋无障碍标签承载）；
   卡内下半附**按年汇总**（每年收/送/净额，范围口径同当前档）。
3. **关系分布**：SectorMark 环图（按 RelationCatalog 关系分组的往来总额
   占比），中心滚动显示往来总额；下方明细表逐关系给色点、笔数、占比、金额。
   配色单色族：最大组朱砂，其余暖灰阶（令牌不透明度推导，不写死 hex）。
4. **场合分布**：按礼簿逐本汇总收+送的横向条形 Top 8＋明细行
   （事由、收/送拆分、笔数）。
5. **人物洞察**：往来总额 Top 10 横向条形＋金额标注。
6. **待回清单**：待回 Top 8 行（姓名/关系/最近往来/待回金额），
   点行经 PeopleView.NameRoute 进人物详情；结清时给「都结清了」正向态。

设计纪律落实：pageBG 打底、卡面无描边分层（审计 1）、朱砂只表收、墨灰表送、
金色零出现；轴线/网格只留横向 hairline 级网格＋紧凑轴标签（过万记「万」）；
每图带 accessibilityLabel 文本等价物；空态双层——全无数据给说明卡
（提示示例礼簿不计入），范围无数据给换范围提示，不编示例数据；
Dynamic Type 走系统字阶与 LazyVGrid 弹性列。

## 三、反馈邮箱

FeedbackMail.address：support@didichou.site → **inkroot001@gmail.com**
（2026-11-08 用户拍板，真实可收件）；邮件标题口径同步 v4.6。

## 四、CI 预签（治 v4.5 拒启与 App Group 未建成）

实证背景：裸包无 entitlements blob → AltSign 读不到能力声明，不建 App
Group；新扩展 profile 缺失可致整 App 拒启（SideStore 官方 issue #1394）。

- ios-native.yml 在 zip 前新增「Ad-hoc presign」步：按 Project.swift 三个
  target 的声明写两份 entitlements plist（App：groups＋aps-environment＋
  icloud-container-identifiers＋icloud-services；Widget/Share：仅 groups），
  codesign --force --sign - 由内向外签 Frameworks → 两 appex → 主 App。
- 签后断言：三二进制逐个 `codesign -d --entitlements :-` 校验含
  application-groups 与组名（App 另验 icloud-services），缺失即构建失败。
- Share Extension 本版恢复进包（v4.5 的手术包 A 曾摘除，此版靠预签回归）。
- 产物名仍叫 unsigned IPA：语义是「无开发者身份、仅 ad-hoc 预签」，
  SideStore 安装时照常重签。

## 五、App Group 解析兜底（AppGroupResolver）

LiqianCore 新增 AppGroupResolver：groupID 优先读当前进程 Bundle 的
Info.plist 中 AltSign 写入的 ALTAppGroups 首项，无则回退常量
group.site.didichou.liqian。统一接入四处：App 的 WidgetSummaryWriter、
Widget 的 SummaryStore 与 OpenQuickRecordIntent、Share 的 ShareChannel
（containerURL 判据同走解析值）。各处原有 nil 降级语义不变。
单测 AppGroupResolverTests 覆盖回退路径与常量对齐。

## 质感审计（对照用户四帖）

### 1. 不画边框，靠 1%~3% 微对比色阶分层 —— ✅ 已改
- 现状：liqianCardSurface（Components.swift）与首页礼簿卡、首页汇总卡，
  共三处「卡面色＋1pt hairline 描边」的装饰性分层。
- 改法：三处描边全数移除，分层只靠色阶＋间距。令牌实测（相对亮度 L*）：
  白天 pageBG #FAF9F7（L*≈98.0）↔ surface #FFFFFF（L*=100），ΔL*≈2.0，
  正落在 2–3% 带内；腾讯蓝/灰色/黄色三套浅色主题同量级（ΔL*≈1.8–2.6），
  均不动令牌。夜晚 pageBG #131315（L*≈5.2）↔ surface #1E1E21（L*≈10.2），
  ΔL*≈5.0——深色下同样的物理色阶人眼需约两倍台阶才可辨（系统深色分组
  背景同此量级），保留现值并在此注明口径，不为凑数字改动整套令牌。
- 保留的功能性描边（勿误拆）：方向签描边（Components.swift 两处，v4.4
  为对比度 ≥4.5:1 而加，浅底＋描边＋semibold 是达标组合）；白事素蓝线
  （baiLine，白事语境的礼制性线条）；金额键盘键面线（RecordFormView，
  键面与底同色、靠线分键，是功能边界）；印章内细框（静态成品造型规格）；
  外观页色点圈线（白色系色点无此线不可见）；年度报告图卡描边（静态成品）。

### 2. 暗色模式字重调细一档 —— ✅ 已改
- 现状：Font.liqianMoney 固定 semibold，不分明暗。
- 改法：新增重载 `Font.liqianMoney(_:dark:)`（dark 时 medium、浅色
  semibold，其余不变）＋组件 `LiqianMoneyText`（内部读 colorScheme）。
  接入面：图表页全部 KPI（RollingMoneyText 与计数指标）、首页汇总卡
  stat、统计页 summaryPair。其余列表级金额仍走原 liqianMoney（字号小、
  降档收益低且改动面大），机制已备，后续按需迁移。

### 3. 等宽数字防乱抖 —— ✅ 已改
- 现状：liqianMoney 已带 monospacedDigit；裸数字未全覆盖。
- 改法：图表页全量等宽（KPI、计数、轴标签、柱标注、占比、笔数、年份行、
  明细行逐处核过）；顺手补统计页三处裸数字（本年笔数页眉、页脚汇总行、
  事由笔数）。首页 stat 金额本就走 liqianMoney（等宽）无需改。

### 4. 统计数字入场滚动、金额平滑滚动 —— ✅ 已改（本版落在图表页）
- KPI：RollingMoneyText 以 TimelineView 驱动数值插值，入场从 0、
  切范围从旧值滚到新值，easeOutCubic 0.9s 先快后慢，滚完自动停表；
  计数指标走 numericText 过渡（首页/统计页原有列表金额同此口径）。
- 图形：柱条以 entrance 进度缩放生长、环图扇区同进度扫入，0.7s easeOut；
  切范围/切年份重启动画。
- Reduce Motion：开启时 KPI 瞬时落值、entrance 恒 1、范围滑块无动画
  （全量守 POLISH 口径）。

### 5. 动效分性格：拖拽瞬间到位、点按 Q 弹 —— ✅ 已改
- 范围切换改自绘滑块式分段控件：matchedGeometryEffect 胶囊指示器＋
  .snappy(0.28) 短程动画＋选择触感（sensoryFeedback .selection），
  无长尾弹簧迟滞。
- 点按类保留既有 ScaleOnPress 轻回弹，不动；滚动/拖拽路径未加任何弹簧。

### 6. 流式打字水墨晕染 —— 审计过，暂不适用（不改）
- 查实：对话管家/问账（AdvisorView）的答案不是流式文本，而是本地引擎
  算出的**结构化结果卡**（差额卡/往来明细卡/待回清单卡/时段汇总卡/事由
  卡＋纯文案提示卡），DeepSeek 只做意图解析、不产正文，全量数据在卡面
  一次呈现。给财务数字卡加 blur-in 晕染既无「流」的来源，也与本 App
  数字清晰直读（numericText、等宽）口径相冲。待将来出现真正的流式
  长文答案（如 AI 撰序的流式输出）再按此帖落实。

### 7. 选择器物理感 —— 保持原生，仅落实第 5 条滑块
- 日期/时间等全为系统原生滚轮（DatePicker），自带惯性与触感，不自造。
- 全 App 审计无自绘数量步进器：金额走数字键盘/金额键盘＋快捷金额钮，
  BatchEntryView 的 minus.circle 是删行按钮而非步进器；金额键盘的
  键面描边为功能性分键线（见第 1 条保留清单）。无连加/翻页数字需要补。

## 待验清单（本机验不了、勿宣称已通）

- [ ] 真机 SideStore 安装 v4.6 完整包（含 Share 扩展）：能否正常打开
      （预签修复是否奏效是本项核心）
- [ ] 真机：App Group 共享是否真的通（小组件读到速览、分享导入暂存承接、
      ALTAppGroups 回写后 AppGroupResolver 是否命中新组名）
- [ ] 真机：四栏下各深链落点（person→往来、share-import→首页弹导入、
      快捷菜单待回→往来、AI 设置通知→我的）
- [ ] 真机视觉：去描边后浅色/夜晚两模式卡面分层是否够读；图表页
      Dynamic Type 大字号下 KPI 网格与明细行不溢出；暗色金额降档观感
- [ ] 真机：图表页范围切换动画与 KPI 滚动在真机帧率下的顺滑度
- [ ] iCloud/CloudKit 在 Production 的部署仍是上架前置（与本版无关、照旧）
