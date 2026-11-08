import Combine
import Foundation
import LiqianCore

/// 问账会话持有者（v5.8，「半路丢单」根治）：会话状态（消息列表、
/// 在途状态、落盘）从 AdvisorView 的 @State 提升到这里，由 App 根
/// 注入（environmentObject），生命周期与页面无关——用户提问后离开
/// 问账页、切 Tab、甚至页面被销毁重建，在途问答照常跑完、原位落地
/// 并落盘；视图只订阅呈现（见 docs/V58-AUDIT.md #11、V58-NOTES）。
///
/// 交付机制三件（本版新增，政策与文案口径沿 v5.7 一字未动）：
/// 1. 提问即落占位：发送瞬间用户气泡＋.pending 占位同批落盘，链
///    完成时原位替换为正式回复（id 不变），失败/超时同样原位换成
///    v5.7 收敛出口的兜底回复——任何情况下不留永久转圈、不留空白。
/// 2. 全链 45 秒总时限：AdvisorTimeBudget 分腿（工具阶段封顶 27s、
///    意图 8s、通用 lane 吃满剩余），每腿起腿前按已耗时问预算，
///    请求超时按腿值传入客户端，另有看门狗到点取消在途请求，
///    不许再叠加成旧链的约 180 秒。
/// 3. 杀进程收敛：init 读回时把遗孤 pending 收敛成提示文案
///    （AdvisorChatStore.reconcilingOrphanedPending），不留死占位。
@MainActor
final class AdvisorSession: ObservableObject {
    @Published private(set) var messages: [AdvisorChatMessage]
    @Published private(set) var isAsking = false
    /// 查账过程状态（v5.3 沿用）：按当前工具映射的人话文案，
    /// 占位行呈现它；nil = 不在查账
    @Published private(set) var activityText: String?
    /// 答案落定触感计数（v4.7 沿用）：正式回复原位落地时 +1
    @Published private(set) var answerTrigger = 0

    private var askTask: Task<Void, Never>?
    /// 在途提问的占位 id：完成回写只认它，防清空/新问之后旧链回写错位
    private var inFlightPendingID: AdvisorChatMessage.ID?

    init() {
        let loaded = AdvisorChatStore.load()
        let reconciled = AdvisorChatStore.reconcilingOrphanedPending(loaded)
        messages = reconciled
        // 有遗孤占位被收敛才回写，让磁盘与内存一致（下次读回已是文案）
        if reconciled != loaded {
            AdvisorChatStore.save(reconciled)
        }
    }

    private func persist() {
        AdvisorChatStore.save(messages)
    }

    // MARK: - 提问入口（视图组装好账目快照后调用）

    func ask(
        question: String,
        entries: [EntrySnapshot],
        ledgers: [AdvisorToolContext.LedgerInfo],
        people: [String]
    ) {
        let question = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty, !isAsking else { return }
        messages.append(AdvisorChatMessage(kind: .user(question)))
        let pending = AdvisorChatMessage(kind: .pending)
        messages.append(pending)
        persist()
        isAsking = true
        activityText = "正在查账…"
        inFlightPendingID = pending.id
        let context = AdvisorToolContext(
            entries: entries,
            ledgers: ledgers,
            today: LiqianDate.todayString()
        )
        let pendingID = pending.id
        askTask = Task { [weak self] in
            await self?.runPipeline(
                question: question, context: context,
                people: people, entries: entries, pendingID: pendingID
            )
        }
    }

    /// 清空对话：连同在途提问一并作废（取消任务、复位状态）；
    /// 已取消的链即便跑完也会被 settle 的 id 守卫挡下，不复活回复
    func clear() {
        askTask?.cancel()
        askTask = nil
        inFlightPendingID = nil
        isAsking = false
        activityText = nil
        messages = []
        AdvisorChatStore.clear()
    }

    // MARK: - 管线（v5.7 顺序与政策原样：工具 → 意图 → 通用 → 收敛）

    private func runPipeline(
        question: String,
        context: AdvisorToolContext,
        people: [String],
        entries: [EntrySnapshot],
        pendingID: AdvisorChatMessage.ID
    ) async {
        // 单调时钟计已耗时，喂给 AdvisorTimeBudget 分腿
        let start = ProcessInfo.processInfo.systemUptime
        func elapsed() -> TimeInterval {
            ProcessInfo.processInfo.systemUptime - start
        }

        // v5.2 主路径：AI 就绪先走工具问答；任何失败落 v4.4 意图管线
        if AIAccess.readiness() == .ready,
           let answer = await answerWithTools(
               question: question, context: context, elapsed: elapsed
           ) {
            settle(pendingID: pendingID, kind: .answer(text: answer.text, cards: answer.cards))
            return
        }
        if Task.isCancelled { return }

        let intent = await resolveIntent(
            question: question, people: people,
            timeout: AdvisorTimeBudget.intentTimeout(elapsedTotal: elapsed())
        )
        if Task.isCancelled { return }
        if let intent {
            settle(
                pendingID: pendingID,
                kind: .result(AdvisorEngine.execute(intent, entries: entries))
            )
            return
        }

        // v5.7 收敛段（永不沉默）：通用 lane → 收敛器裁决，三者必居其一
        let aiReady = AIAccess.readiness() == .ready
        var general: String?
        if aiReady,
           let timeout = AdvisorTimeBudget.generalTimeout(elapsedTotal: elapsed()) {
            general = await answerGenerally(question: question, timeout: timeout)
        }
        if Task.isCancelled { return }
        switch AdvisorReplyConvergence.resolve(aiReady: aiReady, generalAnswer: general) {
        case .generalAnswer(let text):
            settle(pendingID: pendingID, kind: .answer(text: text, cards: []))
        case .unsupportedWithoutAI:
            settle(pendingID: pendingID, kind: .result(.unsupported))
        case .failureApology:
            settle(
                pendingID: pendingID,
                kind: .note(AdvisorReplyConvergence.failureApologyText)
            )
        }
    }

    /// 链完成回写：把占位原位换成正式回复（id 不变，列表身份稳定），
    /// 同步落盘与复位在途状态。占位已被清空等情形下只复位状态、
    /// 不复活回复（settle 的 id 守卫＋索引双保险）。
    private func settle(pendingID: AdvisorChatMessage.ID, kind: AdvisorChatMessage.Kind) {
        guard inFlightPendingID == pendingID else { return }
        inFlightPendingID = nil
        askTask = nil
        isAsking = false
        activityText = nil
        if let index = messages.firstIndex(where: { $0.id == pendingID }) {
            messages[index].kind = kind
            answerTrigger += 1
        }
        persist()
    }

    /// 单腿硬顶：到点取消在途任务，让管线准时降级而不是陪着慢请求
    /// 干等。URLSession 的 data 请求响应取消（抛 URLError.cancelled），
    /// 上层一律按「本腿失败」处理；与客户端按腿传入的 request 超时
    /// 双保险（见 docs/V58-NOTES 时限分配表）。
    private func withLegTimeout<T: Sendable>(
        _ seconds: TimeInterval,
        operation: @Sendable @escaping () async throws -> T
    ) async throws -> T {
        let op = Task { try await operation() }
        let watchdog = Task {
            try? await Task.sleep(
                nanoseconds: UInt64(max(0, seconds) * 1_000_000_000)
            )
            op.cancel()
        }
        defer { watchdog.cancel() }
        return try await op.value
    }

    /// 通用作答 lane（v5.7）：无工具的纯文本对话，账外问题在这里由
    /// 模型用自身知识回答。任何失败返回 nil，交收敛器落致歉兜底。
    private func answerGenerally(question: String, timeout: TimeInterval) async -> String? {
        guard let client = try? DeepSeekClient() else { return nil }
        activityText = "正在整理回答…"
        let system = Self.generalSystemPrompt
        do {
            let text = try await withLegTimeout(timeout) {
                try await client.chatText(system: system, user: question, timeout: timeout)
            }
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        } catch {
            return nil
        }
    }

    /// 通用作答提示词（v5.7 原文）：账外 lane 的纪律——用自身知识答、
    /// 实时信息先声明拿不到再给常识、不编账目数据、不许诺没有的功能。
    private static let generalSystemPrompt = """
        你是「礼记」的问账管家。用户刚问的这个问题与他的人情礼金账无关，或者账里没有答案。用你自己的知识直接、简洁、口语化地回答，不要提「查账」「工具」，不要假装查过他的账，也不要把用户推开说「我只管账目」。
        需要实时信息才能答准的问题（实时天气、新闻、价格行情等）：先明说你拿不到实时数据，再给常识性的回答或建议；不许编造具体的实时数值，也不许只说「查不到」就结束。
        不要编造用户账本里的任何金额、人名和记录。被问到这个 App 怎么用时，只介绍它确实有的功能：记人情账、问账查账、待回提醒、礼谱与报表导出、语音和拍照记账；没有的功能不要许诺。
        """

    /// 工具问答轮数上限（v5.2 沿用）：模型最多连查 4 轮工具，防死循环烧额度
    private static let maxToolRounds = 4

    /// 工具问答主循环（v5.2/v5.3 原样）：模型决定调什么工具 → 本地
    /// AdvisorToolEngine 执行 → 结果回填 → 直到模型给出文字答复；
    /// 执行走 executeDetailed 同步收集 UI 卡片（同次计算，不另查账），
    /// 并按当前工具更新过程状态文案；轮数耗尽时卡片随 nil 一起丢弃，
    /// 整条回答完整落回 v4.4 卡片管线，不拼半成品。
    /// v5.8：每轮起腿前先问 AdvisorTimeBudget——工具阶段封顶或总预算
    /// 已尽就不再起新一轮，直接落降级；每腿超时按预算值双路执行。
    private func answerWithTools(
        question: String, context: AdvisorToolContext,
        elapsed: @escaping () -> TimeInterval
    ) async -> (text: String, cards: [AdvisorCard])? {
        guard let client = try? DeepSeekClient() else { return nil }
        var thread: [DeepSeekChatMessage] = [
            DeepSeekChatMessage(role: "system", content: Self.toolSystemPrompt(today: context.today)),
            DeepSeekChatMessage(role: "user", content: question),
        ]
        var cards: [AdvisorCard] = []
        let toolsJSON = AdvisorTools.definitionsJSON()
        let phaseStart = elapsed()
        for _ in 0..<Self.maxToolRounds {
            guard let leg = AdvisorTimeBudget.toolRoundTimeout(
                elapsedTotal: elapsed(), elapsedToolPhase: elapsed() - phaseStart
            ) else { return nil }
            let turn: DeepSeekTurn
            do {
                let snapshot = thread
                turn = try await withLegTimeout(leg) {
                    try await client.chatTurn(
                        messages: snapshot, toolsJSON: toolsJSON, timeout: leg
                    )
                }
            } catch {
                return nil
            }
            switch turn {
            case .text(let text):
                return (text, cards)
            case .toolCalls(let calls):
                if let first = calls.first {
                    activityText = Self.activityLabel(for: first)
                }
                thread.append(DeepSeekChatMessage(role: "assistant", toolCalls: calls))
                for call in calls {
                    let outcome = AdvisorToolEngine.executeDetailed(
                        AdvisorToolCall(name: call.name, argumentsJSON: call.arguments),
                        context: context
                    )
                    if let card = outcome.card {
                        cards.append(card)
                    }
                    thread.append(DeepSeekChatMessage(role: "tool", content: outcome.json, toolCallID: call.id))
                }
                activityText = "正在整理答案…"
            }
        }
        return nil // 轮数耗尽还没结论：落回卡片管线，不硬编答案
    }

    /// 过程状态文案（v5.3 原样，按工具映射的人话）
    private static func activityLabel(for call: DeepSeekToolCallRef) -> String {
        switch call.name {
        case AdvisorTools.queryPerson:
            if let name = toolArgString(call.arguments, key: "name") {
                return "正在查「\(name)」的账…"
            }
            return "正在查这个人的账…"
        case AdvisorTools.queryRecords:
            return "正在逐笔翻记录…"
        case AdvisorTools.aggregate:
            return "正在汇总对比…"
        case AdvisorTools.pendingList:
            return "正在翻待回名单…"
        case AdvisorTools.upcomingEvents:
            return "正在看近期场次和备礼…"
        case AdvisorTools.draftRecord:
            return "正在整理成记账卡…"
        default:
            return "正在查账…"
        }
    }

    /// 工具参数里取字符串字段（状态文案专用，宽容解析，取不到回 nil）
    private static func toolArgString(_ argumentsJSON: String, key: String) -> String? {
        guard let data = argumentsJSON.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let value = obj[key] as? String else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// 工具问答系统提示词（v5.7 原文，含账外 lane，逐字未动）：问答
    /// 纪律写死——数字只能来自工具结果，查不到就明说。
    private static func toolSystemPrompt(today: String) -> String {
        """
        你是「礼记」的问账管家，帮用户查他自己的人情礼金账。今天是 \(today)。
        你有五个本地查账工具：query_person（查某个人）、query_records（按条件筛逐笔）、aggregate（分组汇总与两时段对比）、pending_list（待回名单）、upcoming_events（近期场次与备礼清单）。需要账目数据时必须先调工具查，不许凭印象回答。
        另外有一个记账工具 draft_record：用户说要记一笔账（如「张三随礼了 500」「我给大舅回礼 800」「李四办满月我随了 1000」）时调它生成待确认记账卡。记账纪律：人名和金额有一项没说清，先向用户追问，绝不猜人名、绝不猜金额；金额只能用用户原话里的数字；方向分不清（是收到还是随出）也先问清再调。draft_record 只是草稿——只有用户在卡片上点「确认入账」才会真正记账，你不要说已经记好了。
        铁律：
        1. 回答里的每一个金额、笔数、日期、人名都只能来自工具返回的结果；工具没查到（ok 为 false、名单为空、账上没这个人）就直说「账里查不到」，绝不猜测、绝不编造、绝不拿别的数据凑。
        2. 相对时间要换算成绝对日期再调工具：如「今年」是 \(today) 所在年份的 1 月 1 日到 12 月 31 日，「最近三个月」按今天往前推三个月。工具返回的金额单位是元。
        3. 回答简洁口语、先给结论；涉及金额时带上口径出处，如「据你 2026 年的账」「你和大舅的全部往来里」。
        4. 回礼建议类问题：先用 query_person 查清差额与最近往来，再结合差额给建议，并说明建议依据的数字来自账里哪笔/哪段汇总；建议金额只能引用工具结果里的数字或其明确加减，不要凭空报数。
        5. 工具返回 ok:false 时，按 error 的意思如实告诉用户，或换个工具/参数再查一次；同一问题最多查 4 轮工具。
        6. 账外问题（与人情账目无关的问题，如天气、常识、礼仪人情、闲聊、问这个 App 怎么用）：不要调任何查账工具，直接用你自己的知识简洁作答；不许说「我只管账目」把用户推开，也不许假装查过账。一句问题里账内账外都有时，账内部分按上面 1-5 条先查工具，账外部分在同一条回复里用自己的知识答。账外回答里不许出现编造的账目金额、人名和记录；被问到这个 App 怎么用时，只介绍它确实有的功能：记人情账、问账查账、待回提醒、礼谱与报表导出、语音和拍照记账，没有的功能不要许诺。需要实时信息才能答准的（实时天气、新闻、价格行情），先明说你拿不到实时数据，再给常识性的回答或建议，不许编一个具体的实时数值，也不许只说「查不到」就结束。
        """
    }

    /// 意图来源顺序（v4.4 原样）：AI 就绪先走 AI 解码 → 解码失败/
    /// 听不懂/网络错，落规则兜底；AI 未就绪直接规则。规则也兜不住
    /// 返回 nil（上层走通用 lane＋收敛）。
    /// v5.8：timeout 为 nil 表示总预算已尽，跳过 AI 解码直接规则，
    /// 不再为意图腿新起网络请求。
    private func resolveIntent(
        question: String, people: [String], timeout: TimeInterval?
    ) async -> AdvisorIntent? {
        let currentYear = Calendar.current.component(.year, from: Date())
        if let timeout, AIAccess.readiness() == .ready {
            do {
                let client = try DeepSeekClient()
                let system = Self.intentSystemPrompt
                let data = try await withLegTimeout(timeout) {
                    try await client.chatJSON(system: system, user: question, timeout: timeout)
                }
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

    /// 只解析意图的提示词（v4.4 原文）：明确不许输出任何金额——返回
    /// 结构里也没有金额的位置，解码层根本不声明金额字段。
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

    // MARK: - 待确认记账卡回写（v5.4 沿用：改选礼簿/确认/取消共用）

    /// 按 draftID 定位并回写某张草稿卡的状态；回写后立即落盘
    /// （v5.8 起落盘由持有者单点负责，不再经视图 onChange）
    func updateDraft(
        messageID: AdvisorChatMessage.ID, draftID: UUID,
        mutate: (inout AdvisorDraftRecordCard) -> Void
    ) {
        guard let mi = messages.firstIndex(where: { $0.id == messageID }),
              case .answer(let text, var cards) = messages[mi].kind else { return }
        for ci in cards.indices {
            if case .draftRecord(var draft) = cards[ci], draft.draftID == draftID {
                mutate(&draft)
                cards[ci] = .draftRecord(draft)
            }
        }
        messages[mi].kind = .answer(text: text, cards: cards)
        persist()
    }

    /// 答案落定触感（视图侧草稿确认入账时借用，与 settle 同一计数）
    func pulseAnswerFeedback() {
        answerTrigger += 1
    }
}
