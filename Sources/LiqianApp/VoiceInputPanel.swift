import SwiftUI
import LiqianDesign

// MARK: - 语音输入面板（v5.6，一句话记账与 AI 问账共用）
//
// 【为什么是面板】用户真机反馈 v5.5.1 的语音「能用但不专业：没有
// 实时转文字、没有声纹」。调研成熟产品（微信语音输入、iOS 语音
// 备忘录、iOS 系统听写、豆包/讯飞输入法、苹果 WWDC25 示例，出处
// 见 docs/V56-NOTES.md 调研节）的共性是：录音是一个明确面板，而
// 不是原按钮变个颜色——面板里同时有四件事：真实电平驱动的声纹
// 波形、边说边长的流式转写（未定稿灰、已定稿正常色）、录音计时、
// 以及「取消 / 完成」两个明确出口。本组件即按此形态实现，两入口
// 共用同一份，提交语义由调用方经 onFinish/onCancel 决定。
//
// 【视觉纪律（DESIGN.md 定版）】内容层纸墨平面、零玻璃：波形是墨
// 色柱、文本是墨/石两色，全是真实数据（电平来自 feeder 在 tap 内
// 对原始 buffer 算的 RMS，没有任何装饰性假动画）；玻璃只进底部
// 行动按钮（功能层：取消走 Mat.regular、完成走 Mat.tinted 主钮）；
// 朱砂（主题强调令牌 Palette.primary）只落两处——录音状态点与
// 「完成」主钮的系统染色。面板不许滑动误关：出口只有两个钮。

struct VoiceInputPanel: View {
    @ObservedObject var transcriber: SpeechTranscriber
    /// 完成：收尾冲刷后的最终全文回调用方（一句话记账＝进文本框
    /// 待解析、AI 问账＝进输入框待发送，与 v5.5.1 的 onText 末态一致）
    var onFinish: (String) -> Void
    /// 取消：本次文本丢弃，调用方不落任何字
    var onCancel: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// 已点「完成」、正等收尾冲刷交付的中间态：两钮禁用防重复点，
    /// 状态行转「正在收尾…」
    @State private var isFinishing = false

    private static let transcriptBottomID = "voicePanelTranscriptBottom"

    var body: some View {
        VStack(alignment: .leading, spacing: LiqianMetrics.spacingM) {
            statusRow
            VoiceWaveformView(
                levels: transcriber.waveformLevels,
                reduceMotion: reduceMotion
            )
            transcriptArea
            actionRow
        }
        .padding(LiqianMetrics.spacingM)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .presentationDetents([.fraction(0.55), .medium])
        .presentationDragIndicator(.hidden)
        .interactiveDismissDisabled(true)
        .presentationBackground(Palette.groupedBackground)
    }

    // MARK: 状态行：录音点＋计时 / 准备中 / 异常人话

    @ViewBuilder
    private var statusRow: some View {
        HStack(spacing: LiqianMetrics.spacingS) {
            if isFinishing {
                ProgressView()
                    .controlSize(.small)
                Text("正在收尾…")
                    .font(.subheadline)
                    .foregroundStyle(Palette.stone)
            } else if transcriber.isRecording {
                // 录音状态点：全屏唯一朱砂点（主题强调令牌）
                Circle()
                    .fill(Palette.primary)
                    .frame(width: 10, height: 10)
                    .accessibilityHidden(true)
                Text("正在录音")
                    .font(.headline)
                    .foregroundStyle(Palette.ink)
                Spacer()
                Text(Self.timeString(transcriber.elapsedSeconds))
                    .font(.headline)
                    .monospacedDigit()
                    .foregroundStyle(Palette.stone)
                    .accessibilityLabel("已录 \(transcriber.elapsedSeconds) 秒")
            } else if transcriber.isStarting {
                ProgressView()
                    .controlSize(.small)
                // 准备期的人话（含资产下载提示）暂存在 errorText 通道，
                // 在此按状态呈现、不当错误显示
                Text(transcriber.errorText ?? "正在准备麦克风…")
                    .font(.subheadline)
                    .foregroundStyle(Palette.stone)
            } else if let speechError = transcriber.errorText {
                Image(systemName: "exclamationmark.circle")
                    .foregroundStyle(Palette.danger)
                    .accessibilityHidden(true)
                Text(speechError)
                    .font(.subheadline)
                    .foregroundStyle(Palette.danger)
            } else {
                // 结果流自行结束（无错误）：会话已收尾，只剩关闭出口
                Text("本次识别已结束。")
                    .font(.subheadline)
                    .foregroundStyle(Palette.stone)
            }
            Spacer(minLength: 0)
        }
        .frame(minHeight: LiqianMetrics.minTapTarget)
    }

    // MARK: 流式转写：定稿墨色、未定稿灰色，自动滚到最新

    private var transcriptArea: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    transcriptContent
                    Color.clear
                        .frame(height: 1)
                        .id(Self.transcriptBottomID)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: .infinity)
            .onChange(of: transcriber.finalizedText) { _, _ in
                scrollToBottom(proxy)
            }
            .onChange(of: transcriber.volatileText) { _, _ in
                scrollToBottom(proxy)
            }
        }
    }

    @ViewBuilder
    private var transcriptContent: some View {
        if transcriber.finalizedText.isEmpty && transcriber.volatileText.isEmpty {
            Text("开始说话，识别的文字会实时出现在这里。")
                .font(.body)
                .foregroundStyle(Palette.stone)
        } else {
            (Text(transcriber.finalizedText).foregroundStyle(Palette.ink)
                + Text(transcriber.volatileText).foregroundStyle(Palette.stone))
                .font(.body)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        if reduceMotion {
            proxy.scrollTo(Self.transcriptBottomID, anchor: .bottom)
        } else {
            withAnimation(.easeOut(duration: 0.15)) {
                proxy.scrollTo(Self.transcriptBottomID, anchor: .bottom)
            }
        }
    }

    // MARK: 底部出口：取消（丢弃）/ 完成（提交最终全文）

    private var actionRow: some View {
        HStack(spacing: LiqianMetrics.spacingSM) {
            Button {
                transcriber.cancelTranscription()
                onCancel()
            } label: {
                Text(transcriber.isRecording || transcriber.isStarting ? "取消" : "关闭")
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: LiqianMetrics.minTapTarget)
            }
            .liqianGlassButton(.regular)
            .disabled(isFinishing)

            if transcriber.isRecording {
                Button {
                    isFinishing = true
                    transcriber.finishTranscription { finalText in
                        onFinish(finalText)
                    }
                } label: {
                    Text("完成")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: LiqianMetrics.minTapTarget)
                }
                .liqianGlassButton(.tinted)
                .disabled(isFinishing)
            }
        }
    }

    /// 计时口径：0:00 起、分:秒两位（分钟不设上限补零）
    static func timeString(_ seconds: Int) -> String {
        String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

// MARK: - 声纹波形（真实电平柱）
//
// 数据是 feeder 在 tap 内对原始 buffer 算 RMS、经 dB 归一化＋电平表
// 惯性平滑后推送的电平历史（旧→新）：新柱从右侧进入、旧柱向左滚
// 出（语音备忘录式滚动）；不满柱数时左侧补零（静音高度）。柱高只
// 由真实电平决定，无声即低平——这里没有任何装饰性动画，唯一的
// animation 是柱高变化的系统补间（Reduce Motion 时关掉）。

struct VoiceWaveformView: View {
    let levels: [Float]
    var reduceMotion: Bool = false

    /// 柱数与转写器环形缓冲容量同一口径
    static let barCount = SpeechTranscriber.waveformCapacity

    var body: some View {
        let bars = paddedLevels
        HStack(alignment: .center, spacing: 2.5) {
            ForEach(bars.indices, id: \.self) { index in
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(Palette.ink.opacity(0.85))
                    .frame(width: 3, height: 4 + CGFloat(bars[index]) * 42)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 50)
        .animation(
            reduceMotion ? nil : .easeOut(duration: 0.09),
            value: levels
        )
        // 纯数据呈现、无语义：录音状态由状态行播报，波形对读屏隐藏
        .accessibilityHidden(true)
    }

    /// 左侧补零对齐到满柱数（新电平从右侧长出）
    private var paddedLevels: [Float] {
        guard levels.count < Self.barCount else {
            return Array(levels.suffix(Self.barCount))
        }
        return Array(repeating: 0, count: Self.barCount - levels.count) + levels
    }
}
