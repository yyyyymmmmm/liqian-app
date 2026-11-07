import SwiftData
import SwiftUI
import LiqianCore
import LiqianDesign

/// 批量补录（FR-02.1）：照着纸质旧礼簿一行行搬进来。
/// 每行只填姓名+金额，关系默认「朋友」、方式默认「现金」、日期默认今天，
/// 记完后可在单笔里再改。随礼按已送出记（补录的都是已经发生的事）。
/// 行校验按 form-design 口径：空行跳过、半截行定位到行号就地报错。
struct BatchEntryView: View {
    let ledger: Ledger
    /// 保存成功回调（笔数），由详情页弹提示
    var onSaved: (Int) -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var direction = LiqianConstants.received
    @State private var rows: [Row] = (0..<4).map { _ in Row() }
    @State private var errorRow: Int?
    @State private var errorMessage: String?
    @State private var saveTrigger = 0
    @State private var errorTrigger = 0

    struct Row: Identifiable {
        let id = UUID()
        var person = ""
        var amount = ""
    }

    private var isBai: Bool { ledger.isBai }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("方向", selection: $direction) {
                        Text("收礼（别人给我）").tag(LiqianConstants.received)
                        Text("随礼（我送出去）").tag(LiqianConstants.given)
                    }
                    .pickerStyle(.segmented)
                    Text("照着旧礼簿一行行填就行。关系先按「朋友」、方式先按「现金」记，日期是今天，记完点开单笔可以再改。")
                        .font(.system(size: 12.5))
                        .foregroundStyle(isBai ? Palette.baiStone : Palette.stone)
                    if errorRow == nil, let errorMessage {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }

                Section {
                    ForEach(rows.indices, id: \.self) { i in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 8) {
                                Text("\(i + 1)")
                                    .foregroundStyle(Palette.stone)
                                    .frame(width: 24)
                                TextField("姓名 / 称呼", text: $rows[i].person)
                                TextField("金额（元）", text: $rows[i].amount, prompt: Text("金额"))
                                    .keyboardType(.decimalPad)
                                    .frame(width: 96)
                                Button(role: .destructive) {
                                    if rows.count > 1 {
                                        rows.remove(at: i)
                                    }
                                } label: {
                                    Image(systemName: "minus.circle")
                                }
                                .buttonStyle(.plain)
                                .disabled(rows.count <= 1)
                            }
                            if errorRow == i, let errorMessage {
                                Text(errorMessage)
                                    .font(.footnote)
                                    .foregroundStyle(.red)
                                    .padding(.leading, 32)
                            }
                        }
                        .frame(minHeight: LiqianMetrics.minTapTarget)
                    }
                    Button {
                        rows.append(Row())
                    } label: {
                        Label("加一行", systemImage: "plus")
                    }
                    .frame(minHeight: LiqianMetrics.minTapTarget)
                }
            }
            .scrollContentBackground(.hidden)
            .background((isBai ? Palette.baiPaper : Palette.paper).ignoresSafeArea())
            .navigationTitle("批量补录")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存全部") { save() }
                        .tint(isBai ? Palette.baiPrimary : Palette.primary)
                }
            }
            .sensoryFeedback(.success, trigger: saveTrigger)
            .sensoryFeedback(.warning, trigger: errorTrigger)
            .sensoryFeedback(.selection, trigger: direction)
        }
    }

    private func save() {
        errorRow = nil
        errorMessage = nil
        var out: [(person: String, cents: Int)] = []
        for i in rows.indices {
            let name = rows[i].person.trimmingCharacters(in: .whitespaces)
            let amtText = rows[i].amount.trimmingCharacters(in: .whitespaces)
            if name.isEmpty && amtText.isEmpty { continue } // 空行跳过
            if name.isEmpty || amtText.isEmpty {
                errorRow = i
                errorMessage = "第 \(i + 1) 行没填完整，姓名和金额都要有"
                errorTrigger += 1
                return
            }
            guard let v = Double(amtText), v > 0 else {
                errorRow = i
                errorMessage = "第 \(i + 1) 行金额不对"
                errorTrigger += 1
                return
            }
            out.append((name, Int((v * 100.0).rounded())))
        }
        if out.isEmpty {
            errorMessage = "一行都没填，先填几笔再保存"
            errorTrigger += 1
            return
        }
        for item in out {
            modelContext.insert(
                GiftRecord(
                    ledgerID: ledger.id,
                    person: item.person,
                    amountCents: item.cents,
                    direction: direction,
                    date: LiqianDate.todayString()
                )
            )
        }
        try? modelContext.save()
        saveTrigger += 1
        onSaved(out.count)
        dismiss()
    }
}
