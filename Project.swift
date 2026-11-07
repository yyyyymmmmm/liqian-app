import ProjectDescription

let iOS26 = DeploymentTargets.iOS("26.0")

let project = Project(
    name: "Liqian",
    organizationName: "site.didichou",
    settings: .settings(base: [
        "SWIFT_VERSION": "6.0",
        "TARGETED_DEVICE_FAMILY": "1",
        "MARKETING_VERSION": "4.4.0",
        "CURRENT_PROJECT_VERSION": "44",
    ]),
    targets: [
        .target(
            name: "LiqianCore",
            destinations: .iOS,
            product: .framework,
            bundleId: "site.didichou.liqian.core",
            deploymentTargets: iOS26,
            infoPlist: .default,
            sources: ["Sources/LiqianCore/**"],
            dependencies: []
        ),
        .target(
            name: "LiqianDesign",
            destinations: .iOS,
            product: .framework,
            bundleId: "site.didichou.liqian.design",
            deploymentTargets: iOS26,
            infoPlist: .default,
            sources: ["Sources/LiqianDesign/**"],
            dependencies: [.target(name: "LiqianCore")]
        ),
        .target(
            name: "LiqianApp",
            destinations: .iOS,
            product: .app,
            bundleId: "site.didichou.liqian",
            deploymentTargets: iOS26,
            infoPlist: .extendingDefault(with: [
                "CFBundleDisplayName": "礼记",
                "UIFileSharingEnabled": true,
                "LSSupportsOpeningDocumentsInPlace": true,
                "ITSAppUsesNonExemptEncryption": false,
                "UILaunchScreen": ["UIColorName": "LaunchBackground", "UIImageName": "LaunchImage"],
                "NSFaceIDUsageDescription": "用 Face ID 保护你的人情账本不被旁人看到",
                "NSSpeechRecognitionUsageDescription": "用于将语音转写为记账文字",
                "NSMicrophoneUsageDescription": "用于语音记账，把你说的话转成文字",
                "NSCameraUsageDescription": "用于拍摄纸质礼单，识别姓名与金额",
                // 现场模式 Live Activity（v4.5）：锁屏横幅显示本场收礼进度，
                // 仅本地启动/更新（不走 APNs 推送），无此键 Activity.request 必失败
                "NSSupportsLiveActivities": true,
                // CloudKit 静默推送：数据在其他设备变更时系统唤醒同步（feat/icloud）
                "UIBackgroundModes": ["remote-notification"],
                // 活礼谱（v4.2）：注册 liqian scheme——此前小组件的
                // liqian://quick-record 也未注册（靠系统宽容才通），
                // 祝福深链 liqian://blessing/<id>（礼谱索引页二维码）依赖它。
                "CFBundleURLTypes": [
                    [
                        "CFBundleURLName": "site.didichou.liqian",
                        "CFBundleURLSchemes": ["liqian"],
                    ],
                ],
            ]),
            sources: ["Sources/LiqianApp/**"],
            resources: ["App/Resources/**"],
            entitlements: .dictionary([
                "com.apple.security.application-groups": .array([
                    .string("group.site.didichou.liqian"),
                ]),
                // iCloud 同步（feat/icloud）：CloudKit 私有数据库，容器 = iCloud. + bundle id。
                // 只用 CloudKit，不用 iCloud Documents（无需 ubiquity 容器 entitlement）。
                // 侧载重签通常会剥掉这组 entitlement——代码侧有本地回退，不崩不丢（见 CloudSync.swift）。
                "aps-environment": .string("development"),
                "com.apple.developer.icloud-container-identifiers": .array([
                    .string("iCloud.site.didichou.liqian"),
                ]),
                "com.apple.developer.icloud-services": .array([
                    .string("CloudKit"),
                ]),
            ]),
            dependencies: [
                .target(name: "LiqianCore"),
                .target(name: "LiqianDesign"),
                .target(name: "LiqianWidget"),
            ]
        ),
        .target(
            name: "LiqianWidget",
            destinations: .iOS,
            product: .appExtension,
            bundleId: "site.didichou.liqian.widget",
            deploymentTargets: iOS26,
            infoPlist: .extendingDefault(with: [
                "NSExtension": [
                    "NSExtensionPointIdentifier": "com.apple.widgetkit-extension",
                ],
            ]),
            sources: ["Sources/LiqianWidget/**"],
            entitlements: .dictionary([
                "com.apple.security.application-groups": .array([
                    .string("group.site.didichou.liqian"),
                ]),
            ]),
            dependencies: [.target(name: "LiqianCore")]
        ),
        .target(
            name: "LiqianCoreTests",
            destinations: .iOS,
            product: .unitTests,
            bundleId: "site.didichou.liqian.core.tests",
            deploymentTargets: iOS26,
            infoPlist: .default,
            sources: ["Tests/LiqianCoreTests/**"],
            dependencies: [.target(name: "LiqianCore")]
        ),
    ],
    schemes: [
        .scheme(
            name: "LiqianApp",
            shared: true,
            buildAction: .buildAction(targets: ["LiqianApp"]),
            testAction: .targets(["LiqianCoreTests"]),
            runAction: .runAction(executable: "LiqianApp")
        ),
    ]
)
