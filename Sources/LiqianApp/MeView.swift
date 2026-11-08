import SwiftData
import SwiftUI
import UIKit
import UniformTypeIdentifiers
import LiqianCore
import LiqianDesign

/// 「我的」设置页（v5.0.1 按定版 IA 重组）：List(.insetGrouped) 原生
/// Section 与行，披露箭头由系统唯一提供。分组顺序＝会员卡（顶）→
/// 总览 → 数据 → 提醒 → 外观与偏好 → AI 管家 → 协作 → 隐私与协议 →
/// 帮助 → 关于（沉底）；只重组排序、不删入口、不改子页，逐项对照
/// 见 docs/V501-NOTES.md。危险操作只留在所属组内用 destructive 确认
/// （覆盖恢复在数据组）。全部汇总口径排除示例账本。
struct MeView: View {
    @Environment(\.modelContext) private var modelContext
    /// iCloud 同步状态（容器在启动时选定，开关改动下次启动生效，见 CloudSync.swift）
    @EnvironmentObject private var cloudSync: CloudSyncManager
    /// Pro 权益单点（v5）：本页只问它，不直接碰 StoreKit
    @EnvironmentObject private var entitlements: EntitlementCenter
    @State private var showPaywall = false
    @Query private var records: [GiftRecord]
    @Query(sort: \Ledger.date, order: .reverse) private var ledgers: [Ledger]
    @Query private var reminderDays: [ReminderDay]
    @Query private var members: [LedgerMember]
    @Query private var guestSignatures: [GuestSignature]
    @Query private var voiceBlessings: [VoiceBlessing]

    @State private var csvURL: URL?
    @State private var exportDocument = JSONBackupDocument(data: Data())
    @State private var showExporter = false
    @State private var showImporter = false
    @State private var pendingImport: (ledgers: [BackupLedger], records: [BackupRecord], reminders: [BackupReminderDay], members: [BackupMember])?
    /// 活礼谱（v4.2）：待导入备份的签名/祝福元数据段（无二进制本体）
    @State private var pendingLive: (signatures: [BackupSignature], blessings: [BackupVoiceBlessing])?
    /// 待恢复的自定义关系段（备份无此段时为空数组，覆盖恢复时一并写回目录）
    @State private var pendingCustomRelations: [String] = []
    @State private var showImportConfirm = false
    @State private var infoTitle = ""
    @State private var infoMessage = ""
    @State private var showInfo = false
    @State private var importTrigger = 0
    @AppStorage("privacyLock") private var privacyLock = false
    @AppStorage("hostName") private var hostName = ""
    /// 上次成功导出备份的时间（v4.5 备份提醒）：@AppStorage 订阅，
    /// fileExporter 成功回调里刷新；提醒逻辑见 BackupReminder
    @AppStorage(BackupReminder.lastBackupAtKey) private var lastBackupStamp: Double = 0
    /// 回礼建议年涨幅（v4.3）：0/3/5%，人物详情卡与记一笔提示同键同源
    @AppStorage(ReplyAdvisor.annualRateKey) private var annualRatePercent = ReplyAdvisor.defaultAnnualRatePercent
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

    /// 「关系管理」入口行副标题：显已自定义数（动态读目录，管理页改完返回即刷新）
    private var relationsSubtitle: String {
        let count = RelationCatalog.custom().count
        return count == 0
            ? "可添加系统之外的关系，如闺蜜、战友"
            : "已添加 \(count) 个自定义关系"
    }

    /// 待送出件数（「备礼清单」入口行右侧值，口径与备礼清单页一致：全部记录）
    private var prepCount: Int {
        records.filter { $0.isPendingSend }.count
    }

    /// 关于区版本号：动态读 Bundle，避免写死版本过期（PRO-AUDIT #31）
    static var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
    }

    /// 备份提醒（v4.5）：hasData 用已排除示例的汇总快照判定（只有示例
    /// 账目不算「有账没备份」）；文案规则见 BackupReminder
    private var backupReminder: (title: String, subtitle: String)? {
        BackupReminder.reminder(
            hasData: !snapshots.isEmpty,
            lastBackupAt: lastBackupStamp > 0
                ? Date(timeIntervalSince1970: lastBackupStamp) : nil
        )
    }

    /// 导出备份的唯一动作：数据区的导出行与备份提醒行共用
    private func startBackupExport() {
        exportDocument = JSONBackupDocument(
            data: LiqianBackup.makeBackup(
                ledgers: ledgers, records: records,
                reminders: reminderDays, members: members,
                signatures: guestSignatures, blessings: voiceBlessings,
                customRelations: RelationCatalog.custom()
            )
        )
        showExporter = true
    }

    private var csvFingerprint: String {
        "\(records.count)-\(ledgers.count)-\(records.reduce(0) { $0 + $1.amountCents })"
    }

    var body: some View {
        NavigationStack {
            List {
                // —— 顶部会员卡（v5.0.1 IA）：单行成卡置顶，点进仍是
                // v5 付费墙 PaywallView，不新造；副标题即权益状态。
                Section {
                    NavigationLink {
                        PaywallView()
                    } label: {
                        entryLabel(
                            icon: "seal",
                            title: "礼记 Pro",
                            subtitle: entitlements.isPro
                                ? "已开通 · 全部导出权益可用"
                                : "买断开通 Excel、纪念版礼谱、家族汇册与印刷版礼谱"
                        )
                    }
                } footer: {
                    Text("一次买断、不自动续费。基础礼谱 PDF 与完整备份始终免费。")
                }

                // —— 总览：数据查看入口（人情总览/年度报告/待回礼/备礼
                // 清单经全仓核实仅设置页一处可达，删不得、定版九组无
                // 对应落位，收敛为一组置于会员卡之下，账见 V501-NOTES）。
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
                                .contentTransition(.numericText())
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
                } header: {
                    Text("总览")
                }

                // —— 数据：同步状态打头、导出/恢复居中、回收站收尾
                // （v5.0.1 IA；v5.8.1 示例礼簿行移出设置页——生成入口
                // 在首页/往来/礼簿列表空态，审计 #4）；备份提醒行已移
                // 「提醒」组。
                Section {
                    Toggle(isOn: $cloudSync.syncEnabled) {
                        entryLabel(
                            icon: "icloud",
                            title: "iCloud 同步",
                            subtitle: cloudSync.statusSubtitle
                        )
                    }
                    .task { await cloudSync.refreshAccountStatus() }
                    if cloudSync.showsSettingsShortcut {
                        Button {
                            if let url = URL(string: UIApplication.openSettingsURLString) {
                                UIApplication.shared.open(url)
                            }
                        } label: {
                            entryLabel(
                                icon: "gearshape",
                                title: "打开系统设置",
                                subtitle: "在「设置」顶部登录 iCloud 后，同步会自动开始"
                            )
                        }
                    }
                    Button {
                        startBackupExport()
                    } label: {
                        entryLabel(
                            icon: "tray.and.arrow.up",
                            title: "导出备份（JSON）",
                            subtitle: "包含全部礼簿、记录、提醒日子与礼簿班子，可用于换机恢复；签名图片与祝福录音不在备份内（保存在本机与 iCloud）"
                        )
                    }
                    csvEntryRow
                    Button {
                        showImporter = true
                    } label: {
                        entryLabel(
                            icon: "tray.and.arrow.down",
                            title: "从备份恢复",
                            subtitle: "选一个备份文件，覆盖现在的数据"
                        )
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
                    Text("数据")
                } footer: {
                    Text("iCloud 同步通过你的 iCloud 账号同步礼簿、记录与提醒，换手机或重装 App 后自动回来；导出备份是另一条手动恢复线，两条线互不影响。")
                }

                // —— 提醒：人情提醒与备份提醒归一组（v5.0.1 IA）——
                Section {
                    NavigationLink {
                        RemindersView()
                    } label: {
                        HStack(spacing: LiqianMetrics.spacingSM) {
                            entryLabel(
                                icon: "bell",
                                title: "人情提醒",
                                subtitle: "重要日子与待回礼提醒"
                            )
                            Spacer()
                            if !reminderDays.isEmpty {
                                Text("\(reminderDays.count) 个日子")
                                    .foregroundStyle(Palette.stone)
                            }
                        }
                    }
                    // 备份提醒（v4.5）：从未备份或超过 30 天时才出现，
                    // 点行直接开始导出；备份成功后随 lastBackupStamp 刷新消失
                    if let backupReminder {
                        Button {
                            startBackupExport()
                        } label: {
                            entryLabel(
                                icon: "exclamationmark.circle",
                                title: backupReminder.title,
                                subtitle: backupReminder.subtitle
                            )
                        }
                    }
                } header: {
                    Text("提醒")
                }

                // —— 外观与偏好：主题、落款、关系、年涨幅（v5.0.1 IA）——
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
                    NavigationLink {
                        RelationsManageView()
                    } label: {
                        entryLabel(
                            icon: "person.2",
                            title: "关系管理",
                            subtitle: relationsSubtitle
                        )
                    }
                    HStack(spacing: LiqianMetrics.spacingSM) {
                        entryLabel(
                            icon: "chart.line.uptrend.xyaxis",
                            title: "回礼参考年涨幅",
                            subtitle: "往来越久，回礼参考按年折算的幅度"
                        )
                        Spacer()
                        Picker("回礼参考年涨幅", selection: $annualRatePercent) {
                            Text("不折算").tag(0)
                            Text("3% / 年").tag(3)
                            Text("5% / 年").tag(5)
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .tint(Palette.stone)
                    }
                } header: {
                    Text("外观与偏好")
                } footer: {
                    Text("主题只影响 App 界面，导出的礼谱不变。落款姓名用于礼谱封面、谱序落款与主家印，不填时用「主家谨识」。")
                }

                // —— AI 管家：现有 AI 设置页原样接入 ——
                Section {
                    NavigationLink {
                        AISettingsView()
                    } label: {
                        entryLabel(
                            icon: "wand.and.stars",
                            title: "AI 管家",
                            subtitle: aiStatusText
                        )
                    }
                } header: {
                    Text("AI 管家")
                }

                // —— 协作：协作是礼簿级事务（班子在礼簿详情内），
                // 设置页给一条落点：礼簿列表 → 礼簿详情 → 礼簿班子，
                // 链上全是现有页面（v5.0.1 IA）。
                Section {
                    NavigationLink {
                        LedgersView()
                    } label: {
                        entryLabel(
                            icon: "person.3",
                            title: "家庭协作",
                            subtitle: "选一本礼簿，在详情里管理班子成员与协作"
                        )
                    }
                } header: {
                    Text("协作")
                }

                // —— 隐私与协议：隐私锁从「关于」移出、政策与协议
                // 从 AboutView 子页内升为设置页直达（子页原行保留）。
                Section {
                    Toggle(isOn: $privacyLock) {
                        entryLabel(
                            icon: "faceid",
                            title: "隐私锁",
                            subtitle: "从后台返回超过 30 秒需重新解锁；App 在后台时界面自动模糊。"
                        )
                    }
                    .tint(Palette.primary)
                    NavigationLink {
                        LegalView(doc: LegalTexts.privacyPolicy)
                    } label: {
                        entryLabel(icon: "hand.raised", title: "隐私政策")
                    }
                    NavigationLink {
                        LegalView(doc: LegalTexts.userAgreement)
                    } label: {
                        entryLabel(icon: "doc.text", title: "用户协议")
                    }
                } header: {
                    Text("隐私与协议")
                }

                // —— 帮助：只剩意见反馈（v5.8.1 删「重看引导」行——
                // 设置页不放引导入口，审计 #4；首开引导本体在
                // ContentView 呈现，不经设置页）；不设「给个好评」——
                // 现版无此入口且 ReviewPrompt 既定设计不放常驻评分
                // 入口，账见 V501-NOTES。
                Section {
                    Link(destination: FeedbackMail.url) {
                        HStack(spacing: LiqianMetrics.spacingSM) {
                            entryLabel(icon: "envelope", title: "意见反馈")
                            Spacer()
                            Text(FeedbackMail.address)
                                .font(.footnote)
                                .foregroundStyle(Palette.stone)
                        }
                    }
                } header: {
                    Text("帮助")
                }

                // —— 关于（沉底）：只留关于入口带版本号 ——
                Section {
                    NavigationLink {
                        AboutView()
                    } label: {
                        HStack(spacing: LiqianMetrics.spacingSM) {
                            entryLabel(icon: "info.circle", title: "关于礼记")
                            Spacer()
                            Text(Self.appVersion)
                                .foregroundStyle(Palette.stone)
                        }
                    }
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
                    name: "礼记导出.csv",
                    content: AppSupport.csvText(records: records, ledgers: ledgers)
                )
            }
            .fileExporter(
                isPresented: $showExporter,
                document: exportDocument,
                contentType: .json,
                defaultFilename: "礼记备份"
            ) { result in
                switch result {
                case .success:
                    // 备份提醒的计时起点（v4.5）：只有真导出成功才记，
                    // 取消或失败不刷新，提醒行不会被误消
                    lastBackupStamp = Date().timeIntervalSince1970
                case .failure:
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
                    Text("备份里有 \(p.ledgers.count) 本礼簿、\(p.records.count) 笔记录\(p.reminders.isEmpty ? "" : "、\(p.reminders.count) 个提醒日子")\(p.members.isEmpty ? "" : "、\(p.members.count) 位班子成员")。现在手机里有 \(ledgers.count) 本礼簿、\(records.count) 笔记录，恢复后会被全部覆盖，覆盖了就回不来了。")
                }
            }
            .alert(infoTitle, isPresented: $showInfo) {
                Button("好") {}
            } message: {
                Text(infoMessage)
            }
            .sheet(isPresented: $showPaywall) {
                NavigationStack { PaywallView() }
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

    /// CSV 表格导出（v5 起为 Pro 门控面之一）：未开通时整行改走付费墙，
    /// CSV 文件照常在后台生成（生成不等于导出，分享动作才受门控）；
    /// 全量 JSON 备份（机器可读、能带走）不在门控内，见数据组备份行。
    private var csvEntryRow: some View {
        Group {
            if !entitlements.canUse(.excelExport) {
                Button {
                    showPaywall = true
                } label: {
                    HStack(spacing: LiqianMetrics.spacingSM) {
                        entryLabel(
                            icon: "tablecells",
                            title: "导出 CSV",
                            subtitle: "导出为 CSV 表格，可用 Excel 打开"
                        )
                        Spacer()
                        Text("Pro")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Palette.primary)
                    }
                }
                .buttonStyle(.plain)
            } else if let csvURL {
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
                showInfo(title: "备份文件无效", message: "这个文件读不了，或者不是礼记的备份。数据没有动。")
            }
            return
        }
        let scoped = url.startAccessingSecurityScopedResource()
        defer {
            if scoped { url.stopAccessingSecurityScopedResource() }
        }
        do {
            let data = try Data(contentsOf: url)
            pendingImport = try LiqianBackup.parseBackupFull(data)
            pendingLive = LiqianBackup.parseBackupLive(data)
            pendingCustomRelations = LiqianBackup.parseBackupRelations(data)
            showImportConfirm = true
        } catch {
            showInfo(title: "备份文件无效", message: "这个文件读不了，或者不是礼记的备份。数据没有动。")
        }
    }

    private func performImport() {
        guard let p = pendingImport else { return }
        for r in records { modelContext.delete(r) }
        for l in ledgers { modelContext.delete(l) }
        for d in reminderDays { modelContext.delete(d) }
        for m in members { modelContext.delete(m) }
        // 活礼谱（v4.2）：旧签名/祝福随覆盖恢复一并清掉（录音文件留在
        // 容器里成孤儿，不误删——恢复的祝福元数据可能还引用同名文件）
        for s in guestSignatures { modelContext.delete(s) }
        for b in voiceBlessings { modelContext.delete(b) }
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
        var importedRecordIDs = Set<UUID>()
        for br in p.records {
            guard let lid = idMap[br.ledgerId] else { continue }
            let recordID = br.idUUID ?? UUID()
            importedRecordIDs.insert(recordID)
            modelContext.insert(
                GiftRecord(
                    id: recordID,
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
        for bd in p.reminders {
            modelContext.insert(
                ReminderDay(
                    id: bd.idUUID ?? UUID(),
                    person: bd.person,
                    relation: bd.relation,
                    kind: bd.kind,
                    calendarKind: bd.calendarKind,
                    month: bd.month,
                    day: bd.day,
                    leadDays: bd.leadDays,
                    enabled: bd.enabled,
                    note: bd.note
                )
            )
        }
        // 班子成员（v4.5）：按备份里的 ledgerId 映射到恢复后的礼簿 id
        var importedMembers = 0
        for bm in p.members {
            guard let lid = idMap[bm.ledgerId] else { continue }
            modelContext.insert(
                LedgerMember(
                    id: bm.idUUID ?? UUID(),
                    ledgerID: lid,
                    name: bm.name,
                    role: bm.role,
                    createdAt: LiqianBackup.memberDate(from: bm.createdAt)
                )
            )
            importedMembers += 1
        }
        // 活礼谱元数据恢复（v4.2）：只恢复祝福元数据（转写文字跟着回来）；
        // 记录在本备份里不存在（或 id 被重发）的不挂。录音文件若在新设备
        // 上不存在，播放时会如实提示。签名没有图片本体，不恢复成行——
        // 备份里的签名段只是「谁签过」的存档清单。
        if let live = pendingLive {
            for bb in live.blessings {
                guard let bid = bb.idUUID, let rid = bb.recordUUID,
                      importedRecordIDs.contains(rid)
                else { continue }
                modelContext.insert(
                    VoiceBlessing(
                        id: bid,
                        recordID: rid,
                        fileName: bb.fileName,
                        duration: bb.duration,
                        transcript: bb.transcript,
                        createdAt: LiqianISO8601.date(from: bb.createdAt) ?? Date()
                    )
                )
            }
        }
        pendingLive = nil
        // 自定义关系恢复（覆盖式，与其余段同口径）：写回关系目录；
        // 备份无此段时 pendingCustomRelations 为空数组，即清空本机自定义
        RelationCatalog.setCustom(pendingCustomRelations)
        pendingCustomRelations = []
        try? modelContext.save()
        // 恢复后按新数据重排提醒（旧排期对应的是被覆盖掉的日子）
        ReminderScheduler.reschedule(
            days: p.reminders.map {
                ReminderDayValue(
                    id: $0.idUUID ?? UUID(), person: $0.person, relation: $0.relation,
                    kind: $0.kind, calendarKind: $0.calendarKind, month: $0.month,
                    day: $0.day, leadDays: $0.leadDays, enabled: $0.enabled, note: $0.note
                )
            },
            snapshots: p.records.map { br in
                EntrySnapshot(
                    person: br.person,
                    relation: br.relation,
                    amountCents: br.amountCents,
                    direction: br.direction,
                    date: br.date,
                    status: br.status,
                    ledgerType: p.ledgers.first { $0.id == br.ledgerId }?.type ?? ""
                )
            }
        )
        importTrigger += 1
        pendingImport = nil
        showInfo(
            title: "恢复完成",
            message: "已导入 \(p.ledgers.count) 本礼簿、\(importedRecords) 笔记录\(p.reminders.isEmpty ? "" : "、\(p.reminders.count) 个提醒日子")\(importedMembers == 0 ? "" : "、\(importedMembers) 位班子成员")。"
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
                                    .contentTransition(.numericText())
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

/// 关于礼记（v2.5 包 5：「我的 → 关于」落点）：版本与数据说明，
/// 原「我的」页关于区的页脚文案移入此处，设置页只留一行入口带版本号。
struct AboutView: View {
    var body: some View {
        List {
            Section {
                LabeledContent("版本", value: MeView.appVersion)
            }
            Section {
                Text("礼记记亲友红白事的往来礼钱，方便日后回礼。")
                    .foregroundStyle(Palette.ink)
            } footer: {
                Text("开启 iCloud 同步时，数据通过你自己的 iCloud 账号在你的设备间同步，换手机或重装后自动回来；未开启时数据仅保存在本机。导出备份可手动保存一份到任意位置，与旧版（Flutter 版）互通：两边导出的 JSON 备份可以互相恢复。注意：来宾签名图片与语音祝福录音不在 JSON 备份内，它们保存在本机与 iCloud 中。")
            }
            // 法律与反馈（v4.5）：隐私/协议为内置文本页、离线可读；
            // 反馈走系统邮件，地址与模板在 Feedback.swift
            Section {
                NavigationLink {
                    LegalView(doc: LegalTexts.privacyPolicy)
                } label: {
                    Text("隐私政策")
                        .foregroundStyle(Palette.ink)
                }
                NavigationLink {
                    LegalView(doc: LegalTexts.userAgreement)
                } label: {
                    Text("用户协议")
                        .foregroundStyle(Palette.ink)
                }
                Link(destination: FeedbackMail.url) {
                    HStack(spacing: LiqianMetrics.spacingSM) {
                        Text("意见反馈")
                            .foregroundStyle(Palette.ink)
                        Spacer()
                        Text(FeedbackMail.address)
                            .font(.footnote)
                            .foregroundStyle(Palette.stone)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Palette.pageBG.ignoresSafeArea())
        .navigationTitle("关于礼记")
        .navigationBarTitleDisplayMode(.inline)
    }
}
