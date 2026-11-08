import Foundation

/// 自定义主题派生引擎（v5.9，审计 #1 方案 A）：用户选一个强调基色，
/// 程序化派生出与五张人工令牌表同构的整套令牌（参照 Material 色阶派生
/// 思路：不裸用基色，先过对比度护栏再取档）。
///
/// 派生规则（定版）：
/// - pageBG＝白天纸白与基色 5% 混色（极淡染色，保「90% 中性打底」）；
///   surface＝纯白；ink/sub/line 复用白天中性阶（审计二选一取前者）。
/// - primary＝基色保持色相/饱和度，只在明度轴上向下找「对 pageBG 与
///   surface 均 ≥4.5:1」的最高明度——基色本身达标则原样保留（一分不
///   动），偏浅才调深（UI 侧据此提示「已略调深」）。
/// - primaryFill＝primary 再压深一档（明度 ×0.85），白字对比只增不减。
/// - primaryTint＝primary 混白 88%（选中态衬底）。
/// - moneyGiven 防撞（审计最硬约束）：收＝primary、送＝黛青 #14665A；
///   当基色饱和度 ≥0.20 且与黛青色相夹角 <30°（绿/青系）时，送色自动
///   切换备用黛紫靛 #4F4699（与黛青夹角 ≈75°、与撞色窗右界 202° 亦有
///   ≈44°），切换后同样过 ≥4.5:1 对比度校验。低饱和基色（黑/灰）色相
///   无意义，不触发切换——灰黑与黛青靠明度/饱和天然可分。
///
/// 纯函数、无 IO，可单测；令牌表的装配在 LiqianDesign 侧完成。
public enum CustomTheme {

    /// 基色缺省值（未存过时）：朱砂——与默认白天主题同色，初次进入
    /// 自定义等于从现状出发，不跳变。
    public static let defaultBaseHex: UInt32 = 0xA62B1F
    /// 送礼语义色定版「黛青」（与五主题表同值）
    public static let standardMoneyGivenHex: UInt32 = 0x14665A
    /// 撞色时送礼备用色「黛紫靛」：色相 ≈246°，与黛青、与绿青撞色窗
    /// 都拉开距离；对白底对比 ≈7.5:1，达标有余量（实测见单测）。
    public static let backupMoneyGivenHex: UInt32 = 0x4F4699
    /// 撞色判定：色相夹角阈值（度）
    public static let collisionHueThreshold: Double = 30
    /// 撞色判定：基色饱和度下限（低于此值色相不可靠，不判撞色）
    public static let collisionMinSaturation: Double = 0.20
    /// 文字/金额令牌的对比度下限（WCAG AA 正文）
    public static let minimumContrast: Double = 4.5

    /// 派生令牌（字段与 AppThemeTokens 一一对应，UInt32 hex）
    public struct Tokens: Equatable {
        public var pageBG: UInt32
        public var surface: UInt32
        public var primary: UInt32
        public var primaryFill: UInt32
        public var primaryTint: UInt32
        public var moneyGiven: UInt32
        public var ink: UInt32
        public var sub: UInt32
        public var line: UInt32

        public init(
            pageBG: UInt32, surface: UInt32, primary: UInt32,
            primaryFill: UInt32, primaryTint: UInt32, moneyGiven: UInt32,
            ink: UInt32, sub: UInt32, line: UInt32
        ) {
            self.pageBG = pageBG
            self.surface = surface
            self.primary = primary
            self.primaryFill = primaryFill
            self.primaryTint = primaryTint
            self.moneyGiven = moneyGiven
            self.ink = ink
            self.sub = sub
            self.line = line
        }
    }

    /// 由基色派生整套令牌（主入口）
    public static func tokens(baseHex: UInt32) -> Tokens {
        let base = hsl(of: baseHex)
        let pageBG = mix(0xFAF9F7, baseHex, fraction: 0.05)
        let surface: UInt32 = 0xFFFFFF

        let primary = adjustedPrimary(h: base.h, s: base.s, l: base.l, backgrounds: [pageBG, surface])
        let primaryL = hsl(of: primary).l
        var fillL = primaryL * 0.85
        var fill = hex(h: base.h, s: base.s, l: fillL)
        // primary 对白（surface）已 ≥4.5，压深后白字对比只增不减；
        // 循环只作数值兜底。
        while contrastRatio(fill, 0xFFFFFF) < minimumContrast, fillL > 0 {
            fillL -= 0.02
            fill = hex(h: base.h, s: base.s, l: max(fillL, 0))
        }
        let tint = mix(primary, 0xFFFFFF, fraction: 0.88)

        let moneyGiven = resolvedMoneyGiven(base: base, backgrounds: [pageBG, surface])

        return Tokens(
            pageBG: pageBG, surface: surface,
            primary: primary, primaryFill: fill, primaryTint: tint,
            moneyGiven: moneyGiven,
            ink: 0x1C1917, sub: 0x6B6660, line: 0xE9E4DE
        )
    }

    /// 基色是否会被护栏调深（primary 与基色不一致即是）——UI 提示用
    public static func isAdjusted(baseHex: UInt32) -> Bool {
        tokens(baseHex: baseHex).primary != baseHex
    }

    /// 送礼色裁决：撞色→备用色，否则黛青；两者都过对比度校验
    static func resolvedMoneyGiven(
        base: (h: Double, s: Double, l: Double),
        backgrounds: [UInt32]
    ) -> UInt32 {
        let standardHue = hsl(of: standardMoneyGivenHex).h
        let collides = base.s >= collisionMinSaturation
            && hueDistance(base.h, standardHue) < collisionHueThreshold
        let candidate = collides ? backupMoneyGivenHex : standardMoneyGivenHex
        return ensureContrast(candidate, backgrounds: backgrounds)
    }

    /// primary 裁决：基色达标原样保留；不达标在明度轴二分找最高达标值
    static func adjustedPrimary(
        h: Double, s: Double, l: Double, backgrounds: [UInt32]
    ) -> UInt32 {
        let baseHex = hex(h: h, s: s, l: l)
        if backgrounds.allSatisfy({ contrastRatio(baseHex, $0) >= minimumContrast }) {
            return baseHex
        }
        // 对比度随明度单调（背景皆浅色：越暗越高），二分取最高达标明度
        var lo = 0.0
        var hi = l
        for _ in 0..<48 {
            let mid = (lo + hi) / 2
            let candidate = hex(h: h, s: s, l: mid)
            if backgrounds.allSatisfy({ contrastRatio(candidate, $0) >= minimumContrast }) {
                lo = mid
            } else {
                hi = mid
            }
        }
        return hex(h: h, s: s, l: lo)
    }

    /// 兜底校正：颜色对全部背景达标才返回，否则沿明度轴压暗到达标
    static func ensureContrast(_ color: UInt32, backgrounds: [UInt32]) -> UInt32 {
        if backgrounds.allSatisfy({ contrastRatio(color, $0) >= minimumContrast }) {
            return color
        }
        let hslValue = hsl(of: color)
        var l = hslValue.l
        var candidate = color
        while l > 0 {
            l -= 0.02
            candidate = hex(h: hslValue.h, s: hslValue.s, l: max(l, 0))
            if backgrounds.allSatisfy({ contrastRatio(candidate, $0) >= minimumContrast }) {
                break
            }
        }
        return candidate
    }

    // MARK: - 色彩数学（纯函数）

    /// hex → HSL（h: 0..<360 度，s/l: 0...1）
    public static func hsl(of hexValue: UInt32) -> (h: Double, s: Double, l: Double) {
        let r = Double((hexValue >> 16) & 0xFF) / 255.0
        let g = Double((hexValue >> 8) & 0xFF) / 255.0
        let b = Double(hexValue & 0xFF) / 255.0
        let maxV = max(r, g, b)
        let minV = min(r, g, b)
        let delta = maxV - minV
        let l = (maxV + minV) / 2
        if delta == 0 { return (0, 0, l) }
        let s = delta / (1 - abs(2 * l - 1))
        let h: Double
        if maxV == r {
            h = 60 * ((g - b) / delta).truncatingRemainder(dividingBy: 6)
        } else if maxV == g {
            h = 60 * ((b - r) / delta + 2)
        } else {
            h = 60 * ((r - g) / delta + 4)
        }
        return (h < 0 ? h + 360 : h, min(max(s, 0), 1), l)
    }

    /// HSL → hex
    public static func hex(h: Double, s: Double, l: Double) -> UInt32 {
        let h = (h.truncatingRemainder(dividingBy: 360) + 360)
            .truncatingRemainder(dividingBy: 360)
        let s = min(max(s, 0), 1)
        let l = min(max(l, 0), 1)
        let c = (1 - abs(2 * l - 1)) * s
        let x = c * (1 - abs((h / 60).truncatingRemainder(dividingBy: 2) - 1))
        let m = l - c / 2
        let (r, g, b): (Double, Double, Double)
        switch h {
        case 0..<60: (r, g, b) = (c, x, 0)
        case 60..<120: (r, g, b) = (x, c, 0)
        case 120..<180: (r, g, b) = (0, c, x)
        case 180..<240: (r, g, b) = (0, x, c)
        case 240..<300: (r, g, b) = (x, 0, c)
        default: (r, g, b) = (c, 0, x)
        }
        func byte(_ v: Double) -> UInt32 {
            UInt32(min(max((v + m) * 255, 0), 255).rounded())
        }
        return (byte(r) << 16) | (byte(g) << 8) | byte(b)
    }

    /// WCAG 相对亮度
    public static func relativeLuminance(_ hexValue: UInt32) -> Double {
        func linear(_ byte: UInt32) -> Double {
            let v = Double(byte) / 255.0
            return v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
        }
        let r = linear((hexValue >> 16) & 0xFF)
        let g = linear((hexValue >> 8) & 0xFF)
        let b = linear(hexValue & 0xFF)
        return 0.2126 * r + 0.7152 * g + 0.0722 * b
    }

    /// WCAG 对比度（1...21，对称）
    public static func contrastRatio(_ a: UInt32, _ b: UInt32) -> Double {
        let la = relativeLuminance(a)
        let lb = relativeLuminance(b)
        let (lighter, darker) = la >= lb ? (la, lb) : (lb, la)
        return (lighter + 0.05) / (darker + 0.05)
    }

    /// 色相夹角（0...180 度）
    public static func hueDistance(_ a: Double, _ b: Double) -> Double {
        let diff = abs(a - b).truncatingRemainder(dividingBy: 360)
        return diff > 180 ? 360 - diff : diff
    }

    /// 两色线性混合（sRGB 通道直混，fraction＝b 的占比 0...1）
    public static func mix(_ a: UInt32, _ b: UInt32, fraction: Double) -> UInt32 {
        let f = min(max(fraction, 0), 1)
        func channel(_ shift: UInt32) -> UInt32 {
            let av = Double((a >> shift) & 0xFF)
            let bv = Double((b >> shift) & 0xFF)
            return UInt32((av + (bv - av) * f).rounded())
        }
        return (channel(16) << 16) | (channel(8) << 8) | channel(0)
    }
}
