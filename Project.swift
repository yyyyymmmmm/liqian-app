import ProjectDescription

let iOS26 = DeploymentTargets.iOS("26.0")

let project = Project(
    name: "Liqian",
    organizationName: "site.didichou",
    settings: .settings(base: [
        "SWIFT_VERSION": "6.0",
        "TARGETED_DEVICE_FAMILY": "1",
        "MARKETING_VERSION": "5.10.0",
        "CURRENT_PROJECT_VERSION": "70",
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
                // 版本号直写 Info.plist（v4.4 实证）：Tuist 默认模板不把
                // 工程设置里的 MARKETING_VERSION 展开进 plist，只写字面量
                // 才进包——首版 v4.4 解包验出仍是 1.0/1 后改走这条。
                "CFBundleShortVersionString": "5.10.0",
                "CFBundleVersion": "70",
                // 备用图标（v5.9，审计 #2）：白底不变、只换礼结色的 8 款
                // 变体，文件由 scripts/make_alt_icons.py 生成、随资源进包
                // 根目录（AltIcon-<变体>@2x/@3x.png）。键名与
                // AppIconVariant.alternateName 逐项一致；主图标仍走资源
                // 目录 AppIcon（此处主图标条目为结构完整而写，actool
                // 构建时以资源目录为准合并）。
                "CFBundleIcons": [
                    "CFBundlePrimaryIcon": [
                        "CFBundleIconFiles": ["AppIcon"],
                        "CFBundleIconName": "AppIcon",
                    ],
                    "CFBundleAlternateIcons": [
                        "AltIcon-night": ["CFBundleIconFiles": ["AltIcon-night"]],
                        "AltIcon-tencentBlue": ["CFBundleIconFiles": ["AltIcon-tencentBlue"]],
                        "AltIcon-graphite": ["CFBundleIconFiles": ["AltIcon-graphite"]],
                        "AltIcon-amber": ["CFBundleIconFiles": ["AltIcon-amber"]],
                        "AltIcon-jdRed": ["CFBundleIconFiles": ["AltIcon-jdRed"]],
                        "AltIcon-appleBlue": ["CFBundleIconFiles": ["AltIcon-appleBlue"]],
                        "AltIcon-black": ["CFBundleIconFiles": ["AltIcon-black"]],
                        "AltIcon-brightYellow": ["CFBundleIconFiles": ["AltIcon-brightYellow"]],
                    ],
                ],
                // 长按图标快捷菜单（v4.5）：静态两项——记一笔、查看待回礼。
                // 承接在 AppDelegate（冷启动 launchOptions / 运行时 performActionFor）
                // → ShortcutActions 写标记 → ContentView 消费，与小组件深链同守卫
                // （隐私锁定时不承接）。type 串与 ShortcutActions 常量必须同步改。
                "UIApplicationShortcutItems": [
                    [
                        "UIApplicationShortcutItemType": "site.didichou.liqian.shortcut.record",
                        "UIApplicationShortcutItemTitle": "记一笔",
                        "UIApplicationShortcutItemIconSymbolName": "plus.circle.fill",
                    ],
                    [
                        "UIApplicationShortcutItemType": "site.didichou.liqian.shortcut.pending",
                        "UIApplicationShortcutItemTitle": "查看待回礼",
                        "UIApplicationShortcutItemIconSymbolName": "gift.fill",
                    ],
                ],
                "UIFileSharingEnabled": true,
                "LSSupportsOpeningDocumentsInPlace": true,
                "ITSAppUsesNonExemptEncryption": false,
                "UILaunchScreen": ["UIColorName": "LaunchBackground", "UIImageName": "LaunchImage"],
                "NSFaceIDUsageDescription": "用 Face ID 保护你的人情账本不被旁人看到",
                "NSSpeechRecognitionUsageDescription": "用于将语音转写为记账文字",
                "NSMicrophoneUsageDescription": "用于语音记账和录制语音祝福：把你说的话转成文字，或把祝福原声收进礼谱",
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
                // LiqianShare 依赖自 v4.7 起摘除（休眠）：v4.5/v4.6 两版真机
                // 实证——带 Share 扩展的完整包在 SideStore 重签后整 App 拒启
                // （扩展 profile 注册问题），去分享包可用。本版基线不带它进包；
                // target 定义与 Sources/LiqianShare 源码保留，恢复方法见
                // docs/V47-NOTES.md（把本行加回依赖即可，Share plist 版本
                // 届时需同步升到当版）。
            ]
        ),
        .target(
            name: "LiqianShare",
            destinations: .iOS,
            product: .appExtension,
            bundleId: "site.didichou.liqian.share",
            deploymentTargets: iOS26,
            infoPlist: .extendingDefault(with: [
                // 版本字面量直写（v4.4 实证口径，同 App/Widget）；三 target 每版同步升
                "CFBundleShortVersionString": "4.6.0",
                "CFBundleVersion": "46",
                "NSExtension": [
                    "NSExtensionPointIdentifier": "com.apple.share-services",
                    "NSExtensionPrincipalClass": "$(PRODUCT_MODULE_NAME).ShareViewController",
                    // 只激活纯文本：微信接龙等场景分享进来的就是一段文字，
                    // 图片/文件/链接一律不接（批量解析只吃文本）
                    "NSExtensionAttributes": [
                        "NSExtensionActivationRule": [
                            "NSExtensionActivationSupportsText": true,
                        ],
                    ],
                ],
            ]),
            sources: ["Sources/LiqianShare/**"],
            entitlements: .dictionary([
                "com.apple.security.application-groups": .array([
                    .string("group.site.didichou.liqian"),
                ]),
            ]),
            dependencies: [.target(name: "LiqianCore")]
        ),
        .target(
            name: "LiqianWidget",
            destinations: .iOS,
            product: .appExtension,
            bundleId: "site.didichou.liqian.widget",
            deploymentTargets: iOS26,
            infoPlist: .extendingDefault(with: [
                "CFBundleShortVersionString": "5.10.0",
                "CFBundleVersion": "70",
                "NSExtension": [
                    "NSExtensionPointIdentifier": "com.apple.widgetkit-extension",
                ],
            ]),
            sources: ["Sources/LiqianWidget/**"],
            // Widget 隐私清单（v4.5）：扩展进程独立 bundle，必须自带一份
            resources: ["WidgetResources/**"],
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
