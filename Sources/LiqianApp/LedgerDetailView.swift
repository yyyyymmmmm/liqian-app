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
    @State private var showExport = false
    @State private var showGreeting = false

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
                headerRow
            }

            // 礼谱是护城河功能，入口不藏菜单：一眼可见的行动区（菜单里保留同入口）
            Section {
                Button {
                    showExport = true
                } label: {
                    Label("导出礼谱 PDF", systemImage: "doc.richtext")
                        .foregroundStyle(isBai ? Palette.baiInk : Palette.ink)
                        .frame(minHeight: LiqianMetrics.minTapTarget)
                }
                Button {
                    showGreeting = true
                } label: {
                    Label("生成贺词", systemImage: "text.quote")
                        .foregroundStyle(isBai ? Palette.baiInk : Palette.ink)
                        .frame(minHeight: LiqianMetrics.minTapTarget)
                }
            }

            Section {
                if records.isEmpty {
                    emptyState
                } else {
                    ForEach(records) { record in
                        recordRow(record)
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
        .listStyle(.insetGrouped)
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
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    // 礼谱 v3：导出走 sheet（确认落款姓名、选谱序文体后现生成）
                    Button {
                        showExport = true
                    } label: {
                        Label("导出礼谱", systemImage: "doc.richtext")
                    }
                    Button {
                        showGreeting = true
                    } label: {
                        Label("生成贺词", systemImage: "text.quote")
                    }
                } label: {
                    Label("更多", systemImage: "ellipsis.circle")
                }
            }
        }
        .toolbar(.hidden, for: .tabBar)
        .safeAreaInset(edge: .bottom) {
            GlassEffectContainer(spacing: LiqianMetrics.spacingSM) {
                HStack(spacing: LiqianMetrics.spacingSM) {
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
                .padding(.horizontal, LiqianMetrics.spacingM)
                .padding(.vertical, LiqianMetrics.spacingS)
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
        .sheet(isPresented: $showGreeting) {
            GreetingView(ledger: ledger)
        }
        .sheet(isPresented: $showExport) {
            LibuExportView(ledger: ledger, records: records)
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
            Text("删除后 30 天内可以在「我的 → 最近删除」恢复。")
        }
        .confirmationDialog("删除这本礼簿？", isPresented: $confirmDeleteLedger, titleVisibility: .visible) {
            Button("删除", role: .destructive) { deleteLedger() }
            Button("取消", role: .cancel) {}
        } message: {
            Text("礼簿里的记录会一并删除，30 天内可以在「我的 → 最近删除」恢复。")
        }
        .sensoryFeedback(.warning, trigger: deleteTrigger)
    }

    /// 头部行（PRO-AUDIT-2 第 6 项）：左＝封面满块、右＝标题/日期/三列统计，
    /// 置于首个 Section 内。与列表小签构成「小签在列表、满块在详情」的单一 moment 规则。
    private var headerRow: some View {
        HStack(spacing: LiqianMetrics.spacingSM) {
            coverFullBlock
            VStack(alignment: .leading, spacing: LiqianMetrics.spacingS) {
                Text(ledger.title)
                    .font(.headline)
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                HStack(spacing: LiqianMetrics.spacingXS) {
                    Text(LiqianDate.displayString(for: ledger.date))
                    Text(LiqianDate.lunarString(for: ledger.date))
                }
                .font(.footnote)
                .foregroundStyle(Palette.stone)
                HStack(spacing: LiqianMetrics.spacingM) {
                    headerStat(label: "收礼", value: received, count: receivedCount)
                    headerStat(label: "随礼", value: given, count: givenCount)
                    VStack(spacing: LiqianMetrics.spacingXS) {
                        Text("\(peopleCount)")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(Palette.ink)
                            .contentTransition(.numericText())
                        Text("人数")
                            .font(.footnote)
                            .foregroundStyle(Palette.stone)
                    }
                }
            }
        }
    }

    private func headerStat(label: String, value: Int, count: Int) -> some View {
        VStack(spacing: LiqianMetrics.spacingXS) {
            Text(LedgerMath.fmtMoney(cents: value))
                .font(.liqianMoney(.title3))
                .foregroundStyle(Palette.ink)
                .contentTransition(.numericText())
                .animation(reduceMotion ? nil : .snappy, value: value)
            Text("\(label) · \(count) 笔")
                .font(.footnote)
                .foregroundStyle(Palette.stone)
        }
    }

    /// 封面满块 56×92（全 App 唯一满块）：朱砂 Fill 满底、竖排事由衬线（白名单
    /// moment）、印点、无高光。圆角 8 按同心公式：封面语境圆角 20 − 内边距 12 ＝ 8。
    private var coverFullBlock: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(isBai ? Palette.baiPrimaryFill : Palette.primaryFill)
            VStack(spacing: LiqianMetrics.spacingS) {
                Text(ledger.type.map { String($0) }.joined(separator: "\n"))
                    .font(.liqianSerifFixed(size: 20))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
                Circle()
                    .fill(.white)
                    .frame(width: 7, height: 7)
            }
        }
        .frame(width: 56, height: 92)
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("还没有记录", systemImage: "list.bullet")
        } description: {
            Text("从第一笔开始记。")
        } actions: {
            Button("记一笔") {
                showRecordForm = true
            }
            .buttonStyle(.borderedProminent)
            .tint(isBai ? Palette.baiPrimaryFill : Palette.primaryFill)
        }
        .padding(.vertical, LiqianMetrics.spacingL)
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }

    private func recordRow(_ r: GiftRecord) -> some View {
        Button {
            editingRecord = r
        } label: {
            HStack(alignment: .top, spacing: LiqianMetrics.spacingSM) {
                VStack(alignment: .leading, spacing: LiqianMetrics.spacingXS) {
                    HStack(spacing: LiqianMetrics.spacingS) {
                        Text(r.person)
                            .foregroundStyle(Palette.ink)
                        DirectionTag(direction: r.direction, bai: isBai)
                        if r.isPendingSend {
                            PendingTag(bai: isBai)
                        }
                    }
                    // 副行分列（PRO-AUDIT-2 §3.3）：关系·方式在左、日期在右，不再四段一串
                    HStack(spacing: LiqianMetrics.spacingS) {
                        Text("\(r.relation) · \(r.method)")
                        Spacer()
                        Text(LiqianDate.displayString(for: r.date))
                    }
                    .font(.footnote)
                    .foregroundStyle(Palette.stone)
                    if !r.note.isEmpty {
                        Text(r.note)
                            .font(.footnote)
                            .foregroundStyle(Palette.stone)
                            .lineLimit(1)
                    }
                }
                Spacer()
                Text(LedgerMath.fmtMoney(cents: r.amountCents))
                    .font(.liqianMoney(.title3))
                    .foregroundStyle(Palette.ink)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func deleteRecord(_ r: GiftRecord) {
        TrashStore.archive(record: r)
        modelContext.delete(r)
        try? modelContext.save()
        deleteTrigger += 1
    }

    private func deleteLedger() {
        TrashStore.archive(ledger: ledger, records: records)
        for r in records {
            modelContext.delete(r)
        }
        modelContext.delete(ledger)
        try? modelContext.save()
        deleteTrigger += 1
        dismiss()
    }
}
