import Foundation

/// 备份提醒（v4.5，差距报告 Top 6 的 S 级件）：手动备份链路本身早已完整，
/// 缺的是「用户很久没备份时有人提醒一句」。口径刻意克制：
/// 只在「我的 → 数据」区内嵌一行，不发推送、不弹窗，点行即开始导出。
enum BackupReminder {
    /// 上次成功导出 JSON 备份的时间（timeIntervalSince1970；0/缺省＝从未备份）。
    /// MeView 用 @AppStorage 读同一 key 订阅刷新，导出成功回调里写它。
    static let lastBackupAtKey = "lastBackupAt"

    /// 超过多少天算「旧备份」
    static let staleDays = 30

    /// 提醒文案：不需要提醒时返回 nil。
    /// - hasData 为假（只有示例或空账）不提醒：提醒的对象是「有真账没备份」的人，
    ///   空 App 首启就挂备份警告只是噪音。
    /// - 从未备份（last == nil）→ 提醒；距上次 > staleDays → 带天数提醒。
    static func reminder(
        hasData: Bool,
        lastBackupAt: Date?,
        now: Date = Date()
    ) -> (title: String, subtitle: String)? {
        guard hasData else { return nil }
        guard let lastBackupAt else {
            return (
                title: "还没有导出过备份",
                subtitle: "账目目前只在这台手机里。点按导出一份 JSON 备份存好，换机、重装都不怕。"
            )
        }
        let days = Calendar.current.dateComponents([.day], from: lastBackupAt, to: now).day ?? 0
        guard days > staleDays else { return nil }
        return (
            title: "上次备份是 \(days) 天前",
            subtitle: "这段时间的账目还没进备份。点按再导出一份，存到文件或 iCloud 里。"
        )
    }
}
