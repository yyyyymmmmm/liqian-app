import SwiftUI
import LiqianCore
#if canImport(UIKit)
import UIKit
#endif

// MARK: - 语义令牌（docs/DESIGN.md 配色 v3；v2.5 包 6 起整套入主题令牌表）
// 组件只许引用这里的语义令牌，不写裸 hex（ui-ux-pro-max 硬规则）。
// 界面令牌全部由 AppTheme.tokens 查表生成的动态色（见下方令牌表）。
//
// v3 色彩纪律（大厂口径，去 AI 味）：
// - 90% 中性打底：中性色阶占满界面，强调色只有一个色族、面积受控。
//   强调色族自 v2.4 起由外观主题驱动（默认朱砂，见 AppTheme），纪律不变。
// - 朱砂只出现在：主按钮、选中态、链接、印章、礼簿封面、收礼方向签/小色点、
//   「待回礼」行动提示。金额口径（v5.0.2 用户改版）：逐笔金额符号＋语义
//   双色（收走主题强调、送走黛青），汇总数字仍墨色——见下方金额语义令牌。
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

// MARK: - 外观主题（v2.4，「我的 → 外观」五选一；v5.9 加第六位自定义）
// 白天＝浅色＋朱砂；夜晚＝深色＋朱砂；腾讯蓝＝浅色＋TDesign 蓝 #0052D9；
// 灰色＝浅色＋石墨灰；黄色＝浅色＋琥珀金。划分由用户点名定版：深色仅夜晚提供。
// 自定义（v5.9，审计 #1 方案 A）：用户选一个强调基色，令牌由
// LiqianCore.CustomTheme 程序化派生（对比度护栏＋金额防撞），只做浅色一套。
// 主题驱动 App 界面整套令牌（v2.5 包 6 起，见下方令牌表）；
// 礼谱 PDF 与分享图卡是成品，永远朱砂定版，不读主题。
public enum AppTheme: String, CaseIterable, Identifiable {
    case day
    case night
    case tencentBlue
    case graphite
    case amber
    case custom

    public var id: String { rawValue }

    /// @AppStorage 键（ContentView 与外观页共用）
    public static let storageKey = "appTheme"

    /// 自定义主题基色 @AppStorage 键（存 hex 字符串如 "A62B1F"）
    public static let customBaseStorageKey = "customThemeBaseHex"

    /// 自定义主题当前基色：读 UserDefaults，没存过回朱砂缺省
    public static var customBaseHex: UInt32 {
        guard let raw = UserDefaults.standard.string(forKey: customBaseStorageKey),
              let value = UInt32(raw, radix: 16) else {
            return CustomTheme.defaultBaseHex
        }
        return value
    }

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
        case .custom: return "自定义"
        }
    }

    /// 强制的外观：夜晚深色，其余主题（含自定义）一律浅色
    public var colorScheme: ColorScheme {
        self == .night ? .dark : .light
    }

    /// 主题色点（外观页列表的识别色块）：取该主题的强调色浅色值；
    /// 自定义取用户当前基色原色（未经护栏调整，所见即所选）
    public var swatch: Color {
        switch self {
        case .day, .night: return Color(hex: 0xA62B1F)
        case .tencentBlue: return Color(hex: 0x0052D9)
        case .graphite: return Color(hex: 0x4E5969)
        case .amber: return Color(hex: 0xB7791F)
        case .custom: return Color(hex: AppTheme.customBaseHex)
        }
    }
}

// MARK: - 主题令牌表（v2.5 包 6，TDesign/Arco 色阶体系口径）
// v2.4 只换一个强调色、背景与容器仍是系统默认，色不融洽（用户点名）。
// 大厂做法是每主题一整套令牌：页面底与容器底带主题色温的微染，
// 品牌色分三档——主色（文字/图标强调）、填充深档（强调底＋白字）、
// 浅染（选中态/标签底）；中性色（ink/sub/line）与品牌同色温。
// 全 App 界面令牌一律由 AppTheme.tokens 查表生成，别处不许再拼动态色。
public struct AppThemeTokens {
    /// 页面底（带主题色温的微染）
    public let pageBG: UInt32
    /// 容器底（卡片、列表行）
    public let surface: UInt32
    /// 品牌主色：文字/图标强调
    public let primary: UInt32
    /// 品牌填充深档：强调底＋白字（主按钮、FAB、封面签、印章）
    public let primaryFill: UInt32
    /// 品牌浅染：选中态衬底、标签底
    public let primaryTint: UInt32
    /// 送礼金额语义色「黛青」（v5.0.2 新增）：与品牌收色一暖一冷成对，
    /// 只给逐笔随礼金额数字与图表随礼系列用；逐主题校过对比度
    /// （对本主题 pageBG/surface 均 ≥4.5:1，实测表见 docs/V502-NOTES.md）
    public let moneyGiven: UInt32
    /// 主文字（与品牌同色温的中性）
    public let ink: UInt32
    /// 次文字
    public let sub: UInt32
    /// 描边线
    public let line: UInt32

    public init(
        pageBG: UInt32, surface: UInt32, primary: UInt32, primaryFill: UInt32,
        primaryTint: UInt32, ink: UInt32, sub: UInt32, line: UInt32,
        moneyGiven: UInt32
    ) {
        self.pageBG = pageBG
        self.surface = surface
        self.primary = primary
        self.primaryFill = primaryFill
        self.primaryTint = primaryTint
        self.ink = ink
        self.sub = sub
        self.line = line
        self.moneyGiven = moneyGiven
    }
}

public extension AppTheme {
    /// 本主题的整套令牌（定值，用户拍板口径；黄色只出现在强调与浅染，
    /// 页面底只取其色温微染，禁止中明度黄铺底）
    var tokens: AppThemeTokens {
        switch self {
        case .day:
            return AppThemeTokens(
                pageBG: 0xFAF9F7, surface: 0xFFFFFF,
                primary: 0xA62B1F, primaryFill: 0x8F241B, primaryTint: 0xF9ECE9,
                ink: 0x1C1917, sub: 0x6B6660, line: 0xE9E4DE,
                moneyGiven: 0x14665A
            )
        case .night:
            return AppThemeTokens(
                pageBG: 0x131315, surface: 0x1E1E21,
                primary: 0xD96A5C, primaryFill: 0xC4533F, primaryTint: 0x2C1E1B,
                ink: 0xF2EFE9, sub: 0xA39E97, line: 0x33302C,
                moneyGiven: 0x4FB3A6
            )
        case .tencentBlue:
            return AppThemeTokens(
                pageBG: 0xF2F3F5, surface: 0xFFFFFF,
                primary: 0x0052D9, primaryFill: 0x003CAB, primaryTint: 0xEAF1FE,
                ink: 0x1F2329, sub: 0x5F6570, line: 0xE3E6EB,
                moneyGiven: 0x14665A
            )
        case .graphite:
            return AppThemeTokens(
                pageBG: 0xF4F4F3, surface: 0xFFFFFF,
                primary: 0x4E5969, primaryFill: 0x39424E, primaryTint: 0xEBEDF0,
                ink: 0x1D2126, sub: 0x646A73, line: 0xE2E4E6,
                moneyGiven: 0x14665A
            )
        case .amber:
            return AppThemeTokens(
                pageBG: 0xFCFAF3, surface: 0xFFFFFF,
                primary: 0xA16207, primaryFill: 0x854D0E, primaryTint: 0xF8EED3,
                ink: 0x221D10, sub: 0x6E6455, line: 0xEAE3D0,
                moneyGiven: 0x14665A
            )
        case .custom:
            // v5.9：第六主题位——整套令牌由用户基色经 Core 派生引擎生成
            // （对比度护栏＋金额防撞在 CustomTheme 内，见其注释与单测）
            let derived = CustomTheme.tokens(baseHex: AppTheme.customBaseHex)
            return AppThemeTokens(
                pageBG: derived.pageBG, surface: derived.surface,
                primary: derived.primary, primaryFill: derived.primaryFill,
                primaryTint: derived.primaryTint,
                ink: derived.ink, sub: derived.sub, line: derived.line,
                moneyGiven: derived.moneyGiven
            )
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

    /// 主题令牌工厂（v2.5 包 6 收敛）：全 App 界面令牌由此一处生成——
    /// provider 解析时读 AppTheme.current 的令牌表，根视图在主题变化时
    /// 重挂子树，颜色随之即时重解析。旧的单色 themed 工厂与系统色直映射
    /// （ink=Color.primary 等）已废止：结构色也入令牌表，才能与品牌同色温。
    private static func token(_ keyPath: KeyPath<AppThemeTokens, UInt32>) -> Color {
        #if canImport(UIKit)
        return Color(uiColor: UIColor(dynamicProvider: { _ in
            UIColor(hex: AppTheme.current.tokens[keyPath: keyPath])
        }))
        #else
        return Color(hex: AppTheme.day.tokens[keyPath: keyPath])
        #endif
    }

    // —— 界面语义令牌（v2.5：全部由主题令牌表查得） ——
    /// 纸：**已退役出界面背景**（PRO-AUDIT-2 §3.1 定版）——仅保留给静态成品
    /// （年度报告分享图卡的纸面），App 界面背景一律用 pageBG，禁止再引用。
    public static let paper = dyn(0xFAF9F6, 0x171716)
    /// 页面底：主题令牌 pageBG（带主题色温的微染），全 App 页面统一引用
    public static let pageBG = token(\.pageBG)
    /// 旧名兼容：分组背景即页面底（v2.5 起同值同源，不再是系统分组色）
    public static let groupedBackground = token(\.pageBG)
    /// 容器底：主题令牌 surface（卡片、列表行、自绘面）
    public static let surface = token(\.surface)
    /// 旧名兼容：卡面即容器底
    public static let card = token(\.surface)
    /// 墨：主文字（金额也用它），主题令牌 ink
    public static let ink = token(\.ink)
    /// 次文字，主题令牌 sub
    public static let sub = token(\.sub)
    /// 旧名兼容：次文字
    public static let stone = token(\.sub)
    /// 描边线，主题令牌 line
    public static let line = token(\.line)
    /// 旧名兼容：描边线
    public static let hairline = token(\.line)
    /// 品牌主色（文字/图标强调），主题令牌 primary：白天朱砂 #A62B1F、
    /// 夜晚 #D96A5C、腾讯蓝 #0052D9、石墨灰 #4E5969、琥珀 #A16207。
    /// 本体只作文字/图标强调，不直接当填充（填充走 primaryFill 深档）。
    public static let primary = token(\.primary)
    /// 品牌填充深档：一切「强调底＋白字」的填充（主按钮、FAB、封面签、印章），
    /// 主题令牌 primaryFill（各主题均为深一档，白字对比达标口径不变）
    public static let primaryFill = token(\.primaryFill)
    /// 品牌浅染：选中态衬底、方向签底、快捷金额钮底等，主题令牌 primaryTint
    public static let primaryTint = token(\.primaryTint)
    /// 描金：**仅礼谱 PDF 与印章等静态成品专用**，App 视图禁止引用（v3 起退出 UI）
    public static let gold = dyn(0xB98A2F, 0xC9A24D)

    // —— 静态成品专用定版（不读主题）：分享图卡与礼谱是留存物，
    // 永远朱砂纸面口径，与 App 主题无关（v2.5 包 6 红线） ——
    /// 图卡纸面文字（＝白天主题 ink 定值）
    public static let paperInk = Color(hex: 0x1C1917)
    /// 图卡纸面次文字（＝白天主题 sub 定值）
    public static let paperStone = Color(hex: 0x6B6660)
    /// 图卡纸面描边（＝白天主题 line 定值）
    public static let paperLine = Color(hex: 0xE9E4DE)
    /// 朱砂填充定版：静态成品里的印章专用（界面内印章走 primaryFill）
    public static let brandFillFixed = Color(hex: 0xA62B1F)

    // —— 反馈语义令牌（PRO-AUDIT §3.1 覆盖门缺位项）：取系统语义色，
    // 视图禁止再裸用 .red/.green/.orange 表达状态 ——
    /// 成功（导入成功行等）
    public static let success = Color.green
    /// 警告（同名提示、需注意行等）
    public static let warning = Color.orange
    /// 危险/错误（失败行、表单错误等）
    public static let danger = Color.red

    // —— 白事语义令牌：底/卡/墨/次/线与红事共用主题令牌表的中性档
    // （v2.5 随包 6 同源），白事身份只由 baiPrimary 一个令牌承载；
    // baiPrimary/baiPrimaryFill 不入主题表、不跟随主题（场景色红线） ——
    /// 白事底：同页面底
    public static let baiPaper = groupedBackground
    /// 白事卡面：同容器底
    public static let baiCard = card
    /// 白事墨：同主文字
    public static let baiInk = ink
    /// 白事次文字：同次文字
    public static let baiStone = stone
    /// 素灰蓝：白事身份色，只作文字/图标强调（深色 #93A1AD 对纯黑底 7.94:1 ✓）
    public static let baiPrimary = dyn(0x5B6770, 0x93A1AD)
    /// 白事填充定版：「素灰蓝底＋白字」填充专用，白字对比 浅 5.80:1 / 深 5.45:1 ✓
    public static let baiPrimaryFill = dyn(0x5B6770, 0x5F6B76)
    /// 白事线：同系统 separator
    public static let baiLine = hairline
    // 注：随礼方向签底色原有独立的 givenTag（全仓唯一非动态令牌），
    // 已按 PRO-AUDIT §3.3 并入 baiPrimary，DirectionTag 直接引用 baiPrimary。

    // —— 金额语义双色（v5.0.2 用户改版）：只给「逐笔」收/送金额数字与
    // 图表收/送系列用；合计/差额/待回等汇总数字不入此口径、仍墨色。
    // 解析口径（方向×白事）收敛在 DesignTokens 的 MoneyTone，组件层
    // 走 SignedMoneyText，不许各页自选金额色。——
    /// 收礼金额色：当前主题强调令牌本身（暖，随五主题走）
    public static var moneyReceived: Color { primary }
    /// 随礼金额色「黛青」：主题令牌 moneyGiven（冷），逐主题对
    /// pageBG/surface 对比均 ≥4.5:1（实测表见 docs/V502-NOTES.md）
    public static let moneyGiven = token(\.moneyGiven)
    /// 白事收礼金额色：朱砂降饱和变体——白事克制口径，不入主题表、
    /// 随深浅外观给两值（浅 #8C4A3E / 深 #C08D81，对比实测同 V502-NOTES）
    public static let moneyReceivedBai = dyn(0x8C4A3E, 0xC08D81)
    /// 白事随礼金额色：黛青降饱和变体（浅 #4C6D66 / 深 #87A29B）
    public static let moneyGivenBai = dyn(0x4C6D66, 0x87A29B)
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

    /// 金额（质感审计第 2 条，v4.6）：暗色模式字重降一档——深色底上 semibold
    /// 会被发光感放大显粗，降 medium 后与浅色观感对齐；浅色恒 semibold 定版。
    /// 调用方读 colorScheme 后传 dark；成组件版见 Components.LiqianMoneyText。
    static func liqianMoney(_ style: Font.TextStyle = .title3, dark: Bool) -> Font {
        .system(style, weight: dark ? .medium : .semibold).monospacedDigit()
    }

    /// 固定字号衬线金额：**仅限静态成品**（年度报告分享图卡，衬线白名单 moment），
    /// 界面内金额禁止使用（界面大字金额走 .system(size:weight:).monospacedDigit()）
    static func liqianMoneyFixed(size: CGFloat) -> Font {
        liqianSerifFixed(size: size).monospacedDigit()
    }
}
