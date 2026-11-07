import Foundation

/// AI 解析共用管线（一句话记账与智能粘贴共用同一条）：DeepSeek 返回的
/// {"records":[...],"uncertain":[...]} 在这里统一解码＋字段映射——
/// 金额元→分换算、关系/方式白名单过滤、方向映射只此一处，改口径先改这里。
/// 解码对单条记录宽容（缺字段按空/0 记为无效条目，不拖垮整批），
/// 只有整体结构不对（非 JSON / 缺 records）才抛错。
public enum AIParse {
    /// 解码后的一条记录（字段已映射成本地口径）
    public struct Record: Equatable, Sendable {
        public var name: String
        /// 金额（分），由 amountYuan（元）换算并四舍五入
        public var amountCents: Int
        /// 只保留 RelationCatalog.all()（系统＋自定义关系）内的值，表外为 nil
        public var relation: String?
        /// 只保留 LiqianConstants.methods 词表内的值，表外为 nil
        public var method: String?
        /// LiqianConstants.received / .given（AI 给 "given" 才是随礼，其余按收礼）
        public var direction: String
        /// 事由提示（一句话记账落备注用）；智能粘贴的返回一般没有
        public var eventHint: String?
        /// 姓名非空且金额 > 0 才算读全了；无效条目保留在结果里并标 false，
        /// 由调用方决定呈现（略过并计数 / 标失败行），绝不静默吞
        public var isValid: Bool

        public init(
            name: String,
            amountCents: Int,
            relation: String?,
            method: String?,
            direction: String,
            eventHint: String?,
            isValid: Bool
        ) {
            self.name = name
            self.amountCents = amountCents
            self.relation = relation
            self.method = method
            self.direction = direction
            self.eventHint = eventHint
            self.isValid = isValid
        }
    }

    public struct Outcome: Equatable, Sendable {
        /// 按 AI 返回顺序的全部条目（含无效条目，靠 isValid 区分）
        public var records: [Record]
        /// AI 自报拿不准的原文行号（智能粘贴用），没有则为空
        public var uncertain: [Int]

        public var validRecords: [Record] { records.filter(\.isValid) }
        public var invalidCount: Int { records.count - validRecords.count }

        public init(records: [Record], uncertain: [Int]) {
            self.records = records
            self.uncertain = uncertain
        }
    }

    public enum ParseError: Error {
        /// 返回内容不是约定的 JSON 结构，整体无法解析
        case unreadable
    }

    private struct RawResponse: Decodable {
        struct RawRecord: Decodable {
            var name: String
            var amountYuan: Double
            var relation: String?
            var method: String?
            var direction: String?
            var eventHint: String?

            private enum CodingKeys: String, CodingKey {
                case name, amountYuan, relation, method, direction, eventHint
            }

            init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                // 单条缺字段不抛错：按空/0 落成无效条目，整批其他条目照常可用
                name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
                amountYuan = try container.decodeIfPresent(Double.self, forKey: .amountYuan) ?? 0
                relation = try container.decodeIfPresent(String.self, forKey: .relation)
                method = try container.decodeIfPresent(String.self, forKey: .method)
                direction = try container.decodeIfPresent(String.self, forKey: .direction)
                eventHint = try container.decodeIfPresent(String.self, forKey: .eventHint)
            }
        }

        var records: [RawRecord]
        var uncertain: [Int]?
    }

    /// 把 DeepSeek 的 chatJSON 返回解码成映射好的记录数组（多笔）
    public static func decode(_ data: Data) throws -> Outcome {
        let raw: RawResponse
        do {
            raw = try JSONDecoder().decode(RawResponse.self, from: data)
        } catch {
            throw ParseError.unreadable
        }
        let records = raw.records.map { rec in
            let name = rec.name.trimmingCharacters(in: .whitespaces)
            return Record(
                name: name,
                amountCents: Int((rec.amountYuan * 100.0).rounded()),
                relation: rec.relation.flatMap { RelationCatalog.all().contains($0) ? $0 : nil },
                method: rec.method.flatMap { LiqianConstants.methods.contains($0) ? $0 : nil },
                direction: rec.direction == "given" ? LiqianConstants.given : LiqianConstants.received,
                eventHint: {
                    guard let hint = rec.eventHint?.trimmingCharacters(in: .whitespaces),
                          !hint.isEmpty else { return nil }
                    return hint
                }(),
                isValid: !name.isEmpty && rec.amountYuan > 0
            )
        }
        return Outcome(records: records, uncertain: raw.uncertain ?? [])
    }
}
