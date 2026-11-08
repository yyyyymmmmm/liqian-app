import SwiftData
import SwiftUI
import LiqianCore
import LiqianDesign

/// 宾客回执·待确认区（v5.12）：宾客扫码自填的回执先落这里，
/// 主家逐条点头才入账——带金额的「入账」走现成记一笔表单预填，
/// 保存成功才置已处理并关联那笔记录；没金额的只有「已阅」；
/// 「忽略」置已忽略并顺手删云端那条（best-effort）。
struct GuestReceiptsView: View {
    let ledger: Ledger

    @Environment(\.modelContext) private var modelContext
    @Query private var allReceipts: [GuestReceipt]
    @ObservedObject private var center = GuestSyncCenter.shared

    @State private var bookingReceipt: GuestReceipt?

    private var receipts: [GuestReceipt] {
        allReceipts.filter { $0.ledgerID == ledger.id }
    }

    private var pending: [GuestReceipt] {
        receipts
            .filter { $0.status == .pending }
            .sorted { $0.serverID > $1.serverID }
    }

    private var handled: [GuestReceipt] {
        receipts
            .filter { $0.status != .pending }
            .sorted { $0.serverID > $1.serverID }
    }

    private var isBai: Bool { ledger.isBai }

    var body: some View {
        List {
            Section {
                HStack {
                    Text(center.status(for: ledger.id) ?? "还没同步过")
                        .font(.footnote)
                        .foregroundStyle(Palette.stone)
                    Spacer()
                    if center.isSyncing(ledger.id) {
                        ProgressView()
                    } else {
                        Button {
                            Task { await center.sync(ledgerID: ledger.id, in: modelContext) }
                        } label: {
                            Label("同步", systemImage: "arrow.clockwise")
                                .font(.footnote)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(Palette.primary)
                    }
                }
            }

            if receipts.isEmpty {
                Section {
                    ContentUnavailableView {
                        Label("还没有宾客回执", systemImage: "person.2.wave.2")
                    } description: {
                        Text("宾客扫码提交后，会先到这里。")
                    }
                    .padding(.vertical, LiqianMetrics.spacingL)
                    .listRowBackground(Color.clear)
                }
            }

            if !pending.isEmpty {
                Section("待确认") {
                    ForEach(pending) { receipt in
                        pendingRow(receipt)
                    }
                }
            }

            if !handled.isEmpty {
                Section("已处理") {
                    ForEach(handled) { receipt in
                        handledRow(receipt)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Palette.pageBG.ignoresSafeArea())
        .navigationTitle("宾客回执")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await center.sync(ledgerID: ledger.id, in: modelContext)
        }
        .sheet(item: $bookingReceipt) { receipt in
            if let cents = receipt.amountCents {
                RecordFormView(
                    ledger: ledger,
                    receiptName: receipt.name,
                    receiptAmountCents: cents,
                    receiptNote: GuestReceiptMapping.recordNote(blessing: receipt.blessing)
                ) { record in
                    markBooked(receipt, recordID: record.id)
                }
            }
        }
    }

    // MARK: - 行

    @ViewBuilder
    private func pendingRow(_ receipt: GuestReceipt) -> some View {
        VStack(alignment: .leading, spacing: LiqianMetrics.spacingS) {
            HStack(alignment: .top, spacing: LiqianMetrics.spacingSM) {
                VStack(alignment: .leading, spacing: LiqianMetrics.spacingXS) {
                    Text(receipt.name)
                        .foregroundStyle(Palette.ink)
                    if !receipt.blessing.isEmpty {
                        Text(receipt.blessing)
                            .font(.footnote)
                            .foregroundStyle(Palette.stone)
                    }
                    Text(Self.timeText(receipt))
                        .font(.footnote)
                        .foregroundStyle(Palette.stone)
                }
                Spacer()
                if let cents = receipt.amountCents {
                    SignedMoneyText(cents: cents, direction: LiqianConstants.received, bai: isBai)
                }
            }
            HStack(spacing: LiqianMetrics.spacingSM) {
                if receipt.canBook {
                    Button("入账") {
                        bookingReceipt = receipt
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .tint(isBai ? Palette.baiPrimaryFill : Palette.primaryFill)
                } else {
                    Button("已阅") {
                        markRead(receipt)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                Button("忽略") {
                    dismiss(receipt)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(.vertical, LiqianMetrics.spacingXS)
    }

    private func handledRow(_ receipt: GuestReceipt) -> some View {
        HStack(alignment: .top, spacing: LiqianMetrics.spacingSM) {
            VStack(alignment: .leading, spacing: LiqianMetrics.spacingXS) {
                Text(receipt.name)
                    .foregroundStyle(Palette.stone)
                if !receipt.blessing.isEmpty {
                    Text(receipt.blessing)
                        .font(.footnote)
                        .foregroundStyle(Palette.stone)
                        .lineLimit(1)
                }
            }
            Spacer()
            Text(handledLabel(receipt))
                .font(.footnote)
                .foregroundStyle(Palette.stone)
        }
    }

    private func handledLabel(_ receipt: GuestReceipt) -> String {
        switch receipt.status {
        case .accepted:
            return receipt.linkedRecordID != nil ? "已入账" : "已阅"
        case .dismissed:
            return "已忽略"
        case .pending:
            return ""
        }
    }

    // MARK: - 处理动作

    /// 入账保存成功回调：置已处理并关联记录；表单「保存并继续」可能
    /// 多次回调，这里按状态幂等——已处理过的回执不再动。
    private func markBooked(_ receipt: GuestReceipt, recordID: UUID) {
        guard receipt.status == .pending else { return }
        receipt.status = .accepted
        receipt.linkedRecordID = recordID
        receipt.handledAt = Date()
        try? modelContext.save()
    }

    private func markRead(_ receipt: GuestReceipt) {
        receipt.status = .accepted
        receipt.handledAt = Date()
        try? modelContext.save()
    }

    private func dismiss(_ receipt: GuestReceipt) {
        receipt.status = .dismissed
        receipt.handledAt = Date()
        try? modelContext.save()
        Task { await center.deleteOnServer(receipt: receipt, in: modelContext) }
    }

    // MARK: - 时间

    static func timeText(_ receipt: GuestReceipt) -> String {
        guard let date = receipt.createdAtDate else { return "" }
        let formatter = DateFormatter()
        formatter.dateFormat = "M月d日 HH:mm"
        return formatter.string(from: date)
    }
}
