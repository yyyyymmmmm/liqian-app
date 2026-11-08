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
//
// 闪退再审（v5.4，用户真机点麦克风仍闪退后的逐行审计，新隐患点）：
// ③ 授权链没有「作废」机制：stop()/页面消失后，在途的语音→麦克风两段
//    授权回调仍会继续调 beginSession()，在已离开的页面上启动音频引擎，
//    甚至与下一个页面的转写器抢同一个 AVAudioSession。修法：代际计数，
//    stop() 必递增代际，每段异步回调落地前先验代际，过期直接丢弃。
// ④ tap 回调（音频线程）的 append 与 stop() 的 endAudio 存在竞争窗口：
//    removeTap 返回时可能仍有一个在途 buffer，endAudio 之后再 append
//    会抛 NSException（SFSpeech 的经典崩点，do/catch 拦不住）。修法：
//    原子接受旗——stop() 先关旗、再摘 tap、最后 endAudio；tap 内先验旗。
// ⑤ setCategory(.record, options: .duckOthers)：该 option 与 record
//    类别组合不合法会抛 AVAudioSession 错误（虽被 catch 成报错、不算
//    闪退，但属无谓失败点）。修法：去掉该 option。
// ⑥ stop() 无条件访问 inputNode：从未启动过也去摘 tap 会凭空创建输入
//    节点；在无输入路由的极端状态下查节点有抛异常的报告。修法：
//    tapInstalled 标记，没装过 tap 的 stop 完全不碰引擎。
// ⑦ recognizer 在 init 时只建一次：系统语音服务中途掉线后 isAvailable
//    状态可能过期。修法：每次 start 现建实例并判空＋判 isAvailable。
// 以上 ③–⑦ 为代码审计推定，真机崩溃日志未到手，待真机验（V54-NOTES）。
//
// 闪退三审（v5.4.1，用户装 v5.4 后真机仍闪退、且「没弹权限申请」）：
// ⑧ 执行者陷阱（强候选）：授权已决时，requestAuthorization /
//    requestRecordPermission 的回调由 TCC 在 XPC 回复线程投递；闭包若被
//    编译器推断为 @MainActor 隔离（在本类内书写即如此），回调入口会触发
//    swift_task_isCurrentExecutor → dispatch_assert_queue_fail
//    （EXC_BREAKPOINT）——已授权用户点麦克风不弹框、直接闪退，与反馈
//    严丝合缝（公开同形案例：emergent-inc/mosaic 的 iOS dictation 修复
//    commit）。修法：先同步读 authorizationStatus() / recordPermission，
//    已决直接走（零回调）；只有未决才发请求，且请求经 nonisolated 桥。
// ⑨ setActive(true, options: .notifyOthersOnDeactivation)：该 option
//    文档上只对停用有效，激活时传它在严格执法的系统上会抛错。修法：
//    激活不带 option（停用侧保留）。
// ⑩ recognizer 现建后是局部变量、recognitionTask 期间无人强引用：
//    补 activeRecognizer 属性持有到 stop()。
// 另全程埋 MicTrace 面包屑（步号见各 mark 调用），下次再闪退，设置页
// 诊断行会显示死在哪一步——本轮目标是修掉或让它自报，不再猜。

@MainActor
final class SpeechTranscriber: ObservableObject {
    @Published var isRecording = false
    /// 授权/启动进行中：这段时间 toggle() 忽略点击，视图据此禁用按钮
    @Published var isStarting = false
    @Published var errorText: String?
    var onText: ((String) -> Void)?

    private let audioEngine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    /// 本轮识别器的强引用（隐患 ⑩）：beginSession 现建后持有到 stop()，
    /// 防止识别途中实例被释放
    private var activeRecognizer: SFSpeechRecognizer?
    /// 面包屑会话已武装：start() 置位、stop() 据此决定要不要 close，
    /// 防止从未启动过的 stop()（如页面 onDisappear）抹掉上次的取证标记
    private var traceArmed = false
    /// 首个识别结果只落一次面包屑
    private var didTraceFirstResult = false
    /// 音频会话已由本类激活（stop 时据此 deactivate，不误关他人状态）
    private var sessionActivated = false
    /// tap 已装标记：stop 只在真装过时才碰 inputNode（隐患 ⑥）
    private var tapInstalled = false
    /// 代际计数：stop()/新一轮 start() 都会推进；在途异步回调落地前
    /// 先验代际，过期回调直接丢弃（隐患 ③）
    private var generation = 0
    /// tap 接受旗（音频线程与主线程共享）：false 后 tap 不再 append（隐患 ④）
    private let bufferGate = OSAllocatedUnfairLock<Bool>(initialState: false)

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
        traceArmed = true
        didTraceFirstResult = false
        MicTrace.mark(step: 1, "点麦克风·开始启动")
        // 先同步探一次可用性（隐患 ⑦）；识别器实例不跨异步链传递
        // （Swift 6 并发：SFSpeechRecognizer 非 Sendable，正式实例在
        // beginSession 里现建）
        guard let probe = SFSpeechRecognizer(locale: Locale(identifier: "zh-CN")),
              probe.isAvailable else {
            MicTrace.mark(step: 2, "识别器探针", detail: "不可用")
            errorText = "语音识别暂时不可用，可直接输入文字。"
            // 这是优雅失败不是闪退：关掉面包屑会话，免得设置页误报诊断行
            traceArmed = false
            MicTrace.close(reason: "识别器不可用，未启动")
            return
        }
        MicTrace.mark(step: 2, "识别器探针", detail: "可用")
        isStarting = true
        generation += 1
        let gen = generation

        // 隐患 ⑧ 同步快路：先同步读两项授权状态。都已决（授权过或
        // 已拒绝）就直接分流、一个异步回调都不发——执行者陷阱专挑
        // 「已决还走回调」触发，已授权用户点麦克风不弹框也正出于此。
        let speechStatus = SFSpeechRecognizer.authorizationStatus()
        let micPermission = AVAudioApplication.shared.recordPermission
        MicTrace.mark(
            step: 3, "同步读授权状态",
            detail: "语音=\(speechStatus.rawValue) 麦克风=\(micPermission.rawValue)"
        )
        switch speechStatus {
        case .denied, .restricted:
            failStart("语音识别未获得权限，可直接输入文字；如需使用，请在系统设置中开启。")
            return
        case .authorized:
            break
        case .notDetermined:
            requestSpeechAuthorization(generation: gen)
            return
        @unknown default:
            failStart("语音识别暂时不可用，可直接输入文字。")
            return
        }
        // 语音已授权，再分流麦克风
        switch micPermission {
        case .granted:
            MicTrace.mark(step: 6, "麦克风已授权（同步快路）")
            beginSession(generation: gen)
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

    /// 语音未决才走这条：请求回调经 nonisolated 桥投递（隐患 ⑧），
    /// 闭包是 @Sendable 非隔离的，回主执行者靠显式 Task 切换
    private func requestSpeechAuthorization(generation gen: Int) {
        MicTrace.mark(step: 4, "请求语音授权")
        Self.requestSpeechAuthorizationBridge { [weak self] status in
            Task { @MainActor in
                guard let self, self.generation == gen else { return }
                MicTrace.mark(step: 5, "语音授权回调", detail: "status=\(status.rawValue)")
                guard status == .authorized else {
                    self.failStart("语音识别未获得权限，可直接输入文字；如需使用，请在系统设置中开启。")
                    return
                }
                // 麦克风同样先同步分流（可能已在语音祝福处授权/拒绝过），
                // 只有未决才发请求回调
                switch AVAudioApplication.shared.recordPermission {
                case .granted:
                    MicTrace.mark(step: 6, "麦克风已授权（同步快路）")
                    self.beginSession(generation: gen)
                case .denied:
                    self.failStart("麦克风未获得权限，可直接输入文字；如需使用，请在系统设置中开启。")
                case .undetermined:
                    self.requestMicPermission(generation: gen)
                @unknown default:
                    self.failStart("麦克风暂时不可用，可直接输入文字。")
                }
            }
        }
    }

    private func requestMicPermission(generation gen: Int) {
        MicTrace.mark(step: 6, "请求麦克风授权")
        Self.requestRecordPermissionBridge { [weak self] granted in
            Task { @MainActor in
                guard let self, self.generation == gen else { return }
                MicTrace.mark(step: 7, "麦克风授权回调", detail: "granted=\(granted)")
                guard granted else {
                    self.failStart("麦克风未获得权限，可直接输入文字；如需使用，请在系统设置中开启。")
                    return
                }
                self.beginSession(generation: gen)
            }
        }
    }

    /// nonisolated 授权桥：TCC 回调在 XPC 回复线程投递，桥函数与回调
    /// 都不带主执行者隔离，杜绝回调入口的执行者断言陷阱（隐患 ⑧）
    nonisolated static func requestSpeechAuthorizationBridge(
        completion: @escaping @Sendable (SFSpeechRecognizerAuthorizationStatus) -> Void
    ) {
        SFSpeechRecognizer.requestAuthorization(completion)
    }

    nonisolated static func requestRecordPermissionBridge(
        completion: @escaping @Sendable (Bool) -> Void
    ) {
        AVAudioApplication.requestRecordPermission(completion)
    }

    private func beginSession(generation gen: Int) {
        guard generation == gen else { return }
        MicTrace.mark(step: 10, "进入 beginSession")
        // 正式识别器在本方法内现建（主线程上下文，不跨异步边界），
        // 并由 activeRecognizer 持有到 stop()（隐患 ⑩）
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "zh-CN")),
              recognizer.isAvailable else {
            failStart("语音识别暂时不可用，可直接输入文字。")
            return
        }
        activeRecognizer = recognizer
        do {
            let session = AVAudioSession.sharedInstance()
            // 隐患 ⑤：.duckOthers 与 .record 组合不合法，去掉该 option
            try session.setCategory(.record, mode: .measurement)
            // 隐患 ⑨：.notifyOthersOnDeactivation 只对停用有效，激活不带
            try session.setActive(true)
            sessionActivated = true
            MicTrace.mark(step: 11, "音频会话已激活")

            let input = audioEngine.inputNode
            let format = input.outputFormat(forBus: 0)
            MicTrace.mark(
                step: 12, "读取输入格式",
                detail: "\(Int(format.sampleRate))Hz/\(format.channelCount)ch"
            )
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
            if tapInstalled {
                input.removeTap(onBus: 0)
                tapInstalled = false
            }
            let gate = bufferGate
            gate.withLock { $0 = true }
            input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
                // 隐患 ④：endAudio 之后再 append 会抛异常，先验接受旗
                guard gate.withLock({ $0 }) else { return }
                request.append(buffer)
            }
            tapInstalled = true
            MicTrace.mark(step: 13, "已装 tap")
            audioEngine.prepare()
            try audioEngine.start()
            MicTrace.mark(step: 14, "引擎已启动")
            isRecording = true
            isStarting = false

            task = recognizer.recognitionTask(with: request) { [weak self] result, error in
                Task { @MainActor in
                    guard let self, self.generation == gen else { return }
                    if let result {
                        if !self.didTraceFirstResult {
                            self.didTraceFirstResult = true
                            MicTrace.mark(step: 15, "首个识别结果")
                        }
                        self.onText?(result.bestTranscription.formattedString)
                    }
                    if error != nil || result?.isFinal == true {
                        MicTrace.mark(
                            step: 16, "识别结束回调",
                            detail: error != nil ? "带 error" : "isFinal"
                        )
                        self.stop()
                    }
                }
            }
        } catch {
            MicTrace.mark(step: 99, "beginSession 异常", detail: error.localizedDescription)
            errorText = "录音启动失败：\(error.localizedDescription)。可直接输入文字。"
            stop()
        }
    }

    func stop() {
        // 代际推进：在途授权/识别回调自此全部作废（隐患 ③）
        generation += 1
        // 先关接受旗，tap 立刻停止 append，再动引擎与请求（隐患 ④ 的顺序）
        bufferGate.withLock { $0 = false }
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        // 没装过 tap 就完全不碰 inputNode（隐患 ⑥）；装过必摘，
        // 否则中途失败残留的 tap 会让下一次启动必崩
        if tapInstalled {
            audioEngine.inputNode.removeTap(onBus: 0)
            tapInstalled = false
        }
        request?.endAudio()
        task?.cancel()
        request = nil
        task = nil
        activeRecognizer = nil
        if sessionActivated {
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            sessionActivated = false
        }
        isRecording = false
        isStarting = false
        // 面包屑收尾：只有真启动过的会话才 close，没启动过的 stop()
        // 不许抹掉上次闪退留下的未结束标记（取证完整性）
        if traceArmed {
            traceArmed = false
            MicTrace.close(reason: "会话正常结束")
        }
    }
}
