import Foundation
import LiqianCore
import SwiftData
import os

/// 保存链 App 侧共用辅助（v5.14.1）：六个落库入口统一走这里。
///
/// 契约（审计 A5 的修法）：真 save；成功才返回 true，调用方才许继续
/// 落印/dismiss/报数/置「已入账」等成功反馈；失败记一行可诊断日志
/// （错误原文只进日志、不进 UI），并把统一人话文案交给 onFailure
/// 呈现，调用方必须显形且保留用户已填内容。成败分发逻辑在 Core
/// 的 SaveFlow（纯函数单测钉死），本文件只接真 ModelContext。
enum SaveSupport {
    private static let logger = Logger(subsystem: "site.didichou.liqian", category: "save")

    /// 尝试落库：成功返回 true；失败返回 false（日志已记、文案已交出）。
    @discardableResult
    static func attempt(_ context: ModelContext, onFailure: (String) -> Void) -> Bool {
        SaveFlow.run(
            save: { try context.save() },
            onFailure: { error in
                logger.error("save failed: \(error.localizedDescription, privacy: .public)")
                onFailure(L10n.string(SaveFlow.failureMessage))
            }
        )
    }

    /// 「上次使用礼簿」回写（键口径同 DefaultLedgerPicker.lastUsedKey）：
    /// 批量/现场/OCR/问账入账成功后同样走这里，与 RecordFormView 的
    /// @AppStorage 写同一个键、同一个 UserDefaults，决策口径不变。
    static func rememberLedger(_ id: UUID) {
        UserDefaults.standard.set(id.uuidString, forKey: DefaultLedgerPicker.lastUsedKey)
    }
}
