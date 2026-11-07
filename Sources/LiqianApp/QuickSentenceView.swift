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

/// 一句话记账：说一句或打一行「张三随了五百，微信」，DeepSeek 解析成一笔，
/// 只把结果预填回记一笔表单，由用户核对后自己点保存——绝不自动落库。
struct QuickSentenceView: View {
    /// 解析成功回调（父视图把结果填进表单字段）
    var onParsed: (QuickSentenceResult) -> Void

    @Environment(\.dismiss) private var dismiss
    @StateObject private var transcriber = SpeechTranscriber()
    @State private var text = ""
    @State private var isParsing = false
    @State private var errorText: String?
    @State private var showGuide = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(
                        "如：张三随了五百，微信",
                        text: $text,
                        prompt: Text("如：张三随了五百，微信"),
                        axis: .vertical
                    )
                    .lineLimit(2...4)
                    HStack(spacing: 12) {
                        Button {
                            transcriber.toggle()
                        } label: {
                            Label(
                                transcriber.isRecording ? "停止录音" : "语音输入",
                                systemImage: transcriber.isRecording ? "stop.circle.fill" : "mic"
                            )
                            .foregroundStyle(transcriber.isRecording ? .red : Palette.primary)
                            .frame(minHeight: LiqianMetrics.minTapTarget)
                        }
                        .buttonStyle(.plain)
                        Spacer()
                        if transcriber.isRecording {
                            Text("正在听，说完点停止…")
                                .font(.system(size: 12.5))
                                .foregroundStyle(Palette.stone)
                        }
                    }
                    if let speechError = transcriber.errorText {
                        Text(speechError)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                    Text("将把这句话发送至 DeepSeek 解析，解析完只预填表单，你核对后自己保存。")
                        .font(.system(size: 12.5))
                        .foregroundStyle(Palette.stone)
                }

                if let errorText {
                    Section {
                        Text(errorText)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }

                Section {
                    Button {
                        Task { await parse() }
                    } label: {
                        HStack {
                            Text("解析并预填")
                            if isParsing {
                                Spacer()
                                ProgressView()
                            }
                        }
                        .frame(maxWidth: .infinity, minHeight: LiqianMetrics.minTapTarget)
                    }
                    .disabled(isParsing || text.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Palette.paper.ignoresSafeArea())
            .navigationTitle("一句话记账")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
            .alert("AI 还没准备好", isPresented: $showGuide) {
                Button("好") {}
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
            let result = try Self.validate(data)
            isParsing = false
            onParsed(result)
            dismiss()
        } catch let error as DeepSeekError {
            isParsing = false
            errorText = error.errorDescription
        } catch let error as QuickSentenceParseError {
            isParsing = false
            errorText = error.errorDescription
        } catch {
            isParsing = false
            errorText = "解析失败：\(error.localizedDescription)"
        }
    }

    private static let systemPrompt = """
        你是礼钱账本的记账助手。用户会说一句中文人情往来记录，请提取成一笔，只输出一个 JSON 对象，不要输出任何其他文字：{"name":"","amountYuan":数字,"relation":null,"method":null,"direction":"received","eventHint":null}
        规则：1) name 姓名照抄原文，绝不猜测或改名；2) amountYuan 是金额数字，单位元，中文数字要换算（如「五百」=500、「一千二」=1200、「八百八」=880）；3) direction：别人送给记账人是 "received"，记账人送出去是 "given"，看不出给 "received"；4) relation 只能是 亲戚/朋友/同事/同学/邻居/其他 之一，看不出给 null；5) method 只能是 现金/微信/支付宝/银行转账/实物 之一，看不出给 null；6) eventHint 是事由（如 婚礼/满月/乔迁），没有就给 null；7) 实在提取不到姓名或金额时 name 给空字符串、amountYuan 给 0，不要编造。
        """

    private struct RawResult: Decodable {
        var name: String
        var amountYuan: Double
        var relation: String?
        var method: String?
        var direction: String?
        var eventHint: String?
    }

    /// 本地校验：姓名非空、金额 > 0 才算成功，绝不静默吞
    private static func validate(_ data: Data) throws -> QuickSentenceResult {
        let raw: RawResult
        do {
            raw = try JSONDecoder().decode(RawResult.self, from: data)
        } catch {
            throw QuickSentenceParseError.unreadable
        }
        let name = raw.name.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, raw.amountYuan > 0 else {
            throw QuickSentenceParseError.incomplete
        }
        return QuickSentenceResult(
            name: name,
            amountCents: Int((raw.amountYuan * 100.0).rounded()),
            relation: raw.relation.flatMap { LiqianConstants.relations.contains($0) ? $0 : nil },
            method: raw.method.flatMap { LiqianConstants.methods.contains($0) ? $0 : nil },
            direction: raw.direction == "given" ? LiqianConstants.given : LiqianConstants.received,
            eventHint: raw.eventHint?.trimmingCharacters(in: .whitespaces).nonEmpty
        )
    }
}

private enum QuickSentenceParseError: LocalizedError {
    case unreadable
    case incomplete

    var errorDescription: String? {
        switch self {
        case .unreadable:
            return "DeepSeek 的返回看不懂，换个说法再试，或者直接在表单里手填。"
        case .incomplete:
            return "这句话里没读出姓名或金额，补全一点再试，如「张三随了五百，微信」。"
        }
    }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}

// MARK: - 语音转写（Speech 框架，zh-CN；权限被拒/不可用都给人话，文本输入始终可用）

@MainActor
final class SpeechTranscriber: ObservableObject {
    @Published var isRecording = false
    @Published var errorText: String?
    var onText: ((String) -> Void)?

    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "zh-CN"))
    private let audioEngine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?

    func toggle() {
        if isRecording {
            stop()
        } else {
            start()
        }
    }

    func start() {
        errorText = nil
        guard recognizer?.isAvailable == true else {
            errorText = "这台手机的语音识别暂时不可用，直接打字就行。"
            return
        }
        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            Task { @MainActor in
                guard let self else { return }
                guard status == .authorized else {
                    self.errorText = "语音识别没给权限，直接打字就行；要用的话去系统设置里打开。"
                    return
                }
                AVAudioApplication.requestRecordPermission { granted in
                    Task { @MainActor in
                        guard granted else {
                            self.errorText = "麦克风没给权限，直接打字就行；要用的话去系统设置里打开。"
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
            errorText = "这台手机的语音识别暂时不可用，直接打字就行。"
            return
        }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true, options: .notifyOthersOnDeactivation)

            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true
            self.request = request

            let input = audioEngine.inputNode
            let format = input.outputFormat(forBus: 0)
            input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
                request.append(buffer)
            }
            audioEngine.prepare()
            try audioEngine.start()
            isRecording = true

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
            errorText = "录音没启动起来：\(error.localizedDescription)。直接打字就行。"
            stop()
        }
    }

    func stop() {
        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }
        request?.endAudio()
        task?.cancel()
        request = nil
        task = nil
        if isRecording {
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
        isRecording = false
    }
}
