# v5.11.1 施工说明（小组件数据显示链：自检可观测性＋组名解析加固）

版本：5.11.1/72。分支：feat/v5111-widget-diag（基线 feat/v511-report-home）。
背景与根因范围见 docs/WIDGET-DIAG.md：真机 Widget 的 SummaryStore.load()
恒 nil，断点锁定在 App Group 共享容器环，代码层分不开三个子情形——
(a) App 侧 suite 为 nil 从没写成；(b) 两侧组名解析不一致、写读异容器；
(c) Widget profile 缺组/组未在免费团队建成。本版不宣称已修复：本版交付
的是「让真机一张截图就能定案」的观测能力＋读侧多候选加固。若子情形是
(c)（配发层），处置在 App 代码之外（SideStore 删除重装后复验），本版
自检正是为区分这一点而建。**真机未验。**

## 做了什么

### 1. 设置页自检行「小组件数据」（我的 → 数据组 → 小组件数据）

入口行副标题是一句摘要（WidgetDiag.Status.summaryLine）：最近写入
时间＋回读是否命中 / 通道不可用 / 尚无记录。详情页 WidgetDataView
三段，全字段来自真实探活与镜像记录，不推测：

| 段 | 字段 | 来源 |
|---|---|---|
| 写入状态 | 解析组名（全文，可长按复制） | AppGroupResolver.groupID |
| | 数据通道：可用/不可用 | UserDefaults(suiteName: 解析名) 是否非 nil |
| | 组容器（配发）：存在/不存在 | containerURL 严口径（AppGroupResolver.containerAvailable） |
| | 最近一次尝试 / 尝试结果 | standard 镜像 widgetDiag.attemptAt / .result |
| | 最近写入（时间·字节数） | standard 镜像，缺失时以解析名 suite 的元键补 |
| | 写后回读：命中/未命中/无记录 | 写入时当场回读的字节比对结果 |
| 备用通道 | 全部候选逐个探活：组名＋状态（有数据·N 字节·写入时间 / 通道在暂无数据 / 通道不可用 / 组容器不存在） | 对 candidateGroupIDs 逐家 UserDefaults＋containerURL 现查 |
| 组件回执 | 组件实际读到的组名 / 回执时间 / 尚未收到 | 各候选 suite 内的回执键，任一家命中即呈现 |

### 2. Writer 可观测化（WidgetSummaryWriter.write）

原 guard 的两条静默 return 改为落记录，**写入时机与 reload 口径不变**
（仍由 ContentView 启动/回前台触发，仍只在成功路径 reloadAllTimelines）：

- 每次尝试先往 UserDefaults.standard 镜像记 attemptAt＋当次解析组名；
- suite 为 nil → 镜像 result="suiteNil"；编码失败 → "encodeFailed"；
- 成功：快照照旧写 pendingSummary；同 suite 另写元键
  widgetDiagWrittenAt（时间戳）、widgetDiagBytes（字节数）、
  widgetDiagReadbackOK（写后立即回读、字节全等才 true）；镜像记
  result="ok"＋writtenAt＋bytes＋readbackOK。
- 范围外未动：writeLedgerList 的同款静默 guard（分享扩展通道，非本案
  数据链）、WidgetIntents 的 openQuickRecord 写入（仍单组名）。

### 3. 读取加固（Widget 侧 SummaryStore.load 多候选）

候选集构造（LiqianCore.AppGroupResolver.candidateGroupIDs，纯函数＋
单测钉死）：顺序即优先级、去重保序——
1. 本进程解析名（ALTAppGroups 首项，无则原名）打头；
2. ALTAppGroups 全部项（不只首项，两侧 plist 项序可能不同）；
3. 原始组名 group.site.didichou.liqian（解析名带后缀时，它同时就是
   「去 TeamID 后缀」变体）；
4. TeamID 变体：从已知名提取到的 TeamID 后缀（10 位大写字母/数字）
   补到原名之后（「补后缀」变体）。
诚实注记：以现行 AltSign 的改写形状，第 3、4 条与集内成员重合（去后缀
即原名、补后缀即带后缀的已知名），属防御性冗余；本版候选的实际新增
覆盖来自第 2 条（ALTAppGroups 全部项）与第 1、3 条的跨进程组合——
Widget 进程解析名与 App 写入家不一致时，靠全部项＋原名兜住。

load 逐候选试 suite＋pendingSummary 键＋解码，命中哪家用哪家，并往
命中的那家 suite 写回执键 widgetReceiptGroup（命中组名）＋
widgetReceiptAt（时间戳）。App 侧 Writer 维持只写解析名一家，不向
多家群发，避免同一数据多容器分叉。其余组件行为、数据模型、时间线
策略（.after(1 小时)＋reloadAllTimelines）一律未动。

## 三种子情形 × 预期自检读数对照表（真机定案用）

装 v5.11.1 后：打开一次礼记（等几秒）→ 回桌面看组件 → 截「小组件
数据」详情页全页。对照下表定案：

| 读数 | (a) App 侧从没写成 | (b) 两侧组名不一致 | (c) 组未建成/配发缺组 |
|---|---|---|---|
| 数据通道（UserDefaults 判据） | 不可用 | 可用 | 可用或不可用（两侧配发独立） |
| 组容器（配发） | 不存在（多半） | 存在 | App 侧存在、Widget 侧不存在（App 侧看不到 Widget 侧） |
| 尝试结果 | 失败：数据通道不可用 | 成功 | 成功（写进 App 自己的容器） |
| 写后回读 | 无记录 | 命中 | 命中（自写自读自洽） |
| 备用通道第一家（＝解析名） | 通道不可用/组容器不存在 | 有数据 | 有数据（App 侧探活恒是 App 视角） |
| 组件回执 | 无 | **出现，且回执组名＝App 解析组名 → 组件应已恢复显示** | 恒无 |
| 桌面组件 | 空态占位 | 恢复显示真实数据（多候选命中）或仍空（候选未覆盖到对家名） | 空态占位 |

判读要点：
- **回执是最硬的证据**：有回执＝组件真读到过数据，回执组名即它命中
  的那家；回执组名与 App 解析组名不同，说明组件是从备用通道读到的
  （子情形 b 被多候选兜住的实证）。
- 写入全绿（成功＋回读命中＋第一家有数据）但长期无回执：数据落在
  Widget 到不了的容器——(a) 的变体（写进 App 隔离容器）或 (c)，
  两者在 App 侧读数相同，靠判读 A（大尺寸组件点「记一笔」看表单
  是否自动弹出，WIDGET-DIAG 已述）或直接重装复验区分，属配发层
  处置，不再改 App 代码猜测。
- 备用通道里只有非第一家有数据：App 写入家不是自检解析的这家
  （解析名漂移），把该组名全文发回即可定位。

## 验收（CI 侧，待回填）

- CI run：（待回填）
- 单测：（待回填；基线 293，新增候选集构造单测 8 例）
- 解包验：（待回填；预期 App/Widget 均 5.11.1/72、PlugIns 仅
  LiqianWidget.appex、无 LiqianShare.appex）
- 零改动确认：AnalyzerFeeder、问账全链（Advisor*）、Widget 数据模型
  与时间线策略未动（diff 文件清单可核）。

## 真机待验（不宣称已验）

1. 装包后打开礼记一次，回桌面：组件出真实姓名金额，或仍空态——
   两种结果都按上表截图定案，不再以「出没出数据」二分验收。
2. 「小组件数据」详情页全页截图回传（写入状态/备用通道/组件回执
   三段都要入镜）。
3. 若回执出现：核对回执组名是否等于解析组名（同名＝正路打通；
   异名＝备用通道兜住，记录异名全文）。
4. 顺带回归：问账出卡、语音转写、换图标各点一次（本版未动这些链，
   只作生死线确认）。
