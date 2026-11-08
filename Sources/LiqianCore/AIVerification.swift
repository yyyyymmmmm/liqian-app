import Foundation

// MARK: - AI Key 验证状态持久化（v5.2.1）
//
// v5.2 及以前的病根：验证三态只活在 AISettingsView 的 @State 里，进页面
// 必然重置为「未验证」——Key 明明保存时验过，重进页面照样显示未验证，
// 而页脚又写「验证通过才可用」，状态机与文案自相矛盾（用户截图实锤）。
// 本文件把验证结论落盘：一条记录＝结论＋时间＋Key 尾号指纹；当前 Key
// 尾号与记录对不上（换过 Key）自动视为未验证；删 Key 时记录一并清。
// 只存结论不存 Key 本身，Key 仍只在钥匙串（App target 的 KeychainStore）。

/// 一次验证的落盘记录
public struct AIVerificationRecord: Codable, Equatable, Sendable {
    public enum Outcome: String, Codable, Sendable {
        case verified
        case failed
    }

    public var outcome: Outcome
    /// 验证当时 Key 的尾 4 位（指纹：换 Key 后靠它判定记录失效）
    public var keyLast4: String
    public var at: Date
    /// 失败时的人话原因（成功时为 nil）
    public var failureReason: String?

    public init(outcome: Outcome, keyLast4: String, at: Date, failureReason: String? = nil) {
        self.outcome = outcome
        self.keyLast4 = keyLast4
        self.at = at
        self.failureReason = failureReason
    }
}

/// 页面与门控读取的验证状态（由落盘记录＋当前 Key 派生，不单独存储）
public enum AIVerificationStatus: Equatable, Sendable {
    case noKey
    case unverified
    case verified(at: Date)
    case failed(reason: String, at: Date)
}

public enum AIVerificationStore {
    public static let defaultsKey = "aiVerificationRecord.v1"

    public static func record(
        defaults: UserDefaults = .standard
    ) -> AIVerificationRecord? {
        guard let data = defaults.data(forKey: defaultsKey) else { return nil }
        return try? JSONDecoder().decode(AIVerificationRecord.self, from: data)
    }

    public static func save(
        _ record: AIVerificationRecord,
        defaults: UserDefaults = .standard
    ) {
        guard let data = try? JSONEncoder().encode(record) else { return }
        defaults.set(data, forKey: defaultsKey)
    }

    public static func clear(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: defaultsKey)
    }

    /// 当前状态：无 Key → noKey；无记录或记录尾号与当前 Key 对不上
    /// （换过 Key）→ unverified；否则按记录结论还原。
    public static func status(
        currentKeyLast4: String?,
        defaults: UserDefaults = .standard
    ) -> AIVerificationStatus {
        guard let currentKeyLast4 else { return .noKey }
        guard let record = record(defaults: defaults),
              record.keyLast4 == currentKeyLast4
        else { return .unverified }
        switch record.outcome {
        case .verified:
            return .verified(at: record.at)
        case .failed:
            return .failed(reason: record.failureReason ?? "验证未通过", at: record.at)
        }
    }
}
