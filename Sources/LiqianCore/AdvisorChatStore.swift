import Foundation

// MARK: - 问账对话持久化（v5.4）
//
// v5.3 及以前：对话只活在 AdvisorView 的 @State 里，退出页面再进来
// 历史全空——用户原话「再点击进去记录没有了」。本文件把对话消息
// （含 v5.3 的结构化卡片模型、v5.4 待确认记账卡的交互状态）落成本地
// JSON 文件（Application Support，不进备份口径与 App 数据一致性由
// 系统文件保护兜底），重进页面原样恢复；「清空对话」删文件。
// 只存对话，不存账目数据本身：卡片里是当时查到的快照数字，与全 App
// 「金额以账本为准」不冲突（回执卡打开的是记录详情、实时数据）。

/// 一条可持久化的对话消息（与 AdvisorView 的呈现一一对应）
public struct AdvisorChatMessage: Codable, Equatable, Sendable, Identifiable {
    public enum Kind: Codable, Equatable, Sendable {
        case user(String)
        /// v4.4 降级管线的结构化结果卡
        case result(AdvisorResult)
        /// 工具问答：结论引子文字＋同源结构化卡片
        case answer(text: String, cards: [AdvisorCard])
        /// 纯文案答复（没听懂、没找到人等）
        case note(String)
    }

    public var id: UUID
    public var kind: Kind

    public init(id: UUID = UUID(), kind: Kind) {
        self.id = id
        self.kind = kind
    }
}

public enum AdvisorChatStore {
    /// 历史上限：超出丢最旧的，防文件无限长（对话是辅助，不是账本）
    public static let maxMessages = 120

    /// 默认存储位置：Application Support/liqian-advisor-chat.json
    public static var defaultFileURL: URL {
        let base = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("liqian-advisor-chat.json")
    }

    public static func load(from url: URL = defaultFileURL) -> [AdvisorChatMessage] {
        guard let data = try? Data(contentsOf: url),
              let messages = try? JSONDecoder().decode([AdvisorChatMessage].self, from: data)
        else { return [] }
        return messages
    }

    public static func save(_ messages: [AdvisorChatMessage], to url: URL = defaultFileURL) {
        let trimmed = Array(messages.suffix(maxMessages))
        guard let data = try? JSONEncoder().encode(trimmed) else { return }
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try? data.write(to: url, options: [.atomic])
    }

    public static func clear(from url: URL = defaultFileURL) {
        try? FileManager.default.removeItem(at: url)
    }
}
