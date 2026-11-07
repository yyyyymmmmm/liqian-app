import ProjectDescription

let iOS26 = DeploymentTargets.iOS("26.0")

let project = Project(
    name: "Liqian",
    organizationName: "site.didichou",
    settings: .settings(base: [
        "SWIFT_VERSION": "6.0",
        "TARGETED_DEVICE_FAMILY": "1",
        "MARKETING_VERSION": "1.0.0",
        "CURRENT_PROJECT_VERSION": "1",
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
                "CFBundleDisplayName": "礼钱账本",
                "UIFileSharingEnabled": true,
                "LSSupportsOpeningDocumentsInPlace": true,
                "ITSAppUsesNonExemptEncryption": false,
                "UILaunchScreen": ["UIColorName": "LaunchBackground"],
                "NSFaceIDUsageDescription": "用 Face ID 保护你的人情账本不被旁人看到",
                "NSSpeechRecognitionUsageDescription": "用于将语音转写为记账文字",
                "NSMicrophoneUsageDescription": "用于语音记账，把你说的话转成文字",
            ]),
            sources: ["Sources/LiqianApp/**"],
            resources: ["App/Resources/**"],
            entitlements: .dictionary([
                "com.apple.security.application-groups": .array([
                    .string("group.site.didichou.liqian"),
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
