import AVFoundation
import Speech
import SwiftUI
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
                            transcriber.toggle()
                        } label: {
                            Label(
                                transcriber.isRecording
                                    ? "停止录音"
                                    : (transcriber.isStarting ? "正在启动…" : "语音输入"),
                                systemImage: transcriber.isRecording ? "stop.circle.fill" : "mic"
                            )
                            // 符号动效枚举点：录音中麦克风 .pulse（审计 §3.5）
                            .symbolEffect(.pulse, isActive: transcriber.isRecording)
                            .foregroundStyle(transcriber.isRecording ? Palette.danger : Palette.primary)
                            .frame(minHeight: LiqianMetrics.minTapTarget)
                        }
                        .buttonStyle(.plain)
                        .disabled(transcriber.isStarting)
                        Spacer()
                        if transcriber.isRecording {
                            Text("正在听，说完点停止…")
                                .font(.footnote)
                                .foregroundStyle(Palette.stone)
                        } else if transcriber.isStarting {
                            Text("正在启动麦克风…")
                                .font(.footnote)
                                .foregroundStyle(Palette.stone)
                        }
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
            .onAppear {
                transcriber.onText = { text = $0 }
            }
            .onDisappear {
                transcriber.stop()
            }
        }
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

// MARK: - 语音转写（Speech 框架，zh-CN；权限被拒/不可用都给人话，文本输入始终可用）
//
// 闪退加固（v2.7）：AVAudioEngine 装 tap 有两类 Swift do/catch 拦不住的 NSException——
// ① 输入格式无效（硬件路由未就绪时 sampleRate/channelCount 为 0）时 installTap；
// ② 同一 bus 上重复 installTap。旧代码两条都可能踩：授权回调是异步的，
// isRecording 在引擎真正启动前一直是 false，用户连点或授权慢时 start() 会重入，
// 且 stop() 只在引擎运行时摘 tap，启动中途失败残留的 tap 会让下一次启动必崩。
// 修法：isStarting 重入闸门、装 tap 前校验格式并先摘旧 tap、stop() 无条件摘 tap。

@MainActor
final class SpeechTranscriber: ObservableObject {
    @Published var isRecording = false
    /// 授权/启动进行中：这段时间 toggle() 忽略点击，视图据此禁用按钮
    @Published var isStarting = false
    @Published var errorText: String?
    var onText: ((String) -> Void)?

    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "zh-CN"))
    private let audioEngine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    /// 音频会话已由本类激活（stop 时据此 deactivate，不误关他人状态）
    private var sessionActivated = false

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
        guard let recognizer, recognizer.isAvailable else {
            errorText = "语音识别暂时不可用，可直接输入文字。"
            return
        }
        isStarting = true
        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            Task { @MainActor in
                guard let self else { return }
                guard status == .authorized else {
                    self.isStarting = false
                    self.errorText = "语音识别未获得权限，可直接输入文字；如需使用，请在系统设置中开启。"
                    return
                }
                AVAudioApplication.requestRecordPermission { granted in
                    Task { @MainActor in
                        guard granted else {
                            self.isStarting = false
                            self.errorText = "麦克风未获得权限，可直接输入文字；如需使用，请在系统设置中开启。"
                            return
                        }
                        self.beginSession()
                    }
                }
            }
        }
    }

    private func beginSession() {
        guard let recognizer, recognizer.isAvailable else {
            isStarting = false
            errorText = "语音识别暂时不可用，可直接输入文字。"
            return
        }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true, options: .notifyOthersOnDeactivation)
            sessionActivated = true

            let input = audioEngine.inputNode
            let format = input.outputFormat(forBus: 0)
            // 格式没就绪就装 tap 会触发 AVFAudio 的 NSException（catch 不住、直接闪退），先拦下
            guard format.sampleRate > 0, format.channelCount > 0 else {
                errorText = "麦克风暂时不可用，可直接输入文字。"
                stop()
                return
            }

            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true
            self.request = request

            // 装之前先摘可能残留的旧 tap：同一 bus 只许一个 tap，重复装同样是 NSException
            input.removeTap(onBus: 0)
            input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
                request.append(buffer)
            }
            audioEngine.prepare()
            try audioEngine.start()
            isRecording = true
            isStarting = false

            task = recognizer.recognitionTask(with: request) { [weak self] result, error in
                Task { @MainActor in
                    guard let self else { return }
                    if let result {
                        self.onText?(result.bestTranscription.formattedString)
                    }
                    if error != nil || result?.isFinal == true {
                        self.stop()
                    }
                }
            }
        } catch {
            errorText = "录音启动失败：\(error.localizedDescription)。可直接输入文字。"
            stop()
        }
    }

    func stop() {
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        // 不管引擎跑没跑都摘 tap，否则中途失败残留的 tap 会让下一次启动必崩
        audioEngine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        task?.cancel()
        request = nil
        task = nil
        if sessionActivated {
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            sessionActivated = false
        }
        isRecording = false
        isStarting = false
    }
}
