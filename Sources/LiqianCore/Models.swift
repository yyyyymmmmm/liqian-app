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

    // MARK: - 农历

    private static let lunarMonthNames = [
        "正月", "二月", "三月", "四月", "五月", "六月",
        "七月", "八月", "九月", "十月", "冬月", "腊月",
    ]

    /// 农历日名：初一…初十、十一…十九、二十、廿一…廿九、三十
    private static func lunarDayName(_ day: Int) -> String {
        let digits = ["", "一", "二", "三", "四", "五", "六", "七", "八", "九"]
        switch day {
        case 1...9:
            return "初" + digits[day]
        case 10:
            return "初十"
        case 11...19:
            return "十" + digits[day - 10]
        case 20:
            return "二十"
        case 21...29:
            return "廿" + digits[day - 20]
        case 30:
            return "三十"
        default:
            return "\(day)日"
        }
    }

    /// 农历文本，如「农历十月初八」「农历闰四月廿三」。
    /// 用农历（.chinese）日历取月/日分量，再按传统月名/日名拼中文数字，
    /// 不依赖 DateFormatter 的区域化输出，保证各系统版本结果一致。
    /// （DateFormatter 配 .chinese 日历的标准输出样例即此形态：「十月初八」。）
    public static func lunarString(for dateString: String) -> String {
        let date = date(from: dateString)
        let cal = Calendar(identifier: .chinese)
        let comps = cal.dateComponents([.month, .day], from: date)
        let month = comps.month ?? 1
        let monthName = lunarMonthNames.indices.contains(month - 1)
            ? lunarMonthNames[month - 1]
            : "\(month)月"
        let leap = comps.isLeapMonth == true ? "闰" : ""
        return "农历" + leap + monthName + lunarDayName(comps.day ?? 1)
    }

    /// 农历月日（不带年、不带「农历」前缀），如「十月初八」「闰四月廿三」。
    /// 礼谱内页逐笔日期小字用。
    public static func lunarMonthDay(for dateString: String) -> String {
        let lunar = lunarString(for: dateString)
        return lunar.hasPrefix("农历") ? String(lunar.dropFirst(2)) : lunar
    }

    public static func currentYearString() -> String {
        String(Calendar.current.component(.year, from: Date()))
    }

    /// 界面日期显示（PRO-AUDIT §1.5 定版）：当年「M月d日」、跨年「yyyy年M月d日」。
    /// 存储格式 yyyy-MM-dd 禁止直接出现在用户界面，展示一律走此函数。
    /// 入参不是合法 yyyy-MM-dd 时原样返回（不崩、不编造）。
    public static func displayString(for dateString: String, today: String = todayString()) -> String {
        let parts = dateString.split(separator: "-")
        guard parts.count == 3, let month = Int(parts[1]), let day = Int(parts[2]) else {
            return dateString
        }
        if parts[0] == today.prefix(4) {
            return "\(month)月\(day)日"
        }
        return "\(parts[0])年\(month)月\(day)日"
    }

    // MARK: - 干支纪年（礼谱 v3：封面、谱序落款、纪年印三处统一）

    private static let tianGanNames = ["甲", "乙", "丙", "丁", "戊", "己", "庚", "辛", "壬", "癸"]
    private static let diZhiNames = ["子", "丑", "寅", "卯", "辰", "巳", "午", "未", "申", "酉", "戌", "亥"]

    /// 干支年（民间礼谱口径：以农历年推干支）。
    /// chinese 日历的 year 分量是 60 年周期内的序号（1…60，如 2026 年为周期第 43 年），
    /// 干支序号 = 周期年 − 1；与按公历年 (Y−4) mod 60 取干支恒等（公元 4 年为甲子年）：
    /// 2026-11-16 → 丙午、2025-01-29 → 乙巳、2024-02-10 → 甲辰。
    public static func ganzhiYear(for dateString: String) -> String {
        let date = date(from: dateString)
        let cal = Calendar(identifier: .chinese)
        let cycleYear = cal.component(.year, from: date)
        let index = ((cycleYear - 1) % 60 + 60) % 60
        return tianGanNames[index % 10] + diZhiNames[index % 12]
    }

    /// 全谱统一日期写法：「丙午年十月初八」（干支年 + 农历月日，不带「农历」二字）
    public static func ganzhiFullDate(for dateString: String) -> String {
        let lunar = lunarString(for: dateString)
        let monthDay = lunar.hasPrefix("农历") ? String(lunar.dropFirst(2)) : lunar
        return ganzhiYear(for: dateString) + "年" + monthDay
    }

    // MARK: - 农历月份雅称（纪年印用：干支年 + 月雅称，如「丙午冬月」）

    private static let lunarMonthAliases = [
        "端月", "杏月", "桃月", "槐月", "蒲月", "荷月",
        "巧月", "桂月", "菊月", "冬月", "葭月", "腊月",
    ]

    /// 按农历月序号（1…12）取雅称，越界回退「N月」
    public static func lunarMonthAlias(month: Int) -> String {
        lunarMonthAliases.indices.contains(month - 1)
            ? lunarMonthAliases[month - 1]
            : "\(month)月"
    }

    /// 某日期所在农历月的雅称
    public static func lunarMonthAlias(for dateString: String) -> String {
        let date = date(from: dateString)
        let cal = Calendar(identifier: .chinese)
        return lunarMonthAlias(month: cal.component(.month, from: date))
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
