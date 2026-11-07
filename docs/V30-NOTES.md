# V30-NOTES · 人情提醒（v3.0）

本地通知两类：重要日子提醒＋待回礼超期汇总提醒。无服务器，全部
UNUserNotificationCenter 本地排期。未 commit/push；本机无 Swift 工具链，
未做真编译，需 CI 验证。括号配平（10 个改动 Swift 文件全平）与 grep 自查已过。

## 改动清单

**新增**
- `Sources/LiqianCore/Reminders.swift`：纯计算层——`ReminderDayValue`（模型镜像）、
  `ReminderMath`（下一次日子/触发时刻/倒计时/日期注记）、`OverduePerson`、
  `PlannedNotification`、`ReminderPlanner`（日子排期、待回判定、待回月度排期、合并封顶 60）。
- `Sources/LiqianApp/ReminderScheduler.swift`：App 层薄封装——授权查询/请求、
  按 Core 计划全量重排（先清 `liqian.reminder.` 前缀旧请求再添加，
  UNCalendarNotificationTrigger 不重复）、设置读 UserDefaults。
- `Sources/LiqianApp/RemindersView.swift`：人情提醒页（列表＋待回设置区＋授权横幅）
  与 `ReminderDayFormView`（原生 Form 新建/编辑）。
- `Tests/LiqianCoreTests/ReminderTests.swift`：11 个用例（见下）。

**修改**
- `Sources/LiqianCore/Models.swift`：LiqianConstants 加提醒常量（类型/历法/提前天数选项）；
  新增 `@Model ReminderDay`（独立模型，不挂 Ledger/GiftRecord；person 姓名对齐人物）。
- `Sources/LiqianCore/Backup.swift`：`BackupFile` 加可选段 `reminders`
  （`BackupReminderDay`，自定义解码带默认值）；`makeBackup` 加 `reminders` 参数（默认空）；
  新增 `parseBackupFull`（旧 `parseBackup` 签名不变、内部转调）。
- `Sources/LiqianApp/LiqianApp.swift`：modelContainer 注册 ReminderDay。
- `Sources/LiqianApp/MeView.swift`：「记录」组加「人情提醒」入口（右侧带已设日子数）；
  导出备份带 reminders；恢复时删旧提醒、按备份插入，并按新数据立即重排；
  确认弹窗与完成文案带提醒计数（无提醒时不提）。
- `Sources/LiqianApp/PersonDetailView.swift`：同名人物有日子时多一张「重要日子」
  只读卡（类型＋农历/公历注记＋倒计时＋停用标记），底部「管理提醒」跳人情提醒页。
- `Sources/LiqianApp/ContentView.swift`：启动 `.task` 加提醒校准（口径同提醒页，
  示例账本记录不计入），防系统清排期、授权变化后跟上。

## 功能口径

- 重要日子：每年重复；提前 0/1/3/7 天（默认 3）上午 9:00 推送。
  触发已过（如提前量大于距今天数）顺延到下一年那一次；只排未来 12 个月内、
  每人一条（下一次）。停用的不排。
- 待回礼提醒：默认关；开关＋超过天数（15/30/60/90，默认 30）在提醒页设置区，
  存 UserDefaults（`pendingReminderEnabled`/`pendingReminderDays`）。
  判定＝待回金额 > 0（LedgerMath.people 净差额口径）且距最近一笔收礼
  达到设定天数。排期最多每月一条：已有人超期→明天 9:00 首报，否则在最早一人
  达到超期那天首报，此后逐月；每条正文按触发日投影名单写（假设此后无新往来）。
- 文案：标题恒「礼钱账本」。日子类如「3 天后是 大舅 的生日（农历十月初八）。」
  待回类如「张三 的礼已收下 32 天，还没回。」多人时点最久一位＋「另有 N 位」。
  不煽情、不催债、无营销词。
- 授权：进提醒页时查状态，.notDetermined 就地请求（系统只弹一次）；
  .denied 时页顶横幅明示「通知未开，提醒不会推送」＋「去系统设置打开通知」按钮。
- 重排触发点：提醒页内任何日子/设置变化（onChange 数据签名）、恢复备份后、
  App 启动校准。表单只写数据，重排收敛在列表页与调度器。

## 农历换算口径（ReminderMath.lunarNext）

- 实现：从今天起逐日步进，用 .chinese 日历分量匹配月/日，上限 800 天。
- **闰月：只认正月**（isLeapMonth == false）。闰月里设的日子（现实中多为闰月
  出生）按同名正月过；目标月当年有闰月时，正月在前、先命中正月。
  单测以 2025 闰六月验证：六月十五命中正六月 2025-07-09，非闰六月。
- **小月：** 农历某月只有 29 天而日子设为 30 时，按该月最后一天（廿九）算
  （单测在 2026 年内动态找出一个 29 天的正月验证回退到 29 日）。
- 公历 2 月 29 日：平年按 2 月 28 日，闰年用回 29 日（单测覆盖）。

## 备份兼容

- 新备份顶层多 `reminders` 数组键；旧备份无此键 → parseBackupFull 返回空数组，
  恢复时提醒被清空（与「覆盖恢复」语义一致），礼簿/记录不受影响。
- 旧版 App 读新备份：未知键忽略（既有口径），礼簿/记录可正常恢复、提醒段丢弃。

## 单测（ReminderTests，11 例）

公历生日下一次（含当天命中、已过跳年）／2 月 29 日平年回退／农历十月初八
换算（锚点 2026-11-16）／闰六月按正月／农历小月 30 日回退月末／日子排期
触发时刻（提前 3 天→11-13 09:00）与正文逐字／停用不排＋错过提前量顺延出窗／
待回判定（33 天入选、6 天不选、两清不选）／待回月度排期（明天首报、12 条封顶、
次月汇总正文）／备份提醒往返／旧备份无段解析为空。

## 真机待验

- 首次进提醒页授权弹窗与拒绝后横幅、设置跳转回来后横幅消失（需回前台刷新状态——
  当前实现进入页面时查一次，从设置改完返回需重新进入本页才刷新横幅）。
- 农历生日跨年推送时间点（建议设一个明天到期的农历日子实测）。
- 待回提醒打开后首条在明天 9:00 到达；每月一条不叠加。
- SideStore 重签下通知权限与排期是否随覆盖安装保留。
