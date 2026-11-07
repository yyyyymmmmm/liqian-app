import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

// MARK: - 语义令牌（docs/DESIGN.md 配色 v3，2026-11-07）
// 组件只许引用这里的语义令牌，不写裸 hex（ui-ux-pro-max 硬规则）。
// 全部令牌为动态色：浅色走 v3 色板，深色走 v3 深色令牌。
//
// v3 色彩纪律（大厂口径，去 AI 味）：
// - 90% 中性打底：中性色阶占满界面，强调色只有一个色族、面积受控。
//   强调色族自 v2.4 起由外观主题驱动（默认朱砂，见 AppTheme），纪律不变。
// - 朱砂只出现在：主按钮、选中态、链接、印章、礼簿封面、收礼方向签/小色点、
//   「待回礼」行动提示。记录金额一律墨色，收/送靠 +/− 符号与方向签区分。
// - 描金退出 UI：App 视图禁止引用 Palette.gold，仅礼谱 PDF 等静态成品可参考。

public extension Color {
    /// 0xRRGGBB
    init(hex: UInt32, alpha: Double = 1.0) {
        let r = Double((hex >> 16) & 0xFF) / 255.0
        let g = Double((hex >> 8) & 0xFF) / 255.0
        let b = Double(hex & 0xFF) / 255.0
        self.init(.sRGB, red: r, green: g, blue: b, opacity: alpha)
    }
}

#if canImport(UIKit)
private extension UIColor {
    convenience init(hex: UInt32) {
        let r = CGFloat((hex >> 16) & 0xFF) / 255.0
        let g = CGFloat((hex >> 8) & 0xFF) / 255.0
        let b = CGFloat(hex & 0xFF) / 255.0
        self.init(red: r, green: g, blue: b, alpha: 1.0)
    }
}
#endif

// MARK: - 外观主题（v2.4，「我的 → 外观」五选一）
// 白天＝浅色＋朱砂；夜晚＝深色＋朱砂；腾讯蓝＝浅色＋TDesign 蓝 #0052D9；
// 灰色＝浅色＋石墨灰；黄色＝浅色＋琥珀金。划分由用户点名定版：深色仅夜晚提供。
// 主题只驱动 App 界面强调色族（primary/primaryFill/primaryTint）；
// 礼谱 PDF 与分享图卡是成品，永远朱砂定版，不读主题。
public enum AppTheme: String, CaseIterable, Identifiable {
    case day
    case night
    case tencentBlue
    case graphite
    case amber

    public var id: String { rawValue }

    /// @AppStorage 键（ContentView 与外观页共用）
    public static let storageKey = "appTheme"

    /// 当前主题：读 UserDefaults（动态色 provider 在解析时调用，切换即时生效）
    public static var current: AppTheme {
        AppTheme(rawValue: UserDefaults.standard.string(forKey: storageKey) ?? "") ?? .day
    }

    public var displayName: String {
        switch self {
        case .day: return "白天"
        case .night: return "夜晚"
        case .tencentBlue: return "腾讯蓝"
        case .graphite: return "灰色"
        case .amber: return "黄色"
        }
    }

    /// 强制的外观：夜晚深色，其余四主题一律浅色
    public var colorScheme: ColorScheme {
        self == .night ? .dark : .light
    }

    /// 主题色点（外观页列表的识别色块）：取该主题的强调色浅色值
    public var swatch: Color {
        switch self {
        case .day, .night: return Color(hex: 0xA62B1F)
        case .tencentBlue: return Color(hex: 0x0052D9)
        case .graphite: return Color(hex: 0x4E5969)
        case .amber: return Color(hex: 0xB7791F)
        }
    }
}

public enum Palette {
    /// 动态色工厂：浅/深两套值，系统切换外观时自动生效
    private static func dyn(_ light: UInt32, _ dark: UInt32) -> Color {
        #if canImport(UIKit)
        return Color(uiColor: UIColor(dynamicProvider: { traits in
            traits.userInterfaceStyle == .dark ? UIColor(hex: dark) : UIColor(hex: light)
        }))
        #else
        return Color(hex: light)
        #endif
    }

    /// 主题强调色工厂：provider 解析时读 AppTheme.current，
    /// 根视图在主题变化时重挂子树，颜色随之即时重解析。
    /// day/night 用浅/深两值（夜晚恒取 night 值），其余三主题为浅色专用单值。
    private static func themed(
        dayLight: UInt32,
        dayDark: UInt32,
        night: UInt32,
        blue: UInt32,
        gray: UInt32,
        yellow: UInt32
    ) -> Color {
        #if canImport(UIKit)
        return Color(uiColor: UIColor(dynamicProvider: { traits in
            let dark = traits.userInterfaceStyle == .dark
            switch AppTheme.current {
            case .day: return UIColor(hex: dark ? dayDark : dayLight)
            case .night: return UIColor(hex: night)
            case .tencentBlue: return UIColor(hex: blue)
            case .graphite: return UIColor(hex: gray)
            case .amber: return UIColor(hex: yellow)
            }
        }))
        #else
        return Color(hex: dayLight)
        #endif
    }

    // —— 红事语义令牌（v3：中性打底 + 朱砂单强调） ——
    // 专业化整改（docs/PRO-AUDIT.md §3.3）：结构色不再手搓复刻系统色——
    // ink/stone/hairline/card 直接映射 iOS 系统语义色（深浅自动、对比由系统保证）；
    // 品牌令牌只保留 paper（纸白是本产品的「世界」）、primary/primaryTint（朱砂签名）、
    // 白事六件套与 gold（限静态成品）。primaryPressed/primaryDisabled 曾是零引用
    // 死令牌，已删除（按下/禁用态由系统按钮外观处理）。
    /// 纸：**已退役出界面背景**（PRO-AUDIT-2 §3.1 定版）——真机证明暖底与白卡
    /// 并置即是一层黄，底色是 chrome、必须用系统色。本令牌仅保留给静态成品
    /// （年度报告分享图卡的纸面），App 界面背景一律用 groupedBackground，禁止再引用。
    public static let paper = dyn(0xFAF9F6, 0x171716)
    /// 界面背景定版：系统分组背景（浅 #F2F2F7 / 深 #000000），全 App 页面统一引用
    public static let groupedBackground: Color = {
        #if canImport(UIKit)
        return Color(uiColor: .systemGroupedBackground)
        #else
        return Color(hex: 0xF2F2F7)
        #endif
    }()
    /// 卡面：系统分组背景的次级面（浅色纯白、深色近黑中性，与旧值等效）
    public static let card: Color = {
        #if canImport(UIKit)
        return Color(uiColor: .secondarySystemGroupedBackground)
        #else
        return Color(hex: 0xFFFFFF)
        #endif
    }()
    /// 墨：主文字（金额也用它）＝系统 label
    public static let ink = Color.primary
    /// 次文字＝系统 secondaryLabel
    public static let stone = Color.secondary
    /// 强调色（文字/图标）：由外观主题驱动（v2.4）——白天/夜晚朱砂
    /// （浅 #A62B1F、白底对比 7.03:1；深色面 #D96A5C、黑底约 5.9:1）、
    /// 腾讯蓝 #0052D9（白底约 5.9:1）、石墨灰 #4E5969（约 6.8:1）、
    /// 琥珀金 #A16207（约 4.9:1），均为浅色底上的文字级对比达标值。
    public static let primary = themed(
        dayLight: 0xA62B1F, dayDark: 0xD96A5C, night: 0xD96A5C,
        blue: 0x0052D9, gray: 0x4E5969, yellow: 0xA16207
    )
    /// 强调 tint 底（选中态衬底、快捷金额钮底等），随主题同族
    public static let primaryTint = themed(
        dayLight: 0xF3E2DC, dayDark: 0x38251F, night: 0x38251F,
        blue: 0xE3EDFB, gray: 0xE9EBEE, yellow: 0xF7EBCB
    )
    /// 强调填充定版：一切「强调底＋白字」的填充（主按钮、FAB、封面签、印章）
    /// 白字对比全部 ≥4.5:1——朱砂 #A62B1F 7.03:1（PRO-AUDIT-2 §3.1）、
    /// 腾讯蓝取深一档 #003CAB（约 8.0:1）、石墨灰 #4E5969（约 6.8:1）、
    /// 琥珀金取深档 #854D0E（约 6.3:1，亮黄 #B7791F 白字仅约 3.6:1 禁用）。
    /// primary 本体只作文字/图标强调，不直接当填充。
    public static let primaryFill = themed(
        dayLight: 0xA62B1F, dayDark: 0xA62B1F, night: 0xA62B1F,
        blue: 0x003CAB, gray: 0x4E5969, yellow: 0x854D0E
    )
    /// 描金：**仅礼谱 PDF 与印章等静态成品专用**，App 视图禁止引用（v3 起退出 UI）
    public static let gold = dyn(0xB98A2F, 0xC9A24D)
    /// 描边线：系统 separator（发丝线本就是它的职责）
    public static let hairline: Color = {
        #if canImport(UIKit)
        return Color(uiColor: .separator)
        #else
        return Color(hex: 0xE3E1DA)
        #endif
    }()

    // —— 反馈语义令牌（PRO-AUDIT §3.1 覆盖门缺位项）：取系统语义色，
    // 视图禁止再裸用 .red/.green/.orange 表达状态 ——
    /// 成功（导入成功行等）
    public static let success = Color.green
    /// 警告（同名提示、需注意行等）
    public static let warning = Color.orange
    /// 危险/错误（失败行、表单错误等）
    public static let danger = Color.red

    // —— 白事语义令牌（PRO-AUDIT-2 §3.1 定版）：底/卡/墨/次/线全部退役为系统
    // 语义色映射（与红事同法），白事身份只由 baiPrimary 一个令牌承载 ——
    /// 白事底：同系统分组背景（旧手搓 #ECEEF0 已退役）
    public static let baiPaper = groupedBackground
    /// 白事卡面：同系统次级分组面
    public static let baiCard = card
    /// 白事墨：同系统 label
    public static let baiInk = Color.primary
    /// 白事次文字：同系统 secondaryLabel
    public static let baiStone = Color.secondary
    /// 素灰蓝：白事身份色，只作文字/图标强调（深色 #93A1AD 对纯黑底 7.94:1 ✓）
    public static let baiPrimary = dyn(0x5B6770, 0x93A1AD)
    /// 白事填充定版：「素灰蓝底＋白字」填充专用，白字对比 浅 5.80:1 / 深 5.45:1 ✓
    public static let baiPrimaryFill = dyn(0x5B6770, 0x5F6B76)
    /// 白事线：同系统 separator
    public static let baiLine = hairline
    // 注：随礼方向签底色原有独立的 givenTag（全仓唯一非动态令牌），
    // 已按 PRO-AUDIT §3.3 并入 baiPrimary，DirectionTag 直接引用 baiPrimary。
}

// MARK: - 字阶与度量（ui-checker：全 App 统一，不许各页自创）

public enum LiqianMetrics {
    /// 触摸目标下限 44pt
    public static let minTapTarget: CGFloat = 44
    /// 主表面卡片圆角（定版，PRO-AUDIT §4.3）
    public static let cardCorner: CGFloat = 18
    /// 礼簿封面卡圆角（定版）
    public static let coverCorner: CGFloat = 20
    /// 签形控件圆角（定版：方向签/待送出签/迷你封面）
    public static let tagCorner: CGFloat = 4
    /// 一般控件圆角（定版：键盘键、输入类控件）
    public static let controlCorner: CGFloat = 10
    /// 卡片内边距
    public static let cardPadding: CGFloat = 16
    /// 间距梯队定版（PRO-AUDIT §4.1）：4/8/12/16/24/32 六档，
    /// 栈间距与内边距一律走令牌；仅签形控件内部允许 2pt 级微调字面量并注明。
    public static let spacingXS: CGFloat = 4
    public static let spacingS: CGFloat = 8
    public static let spacingSM: CGFloat = 12
    public static let spacingM: CGFloat = 16
    public static let spacingL: CGFloat = 24
    public static let spacingXL: CGFloat = 32
}

public extension Font {
    /// 衬线语义字阶版。PRO-AUDIT-2 §3.2 定版：衬线只许活在五个 moment
    /// （封面签题字/印章/锁定页品牌块/分享图卡/礼谱 PDF 与详情页封面满块），
    /// 界面标题与金额一律禁用；保留此 API 仅为白名单场景备用，新增调用先查 DESIGN 白名单。
    static func liqianSerif(_ style: Font.TextStyle, weight: Font.Weight = .bold) -> Font {
        .system(style, design: .serif, weight: weight)
    }

    /// 固定字号衬线：**仅限尺寸由版式决定的功能位**——礼簿封面块竖排题字、
    /// 印章（按印面尺寸比例）、迷你封面、分享图卡等静态成品内部排版。
    /// 普通界面文字禁止使用。
    static func liqianSerifFixed(size: CGFloat, weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: weight, design: .serif)
    }

    /// 页面大标题：largeTitle 衬线加粗
    static var liqianBigTitle: Font { liqianSerif(.largeTitle) }

    /// 金额（PRO-AUDIT-2 §3.2 定版）：系统 sans semibold + 等宽数字——衬线金额
    /// 是「AI 中式风」在数字上的直接来源，大厂记账产品金额无一用衬线。
    /// 定版三档：列表 .title3 / 汇总 .title2 / 记账大字显示 .largeTitle（调用点不变）。
    static func liqianMoney(_ style: Font.TextStyle = .title3) -> Font {
        .system(style, weight: .semibold).monospacedDigit()
    }

    /// 固定字号衬线金额：**仅限静态成品**（年度报告分享图卡，衬线白名单 moment），
    /// 界面内金额禁止使用（界面大字金额走 .system(size:weight:).monospacedDigit()）
    static func liqianMoneyFixed(size: CGFloat) -> Font {
        liqianSerifFixed(size: size).monospacedDigit()
    }
}
