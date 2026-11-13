import SwiftData
import SwiftUI
import LiqianCore
import LiqianDesign

/// 新建 / 编辑礼簿（共用）。标题必填，错误就地红字提示。
struct LedgerFormView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let existing: Ledger?

    /// 事由 Picker 里的「自定义」选项值（预置事由之外的自填事由）
    private static let customTypeOption = "自定义"

    @State private var title: String
    @State private var type: String
    @State private var customType: String
    @State private var date: Date
    @State private var note: String
    // 礼谱信息（v2.10：礼簿自身属性，导出时直接读礼簿，不在导出 sheet 里填）
    @State private var hostName: String
    @State private var scribe: String
    @State private var verifier: String
    @State private var location: String
    @State private var titleError: String?
    /// 保存落库失败的显形文案（v5.14.1）：save 不再静默，失败留在
    /// 表单里明说、内容不丢（见 SaveSupport）
    @State private var saveError: String?
    @State private var saveTrigger = 0
    @State private var errorTrigger = 0

    init(existing: Ledger? = nil) {
        self.existing = existing
        _title = State(initialValue: existing?.title ?? "")
        // 已有礼簿若用的是预置外的事由（历史自定义），进表单时落到「自定义」并把原值带入输入框
        let existingIsCustom = existing.map { !LiqianConstants.ledgerTypes.contains($0.type) } ?? false
        _type = State(
            initialValue: existingIsCustom
                ? Self.customTypeOption
                : (existing?.type ?? LiqianConstants.ledgerTypes[0])
        )
        _customType = State(initialValue: existingIsCustom ? (existing?.type ?? "") : "")
        _date = State(initialValue: existing.map { LiqianDate.date(from: $0.date) } ?? Date())
        _note = State(initialValue: existing?.note ?? "")
        // 主家：编辑用礼簿自带值；新建时以全局「礼谱落款姓名」设置预填（可在表单里改）
        _hostName = State(
            initialValue: existing?.hostName
                ?? (existing == nil ? (UserDefaults.standard.string(forKey: "hostName") ?? "") : "")
        )
        _scribe = State(initialValue: existing?.scribe ?? "")
        _verifier = State(initialValue: existing?.verifier ?? "")
        _location = State(initialValue: existing?.location ?? "")
    }

    /// 实际保存的事由：选了「自定义」就用输入值，没填则回退「其他」
    private var finalType: String {
        guard type == Self.customTypeOption else { return type }
        let trimmed = customType.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "其他" : trimmed
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    // 名称行（v2.4 原生化）：行首标签＋输入框，与系统表单一致，
                    // 不再是无标签的胶囊输入（标签不用占位符代替，ux-writing 口径）
                    HStack(spacing: LiqianMetrics.spacingSM) {
                        Text("名称")
                            .foregroundStyle(Palette.ink)
                        TextField("名称", text: $title, prompt: Text("如：我的婚礼 / 爸爸六十大寿"))
                    }
                    if let titleError {
                        Text(titleError)
                            .font(.footnote)
                            .foregroundStyle(Palette.danger)
                    }
                    if let saveError {
                        Text(saveError)
                            .font(.footnote)
                            .foregroundStyle(Palette.danger)
                    }
                }
                Section {
                    Picker("事由", selection: $type) {
                        ForEach(LiqianConstants.ledgerTypes + [Self.customTypeOption], id: \.self) { t in
                            Text(t).tag(t)
                        }
                    }
                    if type == Self.customTypeOption {
                        TextField("事由名称", text: $customType, prompt: Text("如：店铺开业 / 孩子升学"))
                    }
                    DatePicker("日期", selection: $date, displayedComponents: .date)
                    HStack(spacing: LiqianMetrics.spacingSM) {
                        Text("备注")
                            .foregroundStyle(Palette.ink)
                        TextField("备注", text: $note, prompt: Text("选填"))
                    }
                }
                // 礼谱信息（v2.10）：导出礼谱时直接读这本礼簿的属性——
                // 主家落款与印、书记/核实人落款、举办地点入封面与谱序。皆选填。
                Section {
                    libuField("主家", text: $hostName, prompt: "如：杨敏杰")
                    libuField("书记", text: $scribe, prompt: "记账人姓名，选填")
                    libuField("核实人", text: $verifier, prompt: "选填")
                    libuField("举办地点", text: $location, prompt: "如：西故现村，选填")
                } header: {
                    Text("礼谱信息")
                } footer: {
                    Text("导出礼谱时用：主家落款钤印，书记、核实人列在汇总页落款处，地点写进封面与谱序。")
                }
            }
            .scrollContentBackground(.hidden)
            .background(Palette.pageBG.ignoresSafeArea())
            // 滚动交互式收起键盘（v4.4），与记一笔同口径
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(existing == nil ? "新建礼簿" : "编辑礼簿")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                }
            }
            .sensoryFeedback(.success, trigger: saveTrigger)
            .sensoryFeedback(.warning, trigger: errorTrigger)
        }
    }

    /// 礼谱信息行：与本表单一致的行首标签样式
    private func libuField(_ label: String, text: Binding<String>, prompt: String) -> some View {
        HStack(spacing: LiqianMetrics.spacingSM) {
            Text(label)
                .foregroundStyle(Palette.ink)
            TextField(label, text: text, prompt: Text(prompt))
        }
    }

    /// 礼谱属性存法：去首尾空白，空串存 nil（未设）
    private func nilIfEmpty(_ s: String) -> String? {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }

    private func save() {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            titleError = "请填写礼簿名称，如「我的婚礼」"
            errorTrigger += 1
            return
        }
        titleError = nil
        if let existing {
            existing.title = trimmed
            existing.type = finalType
            existing.date = LiqianDate.string(from: date)
            existing.note = note.trimmingCharacters(in: .whitespacesAndNewlines)
            existing.hostName = nilIfEmpty(hostName)
            existing.scribe = nilIfEmpty(scribe)
            existing.verifier = nilIfEmpty(verifier)
            existing.location = nilIfEmpty(location)
        } else {
            modelContext.insert(
                Ledger(
                    title: trimmed,
                    type: finalType,
                    date: LiqianDate.string(from: date),
                    note: note.trimmingCharacters(in: .whitespacesAndNewlines),
                    hostName: nilIfEmpty(hostName),
                    scribe: nilIfEmpty(scribe),
                    verifier: nilIfEmpty(verifier),
                    location: nilIfEmpty(location)
                )
            )
        }
        // v5.14.1：保存失败必须显形——不关表单、内容原样保留可重试
        //（审计 A5：旧 try? 静默吞失败是「建了簿再打开没有」的成立路径）
        guard SaveSupport.attempt(modelContext, onFailure: { saveError = $0 }) else {
            errorTrigger += 1
            return
        }
        saveError = nil
        saveTrigger += 1
        dismiss()
    }
}
