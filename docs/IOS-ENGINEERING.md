# iOS 工程化决策（对标大厂开源项目流程）

日期：2026-11-07 · 决策人：用户（砍安卓、主攻苹果）＋ Muse 落地
调研依据（GitHub 实时）：Tuist ★5.9k（当日活跃）、fastlane ★42.4k、
SwiftLint ★19.8k、Firefox iOS ★13.1k、WordPress iOS ★3.9k 的公开工程实践；
GitHub 官方 runner 镜像表与 Apple 要求：2026-04-28 起 App Store Connect
只接受 Xcode 26 + iOS 26 SDK 构建，macos-26 镜像为当前标准（默认 Xcode 26.x）。

## 选型结论

| 层 | 选择 | 对标 |
|---|---|---|
| 语言/UI | Swift 6 + SwiftUI，原生 | 大厂新项目标准；iOS 26 Liquid Glass 只有原生有真材质 |
| 系统下限 | iOS 26 | 用户指定 iOS 26 设计；上架硬要求 iOS 26 SDK |
| 工程生成 | Tuist（Project.swift 声明式，.xcodeproj 不进 git） | Tuist/大厂模块化实践 |
| 架构 | SwiftUI + MVVM（@Observable），模块分包 | Kickstarter/WordPress 式 MVVM |
| 模块 | App / LiqianCore（模型+账务规则）/ LiqianDesign（礼簿设计系统） | SPM 本地包，边界清晰 |
| 数据 | SwiftData（Ledger/GiftRecord），规则在 Core 层计算 | Apple 现行标准 |
| CI | GitHub Actions macos-26：Tuist 生成 → SwiftLint → build → test → 未签名 IPA | runner 镜像表 + fastlane 实践 |
| 发布自动化 | fastlane（Fastfile 已备 beta lane，待开发者账号与 ASC 密钥启用） | fastlane ★42.4k 行业标准 |
| 质量门 | SwiftLint 规则集 + Core 规则单元测试（差额/未回规则必测） | 大厂 PR 门禁 |

## 砍安卓说明

Flutter 双端版冻结在 v0.3（git tag flutter-v0.3），代码移入 flutter-legacy/
保留可查，不再迭代。产品资源全部转入原生 iOS 线。

## 数据语义（与 Flutter 版一致，移植不得改口径）

金额存分；差额=已收-已送（待送出不计）；未回=最后一笔已送出之后的收礼合计；
事由 9 类；白事克制样式；JSON 全量备份/恢复。规则实现以 LiqianCore 单元测试为准。
