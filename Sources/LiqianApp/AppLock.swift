import LocalAuthentication
import SwiftUI
import LiqianDesign

/// 隐私锁的生物/密码验证封装。
/// 用 .deviceOwnerAuthentication：有 Face ID/Touch ID 先走生物识别，
/// 没有或多次失败自动落到系统锁屏密码兜底。
enum AppLockAuthenticator {
    /// 正在验证中标记，避免冷启动 onAppear 与回前台逻辑叠加弹两次窗
    private static var inFlight = false

    static func authenticate(completion: @escaping (Bool) -> Void) {
        guard !inFlight else { return }
        inFlight = true
        let context = LAContext()
        var nsError: NSError?
        let policy: LAPolicy = .deviceOwnerAuthentication
        guard context.canEvaluatePolicy(policy, error: &nsError) else {
            // 设备连锁屏密码都没设：没有任何凭据可校验，
            // 直接放行避免把用户锁死在自己数据外面
            inFlight = false
            completion(true)
            return
        }
        context.evaluatePolicy(policy, localizedReason: "解锁礼钱账本") { success, _ in
            DispatchQueue.main.async {
                inFlight = false
                completion(success)
            }
        }
    }
}

/// 锁定页：礼簿色板，只放品牌与解锁动作，不出现任何金额信息
struct LockScreenView: View {
    let onUnlockTap: () -> Void

    var body: some View {
        ZStack {
            Palette.paper.ignoresSafeArea()
            VStack(spacing: 24) {
                coverMark
                Text("礼钱账本已锁定")
                    .font(.system(size: 17, weight: .semibold))
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

    /// 与礼簿封面同语言的品牌标记：朱砂封面块 + 竖排字 + 描金边
    private var coverMark: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(Palette.primary)
            RoundedRectangle(cornerRadius: 8)
                .fill(
                    LinearGradient(
                        colors: [.white.opacity(0.28), .white.opacity(0)],
                        startPoint: .top,
                        endPoint: .center
                    )
                )
            Text("礼\n簿")
                .font(.liqianSerif(size: 24))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
        }
        .frame(width: 64, height: 100)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Palette.gold, lineWidth: 1)
        )
    }
}
