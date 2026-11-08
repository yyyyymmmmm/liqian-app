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
/// v5.3 呈现重做：工具执行同一路径加挂结构化卡片（AdvisorCard，见
/// LiqianCore/AdvisorCards.swift）——模型文字退为卡片上方的结论引子并走
/// Markdown 渲染＋打字机揭示（v5.2 时纯文本直印、星号横杠全露是实锤
/// bug）；查账过程有按工具映射的人话状态；气泡/示例签/输入栏走 Mat
/// 材质＋主题染色令牌；消息入场与卡片依次浮入走 Motion 令牌，
/// Reduce Motion 全降级。工具集、问答纪律、降级路径未动。
/// v5.4：对话本地持久化（AdvisorChatStore 落 JSON 文件），退出重进
/// 历史还在，页面菜单可清空；新增 draft_record 记账工具——AI 只起草
/// 待确认卡，用户点「确认入账」才走既有记账数据路径真正写库。
/// v5.7 双修：①问账回答政策「永不沉默」——工具提示词加账外 lane
/// （账外问题模型直接用自身知识作答），管线末端加通用作答 lane＋
/// AdvisorReplyConvergence 收敛裁决，任何出口必落一条可见回复；
/// ②键盘收起三件套：滚动收键盘、点消息区收键盘、键盘附件栏收起钮。
struct AdvisorView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.modelContext) private var modelContext
    @Query private var records: [GiftRecord]
    @Query(sort: \Ledger.date, order: .reverse) private var ledgers: [Ledger]
    @StateObject private var transcriber = SpeechTranscriber()

    @State private var messages: [AdvisorChatMessage] = []
    /// 历史只在首次出现时恢复一次（之后以内存为准、每次变更回写文件）
    @State private var loadedHistory = false
    @State private var showClearConfirm = false
    /// 语音面板（v5.6）：点麦克风开会话＋面板，完成回填输入框、取消不落字
    @State private var showVoicePanel = false
    /// 回执卡点开的记录详情（既有 RecordFormView 编辑形态，与礼簿详情同口径）
    @State private var editingRecord: GiftRecord?
    @State private var input = ""
    @State private var isAsking = false
    /// 键盘收起三件套的焦点锚（v5.7）：输入框绑定它，点空白/附件栏
    /// 收起钮都靠把这一位放掉来收键盘
    @FocusState private var composerFocused: Bool
    /// 查账过程状态（v5.3）：按当前工具映射的人话文案，nil = 不在查账
    @State private var activityText: String?
    /// 答案落定触感（v4.7 审计补齐）：提问全程原无任何触感，答案 append 时 +1
    @State private var answerTrigger = 0
    @State private var personRoute: PeopleView.NameRoute?
    /// 首屏入场（v5.3）：欢迎卡与示例签淡入上浮，Reduce Motion 时直达终态
    @State private var entered = false

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
        "张三随礼了 500，帮我记上",
    ]

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: LiqianMetrics.spacingM) {
                        introBlock
                        ForEach(messages) { message in
                            messageRow(message, proxy: proxy)
                                .id(message.id)
                                .transition(
                                    reduceMotion
                                        ? .identity
                                        : .opacity.combined(with: .offset(y: 8))
                                )
                        }
                        if isAsking {
                            activityRow
                        }
                    }
                    .padding(LiqianMetrics.spacingM)
                    .animation(
                        MotionTokens.resolved(MotionTokens.pageCrossfade, reduceMotion: reduceMotion),
                        value: messages.count
                    )
                }
                // 键盘收起三件套 ①②（v5.7）：滑动消息流交互式收键盘；
                // 点消息区任意处（含卡片按钮，动作照常触发）顺手放焦点
                // 收键盘——simultaneous 不抢占卡片自身的点按与滚动拖动
                .scrollDismissesKeyboard(.interactively)
                .simultaneousGesture(
                    TapGesture().onEnded { composerFocused = false }
                )
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
        .sheet(item: $editingRecord) { record in
            RecordFormView(existing: record)
        }
        .sheet(isPresented: $showVoicePanel, onDismiss: {
            // 兜底：面板被非正常关掉时若会话还在，按取消处理（不落字）
            if transcriber.isRecording || transcriber.isStarting {
                transcriber.cancelTranscription()
            }
        }) {
            VoiceInputPanel(
                transcriber: transcriber,
                onFinish: { finalText in
                    // 提交语义同 v5.5.1 的 onText 末态：全文进输入框
                    // 待发送，不自动发问
                    input = finalText
                    showVoicePanel = false
                },
                onCancel: { showVoicePanel = false }
            )
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button(role: .destructive) {
                        showClearConfirm = true
                    } label: {
                        Label("清空对话", systemImage: "trash")
                    }
                    .disabled(messages.isEmpty)
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityLabel("对话菜单")
            }
            // 键盘收起三件套 ③（v5.7）：键盘附件栏右侧「收起」钮，
            // 键盘升起时才出现，不占输入坞布局
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button {
                    composerFocused = false
                } label: {
                    Image(systemName: "chevron.down")
                }
                .accessibilityLabel("收起键盘")
            }
        }
        .confirmationDialog(
            "清空全部对话记录？",
            isPresented: $showClearConfirm,
            titleVisibility: .visible
        ) {
            Button("清空", role: .destructive) {
                messages = []
                AdvisorChatStore.clear()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("问答历史会从本机删除，账本记录不受影响。")
        }
        .onChange(of: messages) { _, newValue in
            AdvisorChatStore.save(newValue)
        }
        .onAppear {
            if !loadedHistory {
                loadedHistory = true
                if messages.isEmpty {
                    messages = AdvisorChatStore.load()
                }
            }
            if !entered {
                if reduceMotion {
                    entered = true
                } else {
                    withAnimation(MotionTokens.pageCrossfade) { entered = true }
                }
            }
        }
        .onDisappear {
            transcriber.stop()
        }
    }

    /// 查账过程行（v5.3）：转圈＋当前动作的人话状态（按工具映射），
    /// 状态切换交叉淡化，不再是黑箱里的一句「正在查账…」到底
    private var activityRow: some View {
        HStack(spacing: LiqianMetrics.spacingS) {
            ProgressView()
                .controlSize(.small)
            Text(activityText ?? "正在查账…")
                .font(.footnote)
                .foregroundStyle(Palette.stone)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(
            MotionTokens.resolved(MotionTokens.pageCrossfade, reduceMotion: reduceMotion),
            value: activityText
        )
        .transition(reduceMotion ? .identity : .opacity)
    }

    // MARK: - 顶部说明与示例

    private var introBlock: some View {
        VStack(alignment: .leading, spacing: LiqianMetrics.spacingS) {
            Text("问我一句，我从你的账里查。")
                .font(.headline)
                .foregroundStyle(Palette.ink)
            Text("比如谁还没回礼、和谁欠谁、今年和去年比哪个多、最近几个月的趋势、下一场安排。金额都由工具按本机账目现查现算。也可以直接吩咐我记账，如「张三随礼了 500」——我拟好卡片，你核对点确认才入账。")
                .font(.footnote)
                .foregroundStyle(Palette.stone)
            // v5.4：隐私脚注从输入栈里挪进欢迎卡底部——输入区只剩
            // 签行＋输入坞，不再有文字夹在两层控件之间。
            Divider()
            Text("问账走你自己配置的 DeepSeek 接口：问题文字与工具查到的相关结果会发过去帮着组织回答，与问题无关的账目不发；金额全在本机算。对话记录只存这台手机，随时可在右上角菜单里清空。")
                .font(.caption)
                .foregroundStyle(Palette.stone)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .liqianCardSurface()
        .opacity(entered ? 1 : 0)
        .offset(y: reduceMotion ? 0 : (entered ? 0 : 10))
    }

    /// 语音面板入口（v5.6）：先启动转写会话、再上面板；启动即失败
    /// 时面板呈现异常态＋关闭钮，不静默无反应
    private func openVoicePanel() {
        guard !transcriber.isRecording, !transcriber.isStarting else { return }
        transcriber.start()
        showVoicePanel = true
    }

    // MARK: - 输入区（示例 chips + 输入坞）
    // v5.3：示例签走 Mat.tinted 染色玻璃、麦克风落玻璃圆、发送键三态。
    // v5.4 收拾成一坨：签行贴在坞上方，坞（玻璃圆角容器）内只装
    // 麦克风/输入框/发送键；隐私脚注已移出输入栈、收进欢迎卡底部，
    // 输入区与标签栏之间只留令牌间距，不再五层堆叠夹文字。

    private var composer: some View {
        VStack(alignment: .leading, spacing: LiqianMetrics.spacingS) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: LiqianMetrics.spacingS) {
                    ForEach(Self.examples, id: \.self) { example in
                        Button { ask(example) } label: {
                            Text(example)
                                .font(.footnote)
                                .foregroundStyle(Palette.primary)
                                .padding(.horizontal, LiqianMetrics.spacingSM)
                                .padding(.vertical, LiqianMetrics.spacingXS + 2)
                                .liqianGlassSurface(.tinted, in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .disabled(isAsking)
                    }
                }
            }
            .opacity(entered ? 1 : 0)
            .offset(y: reduceMotion ? 0 : (entered ? 0 : 8))
            if transcriber.isRecording {
                Text("正在录音，识别在语音面板里进行…")
                    .font(.footnote)
                    .foregroundStyle(Palette.stone)
            } else if let speechError = transcriber.errorText {
                Text(speechError)
                    .font(.footnote)
                    .foregroundStyle(Palette.danger)
            }
            HStack(spacing: LiqianMetrics.spacingS) {
                Button {
                    openVoicePanel()
                } label: {
                    Image(systemName: "mic")
                        .font(.title3)
                        // 符号动效枚举点：录音中麦克风 .pulse（审计 §3.5）
                        .symbolEffect(.pulse, isActive: transcriber.isRecording)
                        .foregroundStyle(transcriber.isRecording ? Palette.danger : Palette.primary)
                        .frame(width: LiqianMetrics.minTapTarget, height: LiqianMetrics.minTapTarget)
                        .liqianGlassSurface(.regular, in: Circle())
                }
                .buttonStyle(.plain)
                .disabled(transcriber.isStarting)
                .accessibilityLabel(transcriber.isRecording ? "停止录音" : "语音输入")

                TextField("问一句，如：我和大舅谁欠谁", text: $input)
                    .focused($composerFocused)
                    .submitLabel(.send)
                    .onSubmit { ask(input) }

                sendButton
            }
            .padding(.horizontal, LiqianMetrics.spacingS)
            .padding(.vertical, LiqianMetrics.spacingXS)
            .liqianGlassSurface(
                .regular,
                in: RoundedRectangle(cornerRadius: LiqianMetrics.controlCorner)
            )
        }
        .padding(.horizontal, LiqianMetrics.spacingM)
        .padding(.top, LiqianMetrics.spacingS)
        .padding(.bottom, LiqianMetrics.spacingS)
    }

    /// 发送键三态：空输入＝线色圆＋石色箭头（禁用）；可发＝主题填充＋白箭头；
    /// 发送中＝同填充＋白转圈。不再用「问」字圆钮的默认样式感拼凑。
    private var sendButton: some View {
        Button {
            ask(input)
        } label: {
            ZStack {
                Circle()
                    .fill(isAsking || !inputEmpty ? Palette.primaryFill : Palette.line)
                if isAsking {
                    ProgressView()
                        .controlSize(.small)
                        .tint(.white)
                } else {
                    Image(systemName: "arrow.up")
                        .font(.body.weight(.bold))
                        .foregroundStyle(inputEmpty ? Palette.stone : .white)
                }
            }
            .frame(width: LiqianMetrics.minTapTarget, height: LiqianMetrics.minTapTarget)
        }
        .buttonStyle(.plain)
        .disabled(inputEmpty || isAsking)
        .accessibilityLabel("发送问题")
    }

    private var inputEmpty: Bool {
        input.trimmingCharacters(in: .whitespaces).isEmpty
    }

    // MARK: - 消息行

    @ViewBuilder
    private func messageRow(_ message: AdvisorChatMessage, proxy: ScrollViewProxy) -> some View {
        switch message.kind {
        case .user(let text):
            HStack {
                Spacer(minLength: 48)
                Text(text)
                    .foregroundStyle(Palette.ink)
                    .padding(.horizontal, LiqianMetrics.spacingSM)
                    .padding(.vertical, LiqianMetrics.spacingS)
                    .liqianGlassSurface(
                        .tinted,
                        in: RoundedRectangle(cornerRadius: LiqianMetrics.controlCorner)
                    )
            }
        case .result(let result):
            resultCard(result)
        case .answer(let text, let cards):
            answerBlock(text: text, cards: cards, messageID: message.id, proxy: proxy)
        case .note(let text):
            Text(text)
                .font(.footnote)
                .foregroundStyle(Palette.stone)
                .frame(maxWidth: .infinity, alignment: .leading)
                .liqianCardSurface()
        }
    }

    /// 工具问答的回答块（v5.3）：上方结论引子（Markdown 打字机渲染，
    /// 不露标记）＋下方结构化卡片依次浮入（按工具调用顺序）
    private func answerBlock(
        text: String, cards: [AdvisorCard], messageID: AdvisorChatMessage.ID, proxy: ScrollViewProxy
    ) -> some View {
        VStack(alignment: .leading, spacing: LiqianMetrics.spacingS) {
            TypewriterMarkdownText(markdown: text) {
                // 打字机揭示期间把本条钉在底部，长回答不用手动追滚
                if reduceMotion {
                    proxy.scrollTo(messageID, anchor: .bottom)
                } else {
                    withAnimation { proxy.scrollTo(messageID, anchor: .bottom) }
                }
            }
            .font(.body)
            .foregroundStyle(Palette.ink)
            .frame(maxWidth: .infinity, alignment: .leading)
            .liqianCardSurface()

            ForEach(Array(cards.enumerated()), id: \.offset) { index, card in
                toolCard(card, messageID: messageID)
                    .modifier(CardInModifier(index: index, reduceMotion: reduceMotion))
            }
        }
    }

    // MARK: - 工具卡片（v5.3 新增；数字全部来自 AdvisorToolEngine 的同次计算）
    // 金额口径守 v5.0.2 分界：逐笔走 SignedMoneyText（符号＋语义双色），
    // 差值/合计等「算出来的数」保持墨色；条形只作视觉编码（收随双色
    // 与图表系列同口径），条旁数字仍墨色。

    @ViewBuilder
    private func toolCard(_ card: AdvisorCard, messageID: AdvisorChatMessage.ID) -> some View {
        switch card {
        case .person(let payload):
            toolPersonCard(payload)
        case .records(let payload):
            recordsCard(payload)
        case .comparison(let payload):
            comparisonCard(payload)
        case .groups(let payload):
            groupsCard(payload)
        case .totals(let payload):
            totalsCard(payload)
        case .pending(let payload):
            toolPendingCard(payload)
        case .events(let payload):
            eventsCard(payload)
        case .draftRecord(let payload):
            draftRecordCard(payload, messageID: messageID)
        }
    }

    /// 人物卡：复用 v4.4 人物卡外壳（点头像行进人物详情），内容＝差额大字＋最近往来
    private func toolPersonCard(_ payload: AdvisorPersonCard) -> some View {
        personCard(summary: payload.summary) {
            VStack(alignment: .leading, spacing: LiqianMetrics.spacingS) {
                balanceFigure(payload.summary)
                if !payload.recent.isEmpty {
                    VStack(alignment: .leading, spacing: LiqianMetrics.spacingXS) {
                        ForEach(payload.recent) { line in
                            entryLineRow(line)
                        }
                    }
                }
            }
        }
    }

    /// 逐笔流水卡：限量行＋总数提示（还有更多时在卡尾说明）
    private func recordsCard(_ payload: AdvisorRecordsCard) -> some View {
        VStack(alignment: .leading, spacing: LiqianMetrics.spacingS) {
            cardTitle("逐笔记录")
            ForEach(payload.rows) { row in
                toolRecordRow(row)
            }
            if payload.totalCount > payload.rows.count {
                Text("共 \(payload.totalCount) 笔，上面是最近 \(payload.rows.count) 笔")
                    .font(.footnote)
                    .foregroundStyle(Palette.stone)
            }
        }
        .liqianCardSurface()
    }

    /// 流水行（流水卡与备礼清单共用）：日期＋人名/簿名＋待送出素签＋逐笔金额（双色语义）
    private func toolRecordRow(_ row: AdvisorRecordRow) -> some View {
        HStack(spacing: LiqianMetrics.spacingS) {
            Text(LiqianDate.displayString(for: row.date))
                .font(.footnote)
                .foregroundStyle(Palette.stone)
                .frame(width: 86, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(row.person)
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                let sub = [row.ledgerTitle, row.ledgerType]
                    .filter { !$0.isEmpty }
                    .joined(separator: " · ")
                if !sub.isEmpty {
                    Text(sub)
                        .font(.footnote)
                        .foregroundStyle(Palette.stone)
                        .lineLimit(1)
                }
            }
            Spacer()
            if row.isPendingSend {
                PendingTag(bai: row.ledgerType == LiqianConstants.baiType)
            }
            SignedMoneyText(
                cents: row.amountCents,
                direction: row.direction,
                bai: row.ledgerType == LiqianConstants.baiType,
                style: .body
            )
        }
        .frame(minHeight: LiqianMetrics.minTapTarget)
    }

    /// 对比卡：两期各一组双条（收/随），底部给三项差值（墨色，主 − 对比）
    private func comparisonCard(_ payload: AdvisorComparisonCard) -> some View {
        let scale = max(
            payload.main.receivedCents, payload.main.givenCents,
            payload.other.receivedCents, payload.other.givenCents, 1
        )
        return VStack(alignment: .leading, spacing: LiqianMetrics.spacingSM) {
            cardTitle("时段对比")
            comparisonBlock(totals: payload.main, scale: scale)
            comparisonBlock(totals: payload.other, scale: scale)
            // v5.3.2 统计格定版：三项差值等分居中、数字在上
            StatRow {
                StatCell(label: "收礼差", value: deltaText(payload.deltaReceivedCents), style: .body)
                StatCell(label: "随礼差", value: deltaText(payload.deltaGivenCents), style: .body)
                StatCell(label: "净差", value: deltaText(payload.deltaNetCents), style: .body)
            }
        }
        .liqianCardSurface()
    }

    private func comparisonBlock(totals: AdvisorMoneyTotals, scale: Int) -> some View {
        VStack(alignment: .leading, spacing: LiqianMetrics.spacingXS) {
            HStack(spacing: LiqianMetrics.spacingS) {
                Text(totals.rangeLabel)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                Spacer()
                Text("\(totals.recordCount) 笔")
                    .font(.footnote)
                    .foregroundStyle(Palette.stone)
            }
            barRow(label: "收", cents: totals.receivedCents, scale: scale, color: Palette.moneyReceived)
            barRow(label: "随", cents: totals.givenCents, scale: scale, color: Palette.moneyGiven)
        }
    }

    /// 分组条卡：一组一小节（组名＋笔数＋收/随双条），条长按全卡最大值归一
    private func groupsCard(_ payload: AdvisorGroupsCard) -> some View {
        let scale = max(payload.rows.map { max($0.receivedCents, $0.givenCents) }.max() ?? 1, 1)
        return VStack(alignment: .leading, spacing: LiqianMetrics.spacingS) {
            cardTitle(groupsTitle(payload.dimension), detail: payload.rangeLabel)
            if payload.rows.isEmpty {
                Text("这个范围里还没有记录。")
                    .font(.footnote)
                    .foregroundStyle(Palette.stone)
            } else {
                ForEach(payload.rows) { row in
                    VStack(alignment: .leading, spacing: LiqianMetrics.spacingXS) {
                        HStack(spacing: LiqianMetrics.spacingS) {
                            Text(row.key)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Palette.ink)
                                .lineLimit(1)
                            Spacer()
                            Text("\(row.recordCount) 笔")
                                .font(.footnote)
                                .foregroundStyle(Palette.stone)
                        }
                        barRow(label: "收", cents: row.receivedCents, scale: scale, color: Palette.moneyReceived)
                        barRow(label: "随", cents: row.givenCents, scale: scale, color: Palette.moneyGiven)
                    }
                }
            }
        }
        .liqianCardSurface()
    }

    private func groupsTitle(_ dimension: String) -> String {
        switch dimension {
        case "month": return "按月汇总"
        case "year": return "按年汇总"
        case "type": return "按场合汇总"
        case "relation": return "按关系汇总"
        case "ledger": return "按礼簿汇总"
        default: return "分组汇总"
        }
    }

    /// 汇总卡：单时段总计（收/随双大数墨色＋笔数），与时段卡同语汇
    private func totalsCard(_ payload: AdvisorTotalsCard) -> some View {
        VStack(alignment: .leading, spacing: LiqianMetrics.spacingS) {
            cardTitle("汇总", detail: payload.totals.rangeLabel)
            // v5.3.2 统计格定版：两格等分居中、数字在上（旧标签在上
            // 左排，与全 App 统一口径翻正）
            StatRow {
                StatCell(
                    label: "收礼",
                    value: LedgerMath.fmtMoney(cents: payload.totals.receivedCents),
                    style: .title2
                )
                StatCell(
                    label: "随礼",
                    value: LedgerMath.fmtMoney(cents: payload.totals.givenCents),
                    style: .title2
                )
            }
            Text("共 \(payload.totals.recordCount) 笔")
                .font(.footnote)
                .foregroundStyle(Palette.stone)
        }
        .liqianCardSurface()
    }

    /// 待回名单卡（工具版）：逐行姓名＋待回额（SignedMoney 语义），点行直达人物
    private func toolPendingCard(_ payload: AdvisorPendingCard) -> some View {
        VStack(alignment: .leading, spacing: LiqianMetrics.spacingS) {
            HStack(alignment: .firstTextBaseline, spacing: LiqianMetrics.spacingS) {
                Text("待回名单")
                    .font(.headline)
                    .foregroundStyle(Palette.ink)
                Spacer()
                if payload.totalPeople > 0 {
                    Text("共 \(payload.totalPeople) 人 · 合计 \(LedgerMath.fmtMoney(cents: payload.totalPendingCents))")
                        .font(.footnote)
                        .foregroundStyle(Palette.stone)
                        .lineLimit(1)
                }
            }
            if payload.people.isEmpty {
                Text("没有待回的，都结清了。")
                    .font(.footnote)
                    .foregroundStyle(Palette.stone)
            } else {
                ForEach(payload.people) { p in
                    Button {
                        personRoute = PeopleView.NameRoute(name: p.name)
                    } label: {
                        HStack(spacing: LiqianMetrics.spacingS) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(p.name)
                                    .foregroundStyle(Palette.ink)
                                    .lineLimit(1)
                                if !p.relation.isEmpty {
                                    Text(p.relation)
                                        .font(.footnote)
                                        .foregroundStyle(Palette.stone)
                                }
                            }
                            Spacer()
                            SignedMoneyText(
                                cents: p.pendingCents,
                                direction: LiqianConstants.received,
                                style: .title3
                            )
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
                if payload.totalPeople > payload.people.count {
                    Text("还有 \(payload.totalPeople - payload.people.count) 人没列全，去「往来」页看完整名单")
                        .font(.footnote)
                        .foregroundStyle(Palette.stone)
                }
            }
        }
        .liqianCardSurface()
    }

    /// 场次卡：近期场次（名称/事由日期/剩余天数）＋备礼进度（待送出逐笔行）
    private func eventsCard(_ payload: AdvisorEventsCard) -> some View {
        VStack(alignment: .leading, spacing: LiqianMetrics.spacingS) {
            cardTitle("近期场次")
            if payload.events.isEmpty && payload.prep.isEmpty {
                Text("近期没有安排，备礼清单也是空的。")
                    .font(.footnote)
                    .foregroundStyle(Palette.stone)
            }
            ForEach(payload.events) { event in
                HStack(spacing: LiqianMetrics.spacingS) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(event.title)
                            .font(.body.weight(.semibold))
                            .foregroundStyle(Palette.ink)
                            .lineLimit(1)
                        Text("\(event.type) · \(LiqianDate.displayString(for: event.date))")
                            .font(.footnote)
                            .foregroundStyle(Palette.stone)
                    }
                    Spacer()
                    if event.daysUntil == 0 {
                        Text("就是今天")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Palette.primary)
                    } else if event.daysUntil > 0 {
                        Text("还有 \(event.daysUntil) 天")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Palette.primary)
                    }
                }
                .frame(minHeight: LiqianMetrics.minTapTarget)
            }
            if !payload.prep.isEmpty {
                Text("备礼进度：\(payload.prepTotalCount) 笔待送出")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Palette.ink)
                    .padding(.top, LiqianMetrics.spacingXS)
                ForEach(payload.prep) { row in
                    toolRecordRow(row)
                }
            }
        }
        .liqianCardSurface()
    }

    // MARK: - 待确认记账卡（v5.4：AI 只起草，确认才入账）

    /// 候选礼簿：非示例簿（@Query 已按日期倒序）；改选与兜底都从这里取
    private var draftLedgerCandidates: [Ledger] {
        let sample = SampleData.sampleIDs(ledgers: ledgers)
        return ledgers.filter { !sample.contains($0.id) }
    }

    /// 草稿生效的目标礼簿：卡上已选 ＞ 工具建议（仍在候选内）＞ 日期最新非示例簿
    private func effectiveDraftLedger(_ draft: AdvisorDraftRecordCard) -> Ledger? {
        let candidates = draftLedgerCandidates
        if let wanted = draft.chosenLedgerID ?? draft.suggestedLedgerID,
           let hit = candidates.first(where: { $0.id == wanted }) {
            return hit
        }
        return candidates.first
    }

    @ViewBuilder
    private func draftRecordCard(_ draft: AdvisorDraftRecordCard, messageID: AdvisorChatMessage.ID) -> some View {
        VStack(alignment: .leading, spacing: LiqianMetrics.spacingS) {
            switch draft.state {
            case .pending:
                draftPendingBody(draft, messageID: messageID)
            case .saved:
                draftSavedBody(draft)
            case .discarded:
                HStack(spacing: LiqianMetrics.spacingS) {
                    Image(systemName: "xmark.circle")
                        .foregroundStyle(Palette.stone)
                    Text("已取消这笔：\(draft.person) \(draft.direction) \(LedgerMath.fmtMoney(cents: draft.amountCents))，没有入账。")
                        .font(.footnote)
                        .foregroundStyle(Palette.stone)
                }
            }
        }
        .liqianCardSurface()
    }

    @ViewBuilder
    private func draftPendingBody(_ draft: AdvisorDraftRecordCard, messageID: AdvisorChatMessage.ID) -> some View {
        let target = effectiveDraftLedger(draft)
        cardTitle("待确认记账", detail: "核对后点确认才入账")
        draftField(label: "人名", value: draft.relation.isEmpty ? draft.person : "\(draft.person)（\(draft.relation)）")
        HStack(spacing: LiqianMetrics.spacingS) {
            Text("金额")
                .font(.footnote)
                .foregroundStyle(Palette.stone)
                .frame(width: 56, alignment: .leading)
            SignedMoneyText(
                cents: draft.amountCents,
                direction: draft.direction,
                bai: draft.ledgerType == LiqianConstants.baiType,
                style: .title3
            )
            Text(draft.direction)
                .font(.footnote)
                .foregroundStyle(Palette.stone)
        }
        draftField(label: "日期", value: LiqianDate.displayString(for: draft.date))
        if !draft.ledgerType.isEmpty {
            draftField(label: "场合", value: draft.ledgerType)
        }
        HStack(spacing: LiqianMetrics.spacingS) {
            Text("记入")
                .font(.footnote)
                .foregroundStyle(Palette.stone)
                .frame(width: 56, alignment: .leading)
            if draftLedgerCandidates.isEmpty {
                Text("还没有可记的礼簿，先去新建一本礼簿")
                    .font(.footnote)
                    .foregroundStyle(Palette.danger)
            } else {
                Menu {
                    ForEach(draftLedgerCandidates) { ledger in
                        Button {
                            updateDraft(messageID: messageID, draftID: draft.draftID) {
                                $0.chosenLedgerID = ledger.id
                            }
                        } label: {
                            if ledger.id == target?.id {
                                Label(ledger.title, systemImage: "checkmark")
                            } else {
                                Text(ledger.title)
                            }
                        }
                    }
                } label: {
                    HStack(spacing: LiqianMetrics.spacingXS) {
                        Text(target?.title ?? "")
                            .foregroundStyle(Palette.ink)
                            .lineLimit(1)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Palette.stone)
                    }
                }
            }
            Spacer()
        }
        HStack(spacing: LiqianMetrics.spacingS) {
            Button {
                confirmDraft(draft, messageID: messageID)
            } label: {
                Text("确认入账")
                    .frame(minHeight: LiqianMetrics.minTapTarget)
                    .padding(.horizontal, LiqianMetrics.spacingSM)
            }
            .buttonStyle(.glassProminent)
            .tint(Palette.primary)
            .disabled(target == nil)
            Button {
                updateDraft(messageID: messageID, draftID: draft.draftID) { $0.state = .discarded }
            } label: {
                Text("算了")
                    .frame(minHeight: LiqianMetrics.minTapTarget)
                    .padding(.horizontal, LiqianMetrics.spacingSM)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Palette.stone)
        }
    }

    /// 回执形态：已入账＋摘要＋查看这笔（打开既有记录详情/编辑页）
    @ViewBuilder
    private func draftSavedBody(_ draft: AdvisorDraftRecordCard) -> some View {
        let saved = draft.savedRecordID.flatMap { id in records.first { $0.id == id } }
        let ledgerTitle = ledgers.first { $0.id == draft.chosenLedgerID }?.title
            ?? draft.suggestedLedgerTitle
        HStack(spacing: LiqianMetrics.spacingS) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(Palette.success)
            Text("已入账")
                .font(.headline)
                .foregroundStyle(Palette.ink)
            Spacer()
            SignedMoneyText(
                cents: draft.amountCents,
                direction: draft.direction,
                bai: draft.ledgerType == LiqianConstants.baiType,
                style: .body
            )
        }
        Text("\(draft.person) · \(draft.direction) · \(LiqianDate.displayString(for: draft.date))\(ledgerTitle.isEmpty ? "" : " · 记入《\(ledgerTitle)》")")
            .font(.footnote)
            .foregroundStyle(Palette.stone)
        if let saved {
            Button {
                editingRecord = saved
            } label: {
                HStack(spacing: LiqianMetrics.spacingXS) {
                    Text("查看这笔")
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                }
                .frame(minHeight: LiqianMetrics.minTapTarget)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Palette.primary)
        } else {
            Text("这笔记录已不在账本里（可能后来被删除）。")
                .font(.footnote)
                .foregroundStyle(Palette.stone)
        }
    }

    private func draftField(label: String, value: String) -> some View {
        HStack(spacing: LiqianMetrics.spacingS) {
            Text(label)
                .font(.footnote)
                .foregroundStyle(Palette.stone)
                .frame(width: 56, alignment: .leading)
            Text(value)
                .foregroundStyle(Palette.ink)
                .lineLimit(1)
            Spacer()
        }
    }

    /// 确认入账：与 RecordFormView.save() 同一数据路径——同一个
    /// GiftRecord 构造＋modelContext.insert/save，字段口径一致
    /// （随礼/回礼都是已发生的事，status 恒已送出；方式缺省现金与
    /// 表单默认一致；关系缺失回退表单默认「朋友」）。不另起一套构造。
    private func confirmDraft(_ draft: AdvisorDraftRecordCard, messageID: AdvisorChatMessage.ID) {
        guard draft.state == .pending, let ledger = effectiveDraftLedger(draft) else { return }
        let record = GiftRecord(
            ledgerID: ledger.id,
            person: draft.person,
            relation: draft.relation.isEmpty ? "朋友" : draft.relation,
            amountCents: draft.amountCents,
            direction: draft.direction,
            method: "现金",
            note: "",
            date: draft.date,
            status: LiqianConstants.sentStatus
        )
        modelContext.insert(record)
        try? modelContext.save()
        updateDraft(messageID: messageID, draftID: draft.draftID) {
            $0.state = .saved
            $0.chosenLedgerID = ledger.id
            $0.savedRecordID = record.id
        }
        answerTrigger += 1
    }

    /// 按 draftID 定位并回写某张草稿卡的状态（改选礼簿/确认/取消共用）；
    /// messages 变更会经 onChange 自动回写持久化文件
    private func updateDraft(
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
    }

    /// 卡片标题行（工具卡共用）：标题＋可选弱说明
    private func cardTitle(_ title: String, detail: String? = nil) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: LiqianMetrics.spacingS) {
            Text(title)
                .font(.headline)
                .foregroundStyle(Palette.ink)
            if let detail {
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(Palette.stone)
                    .lineLimit(1)
            }
            Spacer()
        }
    }

    /// 双色条行：签＋归一条＋墨色金额（条色是视觉编码，数字守汇总墨色口径）
    private func barRow(label: String, cents: Int, scale: Int, color: Color) -> some View {
        HStack(spacing: LiqianMetrics.spacingS) {
            Text(label)
                .font(.footnote)
                .foregroundStyle(Palette.stone)
                .frame(width: 16, alignment: .leading)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Palette.line.opacity(0.55))
                    RoundedRectangle(cornerRadius: 3)
                        .fill(color)
                        .frame(
                            width: cents > 0
                                ? max(geo.size.width * CGFloat(cents) / CGFloat(scale), 4)
                                : 0
                        )
                }
            }
            .frame(height: 8)
            Text(LedgerMath.fmtMoney(cents: cents))
                .font(.liqianMoney(.footnote))
                .foregroundStyle(Palette.ink)
                .lineLimit(1)
                .frame(minWidth: 72, alignment: .trailing)
        }
    }

    /// 差值文案：带 +/- 号的墨色金额（0 不带号）；减号用数学减号与 signedMoney 同口径
    private func deltaText(_ cents: Int) -> String {
        if cents == 0 { return LedgerMath.fmtMoney(cents: 0) }
        return (cents > 0 ? "+" : "−") + LedgerMath.fmtMoney(cents: abs(cents))
    }

    // MARK: - 结果卡片（v4.4 降级管线；数字全部来自 AdvisorEngine 的本地计算）

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
                // v5.3.2 统计格定版：两格等分居中、数字在上；收礼数
                // 沿用本卡现状 primary 色（口径沿用现状，不借机改色）
                StatRow {
                    StatCell(
                        label: "收礼",
                        value: LedgerMath.fmtMoney(cents: received),
                        style: .title2,
                        color: Palette.primary
                    )
                    StatCell(
                        label: "随礼",
                        value: LedgerMath.fmtMoney(cents: given),
                        style: .title2
                    )
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
        messages.append(AdvisorChatMessage(kind: .user(question)))
        isAsking = true
        activityText = "正在查账…"
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
               let answer = await answerWithTools(question: question, context: toolContext) {
                isAsking = false
                activityText = nil
                messages.append(AdvisorChatMessage(kind: .answer(text: answer.text, cards: answer.cards)))
                answerTrigger += 1
                return
            }
            let intent = await resolveIntent(question: question, people: names)
            if let intent {
                isAsking = false
                activityText = nil
                messages.append(AdvisorChatMessage(kind: .result(
                    AdvisorEngine.execute(intent, entries: entries)
                )))
                answerTrigger += 1
                return
            }
            // v5.7 收敛段（永不沉默）：意图/规则都兜不住时，先过通用
            // 作答 lane 让模型用自身知识回答账外问题；再由收敛器裁决
            // 最终出口——通用回答 / 未开通兜底卡 / 真故障致歉，三者
            // 必居其一，不再有「消息挂着没回复」的第四种结果。
            let aiReady = AIAccess.readiness() == .ready
            let general = aiReady ? await answerGenerally(question: question) : nil
            isAsking = false
            activityText = nil
            switch AdvisorReplyConvergence.resolve(aiReady: aiReady, generalAnswer: general) {
            case .generalAnswer(let text):
                messages.append(AdvisorChatMessage(kind: .answer(text: text, cards: [])))
            case .unsupportedWithoutAI:
                messages.append(AdvisorChatMessage(kind: .result(.unsupported)))
            case .failureApology:
                messages.append(AdvisorChatMessage(kind: .note(
                    AdvisorReplyConvergence.failureApologyText
                )))
            }
            answerTrigger += 1
        }
    }

    /// 通用作答 lane（v5.7）：无工具的纯文本对话，账外问题（天气/
    /// 常识/礼仪/闲聊/用法请教）在这里由模型用自身知识回答。
    /// 任何失败（网络/接口/空回复）返回 nil，交收敛器落致歉兜底，
    /// 本函数自己不吞不编。
    private func answerGenerally(question: String) async -> String? {
        guard let client = try? DeepSeekClient() else { return nil }
        activityText = "正在整理回答…"
        do {
            let text = try await client.chatText(system: Self.generalSystemPrompt, user: question)
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        } catch {
            return nil
        }
    }

    /// 通用作答提示词：账外 lane 的纪律——用自身知识答、实时信息
    /// 先声明拿不到再给常识、不编账目数据、不许诺没有的 App 功能。
    private static let generalSystemPrompt = """
        你是「礼记」的问账管家。用户刚问的这个问题与他的人情礼金账无关，或者账里没有答案。用你自己的知识直接、简洁、口语化地回答，不要提「查账」「工具」，不要假装查过他的账，也不要把用户推开说「我只管账目」。
        需要实时信息才能答准的问题（实时天气、新闻、价格行情等）：先明说你拿不到实时数据，再给常识性的回答或建议；不许编造具体的实时数值，也不许只说「查不到」就结束。
        不要编造用户账本里的任何金额、人名和记录。被问到这个 App 怎么用时，只介绍它确实有的功能：记人情账、问账查账、待回提醒、礼谱与报表导出、语音和拍照记账；没有的功能不要许诺。
        """

    /// 工具问答轮数上限：模型最多连查 4 轮工具，防死循环烧额度
    private static let maxToolRounds = 4

    /// 工具问答主循环：模型决定调什么工具 → 本地 AdvisorToolEngine 执行 →
    /// 结果回填 → 直到模型给出文字答复。任何异常返回 nil（调用方降级）。
    /// v5.3：执行走 executeDetailed 同步收集 UI 卡片（同次计算，不另查账），
    /// 并按当前工具更新过程状态文案；轮数耗尽时卡片随 nil 一起丢弃，
    /// 整条回答完整落回 v4.4 卡片管线，不拼半成品。
    private func answerWithTools(
        question: String, context: AdvisorToolContext
    ) async -> (text: String, cards: [AdvisorCard])? {
        guard let client = try? DeepSeekClient() else { return nil }
        var thread: [DeepSeekChatMessage] = [
            DeepSeekChatMessage(role: "system", content: Self.toolSystemPrompt(today: context.today)),
            DeepSeekChatMessage(role: "user", content: question),
        ]
        var cards: [AdvisorCard] = []
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

    /// 过程状态文案（按工具映射的人话）：让用户看见它正在翻哪本账，
    /// 不再黑箱等。query_person 尽量带上人名（参数里解析，失败回通用文案）。
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

    /// 工具问答系统提示词：问答纪律写死——数字只能来自工具结果，
    /// 查不到就明说，回答带数据口径出处。
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

/// 卡片依次浮入（v5.3）：按序号错开淡入＋轻上浮，走 Motion 令牌；
/// Reduce Motion 时无延迟无位移、直接终态。
private struct CardInModifier: ViewModifier {
    let index: Int
    let reduceMotion: Bool

    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: reduceMotion ? 0 : (shown ? 0 : 10))
            .task {
                if reduceMotion {
                    shown = true
                    return
                }
                // 首卡 0.12s、其后每张 +0.12s：与结论打字机并行浮入，不抢读
                try? await Task.sleep(nanoseconds: UInt64(120_000_000 * Double(index + 1)))
                if Task.isCancelled { return }
                withAnimation(MotionTokens.pageCrossfade) { shown = true }
            }
    }
}

/// 结论文字（v5.3）：Markdown 渲染＋本地打字机揭示。
/// 揭示切的是「渲染后」的 AttributedString——先整段解析再按字数裁剪，
/// 粗体等格式在每一帧都完整，不会打出半个 **；客户端不做流式协议，
/// 揭示纯在本地。解析失败兜底为去标记纯文本：宁可无格式，也不露星号。
/// Reduce Motion 时整段直出。
private struct TypewriterMarkdownText: View {
    let markdown: String
    /// 揭示进度回调（节流后触发，父视图据此把本条钉在底部）
    var onReveal: () -> Void = {}

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var full: AttributedString?
    @State private var revealed = 0

    var body: some View {
        Group {
            if let full {
                Text(slice(full))
            }
        }
        .task(id: markdown) {
            let rendered = Self.render(markdown)
            full = rendered
            let total = NSAttributedString(rendered).length
            if reduceMotion {
                revealed = total
                return
            }
            revealed = 0
            var count = 0
            while count < total {
                count = min(total, count + 3)
                revealed = count
                if count % 24 == 0 { onReveal() }
                try? await Task.sleep(nanoseconds: 16_000_000)
                if Task.isCancelled { return }
            }
            onReveal()
        }
    }

    private func slice(_ attributed: AttributedString) -> AttributedString {
        let ns = NSAttributedString(attributed)
        guard revealed < ns.length else { return attributed }
        return AttributedString(
            ns.attributedSubstring(from: NSRange(location: 0, length: max(revealed, 0)))
        )
    }

    /// Markdown → AttributedString（完整语法：粗体/列表/链接）；
    /// 失败兜底去标记纯文本（见 stripped）
    static func render(_ markdown: String) -> AttributedString {
        var options = AttributedString.MarkdownParsingOptions()
        options.interpretedSyntax = .full
        if let parsed = try? AttributedString(markdown: markdown, options: options) {
            return parsed
        }
        return AttributedString(stripped(markdown))
    }

    /// 去标记兜底：剥 ** / __ / ` 与行首的标题符、列表符，
    /// 保证任何情况下屏幕上不出现 Markdown 源码标记
    static func stripped(_ markdown: String) -> String {
        let flat = markdown
            .replacingOccurrences(of: "**", with: "")
            .replacingOccurrences(of: "__", with: "")
            .replacingOccurrences(of: "`", with: "")
        return flat
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { line in
                var s = line.trimmingCharacters(in: .whitespaces)
                while s.hasPrefix("#") { s.removeFirst() }
                if s.hasPrefix("- ") || s.hasPrefix("* ") { s.removeFirst(2) }
                return s.trimmingCharacters(in: .whitespaces)
            }
            .joined(separator: "\n")
    }
}
