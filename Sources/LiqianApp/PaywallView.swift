import SwiftUI
import LiqianCore
import LiqianDesign

/// 礼记 Pro 付费墙（v5 买断闭环）：一次买断、不自动续费。
/// 文案纪律：权益清单只写已实现项；成书只写「装订成书即将开放」，
/// 不许诺可下单（实体履约走导出页的人工内测意向登记）。
/// 价格只读 Product.displayPrice（商店侧维护），代码不写死价格。
/// 购买与恢复购买同级呈现（两个大按钮并列同规格）。
struct PaywallView: View {
    @EnvironmentObject private var entitlements: EntitlementCenter
    @Environment(\.dismiss) private var dismiss

    private var store: StoreKitManager { entitlements.store }

    var body: some View {
        List {
            Section {
                VStack(spacing: LiqianMetrics.spacingSM) {
                    SealStampView(char: "礼", size: 56)
                    Text("礼记 Pro")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(Palette.ink)
                    Text("一次买断，长期使用 · 不自动续费")
                        .font(.subheadline)
                        .foregroundStyle(Palette.stone)
                    if entitlements.isPro {
                        Label("已开通，全部权益可用", systemImage: "checkmark.seal.fill")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Palette.primary)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, LiqianMetrics.spacingS)
                .listRowBackground(Color.clear)
            }

            Section {
                benefitRow("导出为 CSV 表格，可用 Excel 打开、打印、对账", done: true)
                benefitRow("纪念版礼谱：带「紀念」题签的留存版礼谱", done: true)
                benefitRow("家族汇册：多本礼簿合并成一部家族礼谱", done: true)
                benefitRow("印刷版礼谱：带出血与封面展开图，可直接交印厂", done: true)
                benefitRow("装订成书即将开放：把礼谱做成实体书（首批人工履约内测）", done: false)
            } header: {
                Text("Pro 权益")
            } footer: {
                Text("基础礼谱 PDF 与完整备份（你的数据随时能带走）始终免费，不在 Pro 门控内。")
            }

            if !entitlements.isPro {
                Section {
                    VStack(spacing: LiqianMetrics.spacingSM) {
                        Button {
                            Task { await store.purchase() }
                        } label: {
                            HStack {
                                Spacer()
                                if store.isPurchasing {
                                    ProgressView()
                                } else {
                                    Text("买断开通\(priceSuffix)")
                                        .font(.headline)
                                }
                                Spacer()
                            }
                            .frame(minHeight: LiqianMetrics.minTapTarget)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Palette.primary)
                        .disabled(store.isPurchasing || store.isRestoring)

                        Button {
                            Task { await store.restore() }
                        } label: {
                            HStack {
                                Spacer()
                                if store.isRestoring {
                                    ProgressView()
                                } else {
                                    Text("恢复购买")
                                        .font(.headline)
                                }
                                Spacer()
                            }
                            .frame(minHeight: LiqianMetrics.minTapTarget)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Palette.stone)
                        .disabled(store.isPurchasing || store.isRestoring)

                        if let error = store.lastError {
                            Text(error)
                                .font(.footnote)
                                .foregroundStyle(Palette.danger)
                        }
                    }
                    .listRowBackground(Color.clear)
                } footer: {
                    Text("买断由 App Store 处理：一次付费、绑定你的 Apple 账户，换设备点「恢复购买」即可找回。")
                }
            }

            #if LIQIAN_OWNER_BUILD
            Section {
                Text("本机为机主构建（LIQIAN_OWNER_BUILD）：权益已放行，未经商店购买。此版本不上架。")
                    .font(.footnote)
                    .foregroundStyle(Palette.stone)
            }
            #endif
        }
        .listStyle(.insetGrouped)
        .background(Palette.groupedBackground.ignoresSafeArea())
        .navigationTitle("礼记 Pro")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if store.product == nil { await store.loadProduct() }
            await store.refreshEntitlements()
        }
        .onChange(of: entitlements.isPro) { _, isPro in
            // 只在本页内购买/恢复成功时自动离开；已购用户进来查看权益
            // 不受影响（权益在进页前已定，不会触发这次变化）
            if isPro && (store.isPurchasing || store.isRestoring) { dismiss() }
        }
    }

    /// 价格后缀：读到商店价才显示，读不到就不写（不猜价、不写死）
    private var priceSuffix: String {
        if let price = store.product?.displayPrice {
            return " · \(price)"
        }
        return ""
    }

    private func benefitRow(_ text: String, done: Bool) -> some View {
        HStack(spacing: LiqianMetrics.spacingSM) {
            Image(systemName: done ? "checkmark.circle.fill" : "clock")
                .foregroundStyle(done ? Palette.primary : Palette.stone)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(Palette.ink)
        }
        .frame(minHeight: LiqianMetrics.minTapTarget)
    }
}
