import SwiftData
import SwiftUI
import LiqianCore
import LiqianDesign

/// 新建 / 编辑礼簿（共用）。标题必填，错误就地红字提示。
struct LedgerFormView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let existing: Ledger?

    @State private var title: String
    @State private var type: String
    @State private var date: Date
    @State private var note: String
    @State private var titleError: String?
    @State private var saveTrigger = 0
    @State private var errorTrigger = 0

    init(existing: Ledger? = nil) {
        self.existing = existing
        _title = State(initialValue: existing?.title ?? "")
        _type = State(initialValue: existing?.type ?? LiqianConstants.ledgerTypes[0])
        _date = State(initialValue: existing.map { LiqianDate.date(from: $0.date) } ?? Date())
        _note = State(initialValue: existing?.note ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("礼簿名称", text: $title, prompt: Text("如：我的婚礼 / 爸爸六十大寿"))
                    if let titleError {
                        Text(titleError)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }
                Section {
                    Picker("事由", selection: $type) {
                        ForEach(LiqianConstants.ledgerTypes, id: \.self) { t in
                            Text(t).tag(t)
                        }
                    }
                    DatePicker("日期", selection: $date, displayedComponents: .date)
                    TextField("备注（可选）", text: $note)
                }
            }
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
            titleError = "先给礼簿起个名，如「我的婚礼」"
            errorTrigger += 1
            return
        }
        titleError = nil
        if let existing {
            existing.title = trimmed
            existing.type = type
            existing.date = LiqianDate.string(from: date)
            existing.note = note.trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            modelContext.insert(
                Ledger(
                    title: trimmed,
                    type: type,
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
