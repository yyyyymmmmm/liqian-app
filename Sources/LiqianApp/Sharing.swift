import CloudKit
import SwiftUI
import UIKit
import LiqianCore

/// 协作共享可用性（v4.5 守卫）：先把「为什么不能用」做成明确状态展示给用户，
/// 绝不在不可用环境里尝试创建 CKShare——那是闪退与数据损坏的来源。
///
/// 当前构建不可用的根因（两条，任一成立即不可用）：
/// 1. SwiftData 容器是纯本地存储：LiqianApp 用 `.modelContainer(for:)` 默认
///    配置，没有 CloudKit 镜像库，CKShare 没有可挂的持久化存储；
/// 2. 侧载（SideStore）未签名构建没有 iCloud entitlement，CKContainer 的
///    操作会直接报缺失权限错误。
/// feat/icloud 分支把容器切到 CloudKit 私有库后，将
/// `LedgerSharing.storeIsCloudKitBacked` 置 true，再由 accountStatus
/// 给出真实可用性，UI 与权限映射无需再改（接通点见文末 TODO）。
enum SharingAvailability: Equatable {
    case available
    case noAccount
    case restricted
    case storeNotCloudKit
    case couldNotDetermine

    var isAvailable: Bool { self == .available }

    /// 给用户看的人话说明（不甩技术词）
    var message: String {
        switch self {
        case .available:
            return "可以邀请家人一起管这本礼簿。"
        case .noAccount:
            return "这台手机还没登录 iCloud，登录后才能邀请家人协作。"
        case .restricted:
            return "iCloud 协作被系统限制（例如家长控制），暂时不能邀请。"
        case .storeNotCloudKit:
            return "协作邀请需要正式版的 iCloud 环境，当前版本暂不支持，班子名单和权限都已先备好。"
        case .couldNotDetermine:
            return "暂时读不到 iCloud 状态，请稍后再试。"
        }
    }
}

enum LedgerSharing {
    /// 接通开关：容器启用 CloudKit 镜像后由 feat/icloud 的接通工作置 true。
    /// 在此之前恒为 false——守卫据此短路，连 CKContainer 都不碰。
    static let storeIsCloudKitBacked = false

    static func availability() async -> SharingAvailability {
        guard storeIsCloudKitBacked else { return .storeNotCloudKit }
        // 接通后才走到的真实检查：容器标识须取工程的 iCloud container id，
        // 不用 .default() 猜（签名/entitlement 不一致时会报错而不是给状态）。
        do {
            switch try await CKContainer.default().accountStatus() {
            case .available:
                return .available
            case .noAccount:
                return .noAccount
            case .restricted:
                return .restricted
            case .couldNotDetermine, .temporarilyUnavailable:
                return .couldNotDetermine
            @unknown default:
                return .couldNotDetermine
            }
        } catch {
            return .couldNotDetermine
        }
    }

    /// 班子角色 → 邀请时预设的参与者权限文案（映射逻辑在 Core 的
    /// MemberRole.sharePermission，这里只做展示翻译）。
    static func permissionText(for role: MemberRole) -> String {
        switch role.sharePermission {
        case .owner: return "所有者（礼簿归属人）"
        case .readWrite: return "可查看、可记账"
        case .readOnly: return "只能查看"
        }
    }
}

// TODO(feat/icloud 接通点)：容器切到 CloudKit 后，共享的落地路径是
// 用 NSPersistentCloudKitContainer 在 coordinator 层为礼簿对象取/建 CKShare
// （SwiftData 至今未公开对象级共享 API），再把 CKShare 交给下面的
// CloudSharingView 呈现。参与者按 LedgerMember 名单逐个添加，权限取
// MemberRole.sharePermission 翻译为 CKShare.ParticipantPermission
// （readWrite → .readWrite，readOnly → .readOnly，主家不入参与者名单）。
// 当前构建 availability 恒为 .storeNotCloudKit，此桥不被调起。

/// UICloudSharingController 的 SwiftUI 桥（接通后使用；当前不可达）
struct CloudSharingView: UIViewControllerRepresentable {
    let share: CKShare
    let container: CKContainer
    var title: String = "邀请家人协作"

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIViewController(context: Context) -> UICloudSharingController {
        share[CKShare.SystemFieldKey.title] = title
        let controller = UICloudSharingController(share: share, container: container)
        controller.delegate = context.coordinator
        controller.availablePermissions = [.allowReadOnly, .allowReadWrite, .allowPrivate]
        return controller
    }

    func updateUIViewController(_ controller: UICloudSharingController, context: Context) {}

    final class Coordinator: NSObject, UICloudSharingControllerDelegate {
        func itemTitle(for csc: UICloudSharingController) -> String? {
            "礼簿协作邀请"
        }

        func cloudSharingController(
            _ csc: UICloudSharingController, failedToSaveShareWithError error: Error
        ) {
            // 保存共享失败：系统弹窗已给出重试/取消，这里不额外处理，
            // 也不做任何本地数据变更（共享状态以 CloudKit 为准）。
        }

        func cloudSharingControllerDidSaveShare(_ csc: UICloudSharingController) {}

        func cloudSharingControllerDidStopSharing(_ csc: UICloudSharingController) {}
    }
}
