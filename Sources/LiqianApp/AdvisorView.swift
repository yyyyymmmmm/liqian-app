import SwiftData
import SwiftUI
import LiqianCore
import LiqianDesign

/// 对话管家：自然语言查账。
/// v5.2 主路径（工具问答）：AI 就绪时走 DeepSeek function calling——模型
/// 决定调哪些本地工具（AdvisorToolEngine 对账目快照现查），只把查到的
/// 结果回给模型组织语言；数字只出自工具结果，提示词写死查不到就明说。
/// v4.4 管线（保留为降级）：工具路径失败时，DeepSeek 只解析意图（类型＋
/// 人名/年份/方向/事由）→ AdvisorEngine 本地算数出结构化卡片；AI 未就绪
/// 或解析失败再走 AdvisorRules 关键词兜底。
/// 会话只在本页内存里，离开即散（本期口径，不落库）。
struct AdvisorView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query private var records: [GiftRecord]
    @Query(sort: \Ledger.date, order: .reverse) private var ledgers: [Ledger]
    @StateObject private var transcriber = SpeechTranscriber()

    @State private var messages: [Message] = []
    @State private var input = ""
    @State private var isAsking = false
    /// 答案落定触感（v4.7 审计补齐）：提问全程原无任何触感，答案 append 时 +1
    @State private var answerTrigger = 0
    @State private var personRoute: PeopleView.NameRoute?

    private struct Message: Identifiable {
        let id = UUID()
        var kind: Kind
        enum Kind {
            case user(String)
            case result(AdvisorResult)
            /// v5.2 工具问答的文字答复：内容由模型组织语言，
            /// 数字只许来自工具结果（系统提示词写死，见 toolSystemPrompt）
            case answer(String)
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

    /// 示例问题 chips（v5.2 扩面：查人/对比/趋势/场合/安排各一例，
    /// 点即问，让用户一眼知道现在能问什么——覆盖表见 V52-NOTES）
    private static let examples = [
        "谁还没回礼",
        "我和大舅谁欠谁",
        "今年和去年比，收礼哪个多",
        "婚礼一共收了多少",
        "最近三个月每月随了多少",
        "下一场是什么时候，备礼备了吗",
    ]

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
        .sensoryFeedback(.success, trigger: answerTrigger)
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
            Text("比如谁还没回礼、和谁欠谁、今年和去年比哪个多、最近几个月的趋势、下一场安排。金额都由工具按本机账目现查现算。")
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
                        // 符号动效枚举点：录音中麦克风 .pulse（审计 §3.5）
                        .symbolEffect(.pulse, isActive: transcriber.isRecording)
                        .foregroundStyle(transcriber.isRecording ? Palette.danger : Palette.primary)
                        .frame(width: LiqianMetrics.minTapTarget, height: LiqianMetrics.minTapTarget)
                }
                .buttonStyle(.plain)
                .disabled(transcriber.isStarting)
                .accessibilityLabel(transcriber.isRecording ? "停止录音" : "语音输入")

                TextField("问一句，如：我和大舅谁欠谁", text: $input)
                    .submitLabel(.send)
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
            Text("问账走你自己配置的 DeepSeek 接口：问题文字与工具查到的相关结果会发过去帮着组织回答，与问题无关的账目不发；金额全在本机算。")
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
        case .answer(let text):
            Text(text)
                .font(.body)
                .foregroundStyle(Palette.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
                .liqianCardSurface()
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
            text += "在「我的 → AI 管家」开通 AI 后，我能听懂更多问法。"
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
        let toolContext = AdvisorToolContext(
            entries: entries,
            ledgers: ledgers.map {
                AdvisorToolContext.LedgerInfo(id: $0.id, title: $0.title, type: $0.type, date: $0.date)
            },
            today: LiqianDate.todayString()
        )
        Task {
            // v5.2 主路径：AI 就绪先走工具问答（模型调本地工具查数、再组织语言）；
            // 工具路径任何失败（接口不支持 tools/网络/轮数耗尽）落回 v4.4
            // 意图解析＋结构化卡片管线，卡片能力不回归。
            if AIAccess.readiness() == .ready,
               let text = await answerWithTools(question: question, context: toolContext) {
                isAsking = false
                messages.append(Message(kind: .answer(text)))
                answerTrigger += 1
                return
            }
            let intent = await resolveIntent(question: question, people: names)
            isAsking = false
            if let intent {
                messages.append(Message(kind: .result(
                    AdvisorEngine.execute(intent, entries: entries)
                )))
            } else {
                messages.append(Message(kind: .result(.unsupported)))
            }
            answerTrigger += 1
        }
    }

    /// 工具问答轮数上限：模型最多连查 4 轮工具，防死循环烧额度
    private static let maxToolRounds = 4

    /// 工具问答主循环：模型决定调什么工具 → 本地 AdvisorToolEngine 执行 →
    /// 结果回填 → 直到模型给出文字答复。任何异常返回 nil（调用方降级）。
    private func answerWithTools(question: String, context: AdvisorToolContext) async -> String? {
        guard let client = try? DeepSeekClient() else { return nil }
        var thread: [DeepSeekChatMessage] = [
            DeepSeekChatMessage(role: "system", content: Self.toolSystemPrompt(today: context.today)),
            DeepSeekChatMessage(role: "user", content: question),
        ]
        for _ in 0..<Self.maxToolRounds {
            let turn: DeepSeekTurn
            do {
                turn = try await client.chatTurn(
                    messages: thread, toolsJSON: AdvisorTools.definitionsJSON()
                )
            } catch {
                return nil
            }
            switch turn {
            case .text(let text):
                return text
            case .toolCalls(let calls):
                thread.append(DeepSeekChatMessage(role: "assistant", toolCalls: calls))
                for call in calls {
                    let result = AdvisorToolEngine.execute(
                        AdvisorToolCall(name: call.name, argumentsJSON: call.arguments),
                        context: context
                    )
                    thread.append(DeepSeekChatMessage(role: "tool", content: result, toolCallID: call.id))
                }
            }
        }
        return nil // 轮数耗尽还没结论：落回卡片管线，不硬编答案
    }

    /// 工具问答系统提示词：问答纪律写死——数字只能来自工具结果，
    /// 查不到就明说，回答带数据口径出处。
    private static func toolSystemPrompt(today: String) -> String {
        """
        你是「礼记」的问账管家，帮用户查他自己的人情礼金账。今天是 \(today)。
        你有五个本地查账工具：query_person（查某个人）、query_records（按条件筛逐笔）、aggregate（分组汇总与两时段对比）、pending_list（待回名单）、upcoming_events（近期场次与备礼清单）。需要账目数据时必须先调工具查，不许凭印象回答。
        铁律：
        1. 回答里的每一个金额、笔数、日期、人名都只能来自工具返回的结果；工具没查到（ok 为 false、名单为空、账上没这个人）就直说「账里查不到」，绝不猜测、绝不编造、绝不拿别的数据凑。
        2. 相对时间要换算成绝对日期再调工具：如「今年」是 \(today) 所在年份的 1 月 1 日到 12 月 31 日，「最近三个月」按今天往前推三个月。工具返回的金额单位是元。
        3. 回答简洁口语、先给结论；涉及金额时带上口径出处，如「据你 2026 年的账」「你和大舅的全部往来里」。
        4. 回礼建议类问题：先用 query_person 查清差额与最近往来，再结合差额给建议，并说明建议依据的数字来自账里哪笔/哪段汇总；建议金额只能引用工具结果里的数字或其明确加减，不要凭空报数。
        5. 工具返回 ok:false 时，按 error 的意思如实告诉用户，或换个工具/参数再查一次；同一问题最多查 4 轮工具。
        6. 只回答与人情账目有关的问题；无关问题礼貌说明自己只管查账。
        """
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
