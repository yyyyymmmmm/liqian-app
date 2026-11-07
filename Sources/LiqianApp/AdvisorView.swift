import SwiftData
import SwiftUI
import LiqianCore
import LiqianDesign

/// 对话管家（v4.4）：自然语言查账。混合架构——
/// DeepSeek 只把问题解析成意图（类型＋人名/年份/方向/事由），金额一律由
/// AdvisorEngine 在本机用账目快照计算，模型输出里就算夹带数字也会在解码层被丢弃；
/// AI 未就绪或解析失败时走 AdvisorRules 关键词兜底。
/// 会话只在本页内存里，离开即散（本期口径，不落库）。
struct AdvisorView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query private var records: [GiftRecord]
    @Query(sort: \Ledger.date, order: .reverse) private var ledgers: [Ledger]
    @StateObject private var transcriber = SpeechTranscriber()

    @State private var messages: [Message] = []
    @State private var input = ""
    @State private var isAsking = false
    @State private var personRoute: PeopleView.NameRoute?

    private struct Message: Identifiable {
        let id = UUID()
        var kind: Kind
        enum Kind {
            case user(String)
            case result(AdvisorResult)
            /// 纯文案答复（没听懂、没找到人等，文案在 Core 结果之外由本层拼）
            case note(String)
        }
    }

    private var snapshots: [EntrySnapshot] {
        AppSupport.snapshots(records: records, ledgers: ledgers)
    }

    private var peopleNames: [String] {
        LedgerMath.people(from: snapshots).map(\.name)
    }

    private static let examples = ["谁还没回礼", "我和大舅谁欠谁", "今年一共收了多少"]

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: LiqianMetrics.spacingM) {
                        introBlock
                        ForEach(messages) { message in
                            messageRow(message)
                                .id(message.id)
                        }
                        if isAsking {
                            HStack(spacing: LiqianMetrics.spacingS) {
                                ProgressView()
                                Text("正在查账…")
                                    .font(.footnote)
                                    .foregroundStyle(Palette.stone)
                            }
                        }
                    }
                    .padding(LiqianMetrics.spacingM)
                }
                .onChange(of: messages.count) {
                    if let last = messages.last {
                        // Reduce Motion 时直接定位不滚动动画（v4.4）
                        if reduceMotion {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        } else {
                            withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                        }
                    }
                }
            }
            composer
        }
        .background(Palette.pageBG.ignoresSafeArea())
        .navigationTitle("问账")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $personRoute) { route in
            PersonDetailView(name: route.name)
        }
        .onAppear {
            transcriber.onText = { input = $0 }
        }
        .onDisappear {
            transcriber.stop()
        }
    }

    // MARK: - 顶部说明与示例

    private var introBlock: some View {
        VStack(alignment: .leading, spacing: LiqianMetrics.spacingS) {
            Text("问我一句，我从你的账里查。")
                .font(.headline)
                .foregroundStyle(Palette.ink)
            Text("比如谁还没回礼、和谁谁谁欠谁、今年一共收了多少。金额都是按本机账目现算的。")
                .font(.footnote)
                .foregroundStyle(Palette.stone)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .liqianCardSurface()
    }

    // MARK: - 输入区（示例 chips + 语音/文字输入 + 隐私说明）

    private var composer: some View {
        VStack(alignment: .leading, spacing: LiqianMetrics.spacingS) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: LiqianMetrics.spacingS) {
                    ForEach(Self.examples, id: \.self) { example in
                        Button(example) { ask(example) }
                            .font(.footnote)
                            .foregroundStyle(Palette.primary)
                            .padding(.horizontal, LiqianMetrics.spacingSM)
                            .padding(.vertical, LiqianMetrics.spacingXS + 2)
                            .background(Palette.primaryTint, in: Capsule())
                            .buttonStyle(.plain)
                            .disabled(isAsking)
                    }
                }
            }
            if transcriber.isRecording {
                Text("正在听，说完点停止…")
                    .font(.footnote)
                    .foregroundStyle(Palette.stone)
            } else if let speechError = transcriber.errorText {
                Text(speechError)
                    .font(.footnote)
                    .foregroundStyle(Palette.danger)
            }
            HStack(spacing: LiqianMetrics.spacingS) {
                Button {
                    transcriber.toggle()
                } label: {
                    Image(systemName: transcriber.isRecording ? "stop.circle.fill" : "mic")
                        .font(.title3)
                        .foregroundStyle(transcriber.isRecording ? Palette.danger : Palette.primary)
                        .frame(width: LiqianMetrics.minTapTarget, height: LiqianMetrics.minTapTarget)
                }
                .buttonStyle(.plain)
                .disabled(transcriber.isStarting)
                .accessibilityLabel(transcriber.isRecording ? "停止录音" : "语音输入")

                TextField("问一句，如：我和大舅谁欠谁", text: $input)
                    .onSubmit { ask(input) }

                Button {
                    ask(input)
                } label: {
                    Text("问")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(width: LiqianMetrics.minTapTarget, height: LiqianMetrics.minTapTarget)
                        .background(
                            inputEmpty || isAsking ? Palette.stone : Palette.primaryFill,
                            in: Circle()
                        )
                }
                .buttonStyle(.plain)
                .disabled(inputEmpty || isAsking)
                .accessibilityLabel("发送问题")
            }
            Text("问账时只有问题文字会发给 DeepSeek 帮着理解，账目数据只在本机计算，不外发。")
                .font(.caption)
                .foregroundStyle(Palette.stone)
        }
        .padding(.horizontal, LiqianMetrics.spacingM)
        .padding(.top, LiqianMetrics.spacingS)
        .padding(.bottom, LiqianMetrics.spacingS)
        .background(Palette.surface)
    }

    private var inputEmpty: Bool {
        input.trimmingCharacters(in: .whitespaces).isEmpty
    }

    // MARK: - 消息行

    @ViewBuilder
    private func messageRow(_ message: Message) -> some View {
        switch message.kind {
        case .user(let text):
            HStack {
                Spacer(minLength: 48)
                Text(text)
                    .foregroundStyle(Palette.ink)
                    .padding(.horizontal, LiqianMetrics.spacingSM)
                    .padding(.vertical, LiqianMetrics.spacingS)
                    .background(Palette.primaryTint, in: RoundedRectangle(cornerRadius: LiqianMetrics.controlCorner))
            }
        case .result(let result):
            resultCard(result)
        case .note(let text):
            Text(text)
                .font(.footnote)
                .foregroundStyle(Palette.stone)
                .frame(maxWidth: .infinity, alignment: .leading)
                .liqianCardSurface()
        }
    }

    // MARK: - 结果卡片（数字全部来自 AdvisorEngine 的本地计算）

    @ViewBuilder
    private func resultCard(_ result: AdvisorResult) -> some View {
        switch result {
        case .balance(let summary):
            personCard(summary: summary) {
                balanceFigure(summary)
            }
        case .personHistory(let summary, let lines):
            personCard(summary: summary) {
                VStack(alignment: .leading, spacing: LiqianMetrics.spacingXS) {
                    ForEach(lines.prefix(6)) { line in
                        entryLineRow(line)
                    }
                    if lines.count > 6 {
                        Text("共 \(lines.count) 笔，点开看全部")
                            .font(.footnote)
                            .foregroundStyle(Palette.stone)
                    } else if lines.isEmpty {
                        Text("这个时段没有往来记录")
                            .font(.footnote)
                            .foregroundStyle(Palette.stone)
                    }
                }
            }
        case .pendingList(let list):
            pendingCard(list)
        case .periodSummary(let year, let focus, let received, let given, let count):
            periodCard(year: year, focus: focus, received: received, given: given, count: count)
        case .typeSummary(let rows, _):
            typeCard(rows)
        case .personNotFound(let name):
            noteCard("账上没有叫「\(name)」的人。检查下名字，或者去「往来」页搜一搜。")
        case .needPerson:
            noteCard("想问谁的账？带上名字再问我，如「我和大舅谁欠谁」。")
        case .unsupported:
            noteCard(unsupportedText)
        }
    }

    /// 差额/某人往来共用的人物卡外壳：点头像行进人物详情
    private func personCard<Content: View>(
        summary: PersonSummary,
        @ViewBuilder content: () -> Content
    ) -> some View {
        Button {
            personRoute = PeopleView.NameRoute(name: summary.name)
        } label: {
            VStack(alignment: .leading, spacing: LiqianMetrics.spacingS) {
                HStack(spacing: LiqianMetrics.spacingS) {
                    Text(summary.name)
                        .font(.headline)
                        .foregroundStyle(Palette.ink)
                    Text(summary.relation)
                        .font(.footnote)
                        .foregroundStyle(Palette.stone)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Palette.stone)
                        .accessibilityHidden(true)
                }
                content()
                HStack(spacing: LiqianMetrics.spacingM) {
                    Text("收 \(LedgerMath.fmtMoney(cents: summary.received))")
                    Text("随 \(LedgerMath.fmtMoney(cents: summary.given))")
                    Text("\(summary.count) 笔")
                }
                .font(.footnote)
                .foregroundStyle(Palette.stone)
            }
            .liqianCardSurface()
        }
        .buttonStyle(.plain)
    }

    /// 差额大字（口径与往来页一致：>0 待回、<0 多随、=0 已结清）
    private func balanceFigure(_ summary: PersonSummary) -> some View {
        Group {
            if summary.balance > 0 {
                figureLine(label: "待回", cents: summary.pendingCents, color: Palette.primary)
            } else if summary.balance < 0 {
                figureLine(label: "多随", cents: -summary.balance, color: Palette.ink)
            } else {
                Text("已结清")
                    .font(.liqianMoney(.title2))
                    .foregroundStyle(Palette.stone)
            }
        }
    }

    private func figureLine(label: String, cents: Int, color: Color) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: LiqianMetrics.spacingS) {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(Palette.stone)
            Text(LedgerMath.fmtMoney(cents: cents))
                .font(.liqianMoney(.largeTitle))
                .foregroundStyle(color)
        }
    }

    private func entryLineRow(_ line: AdvisorEntryLine) -> some View {
        HStack(spacing: LiqianMetrics.spacingS) {
            Text(LiqianDate.displayString(for: line.date))
                .font(.footnote)
                .foregroundStyle(Palette.stone)
                .frame(width: 86, alignment: .leading)
            if !line.ledgerType.isEmpty {
                Text(line.ledgerType)
                    .font(.footnote)
                    .foregroundStyle(Palette.stone)
            }
            Spacer()
            Text(line.direction == LiqianConstants.received ? "收" : "随")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(line.direction == LiqianConstants.received ? Palette.primary : Palette.ink)
            Text(LedgerMath.fmtMoney(cents: line.amountCents))
                .font(.liqianMoney(.body))
                .foregroundStyle(Palette.ink)
        }
    }

    private func pendingCard(_ list: [PersonSummary]) -> some View {
        VStack(alignment: .leading, spacing: LiqianMetrics.spacingS) {
            Text("还没回礼的")
                .font(.headline)
                .foregroundStyle(Palette.ink)
            if list.isEmpty {
                Text("没有待回的，都结清了。")
                    .font(.footnote)
                    .foregroundStyle(Palette.stone)
            } else {
                ForEach(list) { p in
                    Button {
                        personRoute = PeopleView.NameRoute(name: p.name)
                    } label: {
                        HStack(spacing: LiqianMetrics.spacingS) {
                            Text(p.name)
                                .foregroundStyle(Palette.ink)
                                .lineLimit(1)
                            Spacer()
                            Text("待回 \(LedgerMath.fmtMoney(cents: p.pendingCents))")
                                .font(.liqianMoney(.title3))
                                .foregroundStyle(Palette.primary)
                                .lineLimit(1)
                                .layoutPriority(1)
                            Image(systemName: "chevron.right")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(Palette.stone)
                                .accessibilityHidden(true)
                        }
                        .frame(minHeight: LiqianMetrics.minTapTarget)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .liqianCardSurface()
    }

    private func periodCard(year: Int?, focus: String?, received: Int, given: Int, count: Int) -> some View {
        VStack(alignment: .leading, spacing: LiqianMetrics.spacingS) {
            Text(periodTitle(year: year))
                .font(.headline)
                .foregroundStyle(Palette.ink)
            if focus == LiqianConstants.given {
                figureLine(label: "随礼合计", cents: given, color: Palette.ink)
                Text("同期收礼 \(LedgerMath.fmtMoney(cents: received)) · 共 \(count) 笔")
                    .font(.footnote)
                    .foregroundStyle(Palette.stone)
            } else if focus == LiqianConstants.received {
                figureLine(label: "收礼合计", cents: received, color: Palette.primary)
                Text("同期随礼 \(LedgerMath.fmtMoney(cents: given)) · 共 \(count) 笔")
                    .font(.footnote)
                    .foregroundStyle(Palette.stone)
            } else {
                HStack(spacing: LiqianMetrics.spacingL) {
                    VStack(alignment: .leading, spacing: LiqianMetrics.spacingXS) {
                        Text("收礼")
                            .font(.footnote)
                            .foregroundStyle(Palette.stone)
                        Text(LedgerMath.fmtMoney(cents: received))
                            .font(.liqianMoney(.title2))
                            .foregroundStyle(Palette.primary)
                    }
                    VStack(alignment: .leading, spacing: LiqianMetrics.spacingXS) {
                        Text("随礼")
                            .font(.footnote)
                            .foregroundStyle(Palette.stone)
                        Text(LedgerMath.fmtMoney(cents: given))
                            .font(.liqianMoney(.title2))
                            .foregroundStyle(Palette.ink)
                    }
                }
                Text("共 \(count) 笔")
                    .font(.footnote)
                    .foregroundStyle(Palette.stone)
            }
        }
        .liqianCardSurface()
    }

    private func periodTitle(year: Int?) -> String {
        guard let year else { return "全部时段汇总" }
        let current = Calendar.current.component(.year, from: Date())
        if year == current { return "今年汇总" }
        if year == current - 1 { return "去年汇总" }
        return "\(year) 年汇总"
    }

    private func typeCard(_ rows: [TypeSummary]) -> some View {
        VStack(alignment: .leading, spacing: LiqianMetrics.spacingS) {
            Text("按事由统计")
                .font(.headline)
                .foregroundStyle(Palette.ink)
            if rows.isEmpty {
                Text("还没有任何记录。")
                    .font(.footnote)
                    .foregroundStyle(Palette.stone)
            } else {
                ForEach(rows) { row in
                    HStack(spacing: LiqianMetrics.spacingS) {
                        Text(row.type)
                            .foregroundStyle(Palette.ink)
                        Spacer()
                        Text("收 \(LedgerMath.fmtMoney(cents: row.received)) · 随 \(LedgerMath.fmtMoney(cents: row.given)) · \(row.count) 笔")
                            .font(.footnote)
                            .foregroundStyle(Palette.stone)
                            .lineLimit(1)
                    }
                    .frame(minHeight: LiqianMetrics.minTapTarget)
                }
            }
        }
        .liqianCardSurface()
    }

    private func noteCard(_ text: String) -> some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(Palette.stone)
            .frame(maxWidth: .infinity, alignment: .leading)
            .liqianCardSurface()
    }

    private var unsupportedText: String {
        var text = "这个问法我还不会，去往来页搜人名也可以。"
        if AIAccess.readiness() != .ready {
            text += "在「我的 → AI 智能助手」开通 AI 后，我能听懂更多问法。"
        }
        return text
    }

    // MARK: - 提问管线：AI 解析意图 → 失败落规则 → 本地执行

    private func ask(_ raw: String) {
        let question = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty, !isAsking else { return }
        transcriber.stop()
        input = ""
        messages.append(Message(kind: .user(question)))
        isAsking = true
        let entries = snapshots
        let names = peopleNames
        Task {
            let intent = await resolveIntent(question: question, people: names)
            isAsking = false
            if let intent {
                messages.append(Message(kind: .result(
                    AdvisorEngine.execute(intent, entries: entries)
                )))
            } else {
                messages.append(Message(kind: .result(.unsupported)))
            }
        }
    }

    /// 意图来源顺序：AI 就绪先走 AI 解码 → 解码失败/听不懂/网络错，落规则兜底；
    /// AI 未就绪直接规则。规则也兜不住返回 nil（UI 出 .unsupported 卡）。
    private func resolveIntent(question: String, people: [String]) async -> AdvisorIntent? {
        let currentYear = Calendar.current.component(.year, from: Date())
        if AIAccess.readiness() == .ready {
            do {
                let client = try DeepSeekClient()
                let data = try await client.chatJSON(system: Self.intentSystemPrompt, user: question)
                let intent = try AdvisorIntentParse.decode(data, currentYear: currentYear)
                if intent.kind != .unknown {
                    return intent
                }
            } catch {
                // 模型/网络/解码任一失败都不让用户白等，落规则兜底
            }
        }
        return AdvisorRules.intent(from: question, people: people, currentYear: currentYear)
    }

    /// 只解析意图的提示词：明确不许输出任何金额——返回结构里也没有金额的位置，
    /// 解码层（AdvisorIntentParse）根本不声明金额字段，模型夹带的数字会被直接丢弃。
    private static let intentSystemPrompt = """
        你是礼记的问账意图解析器。用户会用中文问一句关于人情礼金往来的问题，你只负责听懂他想查什么，不要回答问题本身，更不要计算或猜测任何金额。只输出一个 JSON 对象，不要输出任何其他文字：{"intent":"balance","person":null,"year":null,"direction":null,"type":null}
        intent 取值与含义：
        - "balance"：问和某个人谁欠谁、差额多少（如「我和大舅谁欠谁」「张三还欠我多少」），此时 person 必填；
        - "person"：问某个人的往来明细（如「张三随了多少」「看看我和二姨的往来」），此时 person 必填；
        - "pending"：问谁还没回礼、待回名单（如「谁还没回礼」）；
        - "period"：问一段时间内的汇总（如「今年一共收了多少」「去年随出去多少」）；
        - "type"：按事由问统计（如「婚礼一共收了多少」），此时 type 必填；
        - "unknown"：以上都不是、或听不懂。
        person：问题里的人名照抄原文，不在名单里也照抄，没有就给 null。
        year：问今年给 "this"，去年给 "last"，明确年份给数字（如 2024），没提给 null。
        direction：只问收礼给 "received"，只问随礼/送礼给 "given"，都问或没提给 null。
        type：事由只能是 婚礼/满月/周岁/乔迁/寿宴/升学/开业/白事/其他 之一，没有就给 null。
        重要：JSON 里只有 intent/person/year/direction/type 五个键，绝对不要添加金额、笔数等任何数字结果——账由 App 在本机计算。
        """
}
