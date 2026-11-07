import SwiftData
import SwiftUI
import LiqianCore
import LiqianDesign

struct LedgersView: View {
    @Query(sort: \Ledger.date, order: .reverse) private var ledgers: [Ledger]
    @Query private var records: [GiftRecord]
    @State private var showNewLedger = false
    @Namespace private var zoomSpace
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var totalReceived: Int {
        records.filter { $0.direction == LiqianConstants.received }.reduce(0) { $0 + $1.amountCents }
    }

    private var totalGiven: Int {
        records
            .filter { $0.direction == LiqianConstants.given && !$0.isPendingSend }
            .reduce(0) { $0 + $1.amountCents }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: LiqianMetrics.spacingM) {
                    Text("礼簿")
                        .font(.liqianBigTitle)
                        .foregroundStyle(Palette.ink)
                    summaryCard
                    if ledgers.isEmpty {
                        emptyState
                    } else {
                        LazyVStack(spacing: 12) {
                            ForEach(ledgers) { ledger in
                                NavigationLink {
                                    LedgerDetailView(ledger: ledger)
                                        .navigationTransition(.zoom(sourceID: ledger.id, in: zoomSpace))
                                } label: {
                                    LedgerCoverCard(
                                        ledger: ledger,
                                        receivedCents: received(of: ledger),
                                        givenCents: given(of: ledger),
                                        count: count(of: ledger)
                                    )
                                    .matchedTransitionSource(id: ledger.id, in: zoomSpace)
                                }
                                .buttonStyle(ScaleOnPressButtonStyle())
                            }
                        }
                        .animation(reduceMotion ? nil : .snappy, value: ledgers.count)
                    }
                }
                .padding(LiqianMetrics.spacingM)
            }
            .background(Palette.paper.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showNewLedger = true
                    } label: {
                        Label("新建礼簿", systemImage: "plus")
                    }
                }
            }
            .sheet(isPresented: $showNewLedger) {
                LedgerFormView()
            }
        }
    }

    private var summaryCard: some View {
        HStack {
            stat(label: "累计收礼", value: LedgerMath.fmtMoney(cents: totalReceived), color: Palette.primary, numericValue: totalReceived)
            Spacer()
            stat(label: "累计随礼", value: LedgerMath.fmtMoney(cents: totalGiven), color: Palette.ink, numericValue: totalGiven)
            Spacer()
            stat(label: "礼簿", value: "\(ledgers.count) 本", color: Palette.ink, numericValue: ledgers.count)
        }
        .padding(.vertical, LiqianMetrics.spacingM)
        .padding(.horizontal, 12)
        .background(Palette.card, in: RoundedRectangle(cornerRadius: LiqianMetrics.cardCorner))
        .overlay(
            RoundedRectangle(cornerRadius: LiqianMetrics.cardCorner)
                .stroke(Palette.hairline, lineWidth: 1)
        )
    }

    private func stat(label: String, value: String, color: Color, numericValue: Int) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.liqianMoney(size: 22))
                .foregroundStyle(color)
                .contentTransition(.numericText())
                .animation(reduceMotion ? nil : .snappy, value: numericValue)
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(Palette.stone)
        }
    }

    private var emptyState: some View {
        VStack(spacing: LiqianMetrics.spacingS) {
            Text("还没有礼簿，从最近一场事开始记。")
                .font(.system(size: 15))
                .foregroundStyle(Palette.stone)
            Button("新建第一本礼簿") {
                showNewLedger = true
            }
            .foregroundStyle(Palette.primary)
            .frame(minHeight: LiqianMetrics.minTapTarget)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 48)
    }

    private func received(of ledger: Ledger) -> Int {
        records
            .filter { $0.ledgerID == ledger.id && $0.direction == LiqianConstants.received }
            .reduce(0) { $0 + $1.amountCents }
    }

    private func given(of ledger: Ledger) -> Int {
        records
            .filter { $0.ledgerID == ledger.id && $0.direction == LiqianConstants.given && !$0.isPendingSend }
            .reduce(0) { $0 + $1.amountCents }
    }

    private func count(of ledger: Ledger) -> Int {
        records.filter { $0.ledgerID == ledger.id }.count
    }
}
