# v4.5 第一组落码说明（feat/v45-core，仅落码未 commit）

范围：隐私合规（PrivacyInfo ×2＋隐私政策/用户协议内置页）＋四个 S 级小件
（Quick Actions、备份提醒、评分引导、反馈入口）。口径对齐
`~/workspace/research_notes/liqian-bigfactory-gap-20261107/report.md` Top 1/6/8/9 与③排期。
红线遵守：未动数据模型、待回口径、术语与五主题色板；未碰礼谱 PDF 生成逻辑。

## 1. PrivacyInfo.xcprivacy（两份，均已用 plist 解析器验合法）

- App：`App/Resources/PrivacyInfo.xcprivacy`（App target 已有 resources glob
  `App/Resources/**`，自动进包，不需改工程引用）。
- Widget：`WidgetResources/PrivacyInfo.xcprivacy`；Project.swift 给 Widget target
  新增 `resources: ["WidgetResources/**"]`（扩展是独立 bundle，必须自带）。

申报依据＝2026-11-07 全仓实测，不抄模板：

- Required Reason API 只有 **UserDefaults** 一类命中。文件时间戳
  （attributesOfItem/resourceValues）、磁盘空间（volumeAvailableCapacity）、
  系统启动时间（systemUptime/mach_absolute_time）、活跃键盘四类全仓零调用，未申报。
- App 的 UserDefaults 有两种用法 → reasons 两个都报：
  `.standard`（设置/标记，SampleData/CloudSync/主题等）→ `CA92.1`；
  `suiteName: group.site.didichou.liqian`（WidgetSummary 通道、checkQuickRecord）
  → `1C8F.1`。
- Widget 只用组级 suite（WidgetShared/WidgetIntents）→ 只报 `1C8F.1`。
- 数据收集：App 申报一项 `OtherUserContent / AppFunctionality、未关联、未跟踪`，
  对应唯一离设备的数据流——用户自备 Key 启用 DeepSeek 后、主动提交解析的文本直连。
  **iCloud 私有库数据未申报**：数据在用户自己的 iCloud 账户、开发者无访问，
  按 Apple 口径不属开发者「收集」；此判断请合并时知悉，若上架审核口径有变再补。
- 两份均为 NSPrivacyTracking=false、无跟踪域名。

## 2. 隐私政策 / 用户协议（内置页）

- `Sources/LiqianApp/Legal.swift`：LegalDoc/LegalSection 结构＋两份正文＋LegalView
  （ScrollView 分节排版、可选中复制、离线可读）。
- 入口：MeView 的 AboutView 新增一 Section——隐私政策／用户协议／意见反馈三行，
  与关于页原有数据说明同页、同口径（冲突以法律页为准，正文里已声明核心原则）。
- 正文事实全部来自代码核实：本地优先、无账号无服务器、CloudKit 私有库同步、
  DeepSeek 自备 Key 存本机 Keychain（DeepSeek.swift KeychainStore）、提交文本直连
  且撰序只发事由/日期/地点/主家名/人数不含金额、OCR 为 Vision 端上识别照片不上传、
  无分析/无广告/无 IDFA、备份未加密由用户保管、最近删除 30 天。

## 3. Quick Actions（长按快捷菜单）

- 静态两项在 Project.swift 的 App infoPlist 注入 `UIApplicationShortcutItems`：
  记一笔（plus.circle.fill）、查看待回礼（gift.fill）；type 串与
  `Sources/LiqianApp/ShortcutActions.swift` 的常量一一对应（两处注释互指）。
- 承接：新增 `LiqianAppDelegate`（LiqianApp.swift 挂 `@UIApplicationDelegateAdaptor`），
  冷启动读 `launchOptions[.shortcutItem]`、运行时走 `performActionFor`，两路都只调
  `ShortcutActions.handle` 写标记＋发通知，不新造通道：
  记一笔写 App Group 的 `quickRecordKey`（与 Intent/小组件同一通道）；
  查看待回礼写 standard 标记 `shortcutShowPending`。
- ContentView 消费点四个：`.task`、scenePhase 回前台、新增
  `.onReceive(.liqianShortcutAction)`、以及 checkQuickRecord 既有路径。
  守卫与深链一致：记一笔走 presentQuickRecord 既有守卫（无礼簿不弹、锁定时不弹）；
  查看待回礼锁定时消费即丢弃、不补跳（与 liqian://person 口径一致），解锁后切「往来」Tab。

## 4. 备份提醒

- `Sources/LiqianApp/BackupReminder.swift`：key `lastBackupAt`（timeInterval 秒）、
  规则纯函数 `reminder(hasData:lastBackupAt:now:)`。
- MeView：`@AppStorage` 订阅同 key；fileExporter 完成回调改为 switch，
  **仅 .success 写时间戳**（取消/失败不记）；数据 Section 在恢复行后条件显示提醒行，
  点行与导出行共用抽出的 `startBackupExport()`。不推送、不弹窗（按任务口径）。
- 一处口径决定：`hasData` 用已排除示例账本的 `snapshots` 判定——只有示例数据时
  不提醒，避免新用户被噪音打扰；「从未备份」文案据此只对有真账的人出现。

## 5. 评分引导

- `Sources/LiqianApp/ReviewPrompt.swift`：条件纯函数——累计真实记录 ≥20 笔
  ＋距上次请求 ≥120 天（key `lastReviewRequestAt`）。
- 唯一触发点：LibuExportView `generate()` 成功分支 → `maybeRequestReview()`：
  先 markRequested 再延迟 1.2 秒 `requestReview()`（等预览与成功震动落地）；
  失败分支永不触达。为算累计数给该 View 加了 allRecords/allLedgers 两个 @Query，
  计数排除示例账本。About 页无任何评分诱导文案（按任务口径不加手动入口之外的诱导）。

## 6. 反馈入口

- `Sources/LiqianApp/Feedback.swift`：`FeedbackMail.address` 常量＋mailto URL
  （标题「礼记反馈（v4.5）」为本版交付字面量，后续大版本同步改这一处；
  正文模板含设备型号 utsname 标识、iOS 版本、应用版本三行，自动填好可改）。
- AboutView 以 Link 整行呈现，右侧带邮箱地址明示。

## 版本

Project.swift 三处口径统一升 4.5.0 / 45：工程 base settings、App infoPlist 字面量、
Widget infoPlist 字面量（v4.4 实证口径：只有 plist 直写才进包）。

## ⚠️ 待用户确认（不确认不算完成）

1. **反馈邮箱 support@didichou.site 是否真实可收件**——Feedback.swift 常量处与本文件
   均已醒目标注；若不可用，反馈入口等于摆设，需换地址（只改 FeedbackMail.address 一处）。
2. **隐私政策/用户协议正文请用户过目**——措辞已按事实写，但法律文本对外发布前
   应由用户（知和数智）确认；文中联系邮箱同为 support@didichou.site，同第 1 条绑定。
3. **生效日期占位为「2026 年 11 月」**（Legal.swift 两份文档 effectiveLine）：
   正式对外前确认是否需要落到具体日期；运营主体写「知和数智」，如需全称
   （含「有限公司」等工商登记全称）请一并给出后替换。

## 验证边界

本机无 Swift 工具链/tuist，未做编译与 tuist generate 验证；已做：逐文件 diff 自审、
新文件括号平衡、两份 xcprivacy 的 plist 合法性解析。最终以父级合并后的 CI 为准。
风险点提示（CI 重点看）：Project.swift 的 UIApplicationShortcutItems 字典结构经
Tuist 生成 plist 的形态、Widget target 新增 resources 后的打包路径、
AppDelegate adaptor 与既有 SwiftData 容器装配无冲突。
