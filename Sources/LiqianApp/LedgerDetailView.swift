import SwiftData
import SwiftUI
import LiqianCore
import LiqianDesign

struct LedgerDetailView: View {
    let ledger: Ledger

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query private var allRecords: [GiftRecord]

    @State private var showRecordForm = false
    @State private var editingRecord: GiftRecord?
    @State private var showBatch = false
    @State private var showEditLedger = false
    @State private var confirmDeleteLedger = false
    @State private var recordToDelete: GiftRecord?
    @State private var batchResultText = ""
    @State private var showBatchResult = false
    @State private var deleteTrigger = 0

    private var isBai: Bool { ledger.isBai }

    private var records: [GiftRecord] {
        allRecords
            .filter { $0.ledgerID == ledger.id }
            .sorted { $0.date > $1.date }
    }

    private var received: Int {
        records.filter { $0.direction == LiqianConstants.received }.reduce(0) { $0 + $1.amountCents }
    }

    private var given: Int {
        records
            .filter { $0.direction == LiqianConstants.given && !$0.isPendingSend }
            .reduce(0) { $0 + $1.amountCents }
    }

    private var receivedCount: Int {
        records.filter { $0.direction == LiqianConstants.received }.count
    }

    private var givenCount: Int {
        records.filter { $0.direction == LiqianConstants.given && !$0.isPendingSend }.count
    }

    private var peopleCount: Int {
        Set(records.map(\.person)).count
    }

    var body: some View {
        List {
            Section {
                statsCard
            }
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 4, trailing: 16))

            Section {
                if records.isEmpty {
                    emptyState
                } else {
                    ForEach(records) { record in
                        recordRow(record)
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) {
                                    recordToDelete = record
                                } label: {
                                    Label("删除", systemImage: "trash")
                                }
                                Button {
                                    editingRecord = record
                                } label: {
                                    Label("编辑", systemImage: "pencil")
                                }
                            }
                    }
                }
            }

            Section {
                Button(role: .destructive) {
                    confirmDeleteLedger = true
                } label: {
                    Text("删除这本礼簿")
                        .frame(maxWidth: .infinity, minHeight: LiqianMetrics.minTapTarget)
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background((isBai ? Palette.baiPaper : Palette.paper).ignoresSafeArea())
        .navigationTitle(ledger.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showEditLedger = true
                } label: {
                    Label("编辑礼簿", systemImage: "pencil")
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            GlassEffectContainer(spacing: 12) {
                HStack(spacing: 12) {
                    Button {
                        showRecordForm = true
                    } label: {
                        Label("记一笔", systemImage: "plus")
                            .frame(maxWidth: .infinity, minHeight: LiqianMetrics.minTapTarget)
                    }
                    .buttonStyle(.glassProminent)
                    .tint(isBai ? Palette.baiPrimary : Palette.primary)

                    Button {
                        showBatch = true
                    } label: {
                        Label("批量补录", systemImage: "list.bullet.rectangle")
                            .frame(minHeight: LiqianMetrics.minTapTarget)
                    }
                    .buttonStyle(.glass)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
        }
        .sheet(isPresented: $showRecordForm) {
            RecordFormView(ledger: ledger)
        }
        .sheet(item: $editingRecord) { record in
            RecordFormView(existing: record)
        }
        .sheet(isPresented: $showBatch) {
            BatchEntryView(ledger: ledger) { n in
                batchResultText = "共记 \(n) 笔"
                showBatchResult = true
            }
        }
        .sheet(isPresented: $showEditLedger) {
            LedgerFormView(existing: ledger)
        }
        .alert("批量补录完成", isPresented: $showBatchResult) {
            Button("好") {}
        } message: {
            Text(batchResultText)
        }
        .alert(
            "删除这笔记录？",
            isPresented: Binding(
                get: { recordToDelete != nil },
                set: { if !$0 { recordToDelete = nil } }
            )
        ) {
            Button("删除", role: .destructive) {
                if let r = recordToDelete { deleteRecord(r) }
                recordToDelete = nil
            }
            Button("取消", role: .cancel) { recordToDelete = nil }
        } message: {
            Text("删了恢复不了。")
        }
        .confirmationDialog("删除这本礼簿？", isPresented: $confirmDeleteLedger, titleVisibility: .visible) {
            Button("删除", role: .destructive) { deleteLedger() }
            Button("取消", role: .cancel) {}
        } message: {
            Text("礼簿里的记录会一并删除，删了恢复不了。")
        }
        .sensoryFeedback(.warning, trigger: deleteTrigger)
    }

    private var statsCard: some View {
        HStack {
            stat(label: "收礼", value: LedgerMath.fmtMoney(cents: received), count: receivedCount, color: isBai ? Palette.baiPrimary : Palette.primary, numericValue: received)
            Spacer()
            stat(label: "随礼", value: LedgerMath.fmtMoney(cents: given), count: givenCount, color: isBai ? Palette.baiInk : Palette.ink, numericValue: given)
            Spacer()
            VStack(spacing: 2) {
                Text("\(peopleCount)")
                    .font(.liqianSerif(size: 18))
                    .foregroundStyle(isBai ? Palette.baiInk : Palette.ink)
                    .contentTransition(.numericText())
                Text("人数")
                    .font(.system(size: 12))
                    .foregroundStyle(isBai ? Palette.baiStone : Palette.stone)
            }
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 12)
        .background(
            isBai ? Palette.baiCard : Palette.card,
            in: RoundedRectangle(cornerRadius: LiqianMetrics.cardCorner)
        )
        .overlay(
            RoundedRectangle(cornerRadius: LiqianMetrics.cardCorner)
                .stroke(isBai ? Palette.baiLine : Palette.hairline, lineWidth: 1)
        )
    }

    private func stat(label: String, value: String, count: Int, color: Color, numericValue: Int) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.liqianSerif(size: 18))
                .foregroundStyle(color)
                .contentTransition(.numericText())
                .animation(reduceMotion ? nil : .snappy, value: numericValue)
            Text("\(label) · \(count) 笔")
                .font(.system(size: 12))
                .foregroundStyle(isBai ? Palette.baiStone : Palette.stone)
        }
    }

    private var emptyState: some View {
        VStack(spacing: LiqianMetrics.spacingS) {
            Text("这本礼簿还空着，记第一笔吧。")
                .font(.system(size: 15))
                .foregroundStyle(isBai ? Palette.baiPrimary : Palette.stone)
            Button("记一笔") {
                showRecordForm = true
            }
            .foregroundStyle(isBai ? Palette.baiPrimary : Palette.primary)
            .frame(minHeight: LiqianMetrics.minTapTarget)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 40)
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }

    private func recordRow(_ r: GiftRecord) -> some View {
        Button {
            editingRecord = r
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(r.person)
                            .foregroundStyle(isBai ? Palette.baiInk : Palette.ink)
                        DirectionTag(direction: r.direction, bai: isBai)
                        if r.isPendingSend {
                            PendingTag(bai: isBai)
                        }
                    }
                    Text(subtitle(of: r))
                        .font(.system(size: 12.5))
                        .foregroundStyle(isBai ? Palette.baiStone : Palette.stone)
                }
                Spacer()
                Text(LedgerMath.fmtMoney(cents: r.amountCents))
                    .font(.liqianMoney(size: 16))
                    .foregroundStyle(
                        r.direction == LiqianConstants.received
                            ? (isBai ? Palette.baiPrimary : Palette.primary)
                            : (isBai ? Palette.baiInk : Palette.ink)
                    )
            }
            .padding(12)
            .background(
                isBai ? Palette.baiCard : Palette.card,
                in: RoundedRectangle(cornerRadius: LiqianMetrics.cardCorner)
            )
            .overlay(
                RoundedRectangle(cornerRadius: LiqianMetrics.cardCorner)
                    .stroke(isBai ? Palette.baiLine : Palette.hairline, lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: LiqianMetrics.cardCorner))
        }
        .buttonStyle(.plain)
    }

    private func subtitle(of r: GiftRecord) -> String {
        var s = "\(r.relation) · \(r.method) · \(r.date)"
        if !r.note.isEmpty { s += " · \(r.note)" }
        return s
    }

    private func deleteRecord(_ r: GiftRecord) {
        modelContext.delete(r)
        try? modelContext.save()
        deleteTrigger += 1
    }

    private func deleteLedger() {
        for r in records {
            modelContext.delete(r)
        }
        modelContext.delete(ledger)
        try? modelContext.save()
        deleteTrigger += 1
        dismiss()
    }
}
