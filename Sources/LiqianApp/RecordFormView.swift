import SwiftData
import SwiftUI
import LiqianCore
import LiqianDesign

/// 记一笔 / 编辑记录。
/// 三种入口：从账本（账本固定）、从人物（账本 Picker 选、姓名预填）、编辑（全部预填）。
/// 字段顺序按现场登记的自然顺序：方向 → 姓名 → 金额 → 关系/方式 → 日期 → 备注。
/// 只问必需：姓名/金额必填，其余有默认值；错误就地红字提示，不只靠点了没反应。
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
    @FocusState private var focus: Field?

    enum Field { case person, amount }

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

    /// 同人提示：这个名字在本账本已有的笔数（编辑时不算自己这笔）
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
                if needsLedgerPicker {
                    Section {
                        if allLedgers.isEmpty {
                            Text("先建一本礼簿，再来记账。")
                                .foregroundStyle(Palette.stone)
                        } else {
                            Picker("账本", selection: $selectedLedgerID) {
                                ForEach(allLedgers) { l in
                                    Text(l.title).tag(l.id as UUID?)
                                }
                            }
                        }
                    }
                } else if let l = effectiveLedger {
                    Section {
                        LabeledContent("账本", value: l.title)
                    }
                }

                Section {
                    Picker("方向", selection: $direction) {
                        Text("收礼（别人给我）").tag(LiqianConstants.received)
                        Text("随礼（我送出去）").tag(LiqianConstants.given)
                    }
                    .pickerStyle(.segmented)
                    if direction == LiqianConstants.given {
                        Picker("状态", selection: $status) {
                            Text("已送出").tag(LiqianConstants.sentStatus)
                            Text("待送出（先记着）").tag(LiqianConstants.pendingStatus)
                        }
                        .pickerStyle(.segmented)
                        if status == LiqianConstants.pendingStatus {
                            Text("待送出的先记着，不算进往来差额，送出去后改成「已送出」。")
                                .font(.system(size: 12.5))
                                .foregroundStyle(Palette.stone)
                        }
                    }
                }

                Section {
                    TextField("姓名 / 称呼", text: $person, prompt: Text("如：大舅、二姨、张三"))
                        .focused($focus, equals: .person)
                    if let personError {
                        Text(personError)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                    ForEach(suggestions) { p in
                        Button {
                            person = p.name
                            if LiqianConstants.relations.contains(p.relation) {
                                relation = p.relation
                            }
                        } label: {
                            HStack {
                                Text(p.name)
                                    .foregroundStyle(Palette.ink)
                                Spacer()
                                Text("\(p.relation) · 共 \(p.count) 笔往来")
                                    .font(.system(size: 12.5))
                                    .foregroundStyle(Palette.stone)
                            }
                            .frame(minHeight: LiqianMetrics.minTapTarget)
                        }
                        .buttonStyle(.plain)
                    }
                    if sameLedgerCount > 0 {
                        Text("此人在本账本已有 \(sameLedgerCount) 笔，再记一笔会并列保存。")
                            .font(.system(size: 12.5))
                            .foregroundStyle(Palette.stone)
                    }
                }

                Section {
                    amountDisplay
                    amountChips
                    amountKeypad
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    if let amountError {
                        Text(amountError)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                } header: {
                    Text("金额（元）")
                }

                Section {
                    Picker("关系", selection: $relation) {
                        ForEach(LiqianConstants.relations, id: \.self) { r in
                            Text(r).tag(r)
                        }
                    }
                    Picker("方式", selection: $method) {
                        ForEach(LiqianConstants.methods, id: \.self) { m in
                            Text(m).tag(m)
                        }
                    }
                    DatePicker("日期", selection: $date, displayedComponents: .date)
                    TextField("备注（可选）", text: $note, prompt: Text("实物礼写这里，如：两瓶酒"))
                }

                if existing == nil {
                    Section {
                        Toggle("保存并继续记", isOn: $saveAndContinue)
                        if let savedMessage {
                            Text(savedMessage)
                                .font(.footnote)
                                .foregroundStyle(Palette.stone)
                        }
                    }
                }

                if existing != nil {
                    Section {
                        Button("删除这笔", role: .destructive) {
                            confirmDelete = true
                        }
                        .frame(minHeight: LiqianMetrics.minTapTarget)
                    }
                }
            }
            .navigationTitle(existing == nil ? "记一笔" : "编辑记录")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                }
            }
            .overlay {
                SealStampOverlay(
                    char: sealText,
                    bai: effectiveLedger?.isBai ?? false,
                    presented: showSeal
                )
            }
            .sensoryFeedback(.impact(weight: .light, intensity: 0.5), trigger: amountText)
            .sensoryFeedback(.impact(weight: .medium), trigger: sealTrigger)
            .sensoryFeedback(.success, trigger: saveTrigger)
            .sensoryFeedback(.warning, trigger: errorTrigger)
            .sensoryFeedback(.warning, trigger: deleteTrigger)
            .sensoryFeedback(.selection, trigger: direction)
            .sensoryFeedback(.selection, trigger: status)
            .confirmationDialog("删除这笔记录？", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("删除", role: .destructive) { deleteExisting() }
                Button("取消", role: .cancel) {}
            } message: {
                Text("删除后 30 天内可以在「我的 → 回收站」恢复。")
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

    // MARK: - 金额区：大号显示 + 常用金额 + 自定义大字键盘（三秒记账，不用系统键盘）

    private var amountDisplay: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text("¥")
                .font(.liqianSerif(size: 26))
                .foregroundStyle(Palette.stone)
            Text(amountText.isEmpty ? "0" : amountText)
                .font(.liqianMoney(size: 40))
                .foregroundStyle(amountText.isEmpty ? Palette.stone : Palette.ink)
                .contentTransition(.numericText())
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Spacer()
        }
        .padding(.vertical, 4)
    }

    private var amountChips: some View {
        HStack(spacing: 8) {
            ForEach([100, 200, 300, 500, 800, 1000], id: \.self) { v in
                Button {
                    amountText = "\(v)"
                    amountError = nil
                } label: {
                    Text("\(v)")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Palette.primary)
                        .frame(maxWidth: .infinity, minHeight: LiqianMetrics.minTapTarget)
                        .background(Palette.primaryTint, in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var amountKeypad: some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3),
            spacing: 8
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
                .background(Palette.card, in: RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Palette.hairline, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    /// 删除键：点按删一位，长按清空
    private var keypadDeleteKey: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(Palette.card)
            RoundedRectangle(cornerRadius: 12)
                .stroke(Palette.hairline, lineWidth: 1)
            Image(systemName: "delete.left")
                .font(.system(size: 22))
                .foregroundStyle(Palette.ink)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 56)
        .contentShape(RoundedRectangle(cornerRadius: 12))
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
        let name = person.trimmingCharacters(in: .whitespaces)
        personError = name.isEmpty ? "姓名还没填" : nil
        let amountValue = Double(amountText.trimmingCharacters(in: .whitespaces))
        let cents: Int? = amountValue.flatMap { $0 > 0 ? Int(($0 * 100.0).rounded()) : nil }
        amountError = cents == nil ? "金额不对，检查一下" : nil
        guard personError == nil, let cents, let lid = effectiveLedgerID else {
            errorTrigger += 1
            return
        }
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
            sealText = effectiveLedger.map { String($0.title.prefix(1)) } ?? "礼"
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
                }
            } else {
                Task {
                    try? await Task.sleep(for: .milliseconds(1050))
                    dismiss()
                }
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
