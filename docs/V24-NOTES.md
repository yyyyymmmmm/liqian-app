# v2.4 对齐版落实记录（2026-11-07）

口径来源：用户本轮四点拍板（FAB 收敛 / 文案大厂标准 / 表单原生化 / 五主题）＋
HIG 与微信、支付宝形态＋ ux-writing 公式（动词前置点名结果、说明短句无口语、
空状态先价值后行动、标签不用占位符代替）。前两轮 PRO-AUDIT 定版不回退。

## 包 A：添加模型统一为右下角单一 FAB ✅

- 共享组件 `AddFloatingButton`（LiqianDesign/Components.swift）：圆形 56pt、
  primaryFill 底、白「+」（.title2 semibold）、投影 black 0.20/r10/y4；
  形参 `label`（同时作 accessibilityLabel）、`bottomPadding`；
  常量 `tabBarClearance = 92`（iOS 26 浮动 Tab 栏占位量级）。
- LedgersView：删工具栏「新建礼簿」+；根 ScrollView 挂 overlay FAB
  （bottomPadding = tabBarClearance），内容底部另加 72pt 留白防遮挡。
- LedgerDetailView：删整个底部 safeAreaInset 行动栏（记一笔/批量补录）；
  overlay FAB = 记一笔（bottomPadding = spacingL，本页已隐藏 Tab 栏）；
  「批量补录」移入右上「更多」菜单，排在导出礼谱/生成贺词之前；
  工具栏保留编辑（铅笔）与更多（···）；详情空状态里的「记一笔」
  prominent 按钮保留（ContentUnavailableView actions 惯例，不属行动栏）。
- PersonDetailView 底部双按钮（记一笔收礼/随礼）是回礼决策动作，未动。

## 包 B：文案与信息层级 ✅

- **待回口径（根因与修法）**：矛盾根因在口径层——`PersonSummary.pendingCents`
  旧值是「最后一笔已送出随礼之后的收礼合计」（自动规则），与 balance
  （收−随差额）是两套账：先随 500 后收 200 的人，差额 −300（我多给），
  旧 pending 却是 200，于是「我多给」行下挂「待回礼 ¥200」自相矛盾。
  定版：`pendingCents = max(balance, 0)`，恒等式 balance>0 ⇔ 待回＝balance、
  balance≤0 ⇔ 待回＝0，由 LedgerMath.people 在汇总后统一赋值；
  chrono 排序仅保留给 relation 取值。MeView 待回礼 footer 文案同步改口径
  （旧文案描述的是已废止的自动规则）。
- 单测：新增 `testPendingEqualsPositiveBalanceOnly` 锁定恒等式（含「我多给
  不挂待回」的截图形态）；`testPendingSendFirstThenReceive`、
  `testPendingPartialSendThenReceiveAgain` 两条按新口径改写期望值
  （800→差额 300、300→差额 900）并注明旧值来源；其余 pending 测试在
  新口径下结论不变、未动。
- PeopleView 人物行：主行右＝状态金额单行（lineLimit 1 + layoutPriority）：
  待回 ¥X（朱砂 semibold）/ 多随 ¥X（墨色）/ 已结清（次级色）；
  次行＝「收 ¥A · 随 ¥B · N 笔 · 最近 M月d日」全量数字；
  删除原第二行「待回礼 ¥X」——待回字样只在差额 > 0 时以主行状态出现。
  次行按定版格式不再含关系（关系仍在人物详情与记录行呈现）。
- 备礼清单 footer 定版：「还没送出的礼记在这里，送出后在记录里改为已送出。」（24 字）
- LedgerDetailView 记录行：右列＝金额（上）＋日期（下、footnote、次级色、
  右对齐）；副行只留「关系 · 方式（· 备注）」，备注并入副行尾（原第三行取消）。
- 日期中文化：LiqianApp 根视图 `.environment(\.locale, zh_CN)`，
  全 App 两个 DatePicker（礼簿表单/记一笔）及系统日期控件一并中文；
  自绘日期文本维持 displayString 定版。

## 包 C：表单原生化 ✅

- LedgerFormView：本就是 Form＋Section；本次把名称改为行首标签行
  （「名称」标签＋TextField，示例保留为 placeholder），备注同法
  （「备注」标签＋「选填」placeholder）；事由 Picker、日期行维持原生行。
- RecordFormView：金额键盘区保留自绘（记账类通行做法）；姓名、备注
  改为与礼簿表单一致的行首标签行；其余 Picker/分段/日期本就是原生 Form 行。
- 两表单保存按钮维持工具栏，禁用态规则未动。

## 包 D：外观主题 ✅

- 落点：「我的」新增「外观」组 → 主题行（带当前值）→ AppearanceView
  二级页五选一（色点＋名称＋当前项勾选）；组 footer 与页面 footer 均写明
  「主题只影响 App 界面，导出的礼谱不变」。
- 存储：`@AppStorage("appTheme")`（AppTheme.storageKey），只进
  UserDefaults，不进数据模型与备份。
- 机制一句话：Palette 的 primary/primaryFill/primaryTint 改由
  `UIColor(dynamicProvider:)` 在解析时读 `AppTheme.current` 生成，
  ContentView 以主题值设 preferredColorScheme 并按主题值重挂子树（.id），
  切换即时生效、无须重启。
- 五主题色值（文字级对比均为浅色底上实算约值）：
  - 白天：浅色，朱砂 primary #A62B1F（7.03:1）/ fill #A62B1F / tint #F3E2DC
  - 夜晚：深色，朱砂 primary 深色面 #D96A5C（黑底约 5.9:1）/ fill #A62B1F
    （白字 7.03:1）/ tint #38251F
  - 腾讯蓝：浅色，primary #0052D9（约 5.9:1，TDesign 品牌蓝）/
    fill 深一档 #003CAB（白字约 8.0:1）/ tint #E3EDFB
  - 灰色：浅色，primary 石墨灰 #4E5969（约 6.8:1）/ fill 同值 / tint #E9EBEE
  - 黄色：浅色，primary 琥珀 #A16207（约 4.9:1）/ fill 深档 #854D0E
    （白字约 6.3:1；亮黄 #B7791F 白字仅约 3.6:1，只用作色点识别，
    不作填充、不铺底）/ tint #F7EBCB
- 跟随范围：Tab 选中色（ContentView .tint = Palette.primary）、FAB、
  主按钮、方向签文字、封面签/满块 Fill、App 内落印与印章、金额键盘
  常用额 chips 等全部引用同一组令牌，自动跟随。
- 不跟随：礼谱 PDF（GiftBookPDF 自带朱砂常量、零 Palette 引用，已 grep
  验证）、年度报告分享图卡（仅用 ink/stone 结构色，已 grep 验证）、
  小组件（独立 WPalette，未纳入本轮）、白事 baiPrimary 身份色（定版不动）。

## 取舍与遗留

1. `.id` 重挂的副作用：切换主题时各 Tab 的导航栈会回到根页（在「外观」
   页点选主题会回到「我的」页，正好直观看到新主题全貌）。这是根级重挂
   的固有代价；若后续要保栈，需把导航路径提升为 App 级状态，另立项。
2. LedgersView 的 zoom 导航转场与 FAB overlay 并存：FAB 位于 ScrollView
   overlay 层，不参与转场，点按区域与卡片不重叠（底部留白已加）。
3. 主题对深色模式的影响：非夜晚主题一律强制浅色——即使用户系统开着
   深色，白天/蓝/灰/黄主题下 App 仍为浅色（用户点名划分如此）。

## 真机验收点

- 首页：右上角 + 消失，右下角 FAB 不被 Tab 栏遮挡、点按出新建礼簿。
- 详情：底部行动栏消失，FAB 记一笔可点；「更多」菜单含批量补录；
  记录行日期在金额下方右对齐。
- 往来：人物行状态单行不换行；构造「先随 500 后收 200」的人，
  应显示「多随 ¥300」且无待回字样；备礼清单 footer 为新短句。
- 新建礼簿：日期选择器显示中文（如「2026年11月7日」）；
  名称/备注为行首标签行。
- 外观：五主题逐个切换即时变色（含 Tab 选中、FAB、封面签）；
  夜晚为深色、其余浅色；切到腾讯蓝后导出礼谱，PDF 仍为朱砂。
