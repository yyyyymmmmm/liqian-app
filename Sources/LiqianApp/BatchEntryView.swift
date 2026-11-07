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
    private enum Mode { case rows, paste, ai }
    @State private var mode: Mode = .rows
    @State private var pasteText = ""
    @State private var parsedLines: [ParsedLine]?
    @State private var pasteMessage: String?

    // AI 解析（v2）：杂乱文本发 DeepSeek → JSON → 本地校验 → 同一套预览/导入
    @State private var aiText = ""
    @State private var aiLines: [AIPreviewLine]?
    @State private var aiUncertain: [Int] = []
    @State private var aiParsing = false
    @State private var aiError: String?
    @State private var aiRawResponse: String?
    @State private var aiMessage: String?
    @State private var showAIGuide = false

    /// AI 预览行：ok 可导入；givenBlocked 是随礼行（本页粘贴通道只入收礼，先标出）；
    /// failed 是本地校验没过的（姓名空/金额不对），不静默吞
    private struct AIPreviewLine: Identifiable {
        enum Status {
            case ok(name: String, cents: Int, relation: String?, method: String?)
            case givenBlocked(name: String, cents: Int)
            case failed(reason: String)
        }
        var lineNo: Int
        var status: Status
        var id: Int { lineNo }
    }
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
                        Text("AI 解析").tag(Mode.ai)
                    }
                    .pickerStyle(.segmented)
                }

                if mode == .paste {
                    pasteSections
                } else if mode == .ai {
                    aiSections
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
            .alert("AI 还没准备好", isPresented: $showAIGuide) {
                Button("好") {}
            } message: {
                Text(AIAccess.readiness().guideMessage)
            }
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

    // MARK: - AI 解析

    @ViewBuilder
    private var aiSections: some View {
        Section {
            Text("微信接龙、备忘录流水这种格式乱的文字，粘进来让 AI 读。将把这段文字发送至 DeepSeek 解析，解析结果先进预览，你确认了才入库；金额是本地换算校验的。解析不了或不想发，左边「粘贴导入」是本地规则解析，不出这台手机。")
                .font(.system(size: 12.5))
                .foregroundStyle(isBai ? Palette.baiStone : Palette.stone)
            TextEditor(text: $aiText)
                .frame(minHeight: 140)
            Button {
                Task { await runAIParse() }
            } label: {
                HStack {
                    Label("开始解析", systemImage: "sparkles")
                    if aiParsing {
                        Spacer()
                        ProgressView()
                    }
                }
            }
            .frame(minHeight: LiqianMetrics.minTapTarget)
            .disabled(aiParsing || aiText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            if let aiError {
                Text(aiError)
                    .font(.footnote)
                    .foregroundStyle(.red)
                if let aiRawResponse {
                    DisclosureGroup("查看原始返回（报障用）") {
                        Text(aiRawResponse)
                            .font(.system(size: 11))
                            .foregroundStyle(Palette.stone)
                            .textSelection(.enabled)
                    }
                }
            }
            if let aiMessage {
                Text(aiMessage)
                    .font(.footnote)
                    .foregroundStyle(Palette.stone)
            }
        }

        if let aiLines {
            Section {
                if aiLines.isEmpty {
                    Text("没解析出记录，换段文字试试，或者用「粘贴导入」的规则解析。")
                        .foregroundStyle(Palette.stone)
                } else {
                    ForEach(aiLines) { line in
                        aiParsedRow(line)
                    }
                    let okCount = aiLines.filter {
                        if case .ok = $0.status { return true }
                        return false
                    }.count
                    if okCount > 0 {
                        Button {
                            confirmAIImport()
                        } label: {
                            Label("确认导入 \(okCount) 笔", systemImage: "checkmark.circle")
                        }
                        .frame(minHeight: LiqianMetrics.minTapTarget)
                    }
                }
                if !aiUncertain.isEmpty {
                    Text("第 \(aiUncertain.map(String.init).joined(separator: "、")) 行 AI 拿不准，没有列进来，请用逐个录入补上。")
                        .font(.system(size: 12.5))
                        .foregroundStyle(.orange)
                }
            } header: {
                Text("解析预览")
            }
        }
    }

    @ViewBuilder
    private func aiParsedRow(_ line: AIPreviewLine) -> some View {
        switch line.status {
        case .ok(let name, let cents, let relation, let method):
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text("\(name) · \(LedgerMath.fmtMoney(cents: cents))" + (relation.map { " · \($0)" } ?? "") + (method.map { " · \($0)" } ?? ""))
                            .font(bigMode ? .system(size: 17) : nil)
                            .foregroundStyle(Palette.ink)
                        aiBadge
                    }
                    if existingNames.contains(name) {
                        Text("本簿已有此人，导入后并列保存")
                            .font(.system(size: 12))
                            .foregroundStyle(.orange)
                    }
                }
                Spacer()
            }
        case .givenBlocked(let name, let cents):
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.circle.fill")
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text("\(name) · \(LedgerMath.fmtMoney(cents: cents)) · 随礼")
                            .foregroundStyle(Palette.ink)
                        aiBadge
                    }
                    Text("随礼行暂不支持在这里导入，请用逐个录入记这一笔")
                        .font(.system(size: 12))
                        .foregroundStyle(.orange)
                }
                Spacer()
            }
        case .failed(let reason):
            HStack(spacing: 8) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.red)
                Text(reason)
                    .font(.system(size: 13))
                    .foregroundStyle(.red)
                Spacer()
                aiBadge
            }
        }
    }

    private var aiBadge: some View {
        Text("AI")
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(Palette.primary)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(Palette.primaryTint, in: Capsule())
    }

    private struct AIResponse: Decodable {
        struct Rec: Decodable {
            var name: String
            var amountYuan: Double
            var relation: String?
            var method: String?
            var direction: String?
        }
        var records: [Rec]
        var uncertain: [Int]?
    }

    private static let aiSystemPrompt = """
        你是礼钱账本的解析助手。用户会给你一段中文人情往来记录文本（可能来自微信接龙、备忘录，格式杂乱，一行未必只有一笔）。请提取每一笔记录，只输出一个 JSON 对象，不要输出任何其他文字：{"records":[{"name":"","amountYuan":数字,"relation":null,"method":null,"direction":"received"}],"uncertain":[]}
        规则：1) name 姓名照抄原文，绝不猜测或改名；2) amountYuan 是金额数字，单位元，中文数字要换算（如「五百」=500）；3) direction：别人送给记账人是 "received"，记账人送出去是 "given"，看不出给 "received"；4) relation 只能是 亲戚/朋友/同事/同学/邻居/其他 之一，看不出给 null；5) method 只能是 现金/微信/支付宝/银行转账/实物 之一，看不出给 null；6) 拿不准是哪一笔、或金额读不出的，把原文行号（从 1 起）放进 uncertain，不要编造记录凑数。
        """

    private func runAIParse() async {
        switch AIAccess.readiness() {
        case .ready:
            break
        case .noKey, .notEnabled:
            showAIGuide = true
            return
        }
        aiParsing = true
        aiError = nil
        aiRawResponse = nil
        aiMessage = nil
        do {
            let client = try DeepSeekClient()
            let data = try await client.chatJSON(system: Self.aiSystemPrompt, user: aiText)
            aiParsing = false
            do {
                let response = try JSONDecoder().decode(AIResponse.self, from: data)
                aiUncertain = response.uncertain ?? []
                aiLines = response.records.enumerated().map { index, rec in
                    let name = rec.name.trimmingCharacters(in: .whitespaces)
                    let cents = Int((rec.amountYuan * 100.0).rounded())
                    guard !name.isEmpty, rec.amountYuan > 0 else {
                        return AIPreviewLine(
                            lineNo: index + 1,
                            status: .failed(reason: "第 \(index + 1) 条没读出姓名或金额，没列进来")
                        )
                    }
                    if rec.direction == "given" {
                        return AIPreviewLine(lineNo: index + 1, status: .givenBlocked(name: name, cents: cents))
                    }
                    return AIPreviewLine(
                        lineNo: index + 1,
                        status: .ok(
                            name: name,
                            cents: cents,
                            relation: rec.relation.flatMap { LiqianConstants.relations.contains($0) ? $0 : nil },
                            method: rec.method.flatMap { LiqianConstants.methods.contains($0) ? $0 : nil }
                        )
                    )
                }
            } catch {
                aiError = "AI 返回的格式不对，没能解析。可以再试一次，或改用「粘贴导入」的规则解析。"
                let raw = String(data: data, encoding: .utf8) ?? ""
                aiRawResponse = String(raw.prefix(500))
            }
        } catch let error as DeepSeekError {
            aiParsing = false
            aiError = (error.errorDescription ?? "解析失败") + " 也可以改用「粘贴导入」的规则解析。"
        } catch {
            aiParsing = false
            aiError = "解析失败：\(error.localizedDescription)。也可以改用「粘贴导入」的规则解析。"
        }
    }

    private func confirmAIImport() {
        guard let aiLines else { return }
        var imported = 0
        var remaining: [AIPreviewLine] = []
        for line in aiLines {
            switch line.status {
            case .ok(let name, let cents, let relation, let method):
                modelContext.insert(
                    GiftRecord(
                        ledgerID: ledger.id,
                        person: name,
                        relation: relation ?? "朋友",
                        amountCents: cents,
                        direction: LiqianConstants.received,
                        method: method ?? "现金",
                        date: LiqianDate.todayString()
                    )
                )
                imported += 1
            case .givenBlocked, .failed:
                remaining.append(line)
            }
        }
        guard imported > 0 else { return }
        try? modelContext.save()
        saveTrigger += 1
        if remaining.isEmpty {
            onSaved(imported)
            dismiss()
        } else {
            self.aiLines = remaining
            aiMessage = "已导入 \(imported) 笔收礼；剩下 \(remaining.count) 行没导入（随礼行或没读全的行），按行上的提示处理。"
        }
    }
}
