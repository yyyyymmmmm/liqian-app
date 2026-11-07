import AVFoundation
import SwiftData
import SwiftUI
import UIKit
import LiqianCore
import LiqianDesign

// MARK: - 现场模式（v4.1：婚礼/白事礼房收礼台）
//
// 入口：礼簿详情「更多」→「现场模式」，fullScreenCover 全屏沉浸。
// 四件套：连续登记（存后不退出、清字段续记）／语音播报（落库后唱名唱额）／
// 投屏脱敏（副屏只显姓名与笔数、金额永不进副屏视图）／事后复核（复核单对账、直达导出礼谱）。
// 数据口径：方向固定「收礼」、日期今天；记录走既有 GiftRecord 保存通道，
// 不新增模型字段；关系/方式在本场内保持上次选择（现场成串同类居多，少点按）。
// 本场 session＝进入本页后在本页落库的记录（本地快照数组），汇总与播报都只认它；
// 对账基线＝进入时刻礼簿的收礼笔数/总额快照。

// MARK: 语音播报

/// 现场播报器：每笔落库后播「收到，〈姓名〉，礼金/奠仪〈金额〉」。
/// 金额读法选**阿拉伯读法**（如 1000 元由系统中文语音读作「一千元」）：
/// Core 的金融大写（壹仟元整）是礼谱书面口径，播出来拗口且慢，现场唱额要快要顺。
/// 现场连记时不排队积压——新一笔直接打断上一笔未播完的内容，只播最新。
@MainActor
final class SceneAnnouncer: ObservableObject {
    private let synthesizer = AVSpeechSynthesizer()

    func announce(name: String, amountCents: Int, bai: Bool) {
        let label = bai ? "奠仪" : "礼金"
        let utterance = AVSpeechUtterance(
            string: "收到，\(name)，\(label)\(Self.spokenAmount(cents: amountCents))"
        )
        utterance.voice = AVSpeechSynthesisVoice(language: "zh-CN")
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.98
        synthesizer.stopSpeaking(at: .immediate)
        synthesizer.speak(utterance)
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
    }

    /// 分 → 阿拉伯读法串：整元只给「〈元〉元」；带角分依次缀「X角」「Y分」；
    /// 不满 1 元时省掉「0元」（50 分 → 「5角」）。
    static func spokenAmount(cents: Int) -> String {
        let yuan = cents / 100
        let jiao = (cents % 100) / 10
        let fen = cents % 10
        if jiao == 0 && fen == 0 { return "\(yuan)元" }
        var parts: [String] = []
        if yuan > 0 { parts.append("\(yuan)元") }
        if jiao > 0 { parts.append("\(jiao)角") }
        if fen > 0 { parts.append("\(fen)分") }
        return parts.joined()
    }
}

// MARK: 投屏脱敏大屏

/// 副屏脱敏视图——**代码层脱敏保证**：本视图的入参只有姓名、笔数与红白事标记，
/// 根本不接收金额，金额不可能出现在副屏任何像素里（不是遮罩、不是过滤，是无数据）。
/// 主屏内的「脱敏预览」复用同一视图，主家看到什么、副屏就是什么。
struct MaskedDisplayView: View {
    let latestName: String?
    let registeredCount: Int
    let isBai: Bool

    var body: some View {
        ZStack {
            Palette.pageBG.ignoresSafeArea()
            VStack(spacing: 28) {
                if let latestName {
                    Text(latestName)
                        .font(.system(size: 96, weight: .bold))
                        .foregroundStyle(Palette.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.4)
                    HStack(spacing: 12) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(isBai ? Palette.baiPrimary : Palette.primary)
                        Text("已登记")
                    }
                    .font(.system(size: 40, weight: .semibold))
                    .foregroundStyle(isBai ? Palette.baiPrimary : Palette.primary)
                } else {
                    Text("等待登记")
                        .font(.system(size: 64, weight: .bold))
                        .foregroundStyle(Palette.stone)
                }
                Text("本场累计 \(registeredCount) 笔")
                    .font(.system(size: 34))
                    .foregroundStyle(Palette.stone)
            }
            .padding(48)
        }
    }
}

// MARK: 外接屏呈现

/// 外接屏呈现器：监听 UIScreen 连接/断开，把 MaskedDisplayView 挂到副屏窗口。
/// 窗口只承载脱敏视图；每次新登记调 update 换内容。连接前已有登记时，
/// attach 时用最近一笔快照初始化，副屏一亮就是当前状态。
@MainActor
final class ExternalDisplayPresenter: ObservableObject {
    @Published private(set) var isConnected = false

    private var window: UIWindow?
    private var hosting: UIHostingController<MaskedDisplayView>?
    // 观察者 token 只在主线程增删、deinit 里统一移除；NSObjectProtocol 非 Sendable，
    // Swift 6 下用 nonisolated(unsafe) 承接这一既定用法（deinit 无法访问隔离属性）。
    nonisolated(unsafe) private var observers: [NSObjectProtocol] = []

    // 最近一次脱敏内容快照（连接/重连时回放）
    private var latestName: String?
    private var registeredCount = 0
    private var isBai = false

    init() {
        let center = NotificationCenter.default
        observers.append(center.addObserver(
            forName: UIScreen.didConnectNotification, object: nil, queue: .main
        ) { [weak self] note in
            guard let screen = note.object as? UIScreen else { return }
            Task { @MainActor [weak self] in self?.attach(to: screen) }
        })
        observers.append(center.addObserver(
            forName: UIScreen.didDisconnectNotification, object: nil, queue: .main
        ) { [weak self] note in
            guard let screen = note.object as? UIScreen else { return }
            Task { @MainActor [weak self] in self?.detach(from: screen) }
        })
        if let external = UIScreen.screens.dropFirst().first {
            attach(to: external)
        }
    }

    deinit {
        observers.forEach { NotificationCenter.default.removeObserver($0) }
    }

    func update(name: String?, count: Int, bai: Bool) {
        latestName = name
        registeredCount = count
        isBai = bai
        hosting?.rootView = MaskedDisplayView(
            latestName: name, registeredCount: count, isBai: bai
        )
    }

    private func attach(to screen: UIScreen) {
        guard window == nil else { return }
        let w = UIWindow(frame: screen.bounds)
        w.screen = screen
        let hc = UIHostingController(rootView: MaskedDisplayView(
            latestName: latestName, registeredCount: registeredCount, isBai: isBai
        ))
        w.rootViewController = hc
        w.isHidden = false
        window = w
        hosting = hc
        isConnected = true
    }

    private func detach(from screen: UIScreen) {
        guard window?.screen == screen else { return }
        window = nil
        hosting = nil
        isConnected = false
    }
}

// MARK: - 现场模式主页面

struct SceneModeView: View {
    let ledger: Ledger

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var allRecords: [GiftRecord]

    @StateObject private var presenter = ExternalDisplayPresenter()
    @StateObject private var announcer = SceneAnnouncer()
    @AppStorage("sceneAnnounceEnabled") private var announceEnabled = true

    @State private var person = ""
    @State private var amountText = ""
    @State private var relation = "朋友"
    @State private var method = "现金"
    @State private var isSaving = false
    @State private var errorText: String?
    @State private var session: [SceneEntry] = []
    @State private var baseline: (count: Int, cents: Int)?
    @State private var showMaskPreview = false
    @State private var showReview = false
    @State private var exportAfterReview = false
    @State private var showExport = false
    @State private var saveTrigger = 0
    @State private var errorTrigger = 0
    @FocusState private var focus: Field?

    private enum Field { case name, amount }

    /// 本场落库快照（值类型）：汇总、播报、复核都只读它，不受礼簿其他入口记账干扰
    private struct SceneEntry {
        var person: String
        var amountCents: Int
        var method: String
        var relation: String
    }

    private var isBai: Bool { ledger.isBai }
    private var accentFill: Color { isBai ? Palette.baiPrimaryFill : Palette.primaryFill }

    private var ledgerRecords: [GiftRecord] {
        allRecords.filter { $0.ledgerID == ledger.id }
    }

    private var ledgerReceived: (count: Int, cents: Int) {
        let rs = ledgerRecords.filter { $0.direction == LiqianConstants.received }
        return (rs.count, rs.reduce(0) { $0 + $1.amountCents })
    }

    private var sessionCents: Int { session.reduce(0) { $0 + $1.amountCents } }

    private var methodSubtotals: [(method: String, count: Int, cents: Int)] {
        LiqianConstants.methods.compactMap { m in
            let rows = session.filter { $0.method == m }
            guard !rows.isEmpty else { return nil }
            return (m, rows.count, rows.reduce(0) { $0 + $1.amountCents })
        }
    }

    var body: some View {
        ZStack {
            Palette.pageBG.ignoresSafeArea()
            ScrollView {
                VStack(spacing: LiqianMetrics.spacingL) {
                    header
                    summaryBand
                    inputCard
                    displayRow
                }
                .padding(LiqianMetrics.spacingM)
            }
        }
        .onAppear {
            if baseline == nil { baseline = ledgerReceived }
            presenter.update(name: session.last?.person, count: session.count, bai: isBai)
            // 锁屏 Live Activity（v4.5）：进场开横幅（已有进行中的只同步进度，
            // 不重建）；系统未授权/重签不可用时控制器内部静默跳过
            SceneLiveActivityController.start(
                ledgerTitle: ledger.title, isBai: isBai,
                entryCount: session.count, totalCents: sessionCents,
                lastPerson: session.last?.person ?? ""
            )
            // 收礼台一开就是几个小时：本页在场期间不息屏
            UIApplication.shared.isIdleTimerDisabled = true
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(350))
                focus = .name
            }
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
            announcer.stop()
            // 离场即收横幅（复核单是本页的 sheet，弹出不触发本页 disappear）
            SceneLiveActivityController.end()
        }
        .sensoryFeedback(.success, trigger: saveTrigger)
        .sensoryFeedback(.warning, trigger: errorTrigger)
        .sheet(isPresented: $showReview, onDismiss: {
            if exportAfterReview {
                exportAfterReview = false
                showExport = true
            }
        }) {
            SceneReviewView(
                ledger: ledger,
                sessionCount: session.count,
                sessionCents: sessionCents,
                methodSubtotals: methodSubtotals,
                baseline: baseline ?? (0, 0),
                current: ledgerReceived,
                onExport: {
                    exportAfterReview = true
                    showReview = false
                },
                onFinish: {
                    showReview = false
                    dismiss()
                }
            )
        }
        .sheet(isPresented: $showExport) {
            LibuExportView(ledger: ledger, records: ledgerRecords)
        }
    }

    // MARK: 头部：礼簿名 + 播报开关 + 结束（出复核单）

    private var header: some View {
        HStack(spacing: LiqianMetrics.spacingSM) {
            VStack(alignment: .leading, spacing: LiqianMetrics.spacingXS) {
                Text(ledger.title)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                Text("现场模式 · \(ledger.type)")
                    .font(.subheadline)
                    .foregroundStyle(Palette.stone)
            }
            Spacer()
            Toggle(isOn: $announceEnabled) {
                Label("播报", systemImage: announceEnabled ? "speaker.wave.2.fill" : "speaker.slash")
                    .font(.subheadline.weight(.semibold))
            }
            .toggleStyle(.button)
            .tint(accentFill)
            Button {
                showReview = true
            } label: {
                Text("结束")
                    .font(.headline)
                    .frame(minHeight: LiqianMetrics.minTapTarget)
                    .padding(.horizontal, LiqianMetrics.spacingSM)
            }
            .buttonStyle(.bordered)
            .tint(accentFill)
        }
    }

    // MARK: 实时汇总带

    private var summaryBand: some View {
        HStack(spacing: LiqianMetrics.spacingL) {
            VStack(alignment: .leading, spacing: LiqianMetrics.spacingXS) {
                Text("本场 \(session.count) 笔")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(Palette.ink)
                    .contentTransition(.numericText())
                if let last = session.last {
                    Text("上一笔：\(last.person) · \(last.method)")
                        .font(.footnote)
                        .foregroundStyle(Palette.stone)
                        .lineLimit(1)
                } else {
                    Text("还没有登记")
                        .font(.footnote)
                        .foregroundStyle(Palette.stone)
                }
            }
            Spacer()
            Text(LedgerMath.fmtMoney(cents: sessionCents))
                .font(.liqianMoney(.largeTitle))
                .foregroundStyle(Palette.ink)
                .contentTransition(.numericText())
        }
        .liqianCardSurface(bai: isBai)
    }

    // MARK: 登记卡：姓名 + 金额（大字）+ 常用金额/方式/关系 chips + 大登记钮

    private static let quickAmounts = [100, 200, 300, 500, 800, 1000, 2000]

    private var inputCard: some View {
        VStack(alignment: .leading, spacing: LiqianMetrics.spacingM) {
            HStack(spacing: LiqianMetrics.spacingSM) {
                Text("姓名")
                    .font(.headline)
                    .foregroundStyle(Palette.ink)
                TextField("来宾姓名", text: $person)
                    .font(.system(size: 26, weight: .semibold))
                    .focused($focus, equals: .name)
                    .submitLabel(.next)
                    .onSubmit { focus = .amount }
            }
            Divider()
            HStack(alignment: .firstTextBaseline, spacing: LiqianMetrics.spacingS) {
                Text("¥")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(Palette.stone)
                TextField("0", text: $amountText)
                    .font(.system(size: 44, weight: .bold).monospacedDigit())
                    .foregroundStyle(Palette.ink)
                    .keyboardType(.decimalPad)
                    .focused($focus, equals: .amount)
            }
            chipRow(title: "常用金额") {
                ForEach(Self.quickAmounts, id: \.self) { yuan in
                    chip(label: "\(yuan)", selected: amountText == "\(yuan)") {
                        amountText = "\(yuan)"
                        errorText = nil
                    }
                }
            }
            chipRow(title: "方式") {
                ForEach(LiqianConstants.methods, id: \.self) { m in
                    chip(label: m, selected: method == m) { method = m }
                }
            }
            chipRow(title: "关系") {
                // 数据源＝关系目录（系统＋自定义）；当前值若不在目录内
                // （自定义关系被删）临时并入，选中态不丢
                ForEach(RelationCatalog.pickerOptions(including: relation), id: \.self) { r in
                    chip(label: r, selected: relation == r) { relation = r }
                }
            }
            if let errorText {
                Text(errorText)
                    .font(.headline)
                    .foregroundStyle(Palette.danger)
            }
            Button {
                save()
            } label: {
                Text("登记这一笔")
                    .font(.title3.weight(.bold))
                    .frame(maxWidth: .infinity, minHeight: 64)
            }
            .buttonStyle(.borderedProminent)
            .tint(accentFill)
            .disabled(isSaving)
        }
        .liqianCardSurface(bai: isBai)
    }

    private func chipRow<Content: View>(
        title: String, @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: LiqianMetrics.spacingS) {
            Text(title)
                .font(.footnote)
                .foregroundStyle(Palette.stone)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: LiqianMetrics.spacingS) { content() }
            }
        }
    }

    private func chip(label: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.headline)
                .padding(.horizontal, LiqianMetrics.spacingM)
                .frame(minHeight: 52)
        }
        .buttonStyle(.bordered)
        .tint(selected ? accentFill : Palette.stone)
        .background(
            selected
                ? (isBai ? Palette.baiPrimary.opacity(0.12) : Palette.primaryTint)
                : Color.clear,
            in: Capsule()
        )
    }

    // MARK: 投屏状态行：已连接显状态；未连接给脱敏预览（主家先确认副屏长什么样）

    private var displayRow: some View {
        VStack(alignment: .leading, spacing: LiqianMetrics.spacingS) {
            HStack(spacing: LiqianMetrics.spacingSM) {
                Image(systemName: presenter.isConnected ? "tv.fill" : "tv")
                    .foregroundStyle(isBai ? Palette.baiPrimary : Palette.primary)
                if presenter.isConnected {
                    Text("外接屏已连接，正在脱敏显示（只显姓名与笔数）")
                        .font(.subheadline)
                        .foregroundStyle(Palette.ink)
                } else {
                    Text("未接外接屏")
                        .font(.subheadline)
                        .foregroundStyle(Palette.stone)
                    Spacer()
                    Button(showMaskPreview ? "收起预览" : "脱敏预览") {
                        showMaskPreview.toggle()
                    }
                    .font(.subheadline.weight(.semibold))
                    .frame(minHeight: LiqianMetrics.minTapTarget)
                    .tint(accentFill)
                }
            }
            if showMaskPreview && !presenter.isConnected {
                MaskedDisplayView(
                    latestName: session.last?.person,
                    registeredCount: session.count,
                    isBai: isBai
                )
                .frame(height: 220)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(Palette.hairline)
                )
            }
        }
        .liqianCardSurface(bai: isBai)
    }

    // MARK: 保存：与 RecordFormView 同口径（校验＋isSaving 防重入＋一次落库）

    private func save() {
        guard !isSaving else { return }
        let name = person.trimmingCharacters(in: .whitespaces)
        let amountValue = Double(amountText.trimmingCharacters(in: .whitespaces))
        let cents: Int? = amountValue.flatMap { $0 > 0 ? Int(($0 * 100.0).rounded()) : nil }
        guard !name.isEmpty, let cents else {
            errorText = name.isEmpty ? "先填来宾姓名" : "金额不对，检查一下"
            errorTrigger += 1
            return
        }
        isSaving = true
        errorText = nil
        modelContext.insert(
            GiftRecord(
                ledgerID: ledger.id,
                person: name,
                relation: relation,
                amountCents: cents,
                direction: LiqianConstants.received,
                method: method,
                date: LiqianDate.todayString()
            )
        )
        try? modelContext.save()
        session.append(SceneEntry(person: name, amountCents: cents, method: method, relation: relation))
        saveTrigger += 1
        if announceEnabled {
            announcer.announce(name: name, amountCents: cents, bai: isBai)
        }
        presenter.update(name: name, count: session.count, bai: isBai)
        // 锁屏横幅同步本场进度（v4.5）
        SceneLiveActivityController.update(
            entryCount: session.count, totalCents: sessionCents, lastPerson: name
        )
        person = ""
        amountText = ""
        focus = .name
        isSaving = false
    }
}

// MARK: - 事后复核单

/// 退出时复核：本场汇总＋按方式小计＋与礼簿对账。
/// 对账口径：应有总数＝入场基线（收礼笔数/总额）＋本场；实际＝当前礼簿收礼数（实时查询）。
/// 两者相等显「对账一致」；不等给出差额（多半是本场之外有人同时从别的入口记了账，
/// 或本场记录被删改），只报告不自动修正——礼房对账要人确认，不让程序偷偷改账。
struct SceneReviewView: View {
    let ledger: Ledger
    let sessionCount: Int
    let sessionCents: Int
    let methodSubtotals: [(method: String, count: Int, cents: Int)]
    let baseline: (count: Int, cents: Int)
    let current: (count: Int, cents: Int)
    let onExport: () -> Void
    let onFinish: () -> Void

    @Environment(\.dismiss) private var dismiss

    private var isBai: Bool { ledger.isBai }
    private var expectedCount: Int { baseline.count + sessionCount }
    private var expectedCents: Int { baseline.cents + sessionCents }
    private var diffCount: Int { current.count - expectedCount }
    private var diffCents: Int { current.cents - expectedCents }
    private var reconciled: Bool { diffCount == 0 && diffCents == 0 }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    row("本场登记", "\(sessionCount) 笔")
                    row("本场总额", LedgerMath.fmtMoney(cents: sessionCents))
                } header: {
                    Text("本场汇总")
                }

                if !methodSubtotals.isEmpty {
                    Section {
                        ForEach(methodSubtotals, id: \.method) { item in
                            HStack {
                                Text(item.method)
                                    .foregroundStyle(Palette.ink)
                                Spacer()
                                Text("\(item.count) 笔 · \(LedgerMath.fmtMoney(cents: item.cents))")
                                    .font(.liqianMoney())
                                    .foregroundStyle(Palette.ink)
                            }
                        }
                    } header: {
                        Text("按方式小计")
                    }
                }

                Section {
                    row("入场前已有", "\(baseline.count) 笔 · \(LedgerMath.fmtMoney(cents: baseline.cents))")
                    row("应有总数", "\(expectedCount) 笔 · \(LedgerMath.fmtMoney(cents: expectedCents))")
                    row("礼簿现有", "\(current.count) 笔 · \(LedgerMath.fmtMoney(cents: current.cents))")
                    if reconciled {
                        Label("对账一致", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(Palette.primary)
                    } else {
                        Label(
                            "差额 \(diffCount) 笔 · \(LedgerMath.fmtMoney(cents: diffCents))",
                            systemImage: "exclamationmark.triangle.fill"
                        )
                        .foregroundStyle(Palette.danger)
                        Text("可能有人在本页之外同时记了账，或本场记录被改动。先核对礼簿明细，再决定是否调整。")
                            .font(.footnote)
                            .foregroundStyle(Palette.stone)
                    }
                } header: {
                    Text("与礼簿对账")
                }

                Section {
                    Button {
                        onExport()
                    } label: {
                        Label("导出礼谱", systemImage: "doc.richtext")
                            .frame(maxWidth: .infinity, minHeight: LiqianMetrics.minTapTarget)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(isBai ? Palette.baiPrimaryFill : Palette.primaryFill)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Palette.pageBG.ignoresSafeArea())
            .navigationTitle("复核单")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { onFinish() }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("继续登记") { dismiss() }
                }
            }
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(Palette.ink)
            Spacer()
            Text(value)
                .font(.liqianMoney())
                .foregroundStyle(Palette.ink)
        }
    }
}
