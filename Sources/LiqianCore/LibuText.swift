import Foundation

// MARK: - 礼谱 PDF 专用繁体处理

/// 礼谱 PDF 的固定文字一律繁体（見 GiftBookPDF 与 docs/V28-NOTES.md）。
/// 本文件只负责「程序生成的定式串」——干支日期、农历月日这类由 Core 函数
/// 拼出的文本：其中个别字在 Core 里是简体字形（闰、腊），在 PDF 里换繁体。
///
/// 红线：此映射**禁止**作用于用户数据（人名、礼簿名、事由、关系、备注），
/// 用户数据在礼谱中一律照原样输出。写死的固定串（如欄題、落款用语）直接
/// 在 GiftBookPDF 里以繁体字面量书写，不走这里。
public enum LibuText {
    /// 仅含「生成定式串里可能出现的简体字」→ 繁体，两字：
    /// 闰（闰月）→ 閏、腊（腊月）→ 臘。其余干支/月名/日名字形繁简相同。
    private static let generatedCharMap: [Character: Character] = [
        "闰": "閏",
        "腊": "臘",
    ]

    /// 把程序生成的日期定式串（如 ganzhiFullDate、lunarMonthDay、lunarMonthAlias
    /// 的输出）转为繁体字形。只许喂生成串，严禁喂用户数据。
    public static func traditionalGenerated(_ s: String) -> String {
        String(s.map { generatedCharMap[$0] ?? $0 })
    }
}
