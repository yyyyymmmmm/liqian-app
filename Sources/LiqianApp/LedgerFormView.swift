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
    @State private var titleError: String?
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
            }
            .scrollContentBackground(.hidden)
            .background(Palette.pageBG.ignoresSafeArea())
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
        } else {
            modelContext.insert(
                Ledger(
                    title: trimmed,
                    type: finalType,
                    date: LiqianDate.string(from: date),
                    note: note.trimmingCharacters(in: .whitespacesAndNewlines)
                )
            )
        }
        try? modelContext.save()
        saveTrigger += 1
        dismiss()
    }
}
