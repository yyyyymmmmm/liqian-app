# 小组件套件（v4.5 · feat/widgets）交付说明

按大厂标准（多尺寸＋锁屏＋可交互＋隐私脱敏）补齐整套小组件。分支只落码未 commit，
父级合并后过 CI；本机无 Xcode，编译结论以 CI 为准。

## 落点清单

### 共享快照扩展（只加可选字段，旧字段语义不动）
- App 侧 `Sources/LiqianApp/WidgetSummary.swift`
  - `PendingSummary` 新增可选字段：`pendingTop`（待回前 5，金额降序）、
    `monthReceivedCents`、`monthGivenCents`、`nextReminder`（title/person/occurrence）。
  - `write` 签名扩展为 `write(people:monthReceivedCents:monthGivenCents:nextReminder:)`，
    唯一调用方 ContentView 已同步。
  - 新增 `nextReminder(from:)`：启用日子中下一次 occurrence 最早者，
    与提醒排期共用 Core 的 `ReminderMath.nextOccurrence`（农历口径一致）；
    occurrence 只存日期，剩余天数由 Widget 按当天现算，隔夜不显错数。
  - 兼容：新字段全 Optional——旧快照被新 Widget 解码为 nil → 降级旧版式；
    新快照被旧 Widget 读时多余字段被忽略。双向兼容。
- Widget 侧镜像结构在 `Sources/LiqianWidget/WidgetShared.swift`（WPendingSummary 等）。
- ContentView `refreshWidgetSummary()`：本月口径＝记录 date（yyyy-MM-dd）前缀匹配
  当前年月；随礼只计已送出（待送出不算，同 PersonSummary.given 口径）；
  数据源与旧字段同源（全部记录，不做示例隔离——既有口径未动）。

### 桌面三尺寸（kind 沿用 "LiqianWidget"，老摆放原地升级）
`Sources/LiqianWidget/PendingWidgets.swift`
- small：待回总览——人数大字＋总金额＋「最多的是 X」（沿用旧版式＋privacySensitive）。
- medium：左＝待回前 3 人列表，点行 Link 深链直达人物；右＝「记一笔」真按钮。
- large：待回前 5 人列表＋本月收礼/送礼概览＋下一个重要日子一行。
- 空态（无快照/App Group 不通）：只给「打开礼记查看」引导，不编数据不崩。
- 组件库预览（isPreview 且无真实数据）：示例数据＋「示例」角标，示例行不挂深链。

### 锁屏小组件（同一 Widget 的 accessory 家族）
- accessoryCircular：待回人数＋「待回」；无数据时显示「礼」字标。
- accessoryRectangular：待回 N 人＋待回最多一位姓名与金额；金额 privacySensitive。
- 两款点按均深链直达待回最多那位的人物页（无数据/示例时不挂链）。

### 交互
- medium「记一笔」＝`Button(intent: OpenQuickRecordIntent())`
  （`Sources/LiqianWidget/WidgetIntents.swift`）：与快捷指令同机制——
  perform 在扩展进程往 App Group 写 `openQuickRecord` 标记＋openAppWhenRun 唤起 App，
  ContentView.checkQuickRecord 回前台读标记弹表单。不新造通道。
- 人物行/锁屏/倒计时点按走新深链 `liqian://person/<姓名 URL 编码>`。

### 倒计时组件（新 kind "LiqianReminderWidget"）
`Sources/LiqianWidget/ReminderWidget.swift`：small＝日子名＋大天数＋日期；
medium＝左信息右大天数。天数为 0 显示「今天」。点按深链到该人物页。

### 深链清单（liqian scheme，已注册）
| 深链 | 来源 | 承接 |
|---|---|---|
| `liqian://quick-record` | small 点按、意图标记 | ContentView → 记一笔表单（既有） |
| `liqian://blessing/<id>` | 礼谱二维码 | ContentView → 祝福播放（既有） |
| `liqian://person/<姓名编码>` | medium/large 列表行、锁屏两款、倒计时 | ContentView → 切往来页＋`personDeepLinkName` 绑定 → PeopleView 消费置 `personRoute` 打开人物详情（本轮新增） |
- 解析/生成在 Core `LiqianDeepLink.personURL/personName`（percentEncodedPath 只解一次码）。
- 承接守卫与既有深链一致：隐私锁锁定时不承接；姓名已不在往来名单时静默作罢不硬跳。

### Live Activity（现场模式）——结论：低风险，已落码
- 可行性：仅用本地 ActivityKit（request/update/end），不走 APNs 推送，
  不需要推送证书与服务器；类型定义放 Core（App 与 Widget 共享）。
  风险点只在运行时可用性（系统授权、重签环境），代码侧已全量静默降级：
  `areActivitiesEnabled` 为假或 request 抛错都当功能不存在，现场主流程零影响。
- 落点：
  - `Sources/LiqianCore/SceneActivity.swift`：`SceneActivityAttributes`
    （静态：礼簿名/白事；状态：笔数/合计/最近一位）。
  - `Sources/LiqianWidget/SceneLiveActivityWidget.swift`：锁屏横幅＋灵动岛
    （expanded/compact/minimal），金额 privacySensitive。
  - `Sources/LiqianApp/SceneLiveActivity.swift`：`SceneLiveActivityController`
    （start 已有进行中只更新不重建；update；end 全收）。
  - `Project.swift`：App InfoPlist 加 `NSSupportsLiveActivities: true`（无此键必失败）。
  - `SceneModeView` 最小钩子三处：onAppear 开（带本场当前进度）、
    save() 成功后 update、onDisappear end（复核单是 sheet，弹出不误触发）。

### 入口结构变化
- Widget 扩展 @main 由单个 Widget 改为 `LiqianWidgets: WidgetBundle`
  （`Sources/LiqianWidget/LiqianWidget.swift`），含 PendingWidget＋ReminderWidget
  ＋SceneLiveActivityWidget；共享底座在 `WidgetShared.swift`
  （WPalette 改 internal 供多文件共用，色值未动）。

## 真机待验项（重签环境重点）
1. **App Group 存活**：SideStore 重签后 App 与 Widget 是否同组
   （group.site.didichou.liqian）——不通时全部组件应为空态引导（已按此降级），
   不崩、不显示假数据；通了之后记一笔/改数据回前台应能刷新（Writer 写后
   reloadAllTimelines＋每小时时间线兜底）。
2. **锁屏两款**：添加入口是否出现（accessory 家族需系统提供锁屏编辑位）、
   锁定状态下金额是否被系统打码（privacySensitive 生效与否）。
3. **medium 记一笔按钮**：点按是否唤起 App 并弹出记一笔表单
   （openAppWhenRun＋标记通道）；从锁屏点按时的解锁交互。
4. **人物深链**：中文姓名编码往返（生僻字/含空格姓名）、人物已删除时点旧组件行、
   隐私锁开启时点组件（预期：解锁后停在原页面，不自动跳人）。
5. **Live Activity**：重签下 Activity.request 是否成功、锁屏横幅与灵动岛渲染、
   系统设置里「实时活动」开关关闭时的静默降级、连续进出场不残留横幅
   （start 去重＋onDisappear end）；若重签环境实测不可用，关法＝
   删 Project.swift 的 NSSupportsLiveActivities 并摘掉 SceneModeView 三处钩子，
   其余套件不受影响。
6. **倒计时跨日**：occurrence 为明天时，今晚与明早显示的天数是否正确翻篇
   （天数视图现算＋时间线每小时刷新双保险）。
7. 大尺寸在小屏机型（SE 类）上 5 行＋本月概览是否溢出裁剪。

## 红线自查
- 未改数据模型、未改待回口径（pending=max(balance,0)，仍走 LedgerMath.people）。
- 快照只扩展可选字段，旧字段语义与既有刷新时机（启动/回前台）未动。
- 无快照＝空态引导，示例只出现在组件库预览且带「示例」标。
