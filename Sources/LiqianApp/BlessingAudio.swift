import AVFoundation
import Foundation
import LiqianCore
import Speech

// MARK: - 语音祝福音频存储（v4.2 活礼谱）
//
// 音频本体只存 App 容器 Application Support/Blessings/，SwiftData 里
// VoiceBlessing.fileName 只存文件名（相对路径入库，容器路径变化不失效）。
// 音频不进 JSON 备份（备份只有元数据段，含转写文字）。

enum BlessingAudioStore {
    static var directory: URL {
        let base = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        )[0]
        let dir = base.appendingPathComponent("Blessings", isDirectory: true)
        try? FileManager.default.createDirectory(
            at: dir, withIntermediateDirectories: true
        )
        return dir
    }

    static func url(for fileName: String) -> URL {
        directory.appendingPathComponent(fileName)
    }

    static func exists(_ fileName: String) -> Bool {
        FileManager.default.fileExists(atPath: url(for: fileName).path)
    }

    static func remove(_ fileName: String) {
        try? FileManager.default.removeItem(at: url(for: fileName))
    }

    static func newFileName() -> String {
        "blessing-\(UUID().uuidString).m4a"
    }
}

// MARK: - 播放（同一时刻只播一条；播完自动复位）

@MainActor
final class BlessingPlayer: NSObject, ObservableObject {
    @Published private(set) var playingID: UUID?
    @Published var errorText: String?

    private var player: AVAudioPlayer?

    func isPlaying(_ blessing: VoiceBlessing) -> Bool {
        playingID == blessing.id && player?.isPlaying == true
    }

    func toggle(_ blessing: VoiceBlessing) {
        if playingID == blessing.id {
            stop()
            return
        }
        stop()
        let url = BlessingAudioStore.url(for: blessing.fileName)
        guard BlessingAudioStore.exists(blessing.fileName) else {
            // 诚实口径：录音在录制的那台设备上（换机恢复只有元数据），
            // 不假装能播；转写文字若有，界面上照样读得到。
            errorText = "这段祝福的录音保存在录制的那台设备上，本机没有这个文件。"
            return
        }
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback)
            try AVAudioSession.sharedInstance().setActive(true)
            let p = try AVAudioPlayer(contentsOf: url)
            p.delegate = self
            player = p
            playingID = blessing.id
            p.play()
        } catch {
            errorText = "播放失败，请再试一次。"
        }
    }

    func stop() {
        player?.stop()
        player = nil
        playingID = nil
    }
}

extension BlessingPlayer: AVAudioPlayerDelegate {
    nonisolated func audioPlayerDidFinishPlaying(
        _ player: AVAudioPlayer, successfully flag: Bool
    ) {
        Task { @MainActor [weak self] in
            self?.player = nil
            self?.playingID = nil
        }
    }
}

// MARK: - 录制（AVAudioRecorder，AAC/m4a；权限文案复用既有麦克风说明）

@MainActor
final class BlessingRecorder: ObservableObject {
    @Published private(set) var isRecording = false
    @Published private(set) var elapsed: TimeInterval = 0
    @Published var errorText: String?

    private var recorder: AVAudioRecorder?
    private var timer: Timer?
    private var pendingFileName: String?

    func start() {
        guard !isRecording else { return }
        AVAudioApplication.requestRecordPermission { [weak self] granted in
            Task { @MainActor [weak self] in
                guard let self else { return }
                guard granted else {
                    self.errorText = "没有麦克风权限，去系统设置里打开后就能录祝福了。"
                    return
                }
                self.beginRecording()
            }
        }
    }

    private func beginRecording() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .default)
            try session.setActive(true)
            let fileName = BlessingAudioStore.newFileName()
            let settings: [String: Any] = [
                AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                AVSampleRateKey: 44_100,
                AVNumberOfChannelsKey: 1,
                AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue,
            ]
            let rec = try AVAudioRecorder(
                url: BlessingAudioStore.url(for: fileName), settings: settings
            )
            rec.record()
            recorder = rec
            pendingFileName = fileName
            elapsed = 0
            isRecording = true
            timer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self, let rec = self.recorder else { return }
                    self.elapsed = rec.currentTime
                }
            }
        } catch {
            errorText = "录音没能开始，请再试一次。"
        }
    }

    /// 停止并返回 (文件名, 时长)；太短（<0.5 秒）视作误触，删文件返回 nil
    func stop() -> (fileName: String, duration: TimeInterval)? {
        guard let rec = recorder, let fileName = pendingFileName else { return nil }
        let duration = rec.currentTime
        rec.stop()
        cleanup()
        if duration < 0.5 {
            BlessingAudioStore.remove(fileName)
            return nil
        }
        return (fileName, duration)
    }

    func cancel() {
        recorder?.stop()
        if let fileName = pendingFileName {
            BlessingAudioStore.remove(fileName)
        }
        cleanup()
    }

    private func cleanup() {
        timer?.invalidate()
        timer = nil
        recorder = nil
        pendingFileName = nil
        isRecording = false
        elapsed = 0
    }
}

// MARK: - 录后转写（文件型识别；与 QuickSentenceView 的实时麦克风转写互补）
//
// 复用同一 Speech 框架与授权流：授权被拒/识别不可用/出错一律返回 nil，
// transcript 留空——转写是锦上添花，不可用达不阻塞祝福保存，绝不编造。

enum BlessingTranscriber {
    static func transcribe(fileName: String) async -> String? {
        let status = await withCheckedContinuation { (cont: CheckedContinuation<SFSpeechRecognizerAuthorizationStatus, Never>) in
            SFSpeechRecognizer.requestAuthorization { cont.resume(returning: $0) }
        }
        guard status == .authorized,
              let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "zh-CN")),
              recognizer.isAvailable
        else { return nil }

        let request = SFSpeechURLRecognitionRequest(
            url: BlessingAudioStore.url(for: fileName)
        )
        request.shouldReportPartialResults = false
        if recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }
        return await withCheckedContinuation { (cont: CheckedContinuation<String?, Never>) in
            let once = ResumeOnce(cont)
            recognizer.recognitionTask(with: request) { result, error in
                if let result, result.isFinal {
                    once.resume(result.bestTranscription.formattedString)
                } else if error != nil {
                    once.resume(nil)
                }
            }
        }
    }

    /// recognitionTask 回调可能多次触发，continuation 只能 resume 一次
    private final class ResumeOnce: @unchecked Sendable {
        private let lock = NSLock()
        private var cont: CheckedContinuation<String?, Never>?

        init(_ cont: CheckedContinuation<String?, Never>) { self.cont = cont }

        func resume(_ value: String?) {
            lock.lock()
            let c = cont
            cont = nil
            lock.unlock()
            c?.resume(returning: value)
        }
    }
}

/// 时长展示（0:12 形式），祝福行/索引页共用
func blessingDurationText(_ seconds: Double) -> String {
    let total = max(0, Int(seconds.rounded()))
    return String(format: "%d:%02d", total / 60, total % 60)
}
