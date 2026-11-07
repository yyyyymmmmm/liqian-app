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
/// 输入法互斥（FocusState 三态）：姓名/备注激活→系统键盘、自绘键盘收起；
/// 金额激活→系统键盘收起（无文本框承接焦点）、自绘键盘作为卡下固定面板升起。
/// 任何时刻只有一个输入面。
///
/// 保存语义与校验与旧版一致，未动：姓名必填、金额 > 0、
/// 防重复提交 isSaving、落印等待 1.05s 后关闭（保存并继续则清字段续记）。
struct RecordFormView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Ledger.date, order: .reverse) private var allLedgers: [Ledger]
    @Query private var allRecords: [GiftRecord]

    let fixedLedger: Ledger?
    let existing: GiftRecord?

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

    /// 输入面三态：person/note 走系统键盘，amount 走自绘键盘面板，三者互斥
    enum Field { case person, amount, note }

    /// 从账本新建
    init(ledger: Ledger) {
        fixedLedger = ledger
        existing = nil
        _person = State(initialValue: "")
        _amountText = State(initialValue: "")
        _relation = State(initialValue: "朋友")
        _direction = State(initialValue: LiqianConstants.received)
        _method = State(initialValue: "现金")
        _date = State(initialValue: Date())
        _status = State(initialValue: LiqianConstants.sentStatus)
        _note = State(initialValue: "")
        _showSupplements = State(initialValue: false)
    }

    /// 编辑既有记录
    init(existing: GiftRecord) {
        fixedLedger = nil
        self.existing = existing
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
            ScrollView {
                VStack(spacing: LiqianMetrics.spacingM) {
                    directionSegmented
                    formCard
                    // 活礼谱（v4.2）：签名/祝福挂具体一笔，只在编辑态出现
                    // （新建的笔先保存拿到 id 才有处可挂）
                    if let existing {
                        RecordLiveMediaSection(record: existing)
                    }
                    if existing == nil {
                        saveAndContinueCard
                    }
                    if existing != nil {
                        deleteCard
                    }
                }
                .padding(LiqianMetrics.spacingM)
            }
            .background(Palette.pageBG.ignoresSafeArea())
            .safeAreaInset(edge: .bottom, spacing: 0) {
                // 金额输入面：自绘键盘作为卡下固定面板升起，与系统键盘互斥
                if focus == .amount {
                    amountKeypadPanel
                        .transition(.move(edge: .bottom))
                }
            }
            .animation(.snappy(duration: 0.25), value: focus)
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
                    selectedLedgerID = allLedgers.first?.id
                }
                if existing == nil {
                    focus = .person
                }
            }
        }
    }

    // MARK: - 方向：标准 segmented，卡外上方，不包任何额外胶囊容器

    private var directionSegmented: some View {
        Picker("方向", selection: $direction) {
            Text("收礼").tag(LiqianConstants.received)
            Text("随礼").tag(LiqianConstants.given)
        }
        .pickerStyle(.segmented)
    }

    // MARK: - 主卡：一张纸（surface 底 + 令牌圆角），落印盖在卡上

    private var formCard: some View {
        VStack(spacing: LiqianMetrics.spacingM) {
            if needsLedgerPicker {
                ledgerPickerRow
            }
            amountBlock
            amountChips
            if let advice = replyAdvice {
                replyHintRow(advice)
            }
            nameBlock
            supplementsBlock
        }
        .liqianCardSurface(bai: effectiveLedger?.isBai ?? false)
        .overlay {
            // 落印收尾：印盖在卡片中央偏右（全屏居中是旧版位置，纸在哪印落哪）
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
            labeledRow("账本") {
                Picker("账本", selection: $selectedLedgerID) {
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

    // MARK: - 金额主角：卡内第一行，点按激活自绘键盘

    private var amountBlock: some View {
        VStack(alignment: .leading, spacing: LiqianMetrics.spacingS) {
            HStack(alignment: .center, spacing: LiqianMetrics.spacingS) {
                Text("¥")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(Palette.sub)
                Text(amountText.isEmpty ? "0" : amountText)
                    .font(.system(size: 44, weight: .semibold).monospacedDigit())
                    .foregroundStyle(amountText.isEmpty ? Palette.sub : Palette.ink)
                    .contentTransition(.numericText())
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                if focus == .amount {
                    AmountCaret()
                }
                Spacer()
            }
            .frame(minHeight: LiqianMetrics.minTapTarget)
            .contentShape(Rectangle())
            .onTapGesture { focus = .amount }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("金额")
            .accessibilityValue(amountText.isEmpty ? "未输入，点按输入金额" : "\(amountText) 元")
            .accessibilityAddTraits(.isButton)
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
                .buttonStyle(.plain)
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
                                if LiqianConstants.relations.contains(p.relation) {
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
                            .buttonStyle(.plain)
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

    // MARK: - 补充信息：默认收起，展开为卡内原生行

    private var supplementsBlock: some View {
        VStack(spacing: LiqianMetrics.spacingSM) {
            Button {
                withAnimation(.snappy) { showSupplements.toggle() }
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
                        labeledRow("账本") {
                            Text(l.title)
                                .foregroundStyle(Palette.sub)
                        }
                    }
                    labeledRow("关系") {
                        Picker("关系", selection: $relation) {
                            ForEach(LiqianConstants.relations, id: \.self) { r in
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
                    labeledRow("日期") {
                        DatePicker("日期", selection: $date, displayedComponents: .date)
                            .labelsHidden()
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

    // MARK: - 卡外附属行：保存并继续（新建）／删除（编辑），与主卡同语言的次级纸面

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
        .liqianCardSurface(bai: effectiveLedger?.isBai ?? false, padding: LiqianMetrics.spacingSM)
    }

    private var deleteCard: some View {
        Button("删除这笔", role: .destructive) {
            confirmDelete = true
        }
        .frame(maxWidth: .infinity, minHeight: LiqianMetrics.minTapTarget)
        .liqianCardSurface(bai: effectiveLedger?.isBai ?? false, padding: LiqianMetrics.spacingSM)
    }

    // MARK: - 自绘金额键盘：卡下固定面板，与卡同语言
    // 面板 surface 底、键面 pageBG＋line 描边、数字 ink、删除 sub；
    // 全表单仅此一处用 line 细线——面板顶边这条，隔开金额区（卡）与键盘。

    private var amountKeypadPanel: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(Palette.line)
                .frame(height: 1)
            amountKeypad
                .padding(.horizontal, LiqianMetrics.spacingM)
                .padding(.top, LiqianMetrics.spacingSM)
                .padding(.bottom, LiqianMetrics.spacingS)
        }
        .background(Palette.surface.ignoresSafeArea(edges: .bottom))
    }

    private var amountKeypad: some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: LiqianMetrics.spacingS), count: 3),
            spacing: LiqianMetrics.spacingS
        ) {
            ForEach(["1", "2", "3", "4", "5", "6", "7", "8", "9"], id: \.self) { k in
                keypadKey(k)
            }
            keypadKey(".")
            keypadKey("0")
            keypadDeleteKey
        }
    }

    private func keypadKey(_ label: String) -> some View {
        Button {
            keypadInput(label)
        } label: {
            Text(label)
                .font(.system(size: 24, weight: .medium))
                .foregroundStyle(Palette.ink)
                .frame(maxWidth: .infinity, minHeight: 56)
                .background(Palette.pageBG, in: RoundedRectangle(cornerRadius: LiqianMetrics.controlCorner))
                .overlay(
                    RoundedRectangle(cornerRadius: LiqianMetrics.controlCorner)
                        .stroke(Palette.line, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    /// 删除键：点按删一位，长按清空
    private var keypadDeleteKey: some View {
        ZStack {
            RoundedRectangle(cornerRadius: LiqianMetrics.controlCorner)
                .fill(Palette.pageBG)
            RoundedRectangle(cornerRadius: LiqianMetrics.controlCorner)
                .stroke(Palette.line, lineWidth: 1)
            Image(systemName: "delete.left")
                .font(.system(size: 22))
                .foregroundStyle(Palette.sub)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 56)
        .contentShape(RoundedRectangle(cornerRadius: LiqianMetrics.controlCorner))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("删除一位，长按清空")
        .accessibilityAddTraits(.isButton)
        .onTapGesture { keypadInput("delete") }
        .onLongPressGesture(minimumDuration: 0.45) { keypadInput("clear") }
    }

    /// 键盘输入走字符串拼接并做合法性约束：
    /// 最多两位小数；首位是 0 时再输数字直接替换（不出现 05、00）；
    /// 整数部分上限 7 位（¥9,999,999），现场记账足够。
    private func keypadInput(_ key: String) {
        switch key {
        case "delete":
            if !amountText.isEmpty { amountText.removeLast() }
        case "clear":
            amountText = ""
        case ".":
            if amountText.contains(".") { return }
            amountText = amountText.isEmpty ? "0." : amountText + "."
        default:
            if let dot = amountText.firstIndex(of: ".") {
                let fracCount = amountText[amountText.index(after: dot)...].count
                if fracCount >= 2 { return }
                amountText += key
            } else if amountText == "0" {
                amountText = key
            } else if amountText.count >= 7 {
                return
            } else {
                amountText += key
            }
        }
        amountError = nil
    }

    private func save() {
        guard !isSaving else { return }
        let name = person.trimmingCharacters(in: .whitespaces)
        personError = name.isEmpty ? "请填写姓名" : nil
        let amountValue = Double(amountText.trimmingCharacters(in: .whitespaces))
        let cents: Int? = amountValue.flatMap { $0 > 0 ? Int(($0 * 100.0).rounded()) : nil }
        amountError = cents == nil ? "请输入正确的金额" : nil
        guard personError == nil, let cents, let lid = effectiveLedgerID else {
            errorTrigger += 1
            return
        }
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
            try? modelContext.save()
            saveTrigger += 1
            dismiss()
        } else {
            modelContext.insert(
                GiftRecord(
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
            )
            try? modelContext.save()
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
        try? modelContext.save()
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
        try? modelContext.save()
        deleteTrigger += 1
        dismiss()
    }
}

/// 金额输入光标：金额面激活时在数字后闪烁的细竖线（品牌色），
/// 提示「现在敲的是金额」——系统键盘收起后唯一的输入焦点信号
private struct AmountCaret: View {
    @State private var visible = true

    var body: some View {
        RoundedRectangle(cornerRadius: 1.5)
            .fill(Palette.primary)
            .frame(width: 3, height: 40)
            .opacity(visible ? 1 : 0)
            .onAppear {
                visible = true
                withAnimation(.easeInOut(duration: 0.55).repeatForever(autoreverses: true)) {
                    visible = false
                }
            }
            .accessibilityHidden(true)
    }
}
