import Foundation
import UIKit

/// 意见反馈（v4.5）：「我的 → 关于 → 意见反馈」走系统邮件，
/// 预填标题与设备/版本信息，用户只需写问题本身。
enum FeedbackMail {
    /// 收件地址（2026-11-08 用户拍板）：用真实邮箱 inkroot001@gmail.com，
    /// 原占位 support@didichou.site 不可收件已弃。要换地址只改这一处。
    static let address = "inkroot001@gmail.com"

    /// 标题与正文模板：版本号直接取 Bundle，与「关于」页显示版本同源不写死；
    /// 标题中的 v4.6 是本版交付口径，后续大版本同步改这里。
    static var url: URL {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = address
        components.queryItems = [
            URLQueryItem(name: "subject", value: "礼记反馈（v4.6）"),
            URLQueryItem(name: "body", value: bodyTemplate),
        ]
        return components.url ?? URL(string: "mailto:\(address)")!
    }

    private static var bodyTemplate: String {
        """
        设备型号：\(deviceModel)
        系统版本：iOS \(UIDevice.current.systemVersion)
        应用版本：\(MeView.appVersion)

        请从这里开始写你的问题或建议：


        """
    }

    /// 机器标识（如 iPhone17,2），够定位机型即可，不取任何个人标识
    private static var deviceModel: String {
        var machine = utsname()
        uname(&machine)
        return withUnsafePointer(to: &machine.machine) { pointer in
            pointer.withMemoryRebound(to: CChar.self, capacity: 1) {
                String(cString: $0)
            }
        }
    }
}
