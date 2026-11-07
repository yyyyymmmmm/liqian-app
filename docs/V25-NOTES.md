# v2.5 落实记录（2026-11-07）

口径来源：用户本轮六点（删除进更多／详情页行动区删除／侧滑／返回时 Tab 栏延迟／
设置页归档重组／主题色板系统化）。本机无 Swift 工具链，未做真编译；
全文件括号配平＋关键 grep 自查通过（见文末），需 CI 验证。
纪律：未动数据模型与备份格式；未 commit/push。

## 包 1：删除礼簿收敛到「更多」 ✅

- LedgerDetailView「更多」菜单新增「删除礼簿」（destructive，垫底），
  走既有 confirmationDialog：文案「礼簿里的记录会一并删除，30 天内可以在
  『我的 → 最近删除』恢复」——按现行删除语义如实写的（整簿快照进 TrashStore）。
- 删除的旧入口：详情页页尾独立的「删除这本礼簿」Section 已移除。
- LedgerFormView（编辑表单）里本就没有删除入口（已核），无需移除。
- 结果：详情页内删礼簿只剩「更多」一个入口；另有首页左滑删除（包 3，
  同确认同语义）与最近删除页的恢复/彻底删除，不在此列。

## 包 2：详情页行动区删除、「更多」菜单定序 ✅

- v2.3 加的页内可见行动区（导出礼谱 PDF／生成贺词两按钮 Section）整块移除。
- 「生成贺词」本已在「更多」内，保留；导出菜单项文案由「导出礼谱」
  统一为「导出礼谱 PDF」。
- 工具栏原独立的「编辑礼簿」铅笔按钮收进菜单。菜单最终顺序定版：
  批量补录／导出礼谱 PDF／生成贺词／编辑礼簿／删除礼簿（destructive 垫底）。
- 详情空状态里的「记一笔」prominent 按钮保留（ContentUnavailableView 惯例，
  非行动区）。

## 包 3：主要列表侧滑 ✅

- 礼簿首页：ScrollView＋LazyVStack 自绘卡 → List(.insetGrouped) 承载。
  全部内容同在一个 Section（保证卡间距均匀），每行 listRowBackground 透明、
  分隔线隐藏、行距拆半（上下各 6pt）拼出原 12pt 卡间距，两侧 16pt 与原页边距
  一致；卡片视觉（LedgerCoverCard 自带表面/描边/圆角）不变。礼簿行左滑
  「删除」（destructive，与详情页同款 confirmationDialog＋整簿进最近删除）／
  「编辑」（sheet 打开 LedgerFormView）。点卡进详情由 NavigationLink 改为
  Button＋既有 ledgerRoute 状态（避免 List 行的系统披露箭头与卡面自带
  chevron 叠加），zoom 转场保留（matchedTransitionSource 在卡面、
  navigationTransition 在 destination）。FAB 避让不变，底部留白改用
  contentMargins(.bottom, 72)。
- 详情页记录行：左滑「删除」（确认后进最近删除）／「编辑」——此为既有实现
  （上一轮已落），本轮复核文案与语义无误，未改。
- 备礼清单行（往来页顶部＋包 5 新增的独立页，两处同规）：左滑「删除」
  （确认后 TrashStore.archive(record:) 进最近删除）／「已送出」
  （status 置 LiqianConstants.sentStatus，与记录表单改状态同一口径，
  送出后开始计入差额）。

## 包 4：返回时 Tab 栏延迟 ✅

- 根因确认：`.toolbar(.hidden, for: .tabBar)` 全仓仅两处——LedgerDetailView、
  PersonDetailView。pop 后 SwiftUI 用独立动画补显 Tab 栏，必然慢半拍；
  且当初隐藏的理由（详情页底部行动栏与 Tab 栏打架）已随 v2.4 行动栏删除消失。
- 两处隐藏全部移除（grep `toolbar(.hidden` ＝ 0）。
- LedgerDetailView 的 FAB 改为与列表页一致的 tabBarClearance（92）避让。
- PersonDetailView 无 FAB：其底部双按钮是 safeAreaInset，Tab 栏恢复显示后
  自动落在栏上方，不被遮挡，无需改动（已在代码注释里写明）。

## 包 5：「我的」按大厂设置页重组 ✅

依据 Apple HIG 与微信/iOS 设置结构（GitHub 无设置页品类 skill，已核）：
设置页不放数据看板。原页顶总览统计 Section 与待回礼 Section 撤销：

- 「记录」：人情总览（→既有 StatsView，统计内容本就在那里）／
  人情年度报告（→AnnualReportView）／待回礼（→新 PendingPeopleView，
  入口行右侧带待回总金额，无待回时显示「无」）／备礼清单（→新 PrepListView，
  右侧带待送出件数）／最近删除（→TrashView，自数据组移入）。
- 「礼谱」：礼谱落款姓名（→HostNameEditView，右侧带当前值/未设置；
  用途说明降为组 footer）／示例礼簿（生成/清除按现状 toggleSamples）。
- 「外观」：主题（→AppearanceView，右侧带当前值；footer 不变）。
- 「智能」：AI 智能助手（→AISettingsView，副标题三态文案不变；组名按规格
  由「AI 智能助手」改「智能」）。
- 「数据」：导出 CSV／导出备份（JSON）／从备份恢复（覆盖恢复保持
  destructive 确认，确认文案不变）。
- 「关于」：关于礼钱账本（→新 AboutView，入口行右侧带版本号；原页脚的
  数据说明移入该页）／隐私锁 Toggle。
- PendingPeopleView 与 PrepListView 均为薄页：自带 @Query、复用既有统计口径
  与删除/标记逻辑，现有二级页（StatsView/TrashView/AISettingsView/
  AppearanceView/HostNameEditView/AnnualReportView）全部原样复用。
- 取舍（规格未给落点的三个既有功能，未擅自删除）：
  ① 人情年度报告留在「记录」组——该组 5 行，超「每组 2–4 行」指引一行；
  ② 导出 CSV 留在「数据」组（同为导出，与备份同组合理）；
  ③ 隐私锁 Toggle 放「关于」组第二行（无独立隐私组，避免单行成组）。
  如需再收，点名即可。
- 已删的死代码：overviewStat、总览用 totalReceived/totalGiven/peopleCount/
  realLedgerCount/realRecordCount 计算属性、personRoute 状态与目的地
  （待回礼行改走 NavigationLink 进 PendingPeopleView）。

## 包 6：主题色板系统化 ✅

- Palette 重构：新增 `AppThemeTokens` 令牌表（AppTheme.tokens），八项令牌
  pageBG/surface/primary/primaryFill/primaryTint/ink/sub/line，五主题定值
  逐项按规格表落码（含夜晚 fill #C4533F、黄色 tint #F8EED3 等）。
- 旧的单色 `themed()` 工厂与系统色直映射（ink=Color.primary、
  groupedBackground=systemGroupedBackground 等）全部废止，界面令牌统一由
  `token(_:)` 查表生成；旧名 groupedBackground/card/stone/hairline 保留为
  同源别名（＝pageBG/surface/sub/line），视图调用点无需逐个改名即全量生效。
  新增正名 pageBG/surface/sub/line，新代码用正名。
- 视图关键面改走令牌：所有 List/Form 页加 `.scrollContentBackground(.hidden)`
  ＋`.background(Palette.pageBG)`（我的/往来/详情/统计/最近删除/外观/AI 设置/
  落款姓名/礼簿表单/记录表单/备礼清单/待回礼/关于）；ScrollView 页（首页、
  人物页、报告页、锁屏、批量补录）原本就走 groupedBackground，令牌化后自动
  跟随。卡面走 Palette.card（＝surface）：liqianCardSurface、LedgerCoverCard、
  首页统计卡、记录表单键盘面等自动生效。标签底走 primaryTint（DirectionTag
  为 primary 13% 浅底、金额键盘快捷钮底等）自动同族。
- 例外与红线：红白事场景色 baiPrimary/baiPrimaryFill 不入主题表、保持现状
  （bai 的底/卡/墨/次/线按既有定版与红事共用中性令牌）；礼谱 PDF 自带印刷色
  拷贝，未引用 Palette，未动；分享图卡（AnnualReportCard）改走新静态定版
  令牌 paperInk/paperStone/paperLine＋印章 fixedBrand（恒朱砂 #A62B1F），
  不跟随主题；Palette.paper/gold 维持静态成品专用。
- 取舍：List 系统行底未逐行刷 listRowBackground(surface)——浅色四主题 surface
  为纯白、与系统行底同值；夜晚 surface #1E1E21 与系统深色行底 #1C1C1E 差
  2 个色阶，视觉可接受。自绘卡面（产品的主要容器）已全量走 surface 令牌。
  如需行底逐行对齐，需给各 List 行批量加 modifier，另立小项。

## 自查（本机无 Swift 工具链，未做真编译，需 CI 验）

- 括号/圆括号配平：全部 14 个改动文件 `{}`、`()` 计数相等（中途发现 MeView
  替换 Section 时吞掉 List 闭合括号一处，已定位补回并复验）。
- grep：`toolbar(.hidden` ＝ 0；`themed(` ＝ 0；`overviewStat` ＝ 0；
  `Palette.paper` 仅剩分享图卡一处（App 界面无引用）。
- 菜单顺序、侧滑文案（删除/编辑/已送出）、确认文案与既有口径逐处对齐。
