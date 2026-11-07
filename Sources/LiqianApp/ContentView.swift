import SwiftUI
import LiqianDesign

/// iOS 26 原生 Tab：玻璃底栏由系统提供，不做自定义栏（skill 口径）。
/// 隐私锁（v1.1）：MeView 里开关（@AppStorage "privacyLock"），
/// 开启时冷启动即锁、回前台超过 30 秒重新锁、切后台内容模糊遮罩。
struct ContentView: View {
    @AppStorage("privacyLock") private var privacyLockEnabled = false
    @Environment(\.scenePhase) private var scenePhase
    @State private var isLocked = true
    @State private var backgroundedAt: Date?

    /// 切到后台/多任务预览时是否要盖模糊遮罩
    private var shieldVisible: Bool {
        privacyLockEnabled && scenePhase != .active
    }

    var body: some View {
        ZStack {
            TabView {
                Tab("礼簿", systemImage: "book.closed") {
                    LedgersView()
                }
                Tab("人情", systemImage: "person.2") {
                    PeopleView()
                }
                Tab("我的", systemImage: "person.crop.circle") {
                    MeView()
                }
            }
            .tint(Palette.primary)
            .blur(radius: shieldVisible ? 20 : 0)

            if shieldVisible {
                ZStack {
                    Rectangle()
                        .fill(.ultraThinMaterial)
                        .ignoresSafeArea()
                    Image(systemName: "lock.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(Palette.stone)
                }
            }

            if privacyLockEnabled && isLocked && scenePhase == .active {
                LockScreenView {
                    authenticate()
                }
            }
        }
        .onAppear {
            if privacyLockEnabled {
                isLocked = true
                authenticate()
            } else {
                isLocked = false
            }
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .background:
                backgroundedAt = Date()
            case .active:
                // 真从后台回来且超过 30 秒才重新锁（Face ID 弹窗造成的
                // inactive→active 不经过 .background，不会误触发）
                if privacyLockEnabled, !isLocked,
                   let bg = backgroundedAt,
                   Date().timeIntervalSince(bg) > 30 {
                    isLocked = true
                    authenticate()
                }
                backgroundedAt = nil
            default:
                break
            }
        }
    }

    private func authenticate() {
        Task {
            if await AppLockAuthenticator.authenticate() { isLocked = false }
        }
    }
}
