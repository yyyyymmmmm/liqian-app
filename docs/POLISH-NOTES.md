# 礼钱账本 · v4.4 全量细节/交互/动画打磨（POLISH-NOTES）

分支：`feat/polish`（worktree 落码，未 commit，待父级串行合并＋过 CI）。
范围：任务清单 A/B/C 共 11 项逐项落地。红线遵守：未改数据模型、未改待回
口径（pending = max(balance, 0)，仍由 LedgerMath 单点计算）、未改已定版
术语与五主题色板（Palette 令牌表零改动）、未动礼谱 PDF 生成逻辑
（GiftBookPDF.swift 零改动）。

本机无 Swift 工具链，Core 单测未能本地运行（Tests 仅覆盖 LiqianCore，
本轮未改任何 Core 代码，风险面为零）；App 侧改动以逐文件 diff 自审＋
括号平衡检查收尾，最终以 CI 为准。

---

## A. 动画

### A1. Reduce Motion 全量降级 ✅
原状态：只有 SealStampOverlay、ScaleOnPressButtonStyle（Components 内）
与详情/首页两处 `.animation` 读了 reduceMotion，其余动画裸奔。补齐：
- `RecordFormView.swift`：新增 reduceMotion 环境值——补充信息展开
  `withAnimation(.snappy)` 改 RM 时无动画；表单焦点 `.animation(value: focus)`
  改 RM 时为 nil；金额自绘键盘面板 transition 由 `.move(edge: .bottom)`
  改 RM 时 `.opacity`；`AmountCaret`（金额光标）RM 时常亮不闪烁
  （repeatForever 不启动，焦点信号保留）。
- `AdvisorView.swift`：新消息自动滚动 `withAnimation { scrollTo }` 改
  RM 时直接定位。
- 本轮新增的全部列表/数值动画一律写成
  `.animation(reduceMotion ? nil : .snappy, value:)` 同一口径（见 A2）。
- 系统 zoom 导航转场（首页→详情）由系统按 Reduce Motion 设置自行降级，
  应用层不干预。

### A2. 列表增删动画＋数值 contentTransition ✅
列表增删（此前只有首页礼簿行按 count 有动画，其余整表跳变）：
- `LedgerDetailView.swift`：记录 Section 加
  `.animation(…, value: records.map(\.id))`。
- `LedgersView.swift`：在原 `ledgers.count` 之外补
  `.animation(…, value: statRecords.count)`，汇总/待回/最近三卡的
  出现消失同步平滑。
- `PeopleView.swift`（往来人物＋备礼行）、同文件 `PrepListView`、
  `TrashView.swift`、`LedgerMembersView.swift`、`BatchEntryView.swift`
  （逐行录入行数）、`PersonDetailView.swift`（时间线容器）：均按各自
  集合 id/键加同口径动画。
数值 `.contentTransition(.numericText())` 补齐点（原有：首页汇总、
详情头部金额、记一笔金额、现场模式、年报 headlineStat）：
- `LedgerDetailView` 头部「人数」计数（原只有过渡无动画，一并补）。
- `LedgersView` 待回礼卡：人均金额＋「共 X 人 · ¥Y」头行。
- `PeopleView` 人物行差额状态（待回/多随金额）。
- `PersonDetailView`：收/随合计、结论句、待回礼行、回礼参考区间与建议值。
- `MeView` 待回礼入口行总金额；同文件 `PendingPeopleView` 行金额。
- `StatsView`：事由行收/随、排行总额、summaryPair 汇总对。
- `AnnualReportView`：往来最多 Top3 金额、按事由收/随、待回礼合计行。

### A3. 主操作按钮 ScaleOnPress 统一 ✅（含口径说明）
- `Components.swift` `AddFloatingButton`：`.plain` → `ScaleOnPressButtonStyle()`
  （FAB 是全 App 新增动作收敛入口，此前无任何按压反馈；样式内部已处理
  Reduce Motion）。
- `RecordFormView.swift`：快捷金额 chips、人物联想 chips 改
  `ScaleOnPressButtonStyle()`。
- **有意不叠加**（系统样式自带按压反馈，叠自研样式会破坏材质/渲染）：
  `.borderedProminent`（空状态主行动、现场模式「登记这一笔」、提醒页
  行动钮）、`.glassProminent/.glass`（人物详情底部双钮、年报分享、
  锁定页解锁）、工具栏文字按钮（保存/取消——工具栏由系统接管按压态）。
  金额自绘键盘的数字键同理不叠（键盘键的反馈语义是高亮而非缩放，
  且已有逐键触感）。

## B. 交互

### B4. 触感审计补齐 ✅（沿用既有 sensoryFeedback 体系，只加触发点）
原有覆盖：记一笔（7 点）、批量（保存/错误/方向）、礼簿表单、详情/首页
删除警告、OCR 保存、现场模式、最近删除恢复、我的页导入成功。
本轮新增（均为「此前静默生效」的路径）：
- 删除确认类：`TrashView` 彻底删除与清空最近删除 → `.warning`
  （此前只有恢复有反馈，破坏性操作反而静默）。
- 批量/保存完成类：`LedgerMembersView` 成员新增/编辑 → `.success`、
  删除成员 → `.warning`；`RemindersView.ReminderDayFormView` 保存日子
  → `.success`（批量逐行/粘贴/AI 三路保存原已由 BatchEntryView
  saveTrigger 覆盖，未动）。
- 导出成功类：`LibuExportView` 礼谱生成成功 → `.success`、失败 →
  `.warning`；`HandoverView` 传承包/纪念版生成同口径双触发。
- 提醒开关类：`RemindersView` 待回礼提醒总开关、左滑启用/停用日子
  → `.selection`，左滑删除日子 → `.warning`；日子表单内「启用提醒」
  开关 → `.selection`。
- 左滑操作类：`PeopleView`/`PrepListView` 备礼左滑「标记已送出」
  → `.success`、删除 → `.warning`。
- 其他：`GreetingView` 复制贺词 → `.success`（此前只有文案变「已复制」）。

### B5. 表单键盘 scrollDismissesKeyboard ✅
- `RecordFormView.swift`（ScrollView）、`LedgerFormView.swift`（Form）、
  `BatchEntryView.swift`（Form）：加 `.scrollDismissesKeyboard(.interactively)`。
- 顺带对齐：`GreetingView.swift`、`RemindersView.swift` 的日子表单（同为
  带文本框的 Form）。
- 互斥路径核查：记一笔的自绘金额键盘是 safeAreaInset 面板、不走系统
  键盘通道，scrollDismissesKeyboard 只收系统键盘（姓名/备注焦点时），
  FocusState 三态互斥逻辑零改动、零回归面。

### B6. 图标按钮 VoiceOver 标签审计 ✅（结论：存量合格，仅记录）
全仓逐个核查 icon-only 按钮，均已有 accessibilityLabel：FAB（组件内）、
记一笔麦克风钮（「一句话记账」）、金额自绘键盘删除键（「删除一位，
长按清空」）、金额显示区（合并元素＋值）、批量删行钮、OCR/一句话删笔钮、
问账页麦克风与发送钮、签名删除钮、祝福播放钮。其余 SF Symbol 均为
带文字 Label 的一部分或纯状态指示（现场模式投屏图标旁有状态文字），
无需补标。本项无代码改动。

### B7. 记录行 contextMenu 四动作对齐 ✅
- `LedgerDetailView.swift`：原菜单只有「请来宾签名/语音祝福」两项
  （v4.2 活礼谱遗留），补「编辑」置首、「删除」（destructive，垫底，
  走既有 recordToDelete 确认）——与左滑的编辑/删除同组同序。
- `PersonDetailView.swift`：时间线行原菜单同样只有签名/祝福，补
  「编辑」（与点行同效 formMode=.edit）、「删除」；本页此前无删除路径，
  新增 deleteRecord 与详情页同语义（TrashStore 快照归档＋30 天可恢复
  ＋同款确认弹窗＋`.warning` 触感）。

## C. 审计遗留细节

### C8. Dynamic Type ✅
- **礼簿详情封面副标题**（PRO-AUDIT-2 真机待验遗留）：`LedgerDetailView`
  头部——新增 `headerSubtitle`：正常字号仍公历/农历横排分段；
  `dynamicTypeSize.isAccessibilitySize` 时改纵排两行完整呈现；标题
  大字号放行 2 行；头部三项统计金额与人数加 `lineLimit(1)`＋
  `minimumScaleFactor(0.7)` 防撑破。
- `Components.swift` `LedgerCoverCard`（列表封面卡）：收/随两金额与
  笔数加单行＋`minimumScaleFactor(0.75)`；副标题公历/农历两段加单行
  ＋`minimumScaleFactor(0.8)`（先缩后截，备注最后让位）。
- 其余写死字号位逐个核过，属「尺寸由版式/功能决定」的功能位，按
  Palette 既有豁免口径（liqianSerifFixed 同理）**有意保留并登记**：
  现场模式大字登记面（96/64/44pt——现场模式的产品定义就是大字）、
  记一笔金额显示 44pt 与键盘键 24/22pt（计算器式读数与键面）、
  批量大字模式 34/20/17pt（bigMode 开关本身）、年度报告分享图卡
  11–15pt（静态成品）、祝福详情页 64pt 波形图标（装饰符号）。
  它们若改走语义字阶反而破坏各自功能，待真机大字号目检后再议。

### C9. 方向签对比度 ✅（实算复核后修法与登记数字有出入，如实说明）
登记口径是「随礼方向签深色约 2.6:1」。用 WCAG 公式对现行实现逐组合
实算后：2.64:1 是**已退役的实心填充口径**（白字对 #93A1AD 填充）；
现行浅签（同色文字＋0.13 浅底）下随礼/白事签深色实测 5.07:1 已达标，
真正的缺口在**收礼签**：夜晚主题 4.13:1、黄色主题 4.16:1（文字色对
合成浅底），未过 AA 4.5:1。
修法（不动五主题色板、不动色彩纪律，只调签自身的 tint 与描边——
任务允许口径）：`Components.swift` `DirectionTag` 浅底 0.13 → 0.06，
加同色 1pt 描边（fg.opacity(0.45)）保签形，字重 medium → semibold。
复算五主题 × 收/随全部组合（文字对合成底）：最低 4.53:1（夜晚收礼）、
随礼/白事签最低 5.36:1，全部 ≥ 4.5:1。填充型签（封面小签/满块走
primaryFill/baiPrimaryFill＋白字）原已达标（5.45–7.03:1），未动。

### C10. 数字/日期格式一致性扫尾 ✅
- 金额：全仓展示金额均走 `LedgerMath.fmtMoney`（含小组件，见 C11）。
  扫出的 4 处裸 `String(format: "%.2f")` 逐个核实均为**输入/文件
  语境而非展示**，有意保留：CSV 导出金额列（AppSupport——机器可读
  文件不带千分位）、OCR 与一句话记账的待确认行 amountText 初值、
  记一笔编辑态 amountText 初值（后三者是可编辑输入串，带逗号会
  破坏再解析）。界面上的「¥」裸字面均为输入框前的币种字形，非格式化。
- 日期：展示日期统一走 `LiqianDate.displayString`（定版格式）；
  `TrashView` 的 DateFormatter 已带 zh_CN；`VoiceBlessingView` 的
  `.dateTime` FormatStyle 吃根视图注入的 zh_CN locale（LiqianApp.swift
  已注入）；Core 存储格式 en_US_POSIX 是机器格式，不属展示口径。
- **顺带修一处口径文案**：`AnnualReportView` 待回礼卡脚注旧文案
  「按最近一笔收礼之后是否已送出自动计算」描述的是 v2.4 已废止的
  旧规则——其计算一直走 LedgerMath 净差额（定版口径，未动），
  仅文案改「收礼多于随礼的差额自动计算，不分年份。」与全 App 对齐。

### C11. Widget WPalette 单点化 ◐ 部分落地（色值未收敛，理由如下）
- ✅ **金额格式已单点化**：`LiqianWidget.swift` 删除本地复刻的
  fmtMoney，改调 `LedgerMath.fmtMoney`（widget target 在 Project.swift
  里本就依赖 LiqianCore，零工程改动、零风险）；本地只留一行转发，
  调用点不变。
- ⛔ **色值未收敛到 Palette**（保留镜像常量，文件头注释已写明）：
  ① Palette 界面令牌由 AppTheme 令牌表驱动，解析时读 **App 进程**的
  UserDefaults，小组件扩展进程读不到 App 的主题设置，硬接 Palette.primary
  只会恒回白天主题、与用户所选主题错版；② widget target 未链接
  LiqianDesign（其 Components 还依赖模型层），为两个色值引入整包
  不成比例。镜像值与 AppTheme 白天/夜晚 primary 定值一致
  （#A62B1F / #D96A5C），是全仓唯一保留的手工同步点，改品牌色时
  两处同改。若日后要彻底收敛，前置条件是把主题值写进 App Group
  共享 defaults 供扩展读取——属工程结构项，单独立项。

---

## 改动文件一览（19 个）

LiqianDesign/Components.swift（DirectionTag 对比、FAB 样式、封面卡 DT）；
LiqianApp/LedgerDetailView.swift（菜单四动作、头部 DT、记录动画）；
LiqianApp/PersonDetailView.swift（菜单四动作＋删除路径、数值过渡、时间线动画）；
LiqianApp/LedgersView.swift（记录动画、待回数字过渡）；
LiqianApp/PeopleView.swift（差额过渡、备礼触感、列表动画）；
LiqianApp/MeView.swift（待回入口值过渡；PendingPeopleView 行金额过渡）；
LiqianApp/StatsView.swift、AnnualReportView.swift（数值过渡；年报口径文案）；
LiqianApp/RecordFormView.swift（RM 降级、收键盘、chips 样式、光标静止）；
LiqianApp/LedgerFormView.swift、BatchEntryView.swift（收键盘；批量行动画）；
LiqianApp/TrashView.swift（彻底删除触感、列表动画）；
LiqianApp/RemindersView.swift（提醒开关/删除/保存触感、日子表单收键盘）；
LiqianApp/LibuExportView.swift、HandoverView.swift（导出生成触感）；
LiqianApp/LedgerMembersView.swift（成员保存/删除触感、列表动画）；
LiqianApp/GreetingView.swift（复制触感、收键盘）；
LiqianApp/AdvisorView.swift（RM 滚动降级）；
LiqianWidget/LiqianWidget.swift（fmtMoney 单点化、WPalette 口径注释）。

## 真机验收建议（沿用逐屏口径）
- 开 Reduce Motion：落印只淡入、记一笔键盘面板淡入不滑入、补充信息
  无动画展开、问账新消息直接定位、金额光标不闪。
- 深色（夜晚主题）＋黄色主题下看记录行方向签，文字应明显比旧版清楚。
- 无障碍大字号（AX3–AX5）开礼簿详情：头部公历/农历纵排完整、标题
  两行内、统计不溢出；首页封面卡金额不换行。
- 人情提醒页：开关待回礼提醒、左滑停用/删除日子，均有触感；
  最近删除页彻底删除有警告触感；导出礼谱生成完成有成功触感。
- 礼簿详情与人物详情长按一笔：菜单均为编辑/签名/语音祝福/删除四项。
