import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

// MARK: - 语义令牌（docs/DESIGN.md 配色 v3，2026-11-07）
// 组件只许引用这里的语义令牌，不写裸 hex（ui-ux-pro-max 硬规则）。
// 全部令牌为动态色：浅色走 v3 色板，深色走 v3 深色令牌。
//
// v3 色彩纪律（大厂口径，去 AI 味）：
// - 90% 中性打底：纸白/纯白卡面/中性暖灰墨色阶占满界面，朱砂是唯一强调色。
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
    /// 朱砂：唯一强调色 #A62B1F 不变，使用面按文件头纪律收敛
    public static let primary = dyn(0xA62B1F, 0xD96A5C)
    /// 朱砂 tint 底（选中态衬底、快捷金额钮底等）
    public static let primaryTint = dyn(0xF3E2DC, 0x38251F)
    /// 朱砂填充定版（PRO-AUDIT-2 §3.1）：一切「朱砂底＋白字」的填充（主按钮、
    /// 方向签、封面签、印章）双模式共用浅色值，白字对比 7.03:1 ✓。
    /// primary 本体只作文字/图标强调，不再直接当填充（深色值作填充仅 3.41:1 不达 AA）。
    public static let primaryFill = dyn(0xA62B1F, 0xA62B1F)
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
