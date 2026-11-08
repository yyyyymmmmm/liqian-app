import Foundation

/// 语音采音格式转换的纯计算（v5.5.1）：AVAudioConverter 输出 buffer
/// 的帧容量 = 输入帧数 ×（输出采样率 ÷ 输入采样率）＋ 1 帧余量，与
/// 苹果官方 SpeechAnalyzer 示例的容量口径一致（对非负数，「乘比后
/// 截断再 +1」与「先 +1 再截断」等价）。非法入参（帧数 ≤ 0 或任一
/// 采样率 ≤ 0）返回 0，调用方据此放弃本帧。纯值计算、无 IO，可单测。
public enum AudioConvertMath {
    public static func outputFrameCapacity(
        inputFrameCount: Int,
        inputSampleRate: Double,
        outputSampleRate: Double
    ) -> Int {
        guard inputFrameCount > 0, inputSampleRate > 0, outputSampleRate > 0
        else { return 0 }
        return Int(Double(inputFrameCount) * (outputSampleRate / inputSampleRate)) + 1
    }
}
