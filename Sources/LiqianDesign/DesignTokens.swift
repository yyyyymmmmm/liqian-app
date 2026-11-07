import SwiftUI

// MARK: - v5 设计一期令牌（docs/DESIGN.md 附录定版 / 前沿设计审计 §3）
// 定版融合句：「纸墨为体，玻璃为用。」内容层（卡/列表/图表/表单）永远
// 纸墨平面、零玻璃；玻璃只活在功能层（FAB、行动条、次按钮、指示器），
// 且染色只许走五主题强调令牌（Palette.primary / primaryFill），禁止写死
// 朱砂 hex——本 App 是五主题令牌表，写死必在其他主题下错版。
// 高光/同心圆角/滚动边缘一律系统渲染，禁止手工模仿（附录错令已撤销）。

// MARK: - Mat 材质三档（玻璃染色纪律）

/// 玻璃材质三档令牌：对应的系统 ButtonStyle / glassEffect 档位见下方扩展。
public enum Mat {
    /// 透明档：Sheet 抓手区一类极轻浮层（系统 .glass 的 .clear 变体口径）
    case clear
    /// 常规档：行动条、次按钮（系统 .glass / .regular）
    case regular
    /// 染色档：唯一主操作（系统 .glassProminent ＋主题强调染色）
    case tinted
}

public extension View {
    /// 玻璃按钮令牌入口：regular → .glass；tinted → .glassProminent 并以
    /// 主题强调令牌染色（跟随五主题，不写死色值）；clear 在按钮语境与
    /// regular 同档（系统按钮玻璃只有两档，透明档只用于浮层表面）。
    @ViewBuilder
    func liqianGlassButton(_ mat: Mat) -> some View {
        switch mat {
        case .tinted:
            self.buttonStyle(.glassProminent).tint(Palette.primary)
        case .regular, .clear:
            self.buttonStyle(.glass)
        }
    }

    /// 玻璃表面令牌入口（非按钮浮层）：tinted 以主题浅染令牌轻染，
    /// 不用主色满染——表面染色面积受控，守单强调纪律。
    @ViewBuilder
    func liqianGlassSurface(_ mat: Mat, in shape: some Shape) -> some View {
        switch mat {
        case .clear:
            self.glassEffect(.clear, in: shape)
        case .regular:
            self.glassEffect(.regular, in: shape)
        case .tinted:
            self.glassEffect(.regular.tint(Palette.primaryTint), in: shape)
        }
    }
}

// MARK: - Elevation 两档（转正：替换全仓散落阴影字面量）

/// 阴影规格令牌：全仓阴影只许引用这两档（登记例外：落印浮层阴影属
/// 落印签名动效、年度报告分享图卡是静态成品绘制，均不在 UI 令牌口径内）。
public struct LiqianShadow: Sendable {
    public let opacity: Double
    public let radius: CGFloat
    public let y: CGFloat

    public init(opacity: Double, radius: CGFloat, y: CGFloat) {
        self.opacity = opacity
        self.radius = radius
        self.y = y
    }
}

public enum LiqianElevation {
    /// 卡档：贴面卡片的轻投影（原散落值 black 0.05–0.08 / r12 一带收敛于此）
    public static let card = LiqianShadow(opacity: 0.06, radius: 12, y: 4)
    /// 浮档：浮层与悬浮控件（原散落值 black 0.16–0.20 / r10–16 一带收敛于此）
    public static let floating = LiqianShadow(opacity: 0.18, radius: 14, y: 6)
}

public extension View {
    func liqianElevation(_ shadow: LiqianShadow) -> some View {
        self.shadow(color: .black.opacity(shadow.opacity), radius: shadow.radius, y: shadow.y)
    }
}

// MARK: - 圆角同心机制（子圆角由容器推导，禁止手算）

public enum LiqianRadius {
    /// 同心圆角：内层元素圆角 = 容器圆角 − 内边距，下限 2pt。
    /// 旧手算个案（封面小签 20−16=4）自 v5 起一律走此推导。
    public static func concentric(container: CGFloat, padding: CGFloat) -> CGFloat {
        max(container - padding, 2)
    }
}

// MARK: - Motion 四档曲线＋行为令牌（值取自审计枚举，逐点替换散落曲线）

public enum MotionTokens {
    /// 按压：ScaleOnPress 与一切点按反馈
    public static let press = Animation.snappy(duration: 0.22, extraBounce: 0.05)
    /// 液体弹簧：分段指示器滑移、Tab 形变等跟手位移
    public static let liquidSpring = Animation.interactiveSpring(response: 0.34, dampingFraction: 0.72)
    /// 页面交叉淡化：内容切换的默认过渡
    public static let pageCrossfade = Animation.easeInOut(duration: 0.25)
    /// 落印：盖印签名动效专用（不改清单登记项，值与 v4 既有 .bouncy 0.45 一致）
    public static let sealIn = Animation.bouncy(duration: 0.45, extraBounce: 0.12)

    /// 双 Reduce 降级口径：Reduce Motion 开启时返回 nil（调用方以
    /// withAnimation(resolved) 包裹，nil 即瞬时切换）；Reduce Transparency
    /// 的降级由系统玻璃自动回退实色，不在代码层处理。
    public static func resolved(_ animation: Animation, reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : animation
    }
}
