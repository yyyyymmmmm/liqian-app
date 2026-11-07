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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// 大字模式（办席当天用）：字号与行高放大，持久化记住选择
    @AppStorage("batchBigMode") private var bigMode = false
    @State private var direction = LiqianConstants.received
    @State private var rows: [Row] = (0..<4).map { _ in Row() }
    @State private var errorRow: Int?
    @State private var errorMessage: String?
    @State private var saveTrigger = 0
    @State private var errorTrigger = 0

    // 拍照识别（v2.9）：本页顶部入口，与详情「更多」打开同一个识别 flow
    @State private var showPhotoOCR = false
    @State private var ocrMessage: String?

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

    /// 本礼簿已有姓名（粘贴预览里给同名提示，导入仍并列保存）
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
                // 拍照识别入口置顶（v2.9）：纸质礼单一拍导入，与下方三种录入方式并列；
                // 大字模式下入口字号同步放大（现场登记场景一致）
                Section {
                    Button {
                        showPhotoOCR = true
                    } label: {
                        Label("拍照识别礼单", systemImage: "camera.viewfinder")
                            .font(bigMode ? .system(size: 20) : nil)
                    }
                    .frame(minHeight: LiqianMetrics.minTapTarget)
                    Text("纸质礼单拍一张，自动认出姓名和金额，核对后导入（按收礼记）。")
                        .font(.footnote)
                        .foregroundStyle(isBai ? Palette.baiStone : Palette.stone)
                    if let ocrMessage {
                        Text(ocrMessage)
                            .font(.footnote)
                            .foregroundStyle(Palette.stone)
                    }
                }

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
                        Text("收礼").tag(LiqianConstants.received)
                        Text("随礼").tag(LiqianConstants.given)
                    }
                    .pickerStyle(.segmented)
                    Toggle("大字模式", isOn: $bigMode)
                        .tint(isBai ? Palette.baiPrimary : Palette.primary)
                    Text("按旧礼簿逐行填写。关系默认「朋友」、方式默认「现金」、日期为今天，保存后可逐笔修改。")
                        .font(.footnote)
                        .foregroundStyle(isBai ? Palette.baiStone : Palette.stone)
                    if errorRow == nil, let errorMessage {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(Palette.danger)
                    }
                }

                Section {
                    ForEach(rows.indices, id: \.self) { i in
                        VStack(alignment: .leading, spacing: LiqianMetrics.spacingXS) {
                            HStack(spacing: LiqianMetrics.spacingS) {
                                Text("\(i + 1)")
                                    .foregroundStyle(Palette.stone)
                                    .frame(width: 24)
                                TextField("姓名 / 称呼", text: $rows[i].person)
                                    .font(bigMode ? .system(size: 20) : nil)
                                TextField("金额（元）", text: $rows[i].amount, prompt: Text("金额"))
                                    .keyboardType(.decimalPad)
                                    .font(bigMode ? .system(size: 34, weight: .semibold).monospacedDigit() : nil)
                                    .frame(width: bigMode ? 150 : 96)
                                Button(role: .destructive) {
                                    if rows.count > 1 {
                                        rows.remove(at: i)
                                    }
                                } label: {
                                    Image(systemName: "minus.circle")
                                }
                                .accessibilityLabel("删除这一行")
                                .buttonStyle(.plain)
                                .disabled(rows.count <= 1)
                            }
                            if errorRow == i, let errorMessage {
                                Text(errorMessage)
                                    .font(.footnote)
                                    .foregroundStyle(Palette.danger)
                                    .padding(.leading, LiqianMetrics.spacingXL)
                            }
                        }
                        .frame(minHeight: bigMode ? 76 : LiqianMetrics.minTapTarget)
                    }
                    Button {
                        rows.append(Row())
                    } label: {
                        Label("添加一行", systemImage: "plus")
                    }
                    .frame(minHeight: LiqianMetrics.minTapTarget)
                }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Palette.groupedBackground.ignoresSafeArea())
            // 滚动交互式收起键盘（v4.4）；逐行增删平滑过渡（以行数为值）
            .scrollDismissesKeyboard(.interactively)
            .animation(reduceMotion ? nil : .snappy, value: rows.count)
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
                Button("去设置") {
                    NotificationCenter.default.post(name: .liqianOpenAISettings, object: nil)
                }
                Button("好", role: .cancel) {}
            } message: {
                Text(AIAccess.readiness().guideMessage)
            }
            .sheet(isPresented: $showPhotoOCR) {
                PhotoOCRView(ledger: ledger) { n in
                    ocrMessage = "已通过拍照识别导入 \(n) 笔收礼。"
                }
            }
        }
    }

    /// 实时汇总条（两种录入模式通用）：本礼簿已记笔数/合计/最近一笔，
    /// 数据走 @Query，刚录进去的立刻算进来
    private var liveSummaryBar: some View {
        let mine = allRecords.filter { $0.ledgerID == ledger.id }
        // 分方向合计：待送出不计入随礼（与全 App 口径一致，F7）
        let receivedTotal = mine
            .filter { $0.direction == LiqianConstants.received }
            .reduce(0) { $0 + $1.amountCents }
        let givenTotal = mine
            .filter { $0.direction == LiqianConstants.given && !$0.isPendingSend }
            .reduce(0) { $0 + $1.amountCents }
        return HStack(spacing: LiqianMetrics.spacingS) {
            Text("已记 \(mine.count) 笔 · 收礼 \(LedgerMath.fmtMoney(cents: receivedTotal)) · 随礼 \(LedgerMath.fmtMoney(cents: givenTotal))")
            if let latest = mine.max(by: { $0.date < $1.date }) {
                Text("· 最近一笔（按日期）：\(latest.person) \(LedgerMath.fmtMoney(cents: latest.amountCents))")
                    .lineLimit(1)
            }
            Spacer()
        }
        .font(.footnote)
        .foregroundStyle(isBai ? Palette.baiStone : Palette.stone)
        .padding(.horizontal, LiqianMetrics.spacingM)
        .padding(.vertical, LiqianMetrics.spacingS)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.groupedBackground)
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
                errorMessage = "第 \(i + 1) 行金额格式不正确"
                errorTrigger += 1
                return
            }
            out.append((name, Int((v * 100.0).rounded())))
        }
        if out.isEmpty {
            errorMessage = "尚未填写任何记录"
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
                .font(.footnote)
                .foregroundStyle(isBai ? Palette.baiStone : Palette.stone)
            TextEditor(text: $pasteText)
                .font(bigMode ? .system(size: 20) : nil)
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
        parsedRowContent(line)
            .font(bigMode ? .system(size: 17) : nil)
    }

    @ViewBuilder
    private func parsedRowContent(_ line: ParsedLine) -> some View {
        switch line.result {
        case .success(let name, let cents, let relation):
            HStack(spacing: LiqianMetrics.spacingS) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Palette.success)
                VStack(alignment: .leading, spacing: LiqianMetrics.spacingXS) {
                    Text("\(name) · \(LedgerMath.fmtMoney(cents: cents))" + (relation.map { " · \($0)" } ?? ""))
                        .font(bigMode ? .system(size: 17) : nil)
                        .foregroundStyle(Palette.ink)
                    if existingNames.contains(name) {
                        Text("本礼簿已有同名记录，导入后将并列保存")
                            .font(.footnote)
                            .foregroundStyle(Palette.warning)
                    }
                }
                Spacer()
                Text("第 \(line.lineNo) 行")
                    .font(.footnote)
                    .foregroundStyle(Palette.stone)
            }
        case .failure(let reason):
            HStack(spacing: LiqianMetrics.spacingS) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(Palette.danger)
                VStack(alignment: .leading, spacing: LiqianMetrics.spacingXS) {
                    Text(line.raw)
                        .foregroundStyle(Palette.ink)
                    Text(reason)
                        .font(.footnote)
                        .foregroundStyle(Palette.danger)
                }
                Spacer()
                Text("第 \(line.lineNo) 行")
                    .font(.footnote)
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
                .font(.footnote)
                .foregroundStyle(isBai ? Palette.baiStone : Palette.stone)
            TextEditor(text: $aiText)
                .font(bigMode ? .system(size: 20) : nil)
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
                    .foregroundStyle(Palette.danger)
                if let aiRawResponse {
                    DisclosureGroup("查看原始返回（用于反馈问题）") {
                        Text(aiRawResponse)
                            .font(.caption)
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
                    Text("未解析出记录。请更换文本，或改用规则解析。")
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
                    Text("第 \(aiUncertain.map(String.init).joined(separator: "、")) 行未能确定，没有列进来，请用逐个录入补上。")
                        .font(.footnote)
                        .foregroundStyle(Palette.warning)
                }
            } header: {
                Text("解析预览")
            }
        }
    }

    @ViewBuilder
    private func aiParsedRow(_ line: AIPreviewLine) -> some View {
        aiParsedRowContent(line)
            .font(bigMode ? .system(size: 17) : nil)
    }

    @ViewBuilder
    private func aiParsedRowContent(_ line: AIPreviewLine) -> some View {
        switch line.status {
        case .ok(let name, let cents, let relation, let method):
            HStack(spacing: LiqianMetrics.spacingS) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Palette.success)
                VStack(alignment: .leading, spacing: LiqianMetrics.spacingXS) {
                    HStack(spacing: LiqianMetrics.spacingS) {
                        Text("\(name) · \(LedgerMath.fmtMoney(cents: cents))" + (relation.map { " · \($0)" } ?? "") + (method.map { " · \($0)" } ?? ""))
                            .font(bigMode ? .system(size: 17) : nil)
                            .foregroundStyle(Palette.ink)
                        aiBadge
                    }
                    if existingNames.contains(name) {
                        Text("本礼簿已有同名记录，导入后将并列保存")
                            .font(.footnote)
                            .foregroundStyle(Palette.warning)
                    }
                }
                Spacer()
            }
        case .givenBlocked(let name, let cents):
            HStack(spacing: LiqianMetrics.spacingS) {
                Image(systemName: "exclamationmark.circle.fill")
                    .foregroundStyle(Palette.warning)
                VStack(alignment: .leading, spacing: LiqianMetrics.spacingXS) {
                    HStack(spacing: LiqianMetrics.spacingS) {
                        Text("\(name) · \(LedgerMath.fmtMoney(cents: cents)) · 随礼")
                            .foregroundStyle(Palette.ink)
                        aiBadge
                    }
                    Text("随礼行暂不支持在这里导入，请用逐个录入记这一笔")
                        .font(.footnote)
                        .foregroundStyle(Palette.warning)
                }
                Spacer()
            }
        case .failed(let reason):
            HStack(spacing: LiqianMetrics.spacingS) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(Palette.danger)
                Text(reason)
                    .font(.footnote)
                    .foregroundStyle(Palette.danger)
                Spacer()
                aiBadge
            }
        }
    }

    private var aiBadge: some View {
        Text("AI")
            .font(.caption2.weight(.bold))
            .foregroundStyle(Palette.primary)
            // 徽标内边距为自身规格字面量（同签形控件豁免口径）
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(Palette.primaryTint, in: Capsule())
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
                // 与一句话记账共用 Core 的 AIParse 管线：多笔解码＋金额换算＋白名单过滤只此一处
                let outcome = try AIParse.decode(data)
                aiUncertain = outcome.uncertain
                aiLines = outcome.records.enumerated().map { index, rec in
                    guard rec.isValid else {
                        return AIPreviewLine(
                            lineNo: index + 1,
                            status: .failed(reason: "第 \(index + 1) 条没读出姓名或金额，没列进来")
                        )
                    }
                    if rec.direction == LiqianConstants.given {
                        return AIPreviewLine(lineNo: index + 1, status: .givenBlocked(name: rec.name, cents: rec.amountCents))
                    }
                    return AIPreviewLine(
                        lineNo: index + 1,
                        status: .ok(
                            name: rec.name,
                            cents: rec.amountCents,
                            relation: rec.relation,
                            method: rec.method
                        )
                    )
                }
            } catch {
                aiError = "AI 返回格式异常，无法解析。请重试，或改用规则解析。"
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
