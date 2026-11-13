import SwiftData
import SwiftUI
import LiqianCore
import LiqianDesign

/// 记一笔 / 编辑记录（v2.6 重做：一张纸上落笔）。
/// 三种入口：从账本（账本固定）、从人物（账本 Picker 选、姓名预填）、编辑（全部预填）。
///
/// 旧版被真机斥「没特色、乱七八糟」，三个根源：①每块一个形状（分段裹大胶囊、
/// 姓名全宽胶囊、金额卡片、快捷金额圆形深红钮，四种语言）；②输姓名时系统键盘
/// 弹起盖住自绘金额键盘，两种输入法打架；③通篇通用记账表单，没有礼簿身份。
/// v2.6 定版结构：整个表单收进一张 surface 卡，页面 pageBG；卡内只有
/// 金额（主角）→ 快捷金额（扁平 chips）→ 姓名（联想 chips 行）三件事，
/// 关系/方式/日期/状态/备注收进可展开的「补充信息」；方向分段在卡外上方、
/// 标准 segmented 不包容器。保存成功在卡上落印收尾（礼簿身份）。
///
/// v5.14 全原生整改（第 3 期）：容器 ScrollView＋手堆卡 → 系统 Form
/// （方向/主表单/附属行各成 Section，「一张纸」的构成改由系统分组
/// 表面承载）；自绘金额键盘整段删除，金额改系统 decimalPad 键盘的
/// 真 TextField，旧键盘的输入合法性约束由 Core AmountInputText 承接；
/// 三个输入面（姓名/金额/备注）自此全走系统键盘、FocusState 互斥退役。
///
/// 保存语义与校验与旧版一致，未动：姓名必填、金额 > 0、
/// 防重复提交 isSaving、落印等待 1.05s 后关闭（保存并继续则清字段续记）。
///
/// v5.14.1 热修：①保存走 SaveSupport——失败显形、不装成功（审计
/// A5）；②日期行提出补充信息、到主表单明面，固定簿默认礼簿事由
/// 日、回执入账默认回执提交日（审计 B）。
struct RecordFormView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query(sort: \Ledger.date, order: .reverse) private var allLedgers: [Ledger]
    @Query private var allRecords: [GiftRecord]

    let fixedLedger: Ledger?
    let existing: GiftRecord?
    /// 宾客回执入账（v5.12）专用：新建保存成功后回调一次新建的记录，
    /// 其他入口为 nil。表单「保存并继续」会多次落库、多次回调，
    /// 消费方须按自身状态幂等处理（回执页按 pending 状态守卫）。
    let onSavedNewRecord: ((GiftRecord) -> Void)?

    @State private var person: String
    @State private var amountText: String
    @State private var relation: String
    @State private var direction: String
    @State private var method: String
    @State private var date: Date
    @State private var status: String
    @State private var note: String
    @State private var selectedLedgerID: UUID?
    @State private var saveAndContinue = false
    /// 防重复提交（PRO-AUDIT-2 F3）：落印 1.05s 等待期内锁住保存与退出，
    /// 连点「保存」只落一笔
    @State private var isSaving = false
    /// 保存被拦的整表级原因（v4.2）：显示在主卡上方，不再只有震动反馈
    @State private var formError: String?
    @State private var personError: String?
    @State private var amountError: String?
    @State private var savedMessage: String?
    @State private var saveTrigger = 0
    @State private var showSeal = false
    @State private var sealText = "礼"
    @State private var sealTrigger = 0
    @State private var errorTrigger = 0
    @State private var deleteTrigger = 0
    @State private var confirmDelete = false
    @State private var showQuickSentence = false
    @State private var showAIGuide = false
    /// 补充信息默认收起（主屏只留方向/金额/姓名）；编辑既有记录时默认展开
    @State private var showSupplements: Bool
    @FocusState private var focus: Field?

    /// 输入焦点（v5.14 起三面全走系统键盘，焦点只管键盘归属）
    enum Field { case person, amount, note }

    /// 从账本新建（v5.14.1：日期默认这本礼簿的事由日——在礼簿里
    /// 记账，记的绝大多数就是事由当天那笔，默认值先替用户落对）
    init(ledger: Ledger) {
        fixedLedger = ledger
        existing = nil
        onSavedNewRecord = nil
        _person = State(initialValue: "")
        _amountText = State(initialValue: "")
        _relation = State(initialValue: "朋友")
        _direction = State(initialValue: LiqianConstants.received)
        _method = State(initialValue: "现金")
        _date = State(initialValue: LiqianDate.date(from: ledger.date))
        _status = State(initialValue: LiqianConstants.sentStatus)
        _note = State(initialValue: "")
        _showSupplements = State(initialValue: false)
    }

    /// 编辑既有记录
    init(existing: GiftRecord) {
        fixedLedger = nil
        self.existing = existing
        onSavedNewRecord = nil
        _person = State(initialValue: existing.person)
        _amountText = State(initialValue: Self.amountString(cents: existing.amountCents))
        _relation = State(initialValue: existing.relation)
        _direction = State(initialValue: existing.direction)
        _method = State(initialValue: existing.method)
        _date = State(initialValue: LiqianDate.date(from: existing.date))
        _status = State(initialValue: existing.status)
        _note = State(initialValue: existing.note)
        _showSupplements = State(initialValue: true)
    }

    /// 从人物新建：姓名预填、方向预设，账本用 Picker 选
    init(personName: String, presetDirection: String) {
        fixedLedger = nil
        existing = nil
        onSavedNewRecord = nil
        _person = State(initialValue: personName)
        _amountText = State(initialValue: "")
        _relation = State(initialValue: "朋友")
        _direction = State(initialValue: presetDirection)
        _method = State(initialValue: "现金")
        _date = State(initialValue: Date())
        _status = State(initialValue: LiqianConstants.sentStatus)
        _note = State(initialValue: "")
        _showSupplements = State(initialValue: false)
    }

    /// 宾客回执入账（v5.12）：账本固定、方向收礼，姓名/金额/备注按回执
    /// 预填（备注＝来源＋祝福，见 GuestReceiptMapping.recordNote），
    /// 补充信息默认展开——备注是这笔的来历，用户保存前应当看得见。
    /// v5.14.1：日期默认回执的服务器提交日（receiptDate，调用方传
    /// GuestReceipt.createdAtDate），不再默认今天。
    init(
        ledger: Ledger,
        receiptName: String,
        receiptAmountCents: Int,
        receiptNote: String,
        receiptDate: Date,
        onSavedNewRecord: @escaping (GiftRecord) -> Void
    ) {
        fixedLedger = ledger
        existing = nil
        self.onSavedNewRecord = onSavedNewRecord
        _person = State(initialValue: receiptName)
        _amountText = State(initialValue: Self.amountString(cents: receiptAmountCents))
        _relation = State(initialValue: "朋友")
        _direction = State(initialValue: LiqianConstants.received)
        _method = State(initialValue: "现金")
        _date = State(initialValue: receiptDate)
        _status = State(initialValue: LiqianConstants.sentStatus)
        _note = State(initialValue: receiptNote)
        _showSupplements = State(initialValue: true)
    }

    private static func amountString(cents: Int) -> String {
        cents % 100 == 0 ? "\(cents / 100)" : String(format: "%.2f", Double(cents) / 100.0)
    }

    /// 人物入口模式：既非编辑、也无固定账本时才需要选账本
    private var needsLedgerPicker: Bool { existing == nil && fixedLedger == nil }

    private var effectiveLedgerID: UUID? {
        if let existing { return existing.ledgerID }
        if let fixedLedger { return fixedLedger.id }
        return selectedLedgerID ?? allLedgers.first?.id
    }

    private var effectiveLedger: Ledger? {
        guard let id = effectiveLedgerID else { return nil }
        if let fixedLedger, fixedLedger.id == id { return fixedLedger }
        return allLedgers.first { $0.id == id }
    }

    /// 历史人物联想：名字里出现过的就提示，选中带入上次用的关系（同 Flutter 版）
    private var suggestions: [PersonSummary] {
        let q = person.trimmingCharacters(in: .whitespaces)
        if q.isEmpty { return [] }
        return Array(
            LedgerMath.people(from: AppSupport.snapshots(records: allRecords, ledgers: allLedgers))
                .filter { $0.name.contains(q) && $0.name != q }
                .prefix(5)
        )
    }

    /// 回礼参考年涨幅设置（与人物详情卡同键同源）
    @AppStorage(ReplyAdvisor.annualRateKey) private var annualRatePercent = ReplyAdvisor.defaultAnnualRatePercent

    /// 上次使用礼簿（v5.8.1，审计 #10）：新建记账成功后回写本次所记
    /// 礼簿 ID 字符串，下次新建默认先它（决策顺序在
    /// DefaultLedgerPicker，Core 纯逻辑＋单测）；编辑既有记录不回写
    /// ——编辑不做选簿动作，不算「使用」。
    @AppStorage(DefaultLedgerPicker.lastUsedKey) private var lastUsedLedgerIDRaw = ""

    /// 回礼提示（v4.3）：记随礼、新建、已填姓名且与此人有收礼往来时才有；
    /// 场合＝当前礼簿事由。没依据（没收过他的礼）返回 nil，提示行不出
    private var replyAdvice: ReplyAdvice? {
        guard existing == nil, direction == LiqianConstants.given else { return nil }
        let q = person.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return nil }
        return ReplyAdvisor.advice(
            from: AppSupport.snapshots(records: allRecords, ledgers: allLedgers),
            person: q,
            occasionType: effectiveLedger?.type ?? "",
            today: LiqianDate.todayString(),
            annualRatePercent: annualRatePercent
        )
    }

    /// 同人提示：这个名字在本礼簿已有的笔数（编辑时不算自己这笔）
    private var sameLedgerCount: Int {
        let q = person.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty, let lid = effectiveLedgerID else { return 0 }
        return allRecords.filter {
            $0.ledgerID == lid && $0.person == q && $0.id != existing?.id
        }.count
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    directionSegmented
                }
                Section {
                    formCard
                }
                .listRowInsets(EdgeInsets(
                    top: LiqianMetrics.cardPadding, leading: LiqianMetrics.cardPadding,
                    bottom: LiqianMetrics.cardPadding, trailing: LiqianMetrics.cardPadding
                ))
                .listRowBackground(
                    (effectiveLedger?.isBai ?? false) ? Palette.baiCard : Palette.card
                )
                // 活礼谱（v4.2）：签名/祝福挂具体一笔，只在编辑态出现
                // （新建的笔先保存拿到 id 才有处可挂）；其自有表面保留，
                // 以透明行底嵌进分组列表（与旧滚动版的卡片陈列同观感）
                if let existing {
                    Section {
                        RecordLiveMediaSection(record: existing)
                    }
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                }
                if existing == nil {
                    Section {
                        saveAndContinueCard
                    }
                }
                if existing != nil {
                    Section {
                        deleteCard
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Palette.pageBG.ignoresSafeArea())
            // 滚动时可交互式收起系统键盘（v4.4，v5.14 起三面全走系统键盘）
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(existing == nil ? "记一笔" : "编辑记录")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                        .disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                        .disabled(isSaving)
                }
            }
            .interactiveDismissDisabled(isSaving)
            .sensoryFeedback(.impact(weight: .light, intensity: 0.5), trigger: amountText)
            .sensoryFeedback(.impact(weight: .medium), trigger: sealTrigger)
            .sensoryFeedback(.success, trigger: saveTrigger)
            .sensoryFeedback(.warning, trigger: errorTrigger)
            .sensoryFeedback(.warning, trigger: deleteTrigger)
            .sensoryFeedback(.selection, trigger: direction)
            .sensoryFeedback(.selection, trigger: status)
            .sheet(isPresented: $showQuickSentence) {
                QuickSentenceView { results in
                    saveAIResults(results)
                }
            }
            .alert("AI 还没准备好", isPresented: $showAIGuide) {
                Button("去设置") {
                    NotificationCenter.default.post(name: .liqianOpenAISettings, object: nil)
                }
                Button("好", role: .cancel) {}
            } message: {
                Text(AIAccess.readiness().guideMessage)
            }
            .confirmationDialog("删除这笔记录？", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("删除", role: .destructive) { deleteExisting() }
                Button("取消", role: .cancel) {}
            } message: {
                Text("删除后 30 天内可以在「我的 → 最近删除」恢复。")
            }
            .onAppear {
                if needsLedgerPicker, selectedLedgerID == nil {
                    // 默认礼簿（v4.2 修复＋v5.8.1 上次使用优先）：此前取
                    // allLedgers.first（顺序不定），示例礼簿常排在前面，
                    // 随礼会默认记进示例簿——而示例数据是统计隔离的，
                    // 往来/差额里看不到，表现为「保存没反应」。
                    // 决策顺序（DefaultLedgerPicker，单测钉死）：上次
                    // 成功记账所用礼簿（仍存在且非示例）→ 日期最新非
                    // 示例礼簿 → 日期最新礼簿（只剩示例时）。
                    let sampleIDs = SampleData.sampleIDs(ledgers: allLedgers)
                    let byDate = allLedgers.sorted { $0.date > $1.date }
                    selectedLedgerID = DefaultLedgerPicker.pick(
                        lastUsedID: UUID(uuidString: lastUsedLedgerIDRaw),
                        ledgerIDsByDateDescending: byDate.map(\.id),
                        sampleIDs: sampleIDs
                    )
                }
                if existing == nil {
                    focus = .person
                }
            }
            .onChange(of: person) { _, _ in formError = nil }
            .onChange(of: amountText) { _, newValue in
                // v5.14：旧自绘键盘的输入合法性约束由 Core 净化函数承接
                // （至多两位小数/整数至多 7 位/不留前导零），系统键盘与
                // 粘贴进来的文本都过同一道口径；保存侧校验不变
                let cleaned = AmountInputText.sanitized(newValue)
                if cleaned != newValue { amountText = cleaned }
                formError = nil
            }
        }
        // 存储不安全时整页阻断（v5.14.2，见 StorageGuard）
        .storageBlockGuard()
    }

    // MARK: - 方向：标准 segmented，卡外上方，不包任何额外胶囊容器

    private var directionSegmented: some View {
        Picker("方向", selection: $direction) {
            Text("收礼").tag(LiqianConstants.received)
            Text("随礼").tag(LiqianConstants.given)
        }
        .pickerStyle(.segmented)
    }

    // MARK: - 主表单：落印盖在其上（v5.14 起由 Form Section 承载表面）

    private var formCard: some View {
        VStack(spacing: LiqianMetrics.spacingM) {
            if let formError {
                Text(formError)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(Palette.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if needsLedgerPicker {
                ledgerPickerRow
            }
            amountBlock
            amountChips
            if let advice = replyAdvice {
                replyHintRow(advice)
            }
            nameBlock
            dateRow
            supplementsBlock
        }
        .overlay {
            // 落印收尾：印盖在表单中央偏右（全屏居中是旧版位置，纸在哪印落哪）
            SealStampOverlay(
                char: sealText,
                bai: effectiveLedger?.isBai ?? false,
                presented: showSeal
            )
            .offset(x: 44)
        }
    }

    /// 选账本行（仅人物/全局入口）：卡内第一行，原生标签行＋菜单 Picker
    @ViewBuilder
    private var ledgerPickerRow: some View {
        if allLedgers.isEmpty {
            Text("先建一本礼簿，再来记账。")
                .font(.footnote)
                .foregroundStyle(Palette.sub)
        } else {
            labeledRow("礼簿") {
                Picker("礼簿", selection: $selectedLedgerID) {
                    ForEach(allLedgers) { l in
                        Text(l.title).tag(l.id as UUID?)
                    }
                }
                .labelsHidden()
            }
        }
    }

    /// 原生标签行：标签左、控件右（补充信息与账本行共用）
    private func labeledRow<Control: View>(_ label: String, @ViewBuilder control: () -> Control) -> some View {
        HStack(spacing: LiqianMetrics.spacingSM) {
            Text(label)
                .foregroundStyle(Palette.ink)
            Spacer()
            control()
        }
        .frame(minHeight: LiqianMetrics.minTapTarget)
    }

    // MARK: - 金额主角：卡内第一行（v5.14：系统 decimalPad 键盘的真
    // TextField，字阶回自家语义金额口径 liqianMoney(.largeTitle)——
    // 定版「记账大字显示」档；旧写死 44pt 与自绘光标一并退役）

    private var amountBlock: some View {
        VStack(alignment: .leading, spacing: LiqianMetrics.spacingS) {
            HStack(alignment: .center, spacing: LiqianMetrics.spacingS) {
                Text("¥")
                    .font(.liqianMoney(.title2))
                    .foregroundStyle(Palette.sub)
                TextField("金额", text: $amountText, prompt: Text("0"))
                    .keyboardType(.decimalPad)
                    .focused($focus, equals: .amount)
                    .font(.liqianMoney(.largeTitle))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .contentTransition(.numericText())
                    .accessibilityLabel("金额")
                Spacer()
            }
            .frame(minHeight: LiqianMetrics.minTapTarget)
            if let amountError {
                Text(amountError)
                    .font(.footnote)
                    .foregroundStyle(Palette.danger)
            }
        }
    }

    /// 快捷金额：圆角矩形扁平 chips（primaryTint 底＋primary 字），
    /// 禁止圆形、禁止深红棕——夜晚主题下也不出浑浊色（走令牌即达标）
    private var amountChips: some View {
        HStack(spacing: LiqianMetrics.spacingS) {
            ForEach([100, 200, 300, 500, 800, 1000], id: \.self) { v in
                Button {
                    amountText = "\(v)"
                    amountError = nil
                } label: {
                    Text("\(v)")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Palette.primary)
                        .frame(maxWidth: .infinity, minHeight: 38)
                        .background(
                            Palette.primaryTint,
                            in: RoundedRectangle(cornerRadius: LiqianMetrics.controlCorner)
                        )
                }
            }
        }
    }

    /// 回礼提示行：金额区下方一行小字，给区间与依据，点按填入建议值（锚定值）
    private func replyHintRow(_ a: ReplyAdvice) -> some View {
        Button {
            amountText = Self.amountString(cents: a.suggestedCents)
            amountError = nil
        } label: {
            HStack(spacing: LiqianMetrics.spacingS) {
                Image(systemName: "arrow.uturn.backward.circle")
                    .font(.footnote)
                Text("回礼参考 \(LedgerMath.fmtMoney(cents: a.lowerCents))–\(LedgerMath.fmtMoney(cents: a.upperCents))（\(a.reasons.first ?? "")），点按填 \(LedgerMath.fmtMoney(cents: a.suggestedCents))")
                    .font(.footnote)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
            }
            .foregroundStyle(Palette.primary)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("回礼参考，点按填入建议金额 \(LedgerMath.fmtMoney(cents: a.suggestedCents))")
    }

    // MARK: - 姓名行：标签＋输入＋麦克风（一句话记账入口）；联想改横向 chips 行

    private var nameBlock: some View {
        VStack(alignment: .leading, spacing: LiqianMetrics.spacingS) {
            HStack(spacing: LiqianMetrics.spacingSM) {
                Text("姓名")
                    .foregroundStyle(Palette.ink)
                TextField("姓名", text: $person, prompt: Text("如：大舅、二姨、张三"))
                    .focused($focus, equals: .person)
                if existing == nil {
                    // 一句话记账（含语音）入口收敛到姓名行右侧麦克风钮：
                    // 点开 QuickSentenceView 拆多笔核对，确认后走 saveAIResults 一次落库
                    Button {
                        openQuickSentence()
                    } label: {
                        Image(systemName: "mic")
                            .font(.body.weight(.medium))
                            .foregroundStyle(Palette.primary)
                            .frame(width: LiqianMetrics.minTapTarget, height: LiqianMetrics.minTapTarget)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("一句话记账")
                }
            }
            if let personError {
                Text(personError)
                    .font(.footnote)
                    .foregroundStyle(Palette.danger)
            }
            if !suggestions.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: LiqianMetrics.spacingS) {
                        ForEach(suggestions) { p in
                            Button {
                                person = p.name
                                if RelationCatalog.all().contains(p.relation) {
                                    relation = p.relation
                                }
                            } label: {
                                HStack(spacing: LiqianMetrics.spacingXS) {
                                    Text(p.name)
                                        .font(.subheadline.weight(.medium))
                                        .foregroundStyle(Palette.ink)
                                    Text(p.relation)
                                        .font(.footnote)
                                        .foregroundStyle(Palette.sub)
                                }
                                .padding(.horizontal, LiqianMetrics.spacingSM)
                                .frame(minHeight: 36)
                                .background(
                                    Palette.primaryTint,
                                    in: RoundedRectangle(cornerRadius: LiqianMetrics.controlCorner)
                                )
                            }
                            .accessibilityLabel("选\(p.name)，\(p.relation)，共 \(p.count) 笔往来")
                        }
                    }
                }
            }
            if sameLedgerCount > 0 {
                Text("此人在本礼簿已有 \(sameLedgerCount) 笔，再记一笔会并列保存。")
                    .font(.footnote)
                    .foregroundStyle(Palette.sub)
            }
        }
    }

    private func openQuickSentence() {
        if AIAccess.readiness() == .ready {
            showQuickSentence = true
        } else {
            showAIGuide = true
        }
    }

    // MARK: - 日期行（v5.14.1 提出补充信息，主表单明面）
    // 不是婚礼当天给的人也要能当场改对日子，不必先展开折叠区找；
    // 默认值口径见各 init（固定簿＝事由日／全局＝今天／回执＝提交日）

    private var dateRow: some View {
        labeledRow("日期") {
            DatePicker("日期", selection: $date, displayedComponents: .date)
                .labelsHidden()
        }
    }

    // MARK: - 补充信息：默认收起，展开为卡内原生行

    private var supplementsBlock: some View {
        VStack(spacing: LiqianMetrics.spacingSM) {
            Button {
                // Reduce Motion 时无动画直接展开（v4.4）；chevron 旋转随之静态切换
                withAnimation(reduceMotion ? nil : .snappy) { showSupplements.toggle() }
            } label: {
                HStack(spacing: LiqianMetrics.spacingS) {
                    Text("补充信息")
                        .foregroundStyle(Palette.ink)
                    Spacer()
                    if !showSupplements {
                        Text("\(relation) · \(method)")
                            .font(.footnote)
                            .foregroundStyle(Palette.sub)
                    }
                    Image(systemName: "chevron.down")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Palette.sub)
                        .rotationEffect(.degrees(showSupplements ? 180 : 0))
                }
                .frame(minHeight: LiqianMetrics.minTapTarget)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(showSupplements ? "收起补充信息" : "展开补充信息")

            if showSupplements {
                VStack(spacing: LiqianMetrics.spacingSM) {
                    if !needsLedgerPicker, let l = effectiveLedger {
                        labeledRow("礼簿") {
                            Text(l.title)
                                .foregroundStyle(Palette.sub)
                        }
                    }
                    labeledRow("关系") {
                        Picker("关系", selection: $relation) {
                            // 数据源＝关系目录（系统＋自定义）；编辑旧记录时现有关系
                            // 若已被删除，临时并入保证选中态不丢
                            ForEach(RelationCatalog.pickerOptions(including: relation), id: \.self) { r in
                                Text(r).tag(r)
                            }
                        }
                        .labelsHidden()
                    }
                    labeledRow("方式") {
                        Picker("方式", selection: $method) {
                            ForEach(LiqianConstants.methods, id: \.self) { m in
                                Text(m).tag(m)
                            }
                        }
                        .labelsHidden()
                    }
                    if direction == LiqianConstants.given {
                        VStack(alignment: .leading, spacing: LiqianMetrics.spacingS) {
                            Text("状态")
                                .foregroundStyle(Palette.ink)
                            Picker("状态", selection: $status) {
                                Text("已送出").tag(LiqianConstants.sentStatus)
                                Text("待送出").tag(LiqianConstants.pendingStatus)
                            }
                            .pickerStyle(.segmented)
                            if status == LiqianConstants.pendingStatus {
                                Text("待送出记录不计入往来差额，送出后请改记为「已送出」。")
                                    .font(.footnote)
                                    .foregroundStyle(Palette.sub)
                            }
                        }
                    }
                    HStack(spacing: LiqianMetrics.spacingSM) {
                        Text("备注")
                            .foregroundStyle(Palette.ink)
                        TextField("备注", text: $note, prompt: Text("选填，实物礼写这里，如：两瓶酒"))
                            .focused($focus, equals: .note)
                    }
                    .frame(minHeight: LiqianMetrics.minTapTarget)
                }
            }
        }
    }

    // MARK: - 附属 Section：保存并继续（新建）／删除（编辑）

    private var saveAndContinueCard: some View {
        VStack(alignment: .leading, spacing: LiqianMetrics.spacingS) {
            Toggle("保存并继续记", isOn: $saveAndContinue)
                .foregroundStyle(Palette.ink)
            if let savedMessage {
                Text(savedMessage)
                    .font(.footnote)
                    .foregroundStyle(Palette.sub)
            }
        }
    }

    private var deleteCard: some View {
        Button("删除这笔", role: .destructive) {
            confirmDelete = true
        }
        .frame(maxWidth: .infinity, minHeight: LiqianMetrics.minTapTarget)
    }

    private func save() {
        guard !isSaving else { return }
        let name = person.trimmingCharacters(in: .whitespaces)
        personError = name.isEmpty ? "请填写姓名" : nil
        let amountValue = Double(amountText.trimmingCharacters(in: .whitespaces))
        let cents: Int? = amountValue.flatMap { $0 > 0 ? Int(($0 * 100.0).rounded()) : nil }
        amountError = cents == nil ? "请输入正确的金额" : nil
        guard personError == nil, let cents, let lid = effectiveLedgerID else {
            // v4.2：保存被拦必须出声——此前只有震动，用户只看到「没反应」。
            // 缺什么说哪个（姓名/金额的字段级红字另有，这里给整表级一句话）。
            if name.isEmpty {
                formError = "请先填写姓名，再保存。"
            } else if cents == nil {
                formError = "请先填写正确的金额，再保存。"
            } else {
                formError = "还没有可以记的礼簿，请先新建一本礼簿再记。"
            }
            errorTrigger += 1
            return
        }
        formError = nil
        isSaving = true
        let finalStatus = direction == LiqianConstants.given ? status : LiqianConstants.sentStatus
        let trimmedNote = note.trimmingCharacters(in: .whitespaces)
        if let existing {
            existing.person = name
            existing.relation = relation
            existing.amountCents = cents
            existing.direction = direction
            existing.method = method
            existing.note = trimmedNote
            existing.date = LiqianDate.string(from: date)
            existing.status = finalStatus
            // v5.14.1：失败显形、不关页（审计 A5）
            guard SaveSupport.attempt(modelContext, onFailure: { formError = $0 }) else {
                isSaving = false
                errorTrigger += 1
                return
            }
            saveTrigger += 1
            dismiss()
        } else {
            let newRecord = GiftRecord(
                ledgerID: lid,
                person: name,
                relation: relation,
                amountCents: cents,
                direction: direction,
                method: method,
                note: trimmedNote,
                date: LiqianDate.string(from: date),
                status: finalStatus
            )
            modelContext.insert(newRecord)
            // v5.14.1：save 真成功才许回调回执/回写上次使用/落印——
            // 失败显形在表单里、内容不丢、不关页（审计 A5）
            guard SaveSupport.attempt(modelContext, onFailure: { formError = $0 }) else {
                isSaving = false
                errorTrigger += 1
                return
            }
            // 宾客回执入账（v5.12）：落库成功即回调，回执据此置已处理并关联
            onSavedNewRecord?(newRecord)
            // 上次使用回写（v5.8.1）：新建落库成功即记住这本，
            // 下次新建默认先它（保存并继续同理，只记一次）
            lastUsedLedgerIDRaw = lid.uuidString
            // 落印：盖印动画约 1 秒，不阻断输入；普通保存等印落完再关闭
            // 印文（v2.6 口径）：收礼「礼」；随礼用既有印资源——礼簿名首字印，
            // 无礼簿名可用时同印「礼」
            sealText = direction == LiqianConstants.received
                ? "礼"
                : (effectiveLedger.map { String($0.title.prefix(1)) } ?? "礼")
            showSeal = true
            sealTrigger += 1
            if saveAndContinue {
                person = ""
                amountText = ""
                note = ""
                personError = nil
                amountError = nil
                savedMessage = "已保存，继续记下一笔"
                focus = .person
                Task {
                    try? await Task.sleep(for: .milliseconds(1050))
                    showSeal = false
                    isSaving = false
                }
            } else {
                Task {
                    try? await Task.sleep(for: .milliseconds(1050))
                    dismiss()
                }
            }
        }
    }

    /// 一句话记账确认后的多笔（1 笔也是走这里）一次落库：沿用 save() 的字段口径
    /// （关系/方式缺失时用表单当前选择、日期用表单日期、随礼状态口径与 save() 一致）
    /// 与防重入 isSaving；整批只 save 一次、落印只盖一次
    private func saveAIResults(_ results: [QuickSentenceResult]) {
        guard !isSaving, !results.isEmpty, let lid = effectiveLedgerID else { return }
        isSaving = true
        let dateString = LiqianDate.string(from: date)
        for result in results {
            modelContext.insert(
                GiftRecord(
                    ledgerID: lid,
                    person: result.name,
                    relation: result.relation ?? relation,
                    amountCents: result.amountCents,
                    direction: result.direction,
                    method: result.method ?? method,
                    note: result.eventHint ?? "",
                    date: dateString,
                    status: result.direction == LiqianConstants.given
                        ? status
                        : LiqianConstants.sentStatus
                )
            )
        }
        guard SaveSupport.attempt(modelContext, onFailure: { formError = $0 }) else {
            isSaving = false
            errorTrigger += 1
            return
        }
        // 上次使用回写（v5.8.1）：与 save() 新建同口径
        lastUsedLedgerIDRaw = lid.uuidString
        saveTrigger += 1
        // 落印口径同 save()：全是随礼用礼簿名首字印，其余（含混合）盖「礼」印
        sealText = results.allSatisfy { $0.direction == LiqianConstants.given }
            ? (effectiveLedger.map { String($0.title.prefix(1)) } ?? "礼")
            : "礼"
        showSeal = true
        sealTrigger += 1
        if saveAndContinue {
            person = ""
            amountText = ""
            note = ""
            personError = nil
            amountError = nil
            savedMessage = "已保存 \(results.count) 笔，继续记下一笔"
            focus = .person
            Task {
                try? await Task.sleep(for: .milliseconds(1050))
                showSeal = false
                isSaving = false
            }
        } else {
            Task {
                try? await Task.sleep(for: .milliseconds(1050))
                dismiss()
            }
        }
    }

    private func deleteExisting() {
        guard let existing else { return }
        TrashStore.archive(record: existing)
        modelContext.delete(existing)
        // v5.14.1：删除落库失败同样不许装成功（不关页、表单内显形）
        guard SaveSupport.attempt(modelContext, onFailure: { formError = $0 }) else {
            errorTrigger += 1
            return
        }
        deleteTrigger += 1
        dismiss()
    }
}
