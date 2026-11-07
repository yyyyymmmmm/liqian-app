import LocalAuthentication
import SwiftUI
import LiqianDesign

/// 隐私锁的生物/密码验证封装。
/// 用 .deviceOwnerAuthentication：有 Face ID/Touch ID 先走生物识别，
/// 没有或多次失败自动落到系统锁屏密码兜底。
@MainActor
enum AppLockAuthenticator {
    /// 正在验证中标记，避免冷启动 onAppear 与回前台逻辑叠加弹两次窗
    private static var inFlight = false

    static func authenticate() async -> Bool {
        // 已有一次验证在弹系统窗时，第二次调用直接返回未解锁，
        // 调用方保持锁定态即可（第一次的结果会负责解锁）
        guard !inFlight else { return false }
        inFlight = true
        defer { inFlight = false }
        let context = LAContext()
        var nsError: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &nsError) else {
            // 设备连锁屏密码都没设：没有任何凭据可校验，
            // 直接放行避免把用户锁死在自己数据外面
            return true
        }
        do {
            return try await context.evaluatePolicy(
                .deviceOwnerAuthentication, localizedReason: "解锁礼记")
        } catch {
            return false
        }
    }
}

/// 锁定页：礼簿色板，只放品牌与解锁动作，不出现任何金额信息
struct LockScreenView: View {
    let onUnlockTap: () -> Void

    var body: some View {
        ZStack {
            Palette.groupedBackground.ignoresSafeArea()
            VStack(spacing: LiqianMetrics.spacingL) {
                coverMark
                Text("礼记已锁定")
                    .font(.headline)
                    .foregroundStyle(Palette.ink)
                Button {
                    onUnlockTap()
                } label: {
                    Label("解锁", systemImage: "faceid")
                        .frame(minWidth: 120, minHeight: LiqianMetrics.minTapTarget)
                }
                .buttonStyle(.glassProminent)
                .tint(Palette.primary)
            }
        }
    }

    /// 与礼簿封面同语言的品牌标记：朱砂封面块 + 竖排字（v3 无金边）
    private var coverMark: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(Palette.primaryFill)
            Text("礼\n簿")
                .font(.liqianSerifFixed(size: 24))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
        }
        .frame(width: 64, height: 100)
    }
}
