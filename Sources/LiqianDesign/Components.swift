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
        // 浅签口径（对标大厂列表）：实心填充每行一枚会把强调色摊成底纹；
        // 改浅底＋同色文字，方向靠色相区分，白事/随礼统一素灰蓝
        let fg = isReceived ? (bai ? Palette.baiPrimary : Palette.primary) : Palette.baiPrimary
        let bg = fg.opacity(0.13)
        Text(direction)
            .font(.caption2.weight(.medium))
            .foregroundStyle(fg)
            // 签内边距为签形控件内部微调字面量（PRO-AUDIT §4.1 豁免口径），不走梯队
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(bg, in: RoundedRectangle(cornerRadius: LiqianMetrics.tagCorner))
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
            .font(.caption2)
            .foregroundStyle(color)
            // 同 DirectionTag：签内边距字面量豁免
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .overlay(
                RoundedRectangle(cornerRadius: LiqianMetrics.tagCorner)
                    .stroke(color, lineWidth: 1)
            )
    }
}

// MARK: - 礼簿封面卡（列表行）
// 左：事由小签（朱砂/白事素灰蓝窄签，竖排事由 + 印点）——PRO-AUDIT #6 定版：
// 封面满块是唯一记忆点，只出现在礼簿详情页头部一次；列表逐行重复会把记忆点摊成底纹
// 右：标题、日期备注、收/随小计与笔数（金额一律墨色，v3 纪律）

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
        HStack(spacing: LiqianMetrics.spacingSM) {
            coverBlock
            VStack(alignment: .leading, spacing: LiqianMetrics.spacingXS) {
                Text(ledger.title)
                    .font(.headline)
                    .foregroundStyle(isBai ? Palette.baiInk : Palette.ink)
                    .lineLimit(1)
                subtitleRow
                HStack(spacing: 0) {
                    Text("收礼")
                        .font(.footnote)
                        .foregroundStyle(isBai ? Palette.baiStone : Palette.stone)
                    Text(LedgerMath.fmtMoney(cents: receivedCents))
                        .font(.liqianMoney(.title3))
                        .foregroundStyle(isBai ? Palette.baiInk : Palette.ink)
                    Spacer().frame(width: 14)
                    Text("随礼")
                        .font(.footnote)
                        .foregroundStyle(isBai ? Palette.baiStone : Palette.stone)
                    Text(LedgerMath.fmtMoney(cents: givenCents))
                        .font(.liqianMoney(.title3))
                        .foregroundStyle(isBai ? Palette.baiInk : Palette.ink)
                    Spacer()
                    Text("\(count) 笔")
                        .font(.footnote)
                        .foregroundStyle(isBai ? Palette.baiStone : Palette.stone)
                }
                .padding(.top, LiqianMetrics.spacingS)
            }
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(isBai ? Palette.baiStone : Palette.stone)
        }
        .padding(LiqianMetrics.cardPadding)
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

    /// 副标题分段排布（PRO-AUDIT §4.4：弃用中点拼接的元信息串）：
    /// 公历（displayString 定版格式）/ 农历 / 备注各成一段，备注超长截断
    private var subtitleRow: some View {
        HStack(spacing: LiqianMetrics.spacingXS) {
            Text(LiqianDate.displayString(for: ledger.date))
            Text(LiqianDate.lunarString(for: ledger.date))
            if !ledger.note.isEmpty {
                Text(ledger.note)
                    .lineLimit(1)
            }
        }
        .font(.footnote)
        .foregroundStyle(isBai ? Palette.baiStone : Palette.stone)
    }

    /// 事由小签（PRO-AUDIT #6）：30×64 朱砂窄签、竖排事由、无高光拟物；
    /// 满块封面移交礼簿详情页头部（LedgerDetailView 自有封面块）
    private var coverBlock: some View {
        let base = isBai ? Palette.baiPrimaryFill : Palette.primaryFill
        return ZStack {
            RoundedRectangle(cornerRadius: LiqianMetrics.tagCorner)
                .fill(base)
            VStack(spacing: LiqianMetrics.spacingXS) {
                Text(ledger.type.map { String($0) }.joined(separator: "\n"))
                    .font(.liqianSerifFixed(size: 15))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .lineSpacing(1)
                Circle()
                    .fill(.white)
                    .frame(width: 5, height: 5)
            }
        }
        .frame(width: 30, height: 64)
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

// MARK: - 印章：纯朱砂圆角方印、白字衬线、无金边（v3；礼谱 PDF 封面/汇总页用同款造型绘制）
// PDF 与分享图卡是静态绘制，那边按此规格复刻：圆角 8、朱砂底、白字、内细框。

public struct SealStampView: View {
    /// 印面字（通常取礼簿名首字）
    public let char: String
    public let size: CGFloat
    public let bai: Bool

    public init(char: String, size: CGFloat = 56, bai: Bool = false) {
        self.char = char
        self.size = size
        self.bai = bai
    }

    public var body: some View {
        let bg = bai ? Palette.baiPrimaryFill : Palette.primaryFill
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.16)
                .fill(bg)
            // 印面内框：白文印的内细线
            RoundedRectangle(cornerRadius: size * 0.10)
                .stroke(.white.opacity(0.55), lineWidth: 1)
                .padding(size * 0.09)
            Text(char)
                .font(.liqianSerifFixed(size: size * 0.52))
                .foregroundStyle(.white)
        }
        .frame(width: size, height: size)
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
        .accessibilityHidden(true)
    }
}

// MARK: - 右下角浮动添加按钮（FAB，v2.4 添加模型定版）
// 全 App 新增动作收敛到这一个入口：圆形 56pt、强调填充底、白「+」、带投影。
// 用法：挂在页面根视图的 .overlay(alignment: .bottomTrailing)，
// bottomPadding 由调用方按场景传——Tab 页须避让浮动 Tab 栏（传 tabBarClearance），
// 已隐藏 Tab 栏的详情页传常规间距即可。

public struct AddFloatingButton: View {
    /// 无障碍与提示文案，如「新建礼簿」「记一笔」
    public let label: String
    public let bottomPadding: CGFloat
    public let action: () -> Void

    /// Tab 栏避让量：iOS 26 浮动 Tab 栏（高约 64 + 底部留白）占位约 92pt
    public static let tabBarClearance: CGFloat = 92

    public init(
        label: String,
        bottomPadding: CGFloat = LiqianMetrics.spacingM,
        action: @escaping () -> Void
    ) {
        self.label = label
        self.bottomPadding = bottomPadding
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Image(systemName: "plus")
                .font(.title2.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 56, height: 56)
                .background(Palette.primaryFill, in: Circle())
                .shadow(color: .black.opacity(0.20), radius: 10, x: 0, y: 4)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .padding(.trailing, LiqianMetrics.spacingM)
        .padding(.bottom, bottomPadding)
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
