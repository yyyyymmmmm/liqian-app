import SwiftUI
import SwiftData
import LiqianCore
import LiqianDesign

/// 首开引导（v5，讲尖刀）：三页——尖刀页（礼簿成礼谱）→ 信任页
/// （数据在你自己手里）→ 起簿页（场景预设建第一本）。一次性标记在
/// 呈现方（ContentView）手里，本视图只负责呈现与建簿，关闭走 onFinish。
/// 只服务首开（v5.8.1 起设置页无重看入口，审计 #4）。视觉走 v5 令牌：
/// 纸墨内容＋玻璃功能层（继续钮 Mat.tinted），不新造插画——意象用
/// 礼谱封面小签＋印章（衬线白名单的封面小签/印章 moment，不越界）。
struct OnboardingView: View {
    /// 完成或跳过（呈现方据此关页；首开路径同时置一次性标记）
    let onFinish: () -> Void

    @Environment(\.modelContext) private var modelContext
    @State private var page = 0

    /// 一次性标记键（首开判断在 ContentView）
    static let doneKey = "liqian.onboarding.v5.done"

    var body: some View {
        ZStack(alignment: .topTrailing) {
            TabView(selection: $page) {
                jiandaoPage.tag(0)
                trustPage.tag(1)
                startPage.tag(2)
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .indexViewStyle(.page(backgroundDisplayMode: .interactive))

            if page < 2 {
                Button("跳过") { onFinish() }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Palette.stone)
                    .padding(.horizontal, LiqianMetrics.spacingL)
                    .padding(.vertical, LiqianMetrics.spacingSM)
                    .accessibilityLabel("跳过引导")
            }
        }
        .background(Palette.pageBG.ignoresSafeArea())
    }

    // MARK: - 第 1 页 · 尖刀

    private var jiandaoPage: some View {
        pageShell {
            coverMotif
            Text("把你家的礼簿，\n做成一本能传下去的礼谱")
                .font(.title.weight(.bold))
                .foregroundStyle(Palette.ink)
                .multilineTextAlignment(.center)
            Text("亲友往来先记成礼簿，清清楚楚；时候到了，一键导出印刷级的礼谱，还能装订成书——摆在家里，传给后人。")
                .font(.subheadline)
                .foregroundStyle(Palette.stone)
                .multilineTextAlignment(.center)
                .padding(.horizontal, LiqianMetrics.spacingL)
            continueButton
        }
    }

    /// 礼谱意象：封面小签（竖排衬线，白名单 moment ①）＋印章（moment ②）
    private var coverMotif: some View {
        ZStack(alignment: .bottomTrailing) {
            RoundedRectangle(cornerRadius: LiqianMetrics.coverCorner)
                .fill(Palette.surface)
                .frame(width: 148, height: 196)
                .liqianElevation(LiqianElevation.card)
                .overlay {
                    VStack(spacing: LiqianMetrics.spacingSM) {
                        Text("禮\n譜")
                            .font(.liqianSerifFixed(size: 30))
                            .foregroundStyle(Palette.ink)
                            .multilineTextAlignment(.center)
                            .lineSpacing(4)
                        RoundedRectangle(
                            cornerRadius: LiqianRadius.concentric(
                                container: LiqianMetrics.coverCorner,
                                padding: LiqianMetrics.cardPadding
                            )
                        )
                        .fill(Palette.primaryFill)
                        .frame(width: 30, height: 64)
                        .overlay {
                            Text("婚\n禮")
                                .font(.liqianSerifFixed(size: 14))
                                .foregroundStyle(.white)
                                .multilineTextAlignment(.center)
                                .lineSpacing(2)
                        }
                    }
                }
            SealStampView(char: "礼", size: 46)
                .offset(x: 14, y: 14)
        }
        .padding(.bottom, 14)
    }

    // MARK: - 第 2 页 · 信任

    private var trustPage: some View {
        pageShell {
            Text("你的数据，只在你自己手里")
                .font(.title.weight(.bold))
                .foregroundStyle(Palette.ink)
                .multilineTextAlignment(.center)
            VStack(spacing: LiqianMetrics.spacingM) {
                trustRow(
                    icon: "person.crop.circle.badge.xmark",
                    title: "不用注册账号",
                    detail: "没有手机号绑定、没有服务器账号，开箱就能记。"
                )
                trustRow(
                    icon: "icloud",
                    title: "同步走你自己的 iCloud",
                    detail: "礼簿存在你的 iCloud 里，换手机、重装 App 都能自动回来。"
                )
                trustRow(
                    icon: "tray.and.arrow.up",
                    title: "备份随时带走",
                    detail: "完整备份一键导出、随时能恢复——数据不在任何人手里扣着。基础礼谱导出与备份，始终免费。"
                )
            }
            .padding(.horizontal, LiqianMetrics.spacingM)
            continueButton
        }
    }

    private func trustRow(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: LiqianMetrics.spacingSM) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(Palette.primary)
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(Palette.ink)
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(Palette.stone)
            }
            Spacer(minLength: 0)
        }
        .padding(LiqianMetrics.spacingM)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: LiqianMetrics.cardCorner))
    }

    // MARK: - 第 3 页 · 起簿

    private struct Template: Identifiable {
        let id = UUID()
        let label: String
        let type: String
        let title: String
        let icon: String
        let bai: Bool
    }

    private var templates: [Template] {
        [
            Template(label: "婚礼", type: "婚礼", title: "婚礼礼簿", icon: "heart", bai: false),
            Template(label: "生日", type: "寿宴", title: "生日寿宴礼簿", icon: "birthday.cake", bai: false),
            Template(label: "白事", type: LiqianConstants.baiType, title: "白事礼簿", icon: "leaf", bai: true),
            Template(label: "通用", type: "其他", title: "人情礼簿", icon: "book.closed", bai: false),
        ]
    }

    private var startPage: some View {
        pageShell {
            Text("先起第一本礼簿")
                .font(.title.weight(.bold))
                .foregroundStyle(Palette.ink)
                .multilineTextAlignment(.center)
            Text("选一个最接近的场景，按它的规矩帮你建好；名字和日期以后随时能改。")
                .font(.subheadline)
                .foregroundStyle(Palette.stone)
                .multilineTextAlignment(.center)
                .padding(.horizontal, LiqianMetrics.spacingL)
            LazyVGrid(
                columns: [GridItem(.flexible()), GridItem(.flexible())],
                spacing: LiqianMetrics.spacingSM
            ) {
                ForEach(templates) { template in
                    Button {
                        createLedger(template)
                    } label: {
                        VStack(spacing: LiqianMetrics.spacingS) {
                            Image(systemName: template.icon)
                                .font(.title2)
                                .foregroundStyle(template.bai ? Palette.baiPrimary : Palette.primary)
                            Text(template.label)
                                .font(.headline)
                                .foregroundStyle(template.bai ? Palette.baiInk : Palette.ink)
                            Text(template.type == "寿宴" ? "寿宴 · 生日" : template.type)
                                .font(.caption)
                                .foregroundStyle(Palette.stone)
                        }
                        .frame(maxWidth: .infinity, minHeight: 108)
                        .background(
                            Palette.surface,
                            in: RoundedRectangle(cornerRadius: LiqianMetrics.cardCorner)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, LiqianMetrics.spacingM)
            Button("先不建，看看再说") { onFinish() }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Palette.stone)
                .frame(minHeight: LiqianMetrics.minTapTarget)
        }
    }

    private func createLedger(_ template: Template) {
        let ledger = Ledger(
            title: template.title,
            type: template.type,
            date: LiqianDate.todayString()
        )
        modelContext.insert(ledger)
        try? modelContext.save()
        onFinish()
    }

    // MARK: - 页壳

    private func pageShell<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: LiqianMetrics.spacingL) {
            Spacer()
            content()
            Spacer()
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var continueButton: some View {
        Button {
            withAnimation(MotionTokens.pageCrossfade) { page += 1 }
        } label: {
            Text("继续")
                .font(.headline)
                .frame(maxWidth: .infinity, minHeight: LiqianMetrics.minTapTarget)
        }
        .liqianGlassButton(.tinted)
        .padding(.horizontal, LiqianMetrics.spacingXL)
    }
}
