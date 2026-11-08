import AVFoundation
import Speech
import SwiftUI
import os
import LiqianCore
import LiqianDesign

/// 一句话解析结果（金额已换算成分，方向已映射成本地口径 收礼/随礼）
struct QuickSentenceResult {
    var name: String
    var amountCents: Int
    var relation: String?
    var method: String?
    /// LiqianConstants.received / .given
    var direction: String
    var eventHint: String?
}

/// 一句话记账：说一句或打一段「大舅2000，二姨1000，张三给了500」，DeepSeek 拆成多笔，
/// 在本页逐笔核对（姓名/金额/方向可改、行可删），点「保存全部（N 笔）」后由记一笔表单
/// 的保存通道一次落库并落印。本页不直接写库；只解析出 1 笔时也是同一份列表（N=1）。
struct QuickSentenceView: View {
    /// 确认保存回调（父视图沿用既有保存通道一次落库全部记录）
    var onConfirm: ([QuickSentenceResult]) -> Void

    @Environment(\.dismiss) private var dismiss
    @StateObject private var transcriber = SpeechTranscriber()
    @State private var text = ""
    /// 语音面板（v5.6）：点麦克风开会话＋面板，完成回填、取消不落字
    @State private var showVoicePanel = false
    @State private var isParsing = false
    @State private var errorText: String?
    @State private var showGuide = false
    /// 解析后的待确认行（已过滤无效条目）；hasParsed 为 false 时不展示确认区
    @State private var rows: [EditableRow] = []
    @State private var hasParsed = false
    /// 被 AIParse 标为无效（缺姓名/金额）而略过的条数，明示给用户不静默吞
    @State private var skippedCount = 0

    /// 待确认行：姓名/金额（元）/方向可改，其余字段随保存带走
    private struct EditableRow: Identifiable {
        let id = UUID()
        var name: String
        var amountText: String
        var direction: String
        var relation: String?
        var method: String?
        var eventHint: String?

        init(record: AIParse.Record) {
            name = record.name
            amountText = record.amountCents % 100 == 0
                ? "\(record.amountCents / 100)"
                : String(format: "%.2f", Double(record.amountCents) / 100.0)
            direction = record.direction
            relation = record.relation
            method = record.method
            eventHint = record.eventHint
        }

        /// 改完后的行再校验一次：姓名非空、金额 > 0 才允许保存
        func toResult() -> QuickSentenceResult? {
            let trimmedName = name.trimmingCharacters(in: .whitespaces)
            let yuan = Double(amountText.trimmingCharacters(in: .whitespaces))
            guard !trimmedName.isEmpty, let yuan, yuan > 0 else { return nil }
            return QuickSentenceResult(
                name: trimmedName,
                amountCents: Int((yuan * 100.0).rounded()),
                relation: relation,
                method: method,
                direction: direction,
                eventHint: eventHint
            )
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(
                        "如：大舅2000，二姨1000",
                        text: $text,
                        prompt: Text("如：大舅2000，二姨1000，张三给了500"),
                        axis: .vertical
                    )
                    .lineLimit(2...4)
                    HStack(spacing: LiqianMetrics.spacingSM) {
                        Button {
                            openVoicePanel()
                        } label: {
                            Label(
                                transcriber.isStarting ? "正在启动…" : "语音输入",
                                systemImage: "mic"
                            )
                            // 符号动效枚举点：录音中麦克风 .pulse（审计 §3.5）
                            .symbolEffect(.pulse, isActive: transcriber.isRecording)
                            .foregroundStyle(transcriber.isRecording ? Palette.danger : Palette.primary)
                            .frame(minHeight: LiqianMetrics.minTapTarget)
                        }
                        .buttonStyle(.plain)
                        .disabled(transcriber.isStarting)
                        Spacer()
                    }
                    if let speechError = transcriber.errorText {
                        Text(speechError)
                            .font(.footnote)
                            .foregroundStyle(Palette.danger)
                    }
                    Text("将把这段话发送至 DeepSeek 解析。一句话里有几笔就拆几笔，逐笔核对后一次保存。")
                        .font(.footnote)
                        .foregroundStyle(Palette.stone)
                }

                if let errorText {
                    Section {
                        Text(errorText)
                            .font(.footnote)
                            .foregroundStyle(Palette.danger)
                    }
                }

                Section {
                    Button {
                        Task { await parse() }
                    } label: {
                        HStack {
                            Text(hasParsed ? "重新解析" : "解析")
                            if isParsing {
                                Spacer()
                                ProgressView()
                            }
                        }
                        .frame(maxWidth: .infinity, minHeight: LiqianMetrics.minTapTarget)
                    }
                    .disabled(isParsing || text.trimmingCharacters(in: .whitespaces).isEmpty)
                }

                if hasParsed {
                    confirmSections
                }
            }

            .navigationTitle("一句话记账")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
            .alert("AI 还没准备好", isPresented: $showGuide) {
                Button("去设置") {
                    NotificationCenter.default.post(name: .liqianOpenAISettings, object: nil)
                }
                Button("好", role: .cancel) {}
            } message: {
                Text(AIAccess.readiness().guideMessage)
            }
            .sheet(isPresented: $showVoicePanel, onDismiss: {
                // 兜底：面板被非正常关掉（系统回收等）时若会话还在，
                // 按取消处理——停录且不交付，本次文本丢弃
                if transcriber.isRecording || transcriber.isStarting {
                    transcriber.cancelTranscription()
                }
            }) {
                VoiceInputPanel(
                    transcriber: transcriber,
                    onFinish: { finalText in
                        // 提交语义同 v5.5.1 的 onText 末态：全文进
                        // 文本框，待用户点「解析」走原解析流
                        text = finalText
                        showVoicePanel = false
                    },
                    onCancel: { showVoicePanel = false }
                )
            }
            .onDisappear {
                transcriber.stop()
            }
        }
    }

    /// 语音面板入口（v5.6）：先启动转写会话、再上面板；启动即失败
    /// （设备不支持等）时面板呈现异常态＋关闭钮，不静默无反应
    private func openVoicePanel() {
        guard !transcriber.isRecording, !transcriber.isStarting else { return }
        transcriber.start()
        showVoicePanel = true
    }

    // MARK: - 待确认列表：逐行可改可删，底部一次保存全部

    @ViewBuilder
    private var confirmSections: some View {
        Section {
            if rows.isEmpty {
                Text("没有要保存的记录了。改一下说法，点「重新解析」再试。")
                    .font(.footnote)
                    .foregroundStyle(Palette.stone)
            } else {
                ForEach($rows) { $row in
                    rowEditor($row)
                }
            }
            if skippedCount > 0 {
                Text("另有 \(skippedCount) 条没读出姓名或金额，已略过。")
                    .font(.footnote)
                    .foregroundStyle(Palette.warning)
            }
        } header: {
            Text("待确认（\(rows.count) 笔）")
        }

        if !rows.isEmpty {
            Section {
                Button {
                    saveAll()
                } label: {
                    Text("保存全部（\(rows.count) 笔）")
                        .frame(maxWidth: .infinity, minHeight: LiqianMetrics.minTapTarget)
                }
            }
        }
    }

    private func rowEditor(_ row: Binding<EditableRow>) -> some View {
        VStack(alignment: .leading, spacing: LiqianMetrics.spacingS) {
            HStack(spacing: LiqianMetrics.spacingS) {
                TextField("姓名", text: row.name, prompt: Text("姓名"))
                HStack(spacing: 2) {
                    Text("¥")
                        .foregroundStyle(Palette.stone)
                    TextField("金额", text: row.amountText, prompt: Text("金额"))
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 96)
                }
                Button(role: .destructive) {
                    let id = row.wrappedValue.id
                    rows.removeAll { $0.id == id }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Palette.stone)
                        .frame(minHeight: LiqianMetrics.minTapTarget)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("删掉这一笔")
            }
            Picker("方向", selection: row.direction) {
                Text("收礼").tag(LiqianConstants.received)
                Text("随礼").tag(LiqianConstants.given)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
    }

    private func saveAll() {
        let results = rows.compactMap { $0.toResult() }
        guard results.count == rows.count else {
            errorText = "有记录缺姓名或金额，改好、或删掉那一行再保存。"
            return
        }
        guard !results.isEmpty else { return }
        errorText = nil
        onConfirm(results)
        dismiss()
    }

    private func parse() async {
        let sentence = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sentence.isEmpty else { return }
        switch AIAccess.readiness() {
        case .ready:
            break
        case .noKey, .notEnabled:
            showGuide = true
            return
        }
        transcriber.stop()
        isParsing = true
        errorText = nil
        do {
            let client = try DeepSeekClient()
            let data = try await client.chatJSON(system: Self.systemPrompt, user: sentence)
            let outcome = try AIParse.decode(data)
            isParsing = false
            let valid = outcome.validRecords
            guard !valid.isEmpty else {
                // 0 笔可用：明确提示，不静默、也不进确认态
                hasParsed = false
                rows = []
                skippedCount = 0
                errorText = "没听出可记的账，换个说法试试。"
                return
            }
            skippedCount = outcome.invalidCount
            rows = valid.map { EditableRow(record: $0) }
            hasParsed = true
        } catch let error as DeepSeekError {
            isParsing = false
            errorText = error.errorDescription
        } catch is AIParse.ParseError {
            isParsing = false
            errorText = "AI 返回内容格式异常，无法解析。请重试，或直接在表单中填写。"
        } catch {
            isParsing = false
            errorText = "解析失败：\(error.localizedDescription)"
        }
    }

    private static let systemPrompt = """
        你是礼记的记账助手。用户会说一段中文人情往来记录，可能一句话里包含好几个人、多笔账（也可能只有一笔），也可能是多行文本。请把每一笔都提取出来，只输出一个 JSON 对象，不要输出任何其他文字：{"records":[{"name":"","amountYuan":数字,"relation":null,"method":null,"direction":"received","eventHint":null}]}
        规则：1) 有几笔就给几条，如「大舅2000，二姨1000，张三给了500」要返回 3 条；多行文本逐行逐笔提取，不要把多人合并成一条；2) name 姓名照抄原文，绝不猜测或改名；3) amountYuan 是金额数字，单位元，中文数字要换算（如「五百」=500、「一千二」=1200、「八百八」=880）；4) direction：别人送给记账人是 "received"，记账人送出去是 "given"，看不出给 "received"；5) relation 只能是 亲戚/朋友/同事/同学/邻居/其他 之一，看不出给 null；6) method 只能是 现金/微信/支付宝/银行转账/实物 之一，看不出给 null；7) eventHint 是事由（如 婚礼/满月/乔迁），没有就给 null；8) 某笔实在提取不到姓名或金额时，那条 name 给空字符串、amountYuan 给 0，不要编造，也不要因为一笔读不出就丢掉其他笔。
        """
}

// MARK: - 语音转写（v5.5 起：SpeechAnalyzer 新框架，zh-CN，全程本机识别）
//
// 【旧链退役说明】v5.4.2 及以前的实时链是 AVAudioEngine tap →
// SFSpeechAudioBufferRecognitionRequest.append → SFSpeechRecognizer
// recognitionTask。真机闪退连追四轮（v2.7 加固、v5.4 五修、v5.4.1 授权
// 同步快路、v5.4.2 启动次序翻正），黑匣子面包屑最终钉死：v5.4.2 装机
// 后仍停在「#14 引擎已启动」——engine.start() 成功，首个 buffer 落标、
// 0.5 秒存活标、首个结果全都没到达。四轮的共同分母只剩旧管线本身，
// 按 V542-NOTES 预案整链换实现，本类内部不再出现 SFSpeechRecognizer /
// SFSpeechAudioBufferRecognitionRequest / recognitionTask。
//
// 【新链形状】（API 形状按苹果官方文档核对，出处见 docs/V55-NOTES.md）
// Speech.SpeechTranscriber（新框架转写模块，全名避与本类同名冲突）
// + Speech.SpeechAnalyzer（actor 会话）+ AsyncStream<AnalyzerInput>
// 喂入；音频仍经 AVAudioEngine 采音，逐 buffer 用 AVAudioConverter
// 转到 SpeechAnalyzer.bestAvailableAudioFormat 后喂入——分析器不替
// 调用方做任何格式转换（官方文档明示）。结果走 module.results
// 异步序列：volatile（未定稿）整体替换、final 顺序拼接，累积逻辑在
// LiqianCore.TranscriptAccumulator（可单测），onText 仍是「每次给
// 全量文本」，与旧链语义一致，两个调用方（一句话记账、AI 问账）
// 零改动。
//
// 【选型】模块选 SpeechTranscriber 不选 DictationTranscriber：前者是
// 苹果为取代 SFSpeechRecognizer 推出的新一代本机模型（WWDC25 277），
// 官方实时采音示例用的正是它＋volatile 结果；后者复用旧听写模型、
// 定位是老设备/语言兜底。设备硬件不支持时（isAvailable == false）
// 给明确人话、不静默换引擎；DictationTranscriber 兜底留作后备方向，
// 记录在 V55-NOTES，本轮不做。
//
// 【隔离定版（v5.5.1）】v5.5 装机后仍闪退，用户发来两份 .ips 定罪：
// 异常同为 EXC_BREAKPOINT，栈同为 _dispatch_assert_queue_fail ←
// swift_task_isCurrentExecutor——本类是 @MainActor 隔离类型，在自身
// 方法里形成的闭包继承 MainActor 隔离、自带执行者断言序言，框架从
// 自有队列回调时正文一行未跑就被击杀（11-07 死于 TCC 授权回调、
// 11-08 死于 tap 闭包被音频队列调用）。修法是结构搬迁：采音喂入
// （引擎/tap/转换/输入流）整体搬进 nonisolated 的 AnalyzerFeeder，
// 本类只同步调用其 start/stop；语音功能内全部框架回调的清点与
// 去隔离结论见 docs/V551-NOTES.md。
//
// 【授权】新框架文档与官方示例均不要求语音识别授权（示例工程只声明
// 麦克风权限键）——本链只走麦克风授权，且沿用 v5.4.1 同步分流口径：
// 已决状态同步读、零回调，未决才经 nonisolated 桥发请求（避 TCC
// 回调执行者陷阱）。两个 static 桥保留：BlessingRecorder 仍在用
// requestRecordPermissionBridge（它属于祝福录音链，不在本轮范围）。
//
// 【资产】zh-CN 模型是系统托管资产：未安装时经 AssetInventory
// .assetInstallationRequest(supporting:) → downloadAndInstall() 正规
// 下载，过程经 isStarting/errorText 如实呈现；下载失败给明确文案，
// 不回退旧管线。locale 经 supportedLocale(equivalentTo:) 归一化
// （官方论坛口径：Locale(identifier:) 直造的 locale 可能对不上）。
//
// 【音频会话】按新框架官方示例口径改 .playAndRecord + .spokenAudio
// （旧链的 .record + .measurement 随旧链退役）；激活不带
// .notifyOthersOnDeactivation（只对停用有效，v5.4.1 ⑨）。
//
// 【面包屑步号（v5.5 新链）】1 点麦克风 → 2 新框架可用 → 3 同步读
// 麦克风授权 →（4 请求麦克风授权 → 5 授权回调）→ 6 麦克风已授权 →
// 20 资产状态 →（21 下载开始）→ 22 资产就绪 → 23 分析器格式就绪 →
// 24 音频会话已激活 → 25 输入格式 → 26 已装 tap → 27 分析器已启动 →
// 28 首个音频已喂入 → 29 首个识别结果 → 30 结果流结束/异常；
// 98 启动失败 / 99 启动异常。旧链步号 2–19 退役对照表见 V55-NOTES。
//
// 【v5.6 面板数据面】用户真机反馈 v5.5.1「能用但不专业：没有实时
// 转文字的可见过程、没有声纹」。本类在原有编排之上多发布四样东西
// 给 VoiceInputPanel：波形电平历史（feeder 在 tap 内算 RMS、经新增
// @Sendable 电平钩子推送，口径见 LiqianCore.VoiceLevelMath 与
// docs/V56-NOTES）、定稿/未定稿两段文本（累积器本来就分两段，本
// 轮只是同步发布）、已录秒数；并新增两个面板出口语义：
// finishTranscription（收尾冲刷后交付最终全文）与
// cancelTranscription（丢弃不交付）。onText 保留原语义继续回调
// （面板不再依赖它回填，两个调用方改走完成回调，见 V56-NOTES）。
// MicTrace 步号一字未动；feeder 隔离结构一字未动（电平钩子是既有
// @Sendable 钩子范式的第三个实例，tap 捕获名单只增两个 Sendable 值）。

@MainActor
final class SpeechTranscriber: ObservableObject {
    @Published var isRecording = false
    /// 授权/资产准备/启动/收尾进行中：视图据此禁用按钮
    @Published var isStarting = false
    @Published var errorText: String?
    var onText: ((String) -> Void)?

    // MARK: 语音面板数据面（v5.6）
    /// 波形电平历史（旧→新）：feeder 经电平钩子推送、本类回主执行者
    /// 追加，环形保留最近 waveformCapacity 个（面板柱数同一口径）
    @Published private(set) var waveformLevels: [Float] = []
    /// 已定稿文本（面板墨色段）：与 TranscriptAccumulator.finalizedText 同步
    @Published private(set) var finalizedText = ""
    /// 未定稿文本（面板灰色段）：与 TranscriptAccumulator.volatileText 同步
    @Published private(set) var volatileText = ""
    /// 已录秒数（面板计时）：录音开始点起算、0.25 秒刷新
    @Published private(set) var elapsedSeconds = 0
    /// 波形柱数＝环形缓冲容量（面板 VoiceWaveformView 引用同一口径）
    static let waveformCapacity = 42

    /// 采音喂入（nonisolated，v5.5.1）：引擎/tap/转换/输入流全在
    /// AnalyzerFeeder 里，本类只同步调它的启动/收尾方法——隔离
    /// 红线见该文件头与 docs/V551-NOTES.md
    private let feeder = AnalyzerFeeder()
    private var analyzer: Speech.SpeechAnalyzer?
    private var module: Speech.SpeechTranscriber?
    /// analyzer.start(inputSequence:) 是否已成功返回（收尾时据此决定
    /// 要不要 finalize：未启动过的分析器直接释放即可，官方文档口径
    /// 「调用 finish 方法或释放分析器」二选一）
    private var analyzerStarted = false
    private var resultsTask: Task<Void, Never>?
    private var setupTask: Task<Void, Never>?
    private var teardownTask: Task<Void, Never>?
    /// 结果累积（Core 纯逻辑）：定稿拼接＋volatile 替换
    private var accumulator = TranscriptAccumulator()
    /// 面包屑会话已武装：start() 置位、收尾据此决定要不要 close，
    /// 防止从未启动过的 stop()（如页面 onDisappear）抹掉上次取证标记
    private var traceArmed = false
    /// 首个识别结果只落一次面包屑
    private var didTraceFirstResult = false
    /// 代际计数：stop()/新一轮 start() 都会推进；授权/资产等在途异步
    /// 回调落地前先验代际，过期直接丢弃（旧链隐患 ③，沿用）
    private var generation = 0
    /// 结果消费令牌：stop 收尾的 finalize flush 完成前保持有效，让
    /// 最后一句的 final 结果仍能送达 onText；收尾完成后推进作废
    private var sessionToken = 0
    /// 计时任务（v5.6）：录音开始时建、收尾时取消；起点单独存，
    /// elapsedSeconds 只是它的显示值
    private var elapsedTask: Task<Void, Never>?
    private var recordingStartedAt: Date?
    /// 面板「完成」的待交付回调（v5.6）：点完成时登记、收尾 finalize
    /// 冲刷完成后以 accumulator 全文交付一次；「取消」不登记，文本
    /// 随会话丢弃、不落任何输入框
    private var pendingFinish: ((String) -> Void)?

    func toggle() {
        if isRecording {
            stop()
        } else if !isStarting {
            start()
        }
    }

    func start() {
        guard !isRecording, !isStarting else { return }
        errorText = nil
        // 面板数据面清零（v5.6）：面板一打开就是干净的波形/文本/计时
        waveformLevels = []
        finalizedText = ""
        volatileText = ""
        elapsedSeconds = 0
        module = nil
        analyzer = nil
        analyzerStarted = false
        traceArmed = true
        didTraceFirstResult = false
        MicTrace.mark(step: 1, "点麦克风·开始启动")
        // 新框架硬件可用性是同步静态量：不支持直接给人话，不进异步链
        guard Speech.SpeechTranscriber.isAvailable else {
            errorText = "这台设备不支持新版语音识别，可直接输入文字。"
            traceArmed = false
            MicTrace.close(reason: "设备不支持新框架，未启动")
            return
        }
        MicTrace.mark(step: 2, "新框架可用", detail: "SpeechAnalyzer")
        isStarting = true
        generation += 1
        let gen = generation

        // 麦克风授权同步分流（沿用 v5.4.1 ⑧ 口径）：已决状态同步读、
        // 一个异步回调都不发；只有未决才经 nonisolated 桥发请求。
        let micPermission = AVAudioApplication.shared.recordPermission
        MicTrace.mark(
            step: 3, "同步读麦克风授权",
            detail: "麦克风=\(micPermission.rawValue)"
        )
        switch micPermission {
        case .granted:
            MicTrace.mark(step: 6, "麦克风已授权（同步快路）")
            beginSetup(generation: gen)
        case .denied:
            failStart("麦克风未获得权限，可直接输入文字；如需使用，请在系统设置中开启。")
        case .undetermined:
            requestMicPermission(generation: gen)
        @unknown default:
            failStart("麦克风暂时不可用，可直接输入文字。")
        }
    }

    /// 启动失败统一收尾：清 isStarting、给人话、面包屑留步后关闭会话
    private func failStart(_ message: String) {
        isStarting = false
        errorText = message
        MicTrace.mark(step: 98, "启动失败", detail: message)
        if traceArmed {
            traceArmed = false
            MicTrace.close(reason: "启动失败收尾")
        }
    }

    private func requestMicPermission(generation gen: Int) {
        MicTrace.mark(step: 4, "请求麦克风授权")
        Self.requestRecordPermissionBridge { [weak self] granted in
            Task { @MainActor in
                guard let self, self.generation == gen else { return }
                MicTrace.mark(step: 5, "麦克风授权回调", detail: "granted=\(granted)")
                guard granted else {
                    self.failStart("麦克风未获得权限，可直接输入文字；如需使用，请在系统设置中开启。")
                    return
                }
                self.beginSetup(generation: gen)
            }
        }
    }

    /// nonisolated 授权桥：TCC 回调在 XPC 回复线程投递，桥函数与回调
    /// 都不带主执行者隔离，杜绝回调入口的执行者断言陷阱（v5.4.1 ⑧）。
    /// requestSpeechAuthorizationBridge 本链已不用（新框架不要求语音
    /// 识别授权），保留供文件转写等旧路径按需取用；
    /// requestRecordPermissionBridge 仍被 BlessingRecorder 共用。
    nonisolated static func requestSpeechAuthorizationBridge(
        completion: @escaping @Sendable (SFSpeechRecognizerAuthorizationStatus) -> Void
    ) {
        SFSpeechRecognizer.requestAuthorization(completion)
    }

    nonisolated static func requestRecordPermissionBridge(
        completion: @escaping @Sendable (Bool) -> Void
    ) {
        AVAudioApplication.requestRecordPermission(completionHandler: completion)
    }

    /// 资产准备＋分析器启动都在异步阶段完成（isStarting 期间），
    /// 每段 await 之后验代际：stop() 已推进代际的，静默退出不碰状态。
    private func beginSetup(generation gen: Int) {
        setupTask = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.prepareAndStart(generation: gen)
            self.setupTask = nil
        }
    }

    private func prepareAndStart(generation gen: Int) async {
        // 1) locale 归一化：必须经 supportedLocale(equivalentTo:) 取
        //    系统认可的 locale 对象（官方论坛口径），nil = 不支持中文
        guard let locale = await Speech.SpeechTranscriber.supportedLocale(
            equivalentTo: Locale(identifier: "zh-CN")
        ) else {
            if generation == gen {
                failStart("语音识别不支持中文（普通话），可直接输入文字。")
            }
            return
        }
        guard generation == gen else { return }
        // 显式选项而非 preset：就要 volatile 实时结果＋时间范围属性，
        // 语义在代码里写死，不依赖 preset 的内部组合
        let module = Speech.SpeechTranscriber(
            locale: locale,
            transcriptionOptions: [],
            reportingOptions: [.volatileResults],
            attributeOptions: [.audioTimeRange]
        )
        self.module = module

        // 2) 资产：状态先查；未安装走 AssetInventory 正规下载流程，
        //    失败给明确文案、不回退旧管线
        let status = await Speech.AssetInventory.status(forModules: [module])
        guard generation == gen else { return }
        MicTrace.mark(step: 20, "语音模型资产状态", detail: "\(status)")
        switch status {
        case .unsupported:
            failStart("这台设备不支持中文语音模型，可直接输入文字。")
            return
        case .installed:
            MicTrace.mark(step: 22, "语音模型已就绪")
        case .supported, .downloading:
            errorText = "正在准备语音模型，首次使用需要下载，请保持网络畅通…"
            MicTrace.mark(step: 21, "语音模型下载开始")
            do {
                if let request = try await Speech.AssetInventory
                    .assetInstallationRequest(supporting: [module]) {
                    try await request.downloadAndInstall()
                }
            } catch {
                if generation == gen {
                    failStart("语音模型下载失败，请检查网络后重试；也可以直接输入文字。")
                }
                return
            }
            guard generation == gen else { return }
            errorText = nil
            MicTrace.mark(step: 22, "语音模型已就绪", detail: "下载完成")
        @unknown default:
            failStart("语音模型暂时不可用，可直接输入文字。")
            return
        }

        // 3) 分析器与目标格式：bestAvailableAudioFormat 必须在资产
        //    就绪后查（未装资产时官方文档明示返回 nil）
        let analyzer = Speech.SpeechAnalyzer(modules: [module])
        self.analyzer = analyzer
        guard let analyzerFormat = await Speech.SpeechAnalyzer
            .bestAvailableAudioFormat(compatibleWith: [module]) else {
            failStart("语音识别暂时不可用，可直接输入文字。")
            return
        }
        guard generation == gen else { return }
        MicTrace.mark(
            step: 23, "分析器格式就绪",
            detail: "\(Int(analyzerFormat.sampleRate))Hz/\(analyzerFormat.channelCount)ch"
        )

        // 输入流先建：tap 喂入与 analyzer.start 共用同一条流
        // （continuation 由 feeder 在 startCapture 里接管持有，收尾
        // 经 feeder.finishInput 结束，v5.5.1）
        let (stream, continuation) = AsyncStream<Speech.AnalyzerInput>.makeStream()

        // 4) 结果消费先行启动（官方示例次序：消费任务先于 start）
        sessionToken += 1
        let token = sessionToken
        accumulator.reset()
        resultsTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                for try await result in module.results {
                    guard self.sessionToken == token else { return }
                    if !self.didTraceFirstResult {
                        self.didTraceFirstResult = true
                        MicTrace.mark(step: 29, "首个识别结果")
                    }
                    self.accumulator.consume(
                        text: String(result.text.characters),
                        isFinal: result.isFinal
                    )
                    // 面板两段文本与累积器同步（v5.6）：定稿墨、未定稿灰
                    self.finalizedText = self.accumulator.finalizedText
                    self.volatileText = self.accumulator.volatileText
                    self.onText?(self.accumulator.text)
                }
                self.resultsEnded(token: token, error: nil)
            } catch {
                self.resultsEnded(token: token, error: error)
            }
        }

        // 5) 采音装配（会话＋tap＋转换器）整体在 nonisolated 的
        //    AnalyzerFeeder 里完成——tap 闭包绝不许在 @MainActor 类型
        //    的方法里形成（11-08 .ips 实锤：继承 MainActor 隔离、
        //    被音频线程调用时死在序言断言，见 docs/V551-NOTES.md），
        //    再启动分析器与引擎
        do {
            try feeder.startCapture(
                analyzerFormat: analyzerFormat,
                continuation: continuation,
                trace: { step, name, detail in
                    MicTrace.mark(step: step, name, detail: detail)
                },
                onFirstBuffer: { [weak self] in
                    // 首包钩子（@Sendable，音频线程触发）：只许建
                    // Task 回主执行者落 28，不许直接碰隔离状态
                    Task { @MainActor [weak self] in
                        guard let self, self.generation == gen else { return }
                        MicTrace.mark(step: 28, "首个音频已喂入分析器")
                    }
                },
                onLevel: { [weak self] level in
                    // 电平钩子（@Sendable，音频线程触发，v5.6）：同
                    // 首包钩子范式——只许建 Task 回主执行者追加波形
                    // 历史（环形截断），不许直接碰隔离状态
                    Task { @MainActor [weak self] in
                        guard let self, self.generation == gen else { return }
                        self.waveformLevels.append(level)
                        if self.waveformLevels.count > Self.waveformCapacity {
                            self.waveformLevels.removeFirst(
                                self.waveformLevels.count - Self.waveformCapacity
                            )
                        }
                    }
                }
            )
            try await analyzer.start(inputSequence: stream)
            analyzerStarted = true
            guard generation == gen else {
                teardownSession()
                return
            }
            try feeder.startEngine()
        } catch {
            MicTrace.mark(step: 99, "启动异常", detail: error.localizedDescription)
            errorText = "录音启动失败：\(error.localizedDescription)。可直接输入文字。"
            stop()
            return
        }
        MicTrace.mark(step: 27, "分析器已启动")
        isRecording = true
        isStarting = false
        // 面板计时（v5.6）：自录音开始点起算，0.25 秒一刷新；
        // teardownSession 收尾时取消。实时转写链没有 app 侧时长
        // 上限（既有口径即无上限），计时只报已录时长、不自设截断。
        recordingStartedAt = Date()
        elapsedSeconds = 0
        elapsedTask?.cancel()
        elapsedTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(250))
                guard let self, let startedAt = self.recordingStartedAt else { return }
                self.elapsedSeconds = Int(Date().timeIntervalSince(startedAt))
            }
        }
    }

    /// 结果流结束/异常的统一入口：正常收尾时 teardown 已在跑，这里
    /// 只处理「录音中结果流自己断了」的自发结束（给人话＋收尾）。
    private func resultsEnded(token: Int, error: Error?) {
        guard sessionToken == token else { return }
        if let error {
            MicTrace.mark(step: 30, "识别结果流异常", detail: error.localizedDescription)
            if isRecording {
                errorText = "语音识别中断了，可直接输入文字。"
            }
        } else {
            MicTrace.mark(step: 30, "识别结果流结束")
        }
        teardownSession()
    }

    func stop() {
        // 代际推进：授权/资产/启动的在途异步回调自此全部作废
        generation += 1
        setupTask?.cancel()
        setupTask = nil
        teardownSession()
    }

    /// 面板「完成」（v5.6）：停录，并在收尾 finalize 冲刷完成后以
    /// 最终全文回调交付一次——交付时点在 teardown 末尾，保证最后
    /// 一句的 final 结果也在内。语义与 v5.5.1 的 onText 末态一致：
    /// 一句话记账＝全文进文本框待解析、AI 问账＝全文进输入框待发送。
    /// 不在录音中调用时直接交付当前累积全文（面板只在录音中亮此钮，
    /// 此分支仅作兜底）。
    func finishTranscription(_ completion: @escaping (String) -> Void) {
        guard isRecording else {
            completion(accumulator.text)
            return
        }
        pendingFinish = completion
        stop()
    }

    /// 面板「取消」（v5.6）：停录并丢弃本次文本——不登记交付回调，
    /// 已转出的文字只活在面板展示状态里，下一轮 start() 即清零，
    /// 任何输入框都不会被它改动。
    func cancelTranscription() {
        pendingFinish = nil
        stop()
    }

    /// 「完成」交付的统一出口：登记过才交付、交付一次即注销
    private func deliverPendingFinish() {
        guard let finish = pendingFinish else { return }
        pendingFinish = nil
        finish(accumulator.text)
    }

    /// 收尾（幂等，stop 与结果流自发结束共用）：关接受旗 → 停引擎 →
    /// 摘 tap → finish 输入流 → finalize 冲刷最后结果（flush 期间结果
    /// 消费令牌保持有效，最后一句不丢）→ 取消消费任务 → 停用会话。
    private func teardownSession() {
        guard teardownTask == nil else { return }
        // 计时先停（v5.6）：无论有无会话残留都不许悬挂
        elapsedTask?.cancel()
        elapsedTask = nil
        recordingStartedAt = nil
        let hasSession = analyzer != nil || feeder.hasSessionArtifacts
            || isRecording
        isRecording = false
        guard hasSession else {
            isStarting = false
            deliverPendingFinish()
            return
        }
        // 收尾完成前保持 isStarting，挡住立刻重开与收尾打架
        isStarting = true
        // 关接受旗 → 停引擎 → 摘 tap（同步段，在 feeder 内完成）
        feeder.stopCapture()
        let feeder = self.feeder
        let analyzer = self.analyzer
        self.analyzer = nil
        let wasStarted = analyzerStarted
        analyzerStarted = false
        let token = sessionToken
        teardownTask = Task { @MainActor [weak self] in
            feeder.finishInput()
            if let analyzer, wasStarted {
                // 冲刷已喂入音频的最终结果；失败不挡收尾
                try? await analyzer.finalizeAndFinishThroughEndOfInput()
            }
            guard let self else { return }
            if self.sessionToken == token { self.sessionToken += 1 }
            self.resultsTask?.cancel()
            self.resultsTask = nil
            feeder.deactivateSession()
            self.module = nil
            self.teardownTask = nil
            self.isStarting = false
            // 面包屑收尾：只有真启动过的会话才 close，没启动过的
            // stop() 不许抹掉上次闪退留下的未结束标记（取证完整性）
            if self.traceArmed {
                self.traceArmed = false
                MicTrace.close(reason: "会话正常结束")
            }
            // 面板「完成」的全文交付（v5.6）：冲刷已完成、消费任务
            // 已取消，此刻的 accumulator.text 就是最终全文
            self.deliverPendingFinish()
        }
    }
}
