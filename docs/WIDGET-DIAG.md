# 小组件不显示真实内容 · 只读诊断（WIDGET-DIAG）

诊断时间：2026-11-08。基线：feat/v511-report-home 顶端（v5.11.0/71）。
本文件为只读诊断产物，未改任何产品代码。

## 症状

用户真机（SideStore 侧载 v5.11，账上有真实数据：待回 4 人合计 ¥2,500、
婚礼 7 笔等）主屏放「待回礼」组件（截图版式＝PendingMediumView：左英雄区
＋右名单），组件只显示空态占位：左「待回礼 / 打开礼记查看」、右「待回
名单会列在这里」，无任何真实姓名与金额。

## 占位文案的确切触发条件（先把症状翻译成代码状态）

两句文案同属 PendingMediumView，且**只在 `entry.summary == nil` 时出现**：

- 「打开礼记查看」：PendingWidgets.swift:237，hero 的 else 分支
  （`if let s = entry.summary` 不成立时）。
- 「待回名单会列在这里」：PendingWidgets.swift:265，list 的 else 分支
  （同一条件）。

**与「待回为空」严格区分**：若快照解码成功但 pendingCount==0，界面是
另一套——左「暂无人情待回 / 账都清了」、右列改显「本月收礼 / 本月送礼」
两行（PendingWidgets.swift:224-231、:248-257）。截图不是这套，所以本案
的确定状态是：**Widget 侧 `SummaryStore.load()` 返回了 nil**。

`load()`（Sources/LiqianWidget/WidgetShared.swift:146-153）是一个三段
guard，三种失败同路落 nil、不可从界面区分：

1. `UserDefaults(suiteName:)` 为 nil（套件不可达）；
2. 该套件里没有 `pendingSummary` 键的数据（从没写进来）；
3. 数据解码 `WPendingSummary` 失败。

## 数据链逐环核查

### 环 1 · 发布侧（App 写）——代码层完整

- 通道：App Group 的 UserDefaults，键 `pendingSummary`，值是
  `PendingSummary` 的 JSON（Codable 默认策略）。
  Sources/LiqianApp/WidgetSummary.swift:8-11（suiteName/key）、:76-100
  （write 本体：组装→encode→set→`WidgetCenter.shared.reloadAllTimelines()`）。
- 触发点齐全：ContentView 根 `.task`（启动，ContentView.swift:160）与
  scenePhase `.active`（回前台，:188）都调 `refreshWidgetSummary()`，
  用全部记录现算（:281-302）。用户日常打开 App 即会重写快照。
- 入参同源性：待回名单由 `LedgerMath.people(from:)` 计算，与 App 内
  问账待回名单卡（用户已实测出 4 人 ¥2,500）同一口径同一数据源。
  **数据本身与计算不是断点。**
- 唯一的静默点：write 的 guard——`UserDefaults(suiteName:)` 为 nil 或
  encode 失败时**直接 return、无日志无提示**（:97-98）。

### 环 2 · 读取侧（Widget 读）——代码层完整

- 同键同套件名读取（WidgetShared.swift:139-161），解码镜像结构
  `WPendingSummary` 与写侧字段逐一对齐（必填：pendingCount /
  pendingAmountCents / topName / updatedAt；可选：pendingTop /
  monthReceivedCents / monthGivenCents / nextReminder / peopleCount）。
- 时间线：PendingProvider/ReminderProvider 走 `SummaryStore.timeline()`，
  策略 `.after(1 小时)`，每次 getTimeline 都现读套件（:163-168）。
  发布侧另有 reloadAllTimelines 主动刷新。**刷新时序不是断点**：
  即使重载全丢，1 小时周期重读＋用户多次开 App 触发重写，数据若在
  同一容器里早该出现。

### 环 3 · 组名解析（两侧是否看同一个容器）——全案核心，未验过

- 两侧 suite 名都走 `AppGroupResolver.groupID`（LiqianCore/
  AppGroupResolver.swift:22-31）：优先读**当前进程自己** Bundle 的
  Info.plist 里 `ALTAppGroups` 首项，没有则回退常量
  `group.site.didichou.liqian`（:18）。
- 背景（文件头注释 :3-12 与 docs/V46-NOTES.md 第五节）：SideStore 的
  AltSign 重签时以 provisioning profile 为准，把真实组名改写为
  「原组名 + "." + TeamID」并写进 Info.plist 的 ALTAppGroups——**代码
  硬认原组名必然对不上**，这是 v4.6 加解析器的原因。解析器注释同时
  自承：扩展进程自身 plist 无此键时回退原组名。
- 外部证据（AltSign 行为）：AltServer 的 prepareInfoPlist 对主 App 与
  每个 appex **都会**写 ALTAppGroups（DeepWiki 对 AltServer-Windows
  代码梳理；另一个侧载项目实录同款「空白组件」坑、根因正是组解析，
  其结论同样是 app 与 appex 均被写入）。这压低了「Widget 侧必然回退
  原名」的概率，但有两点仓库内无从证明：①SideStore 本体（设备端
  AltSign 分支）与 AltServer 桌面端在此步是否完全一致；②免费团队上
  这个 App Group 是否真的**建成并配发**进了 Widget 的 profile
  （组注册失败/配发缺组时，两侧解析再对齐也无容器可用）。
- entitlements 声明侧齐全：Project.swift 三个 target 同为
  `group.site.didichou.liqian`（:111-113、:161-163、:184-186）。
- **历史状态（关键）**：docs/V46-NOTES.md「待验清单」第二项原话——
  「真机：App Group 共享是否真的通（小组件读到速览…）」自 v4.6 起
  挂账**从未验过**；v5.1 组件重做的真机上桌同样一直未验（见各版
  NOTES）。即：这条链在侧载真机上**从来没有被证明通过过一次**，
  不是「曾经好过、后来改坏」。

### 环 4 · 预签覆盖面——声明在，配发不在其管辖内

CI「Ad-hoc presign」步（.github/workflows/ios-native.yml:65-137）对主
App 与遍历到的每个 appex 都 ad-hoc 签入含 application-groups 的
entitlements，并逐二进制断言组名在位（v5.11 出包链含此步、已绿）。
它保证 AltSign「读得到声明、知道要建组」；**不保证**免费团队上组真
建成、也不保证 SideStore 给 appex 的 profile 最终带组。故「预签没
覆盖组」作为独立假设排除；「配发/建成失败」并入环 3。

### 环 5 · 跨版本兼容——排除

必填字段自 v2 首版至今未变（git log -S 实证：topName 在 1d7d498 已在）；
其后新增字段全部可选（pendingTop 等于 v4.5 套件扩展提交 8ca96ba、
peopleCount 于 v5.1 提交 c89c567），旧快照在新 Widget 里解码为 nil
字段降级、不会整份失败。且环 1 表明 App 每次启动/回前台都重写快照，
不存在「旧快照长期滞留」的窗口。**解码漂移排除**（它与无文件同路落
nil 的代码事实成立，但不是本案成因）。

### 环 6 · v5.9–v5.11 是否碰过组件链——排除

`git diff feat/v59-appearance..feat/v511-report-home` 对
WidgetSummary.swift / WidgetShared.swift / AppGroupResolver.swift /
ContentView.swift / LiqianWidget 全部文件**零改动**，组件链文件仅
Project.swift 的版本号字面量变化。三片施工没有动过发布或读取代码。

## 结论（按证据排序）

**断点在环 3：共享容器这一环——App 与 Widget 至少一侧没落到同一个
真实 App Group 容器上。** 依据：症状对应的代码状态唯一（summary==nil）；
写、读、模型、刷新四环代码层全部完整且同源数据在 App 内实测正常；
唯独「容器是否真共享」这一环自 v4.6 起从未在侧载真机上验证通过，
且全链每处失败都是静默 nil（写侧 guard、读侧 guard 各一处），设计上
不会给出任何报错——与「装了多版、一直空白、App 内一切正常」的表象
完全吻合。

代码层无法再分的三个子情形（须真机判读，见下）：

- (a) App 侧 suite 为 nil → 快照从没写成；
- (b) 两侧组名解析不一致（一侧命中 ALTAppGroups、一侧回退原名）
  → 写读异容器；
- (c) Widget 的 profile 缺组/组未在免费团队建成 → 读侧恒 nil。

## 零成本真机判读（不需要新包）

**判读 A（验容器方向性，最关键）**：放大尺寸「待回礼」组件（带
「记一笔」真按钮，OpenQuickRecordIntent，Sources/LiqianWidget/
WidgetIntents.swift:17-22：Widget 进程往同一 resolver 套件写
`openQuickRecord=true` 并唤起 App）。在 App 已解锁状态下点该按钮：
App 被打开是必然的（openAppWhenRun）；**记一笔表单自动弹出**＝标记被
App 读到，容器在 Widget→App 方向通，断点收窄到写侧/读侧其一；
**不弹**＝容器至少此方向不通，环 3 坐实。

判读 B（辅助）：删掉组件重新添加、打开一次 App 后等 1 分钟仍空——
排除时间线未刷新的残余可能（预期仍空，与环 2 分析一致）。

## 最小修复方案（未施工，供拍板）

1. **先加可观测性（无论根因是哪个子情形都该先上）**：全链静默 nil
   是本案拖了多版没被发现的根本原因。建议设置页加一行「小组件数据」
   自检：App 侧显示解析到的组名、最近一次写入时间、写后回读是否
   命中；Widget 空态区分「尚未收到 App 数据」。修完任何一环都靠它
   当场验收，不再靠猜。
2. **解析对齐加固（对应子情形 b）**：Widget 侧读不到时增加回退路
   ——候选组名（含原名与 ALTAppGroups 全部项）逐个尝试；可用性判据
   换用 Share 扩展已有的更严口径（ShareViewController.swift:27-31
   以 containerURL 非 nil 判「组真可用」），而不是裸 UserDefaults。
3. **若判读坐实 (a)/(c)（组未建成/配发缺组）**：属 SideStore 免费
   团队的配发层问题，App 代码改不了配发本身——现实处置是 SideStore
   内删除重装礼记（重走一遍配发）后立刻用判读 A 复验；须如实告知
   用户这是环境层问题、不是 App 内能自愈的。此前各版 NOTES 里
   「小组件待验」应改口径为「已知侧载环境下未通」，不再当普通待验
   项滚动。

以上 1、2 为代码侧小改（限于 WidgetSummaryWriter / SummaryStore /
AppGroupResolver 与设置页一行），3 为操作侧处置。本诊断不动代码。
