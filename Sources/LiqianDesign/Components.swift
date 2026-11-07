import SwiftUI
import LiqianCore

// MARK: - 方向签：收礼＝朱砂底签（白事内用素灰蓝），随礼＝素蓝灰底签

public struct DirectionTag: View {
    public let direction: String
    public let bai: Bool

    public init(direction: String, bai: Bool = false) {
        self.direction = direction
        self.bai = bai
    }

    public var body: some View {
        let isReceived = direction == LiqianConstants.received
        let bg = isReceived ? (bai ? Palette.baiPrimary : Palette.primary) : Palette.givenTag
        Text(direction)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(bg, in: RoundedRectangle(cornerRadius: 4))
    }
}

// MARK: - 待送出素签：描边小签

public struct PendingTag: View {
    public let bai: Bool

    public init(bai: Bool = false) {
        self.bai = bai
    }

    public var body: some View {
        let color = bai ? Palette.baiPrimary : Palette.stone
        Text("待送出")
            .font(.system(size: 11))
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(color, lineWidth: 1)
            )
    }
}

// MARK: - 礼簿封面卡（全 App 唯一的记忆点，其余表面安静克制）
// 左：封面块（朱砂/白事素灰蓝，竖排事由 + 印点 + 描金边，顶部高光模拟纸面光泽）
// 右：标题、日期备注、收/随小计与笔数

public struct LedgerCoverCard: View {
    public let ledger: Ledger
    public let receivedCents: Int
    public let givenCents: Int
    public let count: Int

    public init(ledger: Ledger, receivedCents: Int, givenCents: Int, count: Int) {
        self.ledger = ledger
        self.receivedCents = receivedCents
        self.givenCents = givenCents
        self.count = count
    }

    private var isBai: Bool { ledger.isBai }

    public var body: some View {
        HStack(spacing: 14) {
            coverBlock
            VStack(alignment: .leading, spacing: 4) {
                Text(ledger.title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(isBai ? Palette.baiInk : Palette.ink)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.system(size: 12.5))
                    .foregroundStyle(isBai ? Palette.baiStone : Palette.stone)
                    .lineLimit(1)
                HStack(spacing: 0) {
                    Text("收 ")
                        .font(.system(size: 12.5))
                        .foregroundStyle(isBai ? Palette.baiStone : Palette.stone)
                    Text(LedgerMath.fmtMoney(cents: receivedCents))
                        .font(.liqianMoney(size: 15))
                        .foregroundStyle(isBai ? Palette.baiInk : Palette.primary)
                    Spacer().frame(width: 14)
                    Text("随 ")
                        .font(.system(size: 12.5))
                        .foregroundStyle(isBai ? Palette.baiStone : Palette.stone)
                    Text(LedgerMath.fmtMoney(cents: givenCents))
                        .font(.liqianMoney(size: 15))
                        .foregroundStyle(isBai ? Palette.baiInk : Palette.ink)
                    Spacer()
                    Text("\(count) 笔")
                        .font(.system(size: 12.5))
                        .foregroundStyle(isBai ? Palette.baiStone : Palette.stone)
                }
                .padding(.top, 6)
            }
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(isBai ? Palette.baiStone : Palette.stone)
        }
        .padding(12)
        .frame(minHeight: LiqianMetrics.minTapTarget)
        .background(
            isBai ? Palette.baiCard : Palette.card,
            in: RoundedRectangle(cornerRadius: LiqianMetrics.coverCorner)
        )
        .overlay(
            RoundedRectangle(cornerRadius: LiqianMetrics.coverCorner)
                .stroke(isBai ? Palette.baiLine : Palette.hairline, lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: LiqianMetrics.coverCorner))
    }

    private var subtitle: String {
        // 公历 + 农历（婚丧嫁娶看农历是刚需）；有备注时排在最后，超长由 lineLimit 截断
        let base = "\(ledger.date) · \(LiqianDate.lunarString(for: ledger.date))"
        return ledger.note.isEmpty ? base : "\(base) · \(ledger.note)"
    }

    private var coverBlock: some View {
        let base = isBai ? Palette.baiPrimary : Palette.primary
        return ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(base)
            // 顶部亮面：白 0.28 → 透明（同 Flutter 封面渐变口径）
            RoundedRectangle(cornerRadius: 8)
                .fill(
                    LinearGradient(
                        colors: [.white.opacity(0.28), .white.opacity(0)],
                        startPoint: .top,
                        endPoint: .center
                    )
                )
            VStack(spacing: 6) {
                Text(ledger.type.map { String($0) }.joined(separator: "\n"))
                    .font(.liqianSerif(size: 20))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
                Circle()
                    .fill(isBai ? Palette.baiLine : Palette.paper)
                    .frame(width: 7, height: 7)
            }
            VStack {
                Rectangle()
                    .fill(.white.opacity(0.4))
                    .frame(height: 1)
                    .padding(.horizontal, 9)
                    .padding(.top, 3)
                Spacer()
            }
        }
        .frame(width: 56, height: 92)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isBai ? Palette.baiLine : Palette.gold, lineWidth: 1)
        )
    }
}

// MARK: - 统一卡片表面：卡面色 + hairline 描边 + 18 圆角（白事传 bai: true 换白事令牌）

public extension View {
    func liqianCardSurface(bai: Bool = false, padding: CGFloat = LiqianMetrics.cardPadding) -> some View {
        self
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                bai ? Palette.baiCard : Palette.card,
                in: RoundedRectangle(cornerRadius: LiqianMetrics.cardCorner)
            )
            .overlay(
                RoundedRectangle(cornerRadius: LiqianMetrics.cardCorner)
                    .stroke(bai ? Palette.baiLine : Palette.hairline, lineWidth: 1)
            )
    }
}

// MARK: - 印章：朱砂圆角方印、白字衬线（礼谱 PDF 封面/汇总页用同款造型绘制）
// PDF 与分享图卡是静态绘制，那边按此规格复刻：圆角 8、朱砂底、描金边（白事无金）。

public struct SealStampView: View {
    /// 印面字（通常取礼簿名首字）
    public let char: String
    public let size: CGFloat
    public let bai: Bool
    /// 描金边（白事强制关）
    public let goldBorder: Bool

    public init(char: String, size: CGFloat = 56, bai: Bool = false, goldBorder: Bool = true) {
        self.char = char
        self.size = size
        self.bai = bai
        self.goldBorder = goldBorder
    }

    public var body: some View {
        let bg = bai ? Palette.baiPrimary : Palette.primary
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.16)
                .fill(bg)
            // 印面内框：白文印的内细线
            RoundedRectangle(cornerRadius: size * 0.10)
                .stroke(.white.opacity(0.55), lineWidth: 1)
                .padding(size * 0.09)
            Text(char)
                .font(.liqianSerif(size: size * 0.52))
                .foregroundStyle(.white)
        }
        .frame(width: size, height: size)
        .overlay(
            RoundedRectangle(cornerRadius: size * 0.16)
                .stroke(bai || !goldBorder ? Color.clear : Palette.gold, lineWidth: 1)
        )
    }
}

// MARK: - 落印呈现：盖印动画（放大落下→回正停留→淡出），Reduce Motion 时只淡入淡出
// 用法：父视图维护 presented 布尔，true 时 overlay 本视图；动画时长约 1 秒，
// 父视图在 ~1.05 秒后置回 false 或执行后续动作（如 dismiss）。

public struct SealStampOverlay: View {
    public let char: String
    public let bai: Bool
    public let presented: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var landed = false

    public init(char: String, bai: Bool = false, presented: Bool) {
        self.char = char
        self.bai = bai
        self.presented = presented
    }

    public var body: some View {
        ZStack {
            if presented {
                SealStampView(char: char, size: 84, bai: bai)
                    .scaleEffect(reduceMotion ? 1 : (landed ? 1 : 1.7))
                    .rotationEffect(.degrees(reduceMotion ? 0 : (landed ? 0 : -8)))
                    .opacity(landed ? 1 : 0)
                    .shadow(color: .black.opacity(0.18), radius: 10, y: 4)
                    .onAppear {
                        landed = false
                        if reduceMotion {
                            withAnimation(.easeIn(duration: 0.2)) { landed = true }
                        } else {
                            withAnimation(.bouncy(duration: 0.45)) { landed = true }
                        }
                    }
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - 按压反馈按钮样式：按下缩放 0.98（弹簧），减动效开启时不缩放

public struct ScaleOnPressButtonStyle: ButtonStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        PressableLabel(configuration: configuration)
    }

    private struct PressableLabel: View {
        let configuration: ButtonStyleConfiguration
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        var body: some View {
            configuration.label
                .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1.0)
                .animation(.snappy, value: configuration.isPressed)
        }
    }
}
