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
    /// 纸：全局背景。v3 近乎纸白、只留一丝暖意
    /// （旧值 F6F1E7 米黄饱和过高，与朱砂、描金堆叠出「AI 中式风」，已废）
    public static let paper = dyn(0xFAF9F6, 0x171716)
    /// 卡面：浅色纯白，深色近黑中性
    public static let card = dyn(0xFFFFFF, 0x1F1F1D)
    /// 墨：主文字（中性暖灰阶，金额也用它）
    public static let ink = dyn(0x262520, 0xEBE9E3)
    /// 次文字（#6F6C64：对纸面对比约 5.0，达 WCAG AA；去黄向中性靠）
    public static let stone = dyn(0x6F6C64, 0xA6A29A)
    /// 朱砂：唯一强调色 #A62B1F 不变，使用面按文件头纪律收敛
    public static let primary = dyn(0xA62B1F, 0xD96A5C)
    /// 朱砂按下态（按钮/封面按压反馈用）
    public static let primaryPressed = dyn(0x8E241B, 0xB85547)
    /// 朱砂 tint 底（选中态衬底、快捷金额钮底等）
    public static let primaryTint = dyn(0xF3E2DC, 0x38251F)
    /// 朱砂禁用态
    public static let primaryDisabled = dyn(0xC9A79E, 0x71544C)
    /// 描金：**仅礼谱 PDF 与印章等静态成品专用**，App 视图禁止引用（v3 起退出 UI）
    public static let gold = dyn(0xB98A2F, 0xC9A24D)
    /// 描边线：中性发丝线（旧值 E3DCCB 带黄，已换中性暖灰）
    public static let hairline = dyn(0xE3E1DA, 0x2E2D2A)

    // —— 白事语义令牌（白事账本内整页切换：无红、无金） ——
    public static let baiPaper = dyn(0xECEEF0, 0x14171A)
    public static let baiCard = dyn(0xF7F8F9, 0x1E2226)
    public static let baiInk = dyn(0x33383B, 0xD8DCE0)
    /// 白事次文字：浅色借 baiPrimary（对 baiPaper 对比约 5.4，≥4.5），深色单独提亮
    public static let baiStone = dyn(0x5B6770, 0xA7B2BC)
    /// 素灰蓝：白事主色
    public static let baiPrimary = dyn(0x5B6770, 0x93A1AD)
    public static let baiLine = dyn(0xD5D9DC, 0x2E343A)

    /// 随礼方向签底色（素蓝灰，红白事通用；签内为白字，两套外观下都保持此值以保可读）
    public static let givenTag = Color(hex: 0x5B6770)
}

// MARK: - 字阶与度量（ui-checker：全 App 统一，不许各页自创）

public enum LiqianMetrics {
    /// 触摸目标下限 44pt
    public static let minTapTarget: CGFloat = 44
    /// 主表面卡片圆角
    public static let cardCorner: CGFloat = 18
    /// 礼簿封面卡圆角
    public static let coverCorner: CGFloat = 20
    /// 卡片内边距
    public static let cardPadding: CGFloat = 16
    /// 间距梯队只用 4/8 倍数：4/8/12/16/24
    public static let spacingS: CGFloat = 8
    public static let spacingM: CGFloat = 16
    public static let spacingL: CGFloat = 24
}

public extension Font {
    /// 衬线（礼簿气）：大标题与金额用
    static func liqianSerif(size: CGFloat, weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: weight, design: .serif)
    }

    /// 页面大标题：28 衬线加粗
    static var liqianBigTitle: Font { liqianSerif(size: 28) }

    /// 金额：20–22 衬线加粗 + 等宽数字（变化时配合 numericText 过渡）
    static func liqianMoney(size: CGFloat = 20) -> Font {
        liqianSerif(size: size).monospacedDigit()
    }
}
