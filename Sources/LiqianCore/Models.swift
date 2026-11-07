import Foundation
import SwiftData

// MARK: - 词表（与 Flutter 版 v0.3 完全一致，改口径先改这里并同步 PRD）

public enum LiqianConstants {
    public static let ledgerTypes = ["婚礼", "满月", "周岁", "乔迁", "寿宴", "升学", "开业", "白事", "其他"]
    public static let relations = ["亲戚", "朋友", "同事", "同学", "邻居", "其他"]
    public static let methods = ["现金", "微信", "支付宝", "银行转账", "实物"]
    public static let directions = ["收礼", "随礼"]

    public static let received = "收礼"
    public static let given = "随礼"
    public static let sentStatus = "已送出"
    public static let pendingStatus = "待送出"
    public static let baiType = "白事"
}

// MARK: - 日期（存储一律 String yyyy-MM-dd，与 Flutter 版一致）

public enum LiqianDate {
    public static var formatter: DateFormatter {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }

    public static func string(from date: Date) -> String { formatter.string(from: date) }

    /// 解析失败兜底为今天（表单场景不让它崩）
    public static func date(from string: String) -> Date { formatter.date(from: string) ?? Date() }

    public static func todayString() -> String { string(from: Date()) }

    public static func currentYearString() -> String {
        String(Calendar.current.component(.year, from: Date()))
    }
}

// MARK: - SwiftData 模型

@Model
public final class Ledger {
    @Attribute(.unique) public var id: UUID
    public var title: String
    public var type: String
    /// yyyy-MM-dd
    public var date: String
    public var note: String

    public init(id: UUID = UUID(), title: String, type: String, date: String, note: String = "") {
        self.id = id
        self.title = title
        self.type = type
        self.date = date
        self.note = note
    }

    public var isBai: Bool { type == LiqianConstants.baiType }
}

@Model
public final class GiftRecord {
    @Attribute(.unique) public var id: UUID
    public var ledgerID: UUID
    public var person: String
    public var relation: String
    /// 金额（分）
    public var amountCents: Int
    /// 收礼 / 随礼
    public var direction: String
    public var method: String
    public var note: String
    /// yyyy-MM-dd
    public var date: String
    /// 仅随礼有意义：已送出 / 待送出；收礼忽略。待送出不计入差额与统计。
    public var status: String
    /// v0.1 旧字段兼容位：原生版不再使用（未回按自动规则算），仅为备份格式兼容保留
    public var returned: Bool

    public init(
        id: UUID = UUID(),
        ledgerID: UUID,
        person: String,
        relation: String = "朋友",
        amountCents: Int,
        direction: String,
        method: String = "现金",
        note: String = "",
        date: String,
        status: String = LiqianConstants.sentStatus,
        returned: Bool = false
    ) {
        self.id = id
        self.ledgerID = ledgerID
        self.person = person
        self.relation = relation
        self.amountCents = amountCents
        self.direction = direction
        self.method = method
        self.note = note
        self.date = date
        self.status = status
        self.returned = returned
    }

    /// 待送出的随礼：钱还没真送出去，不算数（与 Flutter 版 isPendingSend 一致）
    public var isPendingSend: Bool {
        direction == LiqianConstants.given && status == LiqianConstants.pendingStatus
    }
}
