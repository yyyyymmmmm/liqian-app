import Foundation

/// 语音面板电平表的纯计算（v5.6）：把 tap 采到的原始音频 RMS 换成
/// 面板声纹柱的 0...1 高度。口径按专业电平表惯例：
///
/// - dB 换算：dB = 20·log10(RMS)，静默地板 −50 dB（地板以下一律 0），
///   0 dB（满量程）→ 1，中间线性映射——日常说话约 −20…−10 dB，
///   落在 0.6…0.8，正是柱体该明显起伏的区间；
/// - 惯性（ballistics）：起（attack）即时跟上新值（说话不迟滞），
///   落（decay）每步乘固定系数衰减（停口后柱体是滑落不是跳崖）。
///
/// 纯值计算、无 IO，feeder 在音频线程调用的全是这里的函数，可单测。
public enum VoiceLevelMath {
    /// 静默地板（dB）：低于此值视为无声
    public static let silenceFloorDB: Float = -50
    /// 衰减系数（每次电平步进）：1 → 约 10 步滑落到 0.04
    public static let decayPerStep: Float = 0.72

    /// RMS（0...1 线性幅度）→ 归一化电平 0...1
    public static func normalizedLevel(rms: Float) -> Float {
        guard rms > 0 else { return 0 }
        let db = 20 * log10(rms)
        let level = (db - silenceFloorDB) / (0 - silenceFloorDB)
        return min(max(level, 0), 1)
    }

    /// 电平表惯性一步：目标更高即时跟上（attack），更低则衰减滑落
    /// （decay），且不跌破目标值本身。
    public static func ballistic(previous: Float, target: Float) -> Float {
        if target >= previous { return target }
        return max(target, previous * decayPerStep)
    }

    /// 电平推送节流阈值：两次推送之间至少间隔的帧数（约 1/30 秒）。
    /// tap 的 buffer 本身约 2048 帧（48kHz 下 ≈ 43ms），常规采样率
    /// 每个 buffer 都够格推送；高采样率（如 96kHz）靠此阈值压回
    /// 约 30 次/秒以内。非法采样率返回 0（每帧都可推，调用方另有兜底）。
    public static func minimumPushFrames(sampleRate: Double) -> Int {
        guard sampleRate > 0 else { return 0 }
        return Int(sampleRate / 30)
    }
}
