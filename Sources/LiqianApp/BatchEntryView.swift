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

    /// 现场大字模式（办席当天用）：字号与行高放大，持久化记住选择
    @AppStorage("batchBigMode") private var bigMode = false
    @State private var direction = LiqianConstants.received
    @State private var rows: [Row] = (0..<4).map { _ in Row() }
    @State private var errorRow: Int?
    @State private var errorMessage: String?
    @State private var saveTrigger = 0
    @State private var errorTrigger = 0

    // 粘贴导入（v2）：整段文字粘贴 → Core 解析预览 → 成功行入库
    private enum Mode { case rows, paste }
    @State private var mode: Mode = .rows
    @State private var pasteText = ""
    @State private var parsedLines: [ParsedLine]?
    @State private var pasteMessage: String?
    @Query private var allRecords: [GiftRecord]

    /// 本簿已有姓名（粘贴预览里给同名提示，导入仍并列保存）
    private var existingNames: Set<String> {
        Set(allRecords.filter { $0.ledgerID == ledger.id }.map(\.person))
    }

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
                    Picker("录入方式", selection: $mode) {
                        Text("逐个录入").tag(Mode.rows)
                        Text("粘贴导入").tag(Mode.paste)
                    }
                    .pickerStyle(.segmented)
                }

                if mode == .paste {
                    pasteSections
                } else {
                Section {
                    Picker("方向", selection: $direction) {
                        Text("收礼（别人给我）").tag(LiqianConstants.received)
                        Text("随礼（我送出去）").tag(LiqianConstants.given)
                    }
                    .pickerStyle(.segmented)
                    Toggle("现场大字", isOn: $bigMode)
                        .tint(isBai ? Palette.baiPrimary : Palette.primary)
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
                                    .font(bigMode ? .system(size: 20) : nil)
                                TextField("金额（元）", text: $rows[i].amount, prompt: Text("金额"))
                                    .keyboardType(.decimalPad)
                                    .font(bigMode ? .liqianMoney(size: 34) : nil)
                                    .frame(width: bigMode ? 150 : 96)
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
                        .frame(minHeight: bigMode ? 76 : LiqianMetrics.minTapTarget)
                    }
                    Button {
                        rows.append(Row())
                    } label: {
                        Label("加一行", systemImage: "plus")
                    }
                    .frame(minHeight: LiqianMetrics.minTapTarget)
                }
                }
            }
            .scrollContentBackground(.hidden)
            .background((isBai ? Palette.baiPaper : Palette.paper).ignoresSafeArea())
            .safeAreaInset(edge: .top, spacing: 0) {
                liveSummaryBar
            }
            .navigationTitle("批量补录")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if mode == .rows {
                        Button("保存全部") { save() }
                            .tint(isBai ? Palette.baiPrimary : Palette.primary)
                    }
                }
            }
            .sensoryFeedback(.success, trigger: saveTrigger)
            .sensoryFeedback(.warning, trigger: errorTrigger)
            .sensoryFeedback(.selection, trigger: direction)
        }
    }

    /// 实时汇总条（两种录入模式通用）：本簿已记笔数/合计/最近一笔，
    /// 数据走 @Query，刚录进去的立刻算进来
    private var liveSummaryBar: some View {
        let mine = allRecords.filter { $0.ledgerID == ledger.id }
        let total = mine.reduce(0) { $0 + $1.amountCents }
        return HStack(spacing: 6) {
            Text("本簿已记 \(mine.count) 笔 · 合计 \(LedgerMath.fmtMoney(cents: total))")
            if let latest = mine.last {
                Text("· 最近：\(latest.person) \(LedgerMath.fmtMoney(cents: latest.amountCents))")
                    .lineLimit(1)
            }
            Spacer()
        }
        .font(.system(size: 13))
        .foregroundStyle(isBai ? Palette.baiStone : Palette.stone)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isBai ? Palette.baiPaper : Palette.paper)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(isBai ? Palette.baiLine : Palette.hairline)
                .frame(height: 1)
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

    // MARK: - 粘贴导入

    @ViewBuilder
    private var pasteSections: some View {
        Section {
            Text("把旧礼簿的文字整段粘进来，一行一笔：「姓名 金额 关系」，关系可不写。粘贴导入一律按收礼记（别人给我），关系没写先按「朋友」、方式「现金」、日期今天，记完点开单笔可以再改。")
                .font(.system(size: 12.5))
                .foregroundStyle(isBai ? Palette.baiStone : Palette.stone)
            TextEditor(text: $pasteText)
                .frame(minHeight: 140)
            Button {
                parsedLines = LedgerTextParser.parse(pasteText)
                pasteMessage = nil
            } label: {
                Label("解析预览", systemImage: "text.magnifyingglass")
            }
            .frame(minHeight: LiqianMetrics.minTapTarget)
            if let pasteMessage {
                Text(pasteMessage)
                    .font(.footnote)
                    .foregroundStyle(Palette.stone)
            }
        }

        if let parsedLines {
            Section {
                ForEach(parsedLines) { line in
                    parsedRow(line)
                }
                if parsedLines.contains(where: { $0.isSuccess }) {
                    Button {
                        confirmImport()
                    } label: {
                        Label(
                            "确认导入 \(parsedLines.filter { $0.isSuccess }.count) 笔",
                            systemImage: "checkmark.circle"
                        )
                    }
                    .frame(minHeight: LiqianMetrics.minTapTarget)
                }
            } header: {
                Text("解析预览")
            }
        }
    }

    @ViewBuilder
    private func parsedRow(_ line: ParsedLine) -> some View {
        switch line.result {
        case .success(let name, let cents, let relation):
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(name) · \(LedgerMath.fmtMoney(cents: cents))" + (relation.map { " · \($0)" } ?? ""))
                        .font(bigMode ? .system(size: 17) : nil)
                        .foregroundStyle(Palette.ink)
                    if existingNames.contains(name) {
                        Text("本簿已有此人，导入后并列保存")
                            .font(.system(size: 12))
                            .foregroundStyle(.orange)
                    }
                }
                Spacer()
                Text("第 \(line.lineNo) 行")
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.stone)
            }
        case .failure(let reason):
            HStack(spacing: 8) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.red)
                VStack(alignment: .leading, spacing: 2) {
                    Text(line.raw)
                        .foregroundStyle(Palette.ink)
                    Text(reason)
                        .font(.system(size: 12))
                        .foregroundStyle(.red)
                }
                Spacer()
                Text("第 \(line.lineNo) 行")
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.stone)
            }
        }
    }

    private func confirmImport() {
        guard let parsedLines else { return }
        var imported = 0
        var failedRaws: [String] = []
        for line in parsedLines {
            switch line.result {
            case .success(let name, let cents, let relation):
                modelContext.insert(
                    GiftRecord(
                        ledgerID: ledger.id,
                        person: name,
                        relation: relation ?? "朋友",
                        amountCents: cents,
                        direction: LiqianConstants.received,
                        date: LiqianDate.todayString()
                    )
                )
                imported += 1
            case .failure:
                failedRaws.append(line.raw)
            }
        }
        guard imported > 0 else { return }
        try? modelContext.save()
        saveTrigger += 1
        if failedRaws.isEmpty {
            onSaved(imported)
            dismiss()
        } else {
            // 失败行留在编辑器里，改好再导；已导入的笔数当面说清
            pasteText = failedRaws.joined(separator: "\n")
            self.parsedLines = nil
            pasteMessage = "已导入 \(imported) 笔，剩下 \(failedRaws.count) 行没成功，改好后重新解析导入。"
        }
    }
}
