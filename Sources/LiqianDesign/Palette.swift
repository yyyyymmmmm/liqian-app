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
    /// 纸：全局背景。v3 近乎纸白、只留一丝暖意（品牌令牌，刻意保留，不用系统色）
    /// （旧值 F6F1E7 米黄饱和过高，与朱砂、描金堆叠出「AI 中式风」，已废）
    public static let paper = dyn(0xFAF9F6, 0x171716)
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

    // —— 白事语义令牌（白事账本内整页切换：无红、无金） ——
    public static let baiPaper = dyn(0xECEEF0, 0x14171A)
    public static let baiCard = dyn(0xF7F8F9, 0x1E2226)
    public static let baiInk = dyn(0x33383B, 0xD8DCE0)
    /// 白事次文字：浅色借 baiPrimary（对 baiPaper 对比约 5.4，≥4.5），深色单独提亮
    public static let baiStone = dyn(0x5B6770, 0xA7B2BC)
    /// 素灰蓝：白事主色
    public static let baiPrimary = dyn(0x5B6770, 0x93A1AD)
    public static let baiLine = dyn(0xD5D9DC, 0x2E343A)
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
    /// 衬线（礼簿气）：语义字阶版——随 Dynamic Type 缩放（PRO-AUDIT §4.2 定版映射）。
    /// 标题与金额一律走此 API（或 liqianMoney），禁止再写死 pt 值。
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

    /// 金额：衬线语义档 + 等宽数字（变化时配合 numericText 过渡）。
    /// 定版三档（PRO-AUDIT §4.2）：列表 .title3 / 汇总 .title2 / 记账大字显示 .largeTitle。
    static func liqianMoney(_ style: Font.TextStyle = .title3) -> Font {
        liqianSerif(style).monospacedDigit()
    }

    /// 固定字号金额：仅限大字模式等功能位（同 liqianSerifFixed 的使用边界）
    static func liqianMoneyFixed(size: CGFloat) -> Font {
        liqianSerifFixed(size: size).monospacedDigit()
    }
}
