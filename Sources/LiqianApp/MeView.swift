import SwiftData
import SwiftUI
import UniformTypeIdentifiers
import LiqianCore
import LiqianDesign

/// 「我的」（v2.5 包 5 按大厂设置页重组）：List(.insetGrouped) 原生 Section 与行，
/// 披露箭头由系统唯一提供（手绘 chevron 已全删）。设置页不放数据看板——
/// 原页顶总览统计与待回礼大卡改为「记录」组里的一行入口（人情总览进 StatsView、
/// 待回礼进行内列表页并带总金额值），其余按功能域归档成组：
/// 记录／礼谱／外观／智能／数据／关于。危险操作只留在所属组内用 destructive
/// 确认（覆盖恢复在数据组），不与普通入口混排无标识。全部汇总口径排除示例账本。
struct MeView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var records: [GiftRecord]
    @Query(sort: \Ledger.date, order: .reverse) private var ledgers: [Ledger]

    @State private var csvURL: URL?
    @State private var exportDocument = JSONBackupDocument(data: Data())
    @State private var showExporter = false
    @State private var showImporter = false
    @State private var pendingImport: (ledgers: [BackupLedger], records: [BackupRecord])?
    @State private var showImportConfirm = false
    @State private var infoTitle = ""
    @State private var infoMessage = ""
    @State private var showInfo = false
    @State private var importTrigger = 0
    @AppStorage("privacyLock") private var privacyLock = false
    @AppStorage("hostName") private var hostName = ""
    @AppStorage(AppTheme.storageKey) private var appThemeRaw = AppTheme.day.rawValue

    /// 当前存在的示例账本 ID（统计隔离与示例状态都按它判定）
    private var sampleIDs: Set<UUID> { SampleData.sampleIDs(ledgers: ledgers) }

    /// 汇总口径快照：示例账本的记录不计入（示例是演示数据，不是用户的账）
    private var snapshots: [EntrySnapshot] {
        let ids = sampleIDs
        return AppSupport.snapshots(
            records: records.filter { !ids.contains($0.ledgerID) },
            ledgers: ledgers
        )
    }

    private var pendingPeople: [PersonSummary] {
        LedgerMath.people(from: snapshots).filter { $0.hasPending }
    }

    /// 待回礼总金额（「待回礼」入口行右侧值）
    private var pendingTotal: Int {
        pendingPeople.reduce(0) { $0 + $1.pendingCents }
    }

    /// 待送出件数（「备礼清单」入口行右侧值，口径与备礼清单页一致：全部记录）
    private var prepCount: Int {
        records.filter { $0.isPendingSend }.count
    }

    /// 关于区版本号：动态读 Bundle，避免写死版本过期（PRO-AUDIT #31）
    static var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
    }

    private var csvFingerprint: String {
        "\(records.count)-\(ledgers.count)-\(records.reduce(0) { $0 + $1.amountCents })"
    }

    var body: some View {
        NavigationStack {
            List {
                // —— 记录：数据看板不进设置流（v2.5 包 5）——总览与待回礼
                // 从页顶大卡改为一行入口，明细在各自二级页；按功能域归档。
                Section {
                    NavigationLink {
                        StatsView()
                    } label: {
                        entryLabel(
                            icon: "chart.bar.xaxis",
                            title: "人情总览",
                            subtitle: "年度、事由、往来排行与关系分布"
                        )
                    }
                    NavigationLink {
                        AnnualReportView()
                    } label: {
                        entryLabel(
                            icon: "chart.bar.doc.horizontal",
                            title: "人情年度报告",
                            subtitle: "含往来第一位亲友的姓名与汇总，其余为年度汇总数据"
                        )
                    }
                    NavigationLink {
                        PendingPeopleView()
                    } label: {
                        HStack(spacing: LiqianMetrics.spacingSM) {
                            entryLabel(icon: "arrow.uturn.backward.circle", title: "待回礼")
                            Spacer()
                            Text(pendingPeople.isEmpty ? "无" : LedgerMath.fmtMoney(cents: pendingTotal))
                                .foregroundStyle(pendingPeople.isEmpty ? Palette.stone : Palette.primary)
                        }
                    }
                    NavigationLink {
                        PrepListView()
                    } label: {
                        HStack(spacing: LiqianMetrics.spacingSM) {
                            entryLabel(icon: "gift", title: "备礼清单")
                            Spacer()
                            if prepCount > 0 {
                                Text("\(prepCount) 件")
                                    .foregroundStyle(Palette.stone)
                            }
                        }
                    }
                    NavigationLink {
                        TrashView()
                    } label: {
                        entryLabel(
                            icon: "trash",
                            title: "最近删除",
                            subtitle: "删除的礼簿与记录保留 30 天，过期自动清除，期间可恢复"
                        )
                    }
                } header: {
                    Text("记录")
                }

                Section {
                    NavigationLink {
                        HostNameEditView()
                    } label: {
                        HStack(spacing: LiqianMetrics.spacingSM) {
                            entryLabel(icon: "signature", title: "礼谱落款姓名")
                            Spacer()
                            Text(hostName.isEmpty ? "未设置" : hostName)
                                .foregroundStyle(Palette.stone)
                                .lineLimit(1)
                        }
                    }
                    Button {
                        toggleSamples()
                    } label: {
                        entryLabel(
                            icon: "sparkles",
                            title: "示例礼簿",
                            subtitle: hasSamples ? "已生成示例数据，点按清除" : "生成两本示例礼簿"
                        )
                    }
                } header: {
                    Text("礼谱")
                } footer: {
                    Text("落款姓名用于礼谱封面、谱序落款与主家印，不填时用「主家谨识」。")
                }

                Section {
                    NavigationLink {
                        AppearanceView()
                    } label: {
                        HStack(spacing: LiqianMetrics.spacingSM) {
                            entryLabel(icon: "paintbrush", title: "主题")
                            Spacer()
                            Text((AppTheme(rawValue: appThemeRaw) ?? .day).displayName)
                                .foregroundStyle(Palette.stone)
                        }
                    }
                } header: {
                    Text("外观")
                } footer: {
                    Text("主题只影响 App 界面，导出的礼谱不变。")
                }

                Section {
                    NavigationLink {
                        AISettingsView()
                    } label: {
                        entryLabel(
                            icon: "wand.and.stars",
                            title: "AI 智能助手",
                            subtitle: aiStatusText
                        )
                    }
                } header: {
                    Text("智能")
                }

                Section {
                    csvEntryRow
                    Button {
                        exportDocument = JSONBackupDocument(
                            data: LiqianBackup.makeBackup(ledgers: ledgers, records: records)
                        )
                        showExporter = true
                    } label: {
                        entryLabel(
                            icon: "tray.and.arrow.up",
                            title: "导出备份（JSON）",
                            subtitle: "包含全部礼簿与记录，可用于换机恢复"
                        )
                    }
                    Button {
                        showImporter = true
                    } label: {
                        entryLabel(
                            icon: "tray.and.arrow.down",
                            title: "从备份恢复",
                            subtitle: "选一个备份文件，覆盖现在的数据"
                        )
                    }
                } header: {
                    Text("数据")
                }

                Section {
                    NavigationLink {
                        AboutView()
                    } label: {
                        HStack(spacing: LiqianMetrics.spacingSM) {
                            entryLabel(icon: "info.circle", title: "关于礼钱账本")
                            Spacer()
                            Text(Self.appVersion)
                                .foregroundStyle(Palette.stone)
                        }
                    }
                    Toggle(isOn: $privacyLock) {
                        HStack(spacing: LiqianMetrics.spacingSM) {
                            Image(systemName: "faceid")
                                .foregroundStyle(Palette.ink)
                                .frame(width: 24)
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: LiqianMetrics.spacingXS) {
                                Text("隐私锁")
                                    .foregroundStyle(Palette.ink)
                                Text("从后台返回超过 30 秒需重新解锁；App 在后台时界面自动模糊。")
                                    .font(.footnote)
                                    .foregroundStyle(Palette.stone)
                            }
                        }
                    }
                    .tint(Palette.primary)
                } header: {
                    Text("关于")
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Palette.pageBG.ignoresSafeArea())
            .navigationTitle("我的")
            .navigationBarTitleDisplayMode(.large)
            .task(id: csvFingerprint) {
                csvURL = AppSupport.writeTempFile(
                    name: "礼钱账本导出.csv",
                    content: AppSupport.csvText(records: records, ledgers: ledgers)
                )
            }
            .fileExporter(
                isPresented: $showExporter,
                document: exportDocument,
                contentType: .json,
                defaultFilename: "礼钱账本备份"
            ) { result in
                if case .failure = result {
                    showInfo(title: "导出失败", message: "备份导出失败，请重试。")
                }
            }
            .fileImporter(isPresented: $showImporter, allowedContentTypes: [.json], allowsMultipleSelection: false) { result in
                handleImport(result)
            }
            .confirmationDialog("覆盖恢复？", isPresented: $showImportConfirm, titleVisibility: .visible) {
                Button("覆盖恢复", role: .destructive) { performImport() }
                Button("取消", role: .cancel) {}
            } message: {
                if let p = pendingImport {
                    Text("备份里有 \(p.ledgers.count) 本礼簿、\(p.records.count) 笔记录。现在手机里有 \(ledgers.count) 本礼簿、\(records.count) 笔记录，恢复后会被全部覆盖，覆盖了就回不来了。")
                }
            }
            .alert(infoTitle, isPresented: $showInfo) {
                Button("好") {}
            } message: {
                Text(infoMessage)
            }
            .sensoryFeedback(.success, trigger: importTrigger)
        }
    }

    // MARK: - 行零件

    /// 设置式入口行内容：图标（统一 ink 色、frame 24）+ 标题/副标题。
    /// 披露箭头不在这里画——NavigationLink 行由系统提供，Button/ShareLink 行本就没有。
    private func entryLabel(icon: String, title: String, subtitle: String? = nil) -> some View {
        HStack(spacing: LiqianMetrics.spacingSM) {
            Image(systemName: icon)
                .foregroundStyle(Palette.ink)
                .frame(width: 24)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: LiqianMetrics.spacingXS) {
                Text(title)
                    .foregroundStyle(Palette.ink)
                if let subtitle {
                    Text(subtitle)
                        .font(.footnote)
                        .foregroundStyle(Palette.stone)
                }
            }
        }
        .frame(minHeight: LiqianMetrics.minTapTarget)
        .contentShape(Rectangle())
    }

    private var csvEntryRow: some View {
        Group {
            if let csvURL {
                ShareLink(item: csvURL) {
                    entryLabel(
                        icon: "tablecells",
                        title: "导出 CSV",
                        subtitle: "导出为 CSV 表格，可用 Excel 打开"
                    )
                }
            } else {
                entryLabel(
                    icon: "tablecells",
                    title: "导出 CSV",
                    subtitle: "导出为 CSV 表格，可用 Excel 打开"
                )
                .opacity(0.5)
            }
        }
    }

    private var hasSamples: Bool { SampleData.hasSamples(ledgers: ledgers) }

    /// 示例数据开关：生成两本示例礼簿看效果，看完一键清掉（不碰真实数据）
    private func toggleSamples() {
        if hasSamples {
            SampleData.clearSamples(ledgers: ledgers, records: records, in: modelContext)
            showInfo(title: "示例数据已清除", message: "示例数据已删除，你的数据未受影响。")
        } else {
            SampleData.generate(into: modelContext)
            showInfo(title: "示例数据已生成", message: "「礼簿」页多了两本示例礼簿，「往来」页能看到往来差额和备礼清单的效果。")
        }
    }

    /// AI 状态小字：没 Key / 已停用 / 已启用，三态说清
    private var aiStatusText: String {
        switch AIAccess.readiness() {
        case .noKey:
            return "填你自己的 DeepSeek API Key，用 AI 解析账目文字、生成贺词"
        case .notEnabled:
            return "已保存 API Key，AI 功能尚未启用"
        case .ready:
            return "已启用：智能解析、一句话记账、贺词生成"
        }
    }

    // MARK: - 导入

    private func handleImport(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result, let url = urls.first else {
            if case .failure = result {
                showInfo(title: "备份文件无效", message: "这个文件读不了，或者不是礼钱账本的备份。数据没有动。")
            }
            return
        }
        let scoped = url.startAccessingSecurityScopedResource()
        defer {
            if scoped { url.stopAccessingSecurityScopedResource() }
        }
        do {
            let data = try Data(contentsOf: url)
            pendingImport = try LiqianBackup.parseBackup(data)
            showImportConfirm = true
        } catch {
            showInfo(title: "备份文件无效", message: "这个文件读不了，或者不是礼钱账本的备份。数据没有动。")
        }
    }

    private func performImport() {
        guard let p = pendingImport else { return }
        for r in records { modelContext.delete(r) }
        for l in ledgers { modelContext.delete(l) }
        // 备份里的 id 是字符串：原生备份是 UUID 串可直转；
        // Flutter 旧备份是时间戳串，转不成 UUID 就新发一个，并按账本逐个建映射保证记录挂得上
        var idMap: [String: UUID] = [:]
        for bl in p.ledgers {
            let newID = bl.idUUID ?? UUID()
            idMap[bl.id] = newID
            modelContext.insert(
                Ledger(
                    id: newID, title: bl.title, type: bl.type, date: bl.date, note: bl.note,
                    hostName: bl.hostName, scribe: bl.scribe,
                    verifier: bl.verifier, location: bl.location
                )
            )
        }
        var importedRecords = 0
        for br in p.records {
            guard let lid = idMap[br.ledgerId] else { continue }
            modelContext.insert(
                GiftRecord(
                    id: br.idUUID ?? UUID(),
                    ledgerID: lid,
                    person: br.person,
                    relation: br.relation,
                    amountCents: br.amountCents,
                    direction: br.direction,
                    method: br.method,
                    note: br.note,
                    date: br.date,
                    status: br.status,
                    returned: br.returned
                )
            )
            importedRecords += 1
        }
        try? modelContext.save()
        importTrigger += 1
        pendingImport = nil
        showInfo(
            title: "恢复完成",
            message: "已导入 \(p.ledgers.count) 本礼簿、\(importedRecords) 笔记录。"
        )
    }

    private func showInfo(title: String, message: String) {
        infoTitle = title
        infoMessage = message
        showInfo = true
    }
}

/// 礼谱落款姓名编辑页（全局默认，@AppStorage("hostName")）：v2.10 起主家是
/// 礼簿自身属性，本设置只作两件事——新建礼簿时预填其「主家」字段；
/// 礼簿没设主家时，导出礼谱的落款回退链第二级读它（再空回退「主家谨识」）。
struct HostNameEditView: View {
    @AppStorage("hostName") private var hostName = ""
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""

    var body: some View {
        List {
            Section {
                TextField("如：杨敏杰", text: $text)
                    .font(.body)
            } footer: {
                Text("写主家在礼谱上落款用的名字，一般 2–4 个字。不填的话，礼谱上用「主家谨识」落款、盖「主家谨识」印。")
            }
            if !hostName.isEmpty {
                Section {
                    Button("清除落款姓名", role: .destructive) {
                        hostName = ""
                        text = ""
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Palette.pageBG.ignoresSafeArea())
        .navigationTitle("礼谱落款姓名")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("保存") {
                    hostName = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    dismiss()
                }
            }
        }
        .onAppear {
            if text.isEmpty { text = hostName }
        }
    }
}

/// 待回礼列表（v2.5 包 5：「我的 → 记录 → 待回礼」落点）：原「我的」页顶的
/// 待回礼大卡收敛为此独立页——只列待回的人，点行进人物详情处理回礼；
/// 口径与首页/往来一致（净差额为正，排除示例账本）。
struct PendingPeopleView: View {
    @Query private var records: [GiftRecord]
    @Query(sort: \Ledger.date, order: .reverse) private var ledgers: [Ledger]

    private var snapshots: [EntrySnapshot] {
        let ids = SampleData.sampleIDs(ledgers: ledgers)
        return AppSupport.snapshots(
            records: records.filter { !ids.contains($0.ledgerID) },
            ledgers: ledgers
        )
    }

    private var pendingPeople: [PersonSummary] {
        LedgerMath.people(from: snapshots).filter { $0.hasPending }
    }

    var body: some View {
        List {
            if pendingPeople.isEmpty {
                ContentUnavailableView {
                    Label("没有待回礼", systemImage: "arrow.uturn.backward.circle")
                } description: {
                    Text("收礼多于随礼时，差额会记在这里。")
                }
                .padding(.vertical, LiqianMetrics.spacingL)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            } else {
                Section {
                    ForEach(pendingPeople) { p in
                        NavigationLink {
                            PersonDetailView(name: p.name)
                        } label: {
                            HStack {
                                Text(p.name)
                                    .foregroundStyle(Palette.ink)
                                Spacer()
                                // 待回礼是行动提示，保留强调色（v3 纪律的明示例外）
                                Text(LedgerMath.fmtMoney(cents: p.pendingCents))
                                    .font(.liqianMoney(.title3))
                                    .foregroundStyle(Palette.primary)
                            }
                            .frame(minHeight: LiqianMetrics.minTapTarget)
                            .contentShape(Rectangle())
                        }
                    }
                } footer: {
                    Text("收礼多于随礼的差额即待回金额，自动计算，无需手动标记。")
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Palette.pageBG.ignoresSafeArea())
        .navigationTitle("待回礼")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// 关于礼钱账本（v2.5 包 5：「我的 → 关于」落点）：版本与数据说明，
/// 原「我的」页关于区的页脚文案移入此处，设置页只留一行入口带版本号。
struct AboutView: View {
    var body: some View {
        List {
            Section {
                LabeledContent("版本", value: MeView.appVersion)
            }
            Section {
                Text("礼钱账本记亲友红白事的往来礼钱，方便日后回礼。")
                    .foregroundStyle(Palette.ink)
            } footer: {
                Text("数据仅保存在本机，不联网、不上传。换手机或重装前，请先导出备份。备份与旧版（Flutter 版）互通：两边导出的 JSON 备份可以互相恢复。")
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Palette.pageBG.ignoresSafeArea())
        .navigationTitle("关于礼钱账本")
        .navigationBarTitleDisplayMode(.inline)
    }
}
