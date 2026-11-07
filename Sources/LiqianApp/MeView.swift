import SwiftData
import SwiftUI
import UniformTypeIdentifiers
import LiqianCore
import LiqianDesign

struct MeView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var records: [GiftRecord]
    @Query(sort: \Ledger.date, order: .reverse) private var ledgers: [Ledger]

    @State private var personRoute: PeopleView.NameRoute?
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

    private var year: String { LiqianDate.currentYearString() }

    private var snapshots: [EntrySnapshot] {
        AppSupport.snapshots(records: records, ledgers: ledgers)
    }

    private var yearSummary: YearSummary {
        LedgerMath.yearSummary(from: snapshots, year: year)
    }

    private var pendingPeople: [PersonSummary] {
        LedgerMath.people(from: snapshots).filter { $0.hasPending }
    }

    private var typeSummaries: [TypeSummary] {
        LedgerMath.typeSummary(from: snapshots).filter { $0.count > 0 }
    }

    private var csvFingerprint: String {
        "\(records.count)-\(ledgers.count)-\(records.reduce(0) { $0 + $1.amountCents })"
    }

    var body: some View {
        NavigationStack {
            List {
                Text("我的")
                    .font(.liqianBigTitle)
                    .foregroundStyle(Palette.ink)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 4, trailing: 16))

                asCardRow(yearCard)
                asCardRow(pendingCard)
                asCardRow(typeCard)

                asCardRow(csvRow)
                asCardRow(jsonExportRow)
                asCardRow(jsonImportRow)

                asCardRow(aboutCard)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Palette.paper.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(item: $personRoute) { route in
                PersonDetailView(name: route.name)
            }
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
                    showInfo(title: "导出失败", message: "备份没能存下来，再试一次。")
                }
            }
            .fileImporter(isPresented: $showImporter, allowedContentTypes: [.json]) { result in
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

    // MARK: - 卡片们

    private var yearCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("\(year) 年往来")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(Palette.ink)
            HStack(spacing: 16) {
                HStack(spacing: 6) {
                    Text("收礼")
                        .foregroundStyle(Palette.stone)
                    Text(LedgerMath.fmtMoney(cents: yearSummary.recv))
                        .font(.liqianMoney(size: 17))
                        .foregroundStyle(Palette.primary)
                }
                HStack(spacing: 6) {
                    Text("随礼")
                        .foregroundStyle(Palette.stone)
                    Text(LedgerMath.fmtMoney(cents: yearSummary.given))
                        .font(.liqianMoney(size: 17))
                        .foregroundStyle(Palette.ink)
                }
                Text("共 \(yearSummary.count) 笔")
                    .foregroundStyle(Palette.stone)
            }
            .font(.system(size: 15))
            Text("全部：\(ledgers.count) 本礼簿 · \(records.count) 笔记录 · \(LedgerMath.people(from: snapshots).count) 位亲友")
                .font(.system(size: 12.5))
                .foregroundStyle(Palette.stone)
        }
        .cardSurface()
    }

    private var pendingCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("还没回的礼")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(Palette.ink)
            if pendingPeople.isEmpty {
                Text("没有欠着的人情，轻松。")
                    .foregroundStyle(Palette.stone)
            } else {
                ForEach(pendingPeople) { p in
                    Button {
                        personRoute = PeopleView.NameRoute(name: p.name)
                    } label: {
                        HStack {
                            Text(p.name)
                                .foregroundStyle(Palette.ink)
                            Spacer()
                            Text(LedgerMath.fmtMoney(cents: p.pendingCents))
                                .font(.liqianMoney(size: 15))
                                .foregroundStyle(Palette.primary)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Palette.stone)
                        }
                        .frame(minHeight: LiqianMetrics.minTapTarget)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                Text("按「最近一次收礼之后还没送出」自动算的，不用手动标。")
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.stone)
            }
        }
        .cardSurface()
    }

    private var typeCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("按事由")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(Palette.ink)
            if typeSummaries.isEmpty {
                Text("还没有记录")
                    .foregroundStyle(Palette.stone)
            } else {
                ForEach(typeSummaries) { t in
                    HStack {
                        Text(t.type)
                            .foregroundStyle(Palette.ink)
                        Text("\(t.count) 笔")
                            .font(.system(size: 12.5))
                            .foregroundStyle(Palette.stone)
                        Spacer()
                        Text("收 \(LedgerMath.fmtMoney(cents: t.received)) · 随 \(LedgerMath.fmtMoney(cents: t.given))")
                            .font(.liqianMoney(size: 14))
                            .foregroundStyle(Palette.ink)
                    }
                    .padding(.vertical, 3)
                }
            }
        }
        .cardSurface()
    }

    private var csvRow: some View {
        Group {
            if let csvURL {
                ShareLink(item: csvURL) {
                    actionRow(
                        icon: "tablecells",
                        title: "导出 CSV",
                        subtitle: "全部记录导出成表格，Excel 能打开"
                    )
                }
                .buttonStyle(.plain)
            } else {
                actionRow(
                    icon: "tablecells",
                    title: "导出 CSV",
                    subtitle: "全部记录导出成表格，Excel 能打开"
                )
                .opacity(0.5)
            }
        }
        .cardSurface(padding: 0)
    }

    private var jsonExportRow: some View {
        Button {
            exportDocument = JSONBackupDocument(
                data: LiqianBackup.makeBackup(ledgers: ledgers, records: records)
            )
            showExporter = true
        } label: {
            actionRow(
                icon: "tray.and.arrow.up",
                title: "导出备份（JSON）",
                subtitle: "全量备份：礼簿和记录都在，换手机靠它恢复"
            )
        }
        .buttonStyle(.plain)
        .cardSurface(padding: 0)
    }

    private var jsonImportRow: some View {
        Button {
            showImporter = true
        } label: {
            actionRow(
                icon: "tray.and.arrow.down",
                title: "从备份恢复",
                subtitle: "选一个备份文件，覆盖现在的数据"
            )
        }
        .buttonStyle(.plain)
        .cardSurface(padding: 0)
    }

    private func actionRow(icon: String, title: String, subtitle: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(Palette.ink)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .foregroundStyle(Palette.ink)
                Text(subtitle)
                    .font(.system(size: 12.5))
                    .foregroundStyle(Palette.stone)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Palette.stone)
        }
        .padding(12)
        .frame(minHeight: LiqianMetrics.minTapTarget)
        .contentShape(Rectangle())
    }

    private var aboutCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("关于")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(Palette.ink)
            Text("礼钱账本 原生版 v1.0\n数据只存在这台手机上，不联网、不上传。换手机前请先用上面的「导出备份」存一份。")
                .font(.system(size: 14))
                .foregroundStyle(Palette.stone)
                .lineSpacing(6)
        }
        .cardSurface()
    }

    // MARK: - 导入

    private func handleImport(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result, let url = urls.first else {
            if case .failure = result {
                showInfo(title: "备份文件有问题", message: "这个文件读不了，或者不是礼钱账本的备份。数据没有动。")
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
            showInfo(title: "备份文件有问题", message: "这个文件读不了，或者不是礼钱账本的备份。数据没有动。")
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
                Ledger(id: newID, title: bl.title, type: bl.type, date: bl.date, note: bl.note)
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

    private func asCardRow<V: View>(_ view: V) -> some View {
        view
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
    }
}

/// 「我的」页卡片表面：卡面色 + 描边线 + 统一圆角/内边距
private extension View {
    func cardSurface(padding: CGFloat = LiqianMetrics.cardPadding) -> some View {
        self
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.card, in: RoundedRectangle(cornerRadius: LiqianMetrics.cardCorner))
            .overlay(
                RoundedRectangle(cornerRadius: LiqianMetrics.cardCorner)
                    .stroke(Palette.hairline, lineWidth: 1)
            )
    }
}
