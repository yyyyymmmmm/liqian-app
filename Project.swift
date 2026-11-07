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
            ]),
            sources: ["Sources/LiqianApp/**"],
            resources: ["App/Resources/**"],
            dependencies: [
                .target(name: "LiqianCore"),
                .target(name: "LiqianDesign"),
            ]
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
