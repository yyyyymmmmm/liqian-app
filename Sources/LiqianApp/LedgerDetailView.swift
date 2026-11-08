import SwiftData
import SwiftUI
import LiqianCore
import LiqianDesign

struct LedgerDetailView: View {
    let ledger: Ledger

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Query private var allRecords: [GiftRecord]
    @Query private var allMembers: [LedgerMember]
    @Query private var allSignatures: [GuestSignature]
    @Query private var allBlessings: [VoiceBlessing]

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
    @State private var showPhotoOCR = false
    @State private var showSceneMode = false
    @State private var ocrResultText = ""
    @State private var showOCRResult = false
    // 活礼谱（v4.2）：记录行长按的两个动作目标
    @State private var signatureRecord: GiftRecord?
    @State private var blessingRecord: GiftRecord?

    private var isBai: Bool { ledger.isBai }

    /// 本簿班子（v4.5）：排序口径与 Core 的 MemberSync.sorted 一致
    /// （角色序 → 加入序 → 姓名），此处对模型直接排，避免值/模型来回映射
    private var members: [LedgerMember] {
        allMembers
            .filter { $0.ledgerID == ledger.id }
            .sorted {
                ($0.roleValue.sortOrder, $0.createdAt, $0.name)
                    < ($1.roleValue.sortOrder, $1.createdAt, $1.name)
            }
    }

    /// 班子摘要（详情页入口行副标题）：如「书记 杨敏杰 · 核实 王芳」，空班子给引导文案
    private var membersSummary: String {
        let named = members.filter { $0.roleValue != .viewer }
        if named.isEmpty {
            return members.isEmpty ? "设主家、书记、核实人" : "共 \(members.count) 人"
        }
        return named.map { "\($0.role) \($0.name)" }.joined(separator: " · ")
    }

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

    /// 活礼谱（v4.2）：本簿全部签名（导出礼谱/电子礼谱用）
    private var ledgerSignatures: [GuestSignature] {
        allSignatures.filter { $0.ledgerID == ledger.id }
    }

    /// 活礼谱（v4.2）：挂在本簿现有记录上的祝福（删掉的记录其祝福不算）
    private var ledgerBlessings: [VoiceBlessing] {
        let ids = Set(records.map(\.id))
        return allBlessings.filter { ids.contains($0.recordID) }
    }

    /// 电子礼谱入口副文案：有签名/祝福就报真实数，没有就只说翻页看
    private var liveSummaryText: String {
        var parts: [String] = []
        if !ledgerSignatures.isEmpty { parts.append("签名 \(ledgerSignatures.count)") }
        if !ledgerBlessings.isEmpty { parts.append("祝福 \(ledgerBlessings.count) 段") }
        return parts.isEmpty ? "翻页看" : parts.joined(separator: " · ")
    }

    var body: some View {
        List {
            Section {
                headerRow
            }

            // 家族协作与传承（v4.5）：班子管理与交接/纪念版是礼簿级事务，
            // 独立成组放在头部之下、记录之上，不进「更多」菜单（菜单顺序是 v2.5 定版）。
            Section {
                NavigationLink {
                    LedgerMembersView(ledger: ledger)
                } label: {
                    HStack(spacing: LiqianMetrics.spacingSM) {
                        Image(systemName: "person.3")
                            .foregroundStyle(Palette.ink)
                            .frame(width: 24)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: LiqianMetrics.spacingXS) {
                            Text("礼簿班子")
                                .foregroundStyle(Palette.ink)
                            Text(membersSummary)
                                .font(.footnote)
                                .foregroundStyle(Palette.stone)
                                .lineLimit(1)
                        }
                        Spacer()
                        if !members.isEmpty {
                            Text("\(members.count) 人")
                                .font(.footnote)
                                .foregroundStyle(Palette.stone)
                        }
                    }
                }
                NavigationLink {
                    HandoverView(ledger: ledger, records: records, members: members)
                } label: {
                    HStack(spacing: LiqianMetrics.spacingSM) {
                        Image(systemName: "arrow.triangle.2.circlepath.doc.on.clipboard")
                            .foregroundStyle(Palette.ink)
                            .frame(width: 24)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: LiqianMetrics.spacingXS) {
                            Text("交接与纪念版")
                                .foregroundStyle(Palette.ink)
                            Text("生成传承包，或导出纪念版礼谱")
                                .font(.footnote)
                                .foregroundStyle(Palette.stone)
                                .lineLimit(1)
                        }
                    }
                }
            }

            // 电子礼谱入口（v4.2 活礼谱）：护城河入口要可见（v2.3 教训），
            // 放头部正下方独立一行，不藏进「更多」菜单
            Section {
                NavigationLink {
                    ElectronicLibuView(ledger: ledger)
                } label: {
                    HStack {
                        Label("电子礼谱", systemImage: "book.pages")
                            .foregroundStyle(Palette.ink)
                        Spacer()
                        Text(liveSummaryText)
                            .font(.footnote)
                            .foregroundStyle(Palette.stone)
                    }
                }
            }

            Section {
                if records.isEmpty {
                    emptyState
                } else {
                    // 行增删动画（v4.4）：以记录 id 集合为值，增删/恢复时整组平滑过渡，
                    // 不再整表跳变；Reduce Motion 时关闭
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
                            // 长按菜单四动作（v4.4 口径对齐）：编辑/删除与左滑同组同序，
                            // 再加活礼谱（v4.2）的签名/语音祝福——此前菜单只有后两项，
                            // 不用左滑的用户在长按里找不到编辑与删除
                            .contextMenu {
                                Button {
                                    editingRecord = record
                                } label: {
                                    Label("编辑", systemImage: "pencil")
                                }
                                Button {
                                    signatureRecord = record
                                } label: {
                                    Label("请来宾签名", systemImage: "signature")
                                }
                                Button {
                                    blessingRecord = record
                                } label: {
                                    Label("语音祝福", systemImage: "waveform")
                                }
                                Divider()
                                Button(role: .destructive) {
                                    recordToDelete = record
                                } label: {
                                    Label("删除", systemImage: "trash")
                                }
                            }
                    }
                }
            }
            .animation(reduceMotion ? nil : .snappy, value: records.map(\.id))

        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Palette.pageBG.ignoresSafeArea())
        .navigationTitle(ledger.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                // 「更多」是本页唯一管理入口（v2.5 包 1/2 定版）：顺序固定为
                // 批量补录／拍照识别礼单（v2.9 紧随批量补录，同为成批录入）／
                // 现场模式（v4.1，收礼台成批录入的现场形态，紧随两个录入入口）／
                // 导出礼谱 PDF／生成贺词／编辑礼簿／删除礼簿，
                // 删除垫底并标 destructive；原页内行动区与页尾删除区已删，
                // 编辑礼簿的工具栏铅笔按钮一并收进本菜单，全页只剩这一个入口。
                Menu {
                    // 批量补录原在底部行动栏，v2.4 随行动栏取消移入「更多」
                    Button {
                        showBatch = true
                    } label: {
                        Label("批量补录", systemImage: "list.bullet.rectangle")
                    }
                    Button {
                        showPhotoOCR = true
                    } label: {
                        Label("拍照识别礼单", systemImage: "camera.viewfinder")
                    }
                    // 现场模式（v4.1）：礼房收礼台全屏页——连续登记＋语音播报＋
                    // 投屏脱敏＋事后复核，fullScreenCover 沉浸呈现（无 Tab 栏干扰）
                    Button {
                        showSceneMode = true
                    } label: {
                        Label("现场模式", systemImage: "person.wave.2")
                    }
                    // 礼谱 v3：导出走 sheet（确认落款姓名、选谱序文体后现生成）
                    Button {
                        showExport = true
                    } label: {
                        Label("导出礼谱 PDF", systemImage: "doc.richtext")
                    }
                    Button {
                        showGreeting = true
                    } label: {
                        Label("生成贺词", systemImage: "text.quote")
                    }
                    Button {
                        showEditLedger = true
                    } label: {
                        Label("编辑礼簿", systemImage: "pencil")
                    }
                    Button(role: .destructive) {
                        confirmDeleteLedger = true
                    } label: {
                        Label("删除礼簿", systemImage: "trash")
                    }
                } label: {
                    Label("更多", systemImage: "ellipsis.circle")
                }
            }
        }
        // 记账动作收敛到右下角 FAB（v2.4 定版，替代原底部行动栏）。
        // v2.5 包 4：不再隐藏 Tab 栏（pop 后系统补显动画必然慢半拍），
        // FAB 与列表页同口径用 tabBarClearance 避让。
        .overlay(alignment: .bottomTrailing) {
            AddFloatingButton(label: "记一笔", bottomPadding: AddFloatingButton.tabBarClearance) {
                showRecordForm = true
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
            LibuExportView(
                ledger: ledger, records: records,
                signatures: ledgerSignatures, blessings: ledgerBlessings
            )
        }
        .sheet(item: $signatureRecord) { record in
            SignatureCaptureView(person: record.person) { png in
                modelContext.insert(
                    GuestSignature(
                        ledgerID: ledger.id, recordID: record.id,
                        person: record.person, imageData: png
                    )
                )
                try? modelContext.save()
            }
        }
        .sheet(item: $blessingRecord) { record in
            RecordBlessingsView(record: record)
        }
        .sheet(isPresented: $showPhotoOCR) {
            PhotoOCRView(ledger: ledger) { n in
                ocrResultText = "共导入 \(n) 笔收礼"
                showOCRResult = true
            }
        }
        .fullScreenCover(isPresented: $showSceneMode) {
            SceneModeView(ledger: ledger)
        }
        .alert("批量补录完成", isPresented: $showBatchResult) {
            Button("好") {}
        } message: {
            Text(batchResultText)
        }
        .alert("识别导入完成", isPresented: $showOCRResult) {
            Button("好") {}
        } message: {
            Text(ocrResultText)
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
                    // 大字号下标题放行两行（v4.4），正常字号仍单行截断
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
                headerSubtitle
                HStack(spacing: LiqianMetrics.spacingM) {
                    headerStat(label: "收礼", value: received, count: receivedCount)
                    headerStat(label: "随礼", value: given, count: givenCount)
                    VStack(spacing: LiqianMetrics.spacingXS) {
                        Text("\(peopleCount)")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(Palette.ink)
                            .contentTransition(.numericText())
                            .animation(reduceMotion ? nil : .snappy, value: peopleCount)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        Text("人数")
                            .font(.footnote)
                            .foregroundStyle(Palette.stone)
                    }
                }
            }
        }
    }

    /// 头部副标题（公历＋农历）：正常字号横排分段；无障碍大字号时改纵排，
    /// 两段各占一行完整呈现——旧实现横排 HStack 在大字号下两段互相挤压截断
    /// （PRO-AUDIT-2 真机待验遗留：详情封面副标题大字号溢出，v4.4 落地）
    @ViewBuilder
    private var headerSubtitle: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: LiqianMetrics.spacingXS) {
                Text(LiqianDate.displayString(for: ledger.date))
                Text(LiqianDate.lunarString(for: ledger.date))
            }
            .font(.footnote)
            .foregroundStyle(Palette.stone)
        } else {
            HStack(spacing: LiqianMetrics.spacingXS) {
                Text(LiqianDate.displayString(for: ledger.date))
                Text(LiqianDate.lunarString(for: ledger.date))
            }
            .font(.footnote)
            .foregroundStyle(Palette.stone)
        }
    }

    private func headerStat(label: String, value: Int, count: Int) -> some View {
        VStack(spacing: LiqianMetrics.spacingXS) {
            Text(LedgerMath.fmtMoney(cents: value))
                .font(.liqianMoney(.title3))
                .foregroundStyle(Palette.ink)
                .contentTransition(.numericText())
                .animation(reduceMotion ? nil : .snappy, value: value)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
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
                    // 副行只留关系·方式（·备注）（v2.4 定版）：日期移入右列，
                    // 不再挤在副行中段把一行拆成两截
                    Text(r.note.isEmpty
                        ? "\(r.relation) · \(r.method)"
                        : "\(r.relation) · \(r.method) · \(r.note)")
                        .font(.footnote)
                        .foregroundStyle(Palette.stone)
                        .lineLimit(1)
                }
                Spacer()
                // 右列：金额（上）＋日期（下，右对齐次级色），纵向成列方便扫读
                VStack(alignment: .trailing, spacing: LiqianMetrics.spacingXS) {
                    SignedMoneyText(cents: r.amountCents, direction: r.direction, bai: isBai)
                    Text(LiqianDate.displayString(for: r.date))
                        .font(.footnote)
                        .foregroundStyle(Palette.stone)
                }
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
        let ms = members
        TrashStore.archive(ledger: ledger, records: records, members: ms)
        for r in records {
            modelContext.delete(r)
        }
        for m in ms {
            modelContext.delete(m)
        }
        modelContext.delete(ledger)
        try? modelContext.save()
        deleteTrigger += 1
        dismiss()
    }
}
