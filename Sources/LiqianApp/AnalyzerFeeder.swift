import AVFoundation
import Foundation
import LiqianCore
import os
import Speech

// MARK: - 分析器喂入（v5.5.1 隔离定版：采音整体搬出 @MainActor 隔离区）
//
// 【为什么有这个类】两份真机崩溃日志（.ips）定罪：麦克风闪退是
// EXC_BREAKPOINT——SpeechTranscriber 是 @MainActor 隔离类型，它在
// 自身方法里形成的闭包继承了 MainActor 隔离、自带执行者断言序言
// （swift_task_isCurrentExecutor）；框架从自有队列回调时，闭包正文
// 一行未跑就被断言击杀：
// - 2026-11-07 19:00:50：start() 的授权回调被 TCC 从 XPC 线程投递；
// - 2026-11-08 14:16:08：installCapture 的 tap 闭包被 AVFAudio 从
//   RealtimeMessenger 音频队列调用（故面包屑 28「首个音频已喂入」
//   永远落不下来——死在序言、没进正文）。
// 五轮修补（格式/次序/快路/换框架）全在闭包正文里，与序言无关，全灭。
//
// 【修法】采音喂入整体搬进本类：显式 nonisolated、无任何全局执行者
// 隔离（本工程亦无默认隔离设置，隔离只来自显式 @MainActor——本类
// 不带）。tap 闭包只在本类方法里形成，捕获列表是显式白名单：三个
// 锁、本次调用的局部值（converter/目标格式/continuation/首包钩子/
// 电平钩子），绝不捕获 SpeechTranscriber、绝不捕获本类实例（self）
// ——框架在任何线程调用它都没有隔离序言可断言。SpeechTranscriber
// （@MainActor、只管 UI 状态与编排）只同步调用本类的 start/stop 方法。
//
// 【线程模型】状态字段（continuation/tapInstalled/sessionActivated）
// 只在调用方串行上下文里读写：SpeechTranscriber 在 MainActor 上同步
// 直调 start/stop 系列方法，调用不跨 await、不换线程。音频（tap）
// 线程只碰三样东西：OSAllocatedUnfairLock 保护的接受旗/首包旗/电平
// 表状态，以及 tap 闭包捕获的局部值（continuation 是 Sendable 结构体、
// converter 只在 tap 串行调用里用）。类标 @unchecked Sendable 即按此
// 模型担责。

nonisolated final class AnalyzerFeeder: @unchecked Sendable {

    /// 面包屑钩子（步号 24/25/26）：startCapture 在调用方线程同步执行
    /// 时逐点回调，调用方据此落 MicTrace——落点次序与 v5.5 在
    /// installCapture 里直落一致（含失败点精度：哪一步抛错，之前的
    /// 步号已落、之后的没落）。
    typealias TraceHook = @Sendable (
        _ step: Int, _ name: String, _ detail: String
    ) -> Void

    /// 电平钩子（v5.6 面板声纹）：tap 在音频线程算好归一化电平
    /// （0...1、已过惯性平滑与推送节流）后触发，调用方据此回主
    /// 执行者追加波形历史——与 onFirstBuffer 同一 @Sendable 钩子范式。
    typealias LevelHook = @Sendable (_ level: Float) -> Void

    private let engine = AVAudioEngine()

    // 以下三个字段只在调用方串行上下文读写（见文件头线程模型），
    // 音频线程不碰。
    private var continuation: AsyncStream<Speech.AnalyzerInput>.Continuation?
    private var tapInstalled = false
    private var sessionActivated = false

    /// tap 接受旗：false 后 tap 立刻停止喂入（收尾第一步先关它）
    private let bufferGate = OSAllocatedUnfairLock<Bool>(initialState: false)
    /// 首个 buffer 旗：音频线程置位、每轮 startCapture 重置，只触发一次
    private let firstBufferGate = OSAllocatedUnfairLock<Bool>(initialState: false)

    /// 电平表状态（v5.6）：平滑后电平＋距上次推送的累计帧数。只在
    /// tap 音频线程读写（startCapture 在调用方线程重置），全程走锁。
    private struct MeterState {
        var smoothed: Float = 0
        var framesSincePush = 0
    }
    private let meterState = OSAllocatedUnfairLock<MeterState>(initialState: MeterState())

    /// 收尾判「有没有会话残留」用（口径同 v5.5：装过 tap 或还持有
    /// 输入流 continuation 即算有残留）
    var hasSessionArtifacts: Bool { tapInstalled || continuation != nil }

    /// 音频会话激活＋读输入格式＋建转换器＋装 tap（不启动引擎：引擎
    /// 由 startEngine 在 analyzer.start 成功后启动，保证喂入前消费端
    /// 已就绪，次序同 v5.5）。抛错口径与 v5.5 installCapture 一致
    /// （LiqianSpeech code 1 = 麦克风格式不可用、code 2 = 转换不可用）。
    func startCapture(
        analyzerFormat: AVAudioFormat,
        continuation: AsyncStream<Speech.AnalyzerInput>.Continuation,
        trace: TraceHook,
        onFirstBuffer: @escaping @Sendable () -> Void,
        onLevel: @escaping LevelHook
    ) throws {
        // 输入流 continuation 先接管：中途抛错时收尾仍能 finish 它
        // （口径同 v5.5——转写器在装配前已把 continuation 存好）
        self.continuation = continuation

        let session = AVAudioSession.sharedInstance()
        // 新框架官方示例口径：.playAndRecord + .spokenAudio
        try session.setCategory(.playAndRecord, mode: .spokenAudio)
        // 激活不带 .notifyOthersOnDeactivation（只对停用有效，v5.4.1 ⑨）
        try session.setActive(true)
        sessionActivated = true
        trace(24, "音频会话已激活", "")

        let input = engine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)
        trace(
            25, "读取输入格式",
            "\(Int(inputFormat.sampleRate))Hz/\(inputFormat.channelCount)ch"
        )
        // 格式没就绪就装 tap 会触发 AVFAudio 的 NSException（catch
        // 不住、直接闪退）——旧链时代的教训，先拦下
        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else {
            throw NSError(
                domain: "LiqianSpeech", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "麦克风暂时不可用"]
            )
        }
        // 格式相同直通；不同才建转换器（primeMethod = .none 是官方
        // 示例口径：牺牲最初几个采样换时间戳不漂移）
        let converter: AVAudioConverter?
        if inputFormat == analyzerFormat {
            converter = nil
        } else {
            converter = AVAudioConverter(from: inputFormat, to: analyzerFormat)
            converter?.primeMethod = .none
            guard converter != nil else {
                throw NSError(
                    domain: "LiqianSpeech", code: 2,
                    userInfo: [NSLocalizedDescriptionKey: "音频格式转换不可用"]
                )
            }
        }

        // 装之前先摘可能残留的旧 tap：同一 bus 只许一个 tap，重复装
        // 同样是 NSException
        if tapInstalled {
            input.removeTap(onBus: 0)
            tapInstalled = false
        }
        let gate = bufferGate
        gate.withLock { $0 = true }
        let firstFlag = firstBufferGate
        firstFlag.withLock { $0 = false }
        let meter = meterState
        meter.withLock { $0 = MeterState() }
        // 【隔离红线】下面这个闭包的显式捕获列表就是审计面：只许有
        // 锁与本次调用的局部值，绝不许出现 self（本类实例）、
        // 更绝不许出现 SpeechTranscriber 或任何 @MainActor 状态。
        // 改这个闭包的人先读文件头与 docs/V551-NOTES.md 的清点表。
        // bufferSize 2048（v5.6 由 4096 改小）：48kHz 下约 43ms 一个
        // buffer，电平推送天然落在约 23 次/秒；喂入语义不变（分析器
        // 按流消费，不按 buffer 边界对齐）。
        input.installTap(onBus: 0, bufferSize: 2048, format: inputFormat) { [
            gate, firstFlag, meter, converter, analyzerFormat, continuation, onFirstBuffer, onLevel
        ] buffer, _ in
            // 接受旗已关（收尾中）就不再喂入
            guard gate.withLock({ $0 }) else { return }
            // 电平（v5.6 面板声纹）：对原始输入 buffer 算 RMS → dB
            // 归一化，在锁内做惯性平滑与推送节流（间隔 ≥ 约 1/30
            // 秒），钩子在锁外触发。音频线程只做逐采样算数与原子
            // 写：不分配大对象、不碰 UI 状态（口径见 LiqianCore
            // .VoiceLevelMath）。
            let target = VoiceLevelMath.normalizedLevel(rms: Self.rms(of: buffer))
            let pushLevel: Float? = meter.withLock { state in
                state.smoothed = VoiceLevelMath.ballistic(
                    previous: state.smoothed, target: target
                )
                state.framesSincePush += Int(buffer.frameLength)
                guard state.framesSincePush
                    >= VoiceLevelMath.minimumPushFrames(sampleRate: buffer.format.sampleRate)
                else { return nil }
                state.framesSincePush = 0
                return state.smoothed
            }
            if let pushLevel { onLevel(pushLevel) }
            let converted: AVAudioPCMBuffer?
            if let converter {
                converted = Self.convertBuffer(buffer, with: converter, to: analyzerFormat)
            } else {
                converted = buffer
            }
            guard let converted else { return }
            continuation.yield(Speech.AnalyzerInput(buffer: converted))
            // 首个音频：本线程只置原子旗并触发钩子，落标在钩子那头
            // 回主执行者做（不在实时音频线程写 UserDefaults）
            let isFirst = firstFlag.withLock { flag -> Bool in
                if flag { return false }
                flag = true
                return true
            }
            if isFirst { onFirstBuffer() }
        }
        tapInstalled = true
        trace(26, "已装 tap", "")
    }

    /// 启动引擎（analyzer.start 成功后由转写器调用）
    func startEngine() throws {
        engine.prepare()
        try engine.start()
    }

    /// 收尾第一段（同步、幂等）：关接受旗 → 停引擎 → 摘 tap
    func stopCapture() {
        bufferGate.withLock { $0 = false }
        if engine.isRunning {
            engine.stop()
        }
        if tapInstalled {
            engine.inputNode.removeTap(onBus: 0)
            tapInstalled = false
        }
    }

    /// 结束输入流（收尾异步段在 finalize 冲刷之前调用）
    func finishInput() {
        continuation?.finish()
        continuation = nil
    }

    /// 停用音频会话（仅当由本类激活过，不误关他人状态）
    func deactivateSession() {
        if sessionActivated {
            try? AVAudioSession.sharedInstance()
                .setActive(false, options: .notifyOthersOnDeactivation)
            sessionActivated = false
        }
    }

    /// 输入 buffer 的均方根幅度（全通道）：float 直读，int16/int32
    /// 按满量程归一。逐采样累加（平方和用 Double 防精度溢出），不
    /// 分配任何对象。tap 音频线程调用，供电平表换算（v5.6）。
    static func rms(of buffer: AVAudioPCMBuffer) -> Float {
        let frames = Int(buffer.frameLength)
        let channels = Int(buffer.format.channelCount)
        guard frames > 0, channels > 0 else { return 0 }
        var sumSquares: Double = 0
        if let data = buffer.floatChannelData {
            for ch in 0..<channels {
                let samples = data[ch]
                for i in 0..<frames {
                    let v = Double(samples[i])
                    sumSquares += v * v
                }
            }
        } else if let data = buffer.int16ChannelData {
            for ch in 0..<channels {
                let samples = data[ch]
                for i in 0..<frames {
                    let v = Double(samples[i]) / 32768.0
                    sumSquares += v * v
                }
            }
        } else if let data = buffer.int32ChannelData {
            for ch in 0..<channels {
                let samples = data[ch]
                for i in 0..<frames {
                    let v = Double(samples[i]) / 2147483648.0
                    sumSquares += v * v
                }
            }
        } else {
            return 0
        }
        return Float(sqrt(sumSquares / Double(frames * channels)))
    }

    /// AVAudioConverter 单 buffer 转换（官方示例的 inputBlock 形状：
    /// 一次喂入、之后报 noDataNow）。在 tap 的音频线程串行调用；
    /// inputBlock 闭包在本方法内形成、只捕获 delivered 旗与入参
    /// buffer，无任何隔离状态。容量走 LiqianCore.AudioConvertMath。
    static func convertBuffer(
        _ buffer: AVAudioPCMBuffer,
        with converter: AVAudioConverter,
        to format: AVAudioFormat
    ) -> AVAudioPCMBuffer? {
        let capacity = AudioConvertMath.outputFrameCapacity(
            inputFrameCount: Int(buffer.frameLength),
            inputSampleRate: buffer.format.sampleRate,
            outputSampleRate: format.sampleRate
        )
        guard capacity > 0,
              let output = AVAudioPCMBuffer(
                pcmFormat: format, frameCapacity: AVAudioFrameCount(capacity)
              )
        else { return nil }
        var error: NSError?
        var delivered = false
        let status = converter.convert(to: output, error: &error) { _, outStatus in
            if delivered {
                outStatus.pointee = .noDataNow
                return nil
            }
            delivered = true
            outStatus.pointee = .haveData
            return buffer
        }
        guard status != .error, output.frameLength > 0 else { return nil }
        return output
    }
}
