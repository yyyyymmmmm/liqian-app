import Foundation
import UIKit

/// 备用图标下线迁移（v5.11.4）：v5.9 的换色备用图标与「图标跟随主题」
/// 机制整体取消（用户拍板），CFBundleAlternateIcons 声明与 AltIcon-*
/// 资产已删。在旧版里选过备用图标的设备，升级后系统侧仍记着当时的
/// alternateIconName——启动时发现非空即复位主图标，并顺手清掉已下线
/// 的「图标跟随主题」偏好键。
///
/// 幂等：复位后 alternateIconName 恒为 nil、偏好键恒不存在，
/// 此后每次启动都只是两次空转检查，不重复弹窗、不重复写盘。
/// 不看 supportsAlternateIcons：声明删掉后该值可能为 false，
/// 但传 nil 复位主图标是任何状态下都合法的调用，必须照常执行。
enum IconCleanup {
    /// 已下线的偏好键（原 AppIconManager.followStorageKey 的字面量，
    /// 原文件已删，此处留档以便清理存量设备上的残值）
    private static let legacyFollowKey = "iconFollowsTheme"

    static func run() {
        if UIApplication.shared.alternateIconName != nil {
            // completion 传 nil——不给框架留回调（本项目有框架回调
            // 隔离击杀的前科，见 docs/V551-NOTES 与原 AppIconManager 口径）
            UIApplication.shared.setAlternateIconName(nil, completionHandler: nil)
        }
        UserDefaults.standard.removeObject(forKey: legacyFollowKey)
    }
}
