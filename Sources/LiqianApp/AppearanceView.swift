import SwiftUI
import UIKit
import LiqianCore
import LiqianDesign

/// 自定义强调色的预置色单（v5.9，用户拍板）：独立色五款
/// （朱砂红/大厂红/蓝/黑/黄）＋与预置主题同色的快捷项四款
/// （白天主题的朱砂与朱砂红同色，不重复列）。
private struct AccentPreset: Identifiable {
    let name: String
    let hex: UInt32
    var id: UInt32 { hex }

    static let all: [AccentPreset] = [
        AccentPreset(name: "朱砂红", hex: 0xA62B1F),
        AccentPreset(name: "大厂红", hex: 0xE1251B),
        AccentPreset(name: "蓝", hex: 0x007AFF),
        AccentPreset(name: "黑", hex: 0x232323),
        AccentPreset(name: "黄", hex: 0xE8A20C),
        AccentPreset(name: "夜晚", hex: 0xD96A5C),
        AccentPreset(name: "腾讯蓝", hex: 0x0052D9),
        AccentPreset(name: "石墨灰", hex: 0x4E5969),
        AccentPreset(name: "琥珀", hex: 0xA16207),
    ]
}

/// 外观（v2.4 主题五选一；v5.9 扩为主题六选一＋自定义色；v5.11.4
/// 取消 v5.9 的换色备用图标与「图标跟随主题」，外观页只管主题）：
/// 选择即写 @AppStorage，ContentView 据此强制外观并重挂子树，切换即时生效。
/// 深色仅「夜晚」提供，其余主题（含自定义）强制浅色（用户点名定版）。
/// 主题只驱动 App 界面；礼谱 PDF 与分享图卡是成品，永远朱砂，不跟随；
/// 小组件读不到 App 主题，用固定默认色对（v5.1 既定边界，自定义色同理）。
struct AppearanceView: View {
    @AppStorage(AppTheme.storageKey) private var appThemeRaw = AppTheme.day.rawValue
    /// 语言偏好（v5.13）：三档即时生效（根视图据存储重挂子树）
    @AppStorage(AppLanguagePreference.storageKey) private var languageRaw = AppLanguagePreference.system.rawValue
    @AppStorage(AppTheme.customBaseStorageKey) private var customBaseHexString = ""

    /// ColorPicker 草稿色：拖动中只改草稿（整 App 重挂不能被拖动连续
    /// 触发），停手 1.2 秒或离开页面时才提交写存储（见 commitDraft）
    @State private var draftColor = Color(hex: CustomTheme.defaultBaseHex)
    @State private var commitTask: Task<Void, Never>?

    private var current: AppTheme {
        AppTheme(rawValue: appThemeRaw) ?? .day
    }

    /// 已提交生效的自定义基色（存储解析，缺省朱砂）
    private var storedBaseHex: UInt32 {
        UInt32(customBaseHexString, radix: 16) ?? CustomTheme.defaultBaseHex
    }

    var body: some View {
        List {
            // 语言（v5.13 语言全跟随）：界面、首开引导与导出的礼谱
            // 都跟随；人名、礼簿名、备注等用户填写的内容不转换。
            Section {
                ForEach(AppLanguagePreference.allCases, id: \.rawValue) { pref in
                    Button {
                        languageRaw = pref.rawValue
                    } label: {
                        HStack(spacing: LiqianMetrics.spacingSM) {
                            Text(L10n.string(languageLabel(pref)))
                                .foregroundStyle(Palette.ink)
                            Spacer()
                            if languageRaw == pref.rawValue {
                                Image(systemName: "checkmark")
                                    .font(.footnote.weight(.semibold))
                                    .foregroundStyle(Palette.primary)
                                    .accessibilityHidden(true)
                            }
                        }
                        .frame(minHeight: LiqianMetrics.minTapTarget)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityValue(languageRaw == pref.rawValue ? "当前语言" : "")
                }
            } header: {
                Text("语言")
            } footer: {
                Text("界面、引导和导出的礼谱都用所选语言；礼簿名、人名、备注是你填的内容，不转换。")
            }

            Section {
                ForEach(AppTheme.allCases) { theme in
                    Button {
                        selectTheme(theme)
                    } label: {
                        HStack(spacing: LiqianMetrics.spacingSM) {
                            Circle()
                                .fill(theme.swatch)
                                .frame(width: 22, height: 22)
                                .overlay(
                                    Circle().stroke(Palette.hairline, lineWidth: 1)
                                )
                                .accessibilityHidden(true)
                            Text(theme.displayName)
                                .foregroundStyle(Palette.ink)
                            Spacer()
                            if theme == current {
                                Image(systemName: "checkmark")
                                    .font(.footnote.weight(.semibold))
                                    .foregroundStyle(Palette.primary)
                                    .accessibilityHidden(true)
                            }
                        }
                        .frame(minHeight: LiqianMetrics.minTapTarget)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityValue(theme == current ? "当前主题" : "")
                }
            } footer: {
                Text("夜晚为深色外观，其余主题（含自定义）为浅色。主题只影响 App 界面，导出的礼谱不变。")
            }

            if current == .custom {
                customColorSection
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Palette.pageBG.ignoresSafeArea())
        .navigationTitle("主题")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            draftColor = Color(hex: storedBaseHex)
        }
        .onDisappear {
            commitTask?.cancel()
            commitDraftIfNeeded()
        }
    }

    /// 语言档位名（字面走本地化表：繁体档下自动出繁體字形）
    private func languageLabel(_ pref: AppLanguagePreference) -> String {
        switch pref {
        case .system: return "跟随系统"
        case .simplified: return "简体"
        case .traditional: return "繁体"
        }
    }

    // MARK: - 自定义强调色（审计 #1 方案 A）

    private var customColorSection: some View {
        Section {
            // 预置色单：点即提交（离散动作，与切主题同节奏）
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 52), spacing: LiqianMetrics.spacingSM)],
                spacing: LiqianMetrics.spacingSM
            ) {
                ForEach(AccentPreset.all) { preset in
                    Button {
                        draftColor = Color(hex: preset.hex)
                        commitBase(preset.hex)
                    } label: {
                        VStack(spacing: LiqianMetrics.spacingXS) {
                            Circle()
                                .fill(Color(hex: preset.hex))
                                .frame(width: 30, height: 30)
                                .overlay(
                                    Circle().stroke(
                                        storedBaseHex == preset.hex
                                            ? Palette.primary : Palette.hairline,
                                        lineWidth: storedBaseHex == preset.hex ? 2 : 1
                                    )
                                )
                            Text(preset.name)
                                .font(.caption2)
                                .foregroundStyle(Palette.sub)
                                .lineLimit(1)
                        }
                        .frame(minHeight: LiqianMetrics.minTapTarget)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("强调色 \(preset.name)")
                    .accessibilityValue(storedBaseHex == preset.hex ? "当前" : "")
                }
            }
            .padding(.vertical, LiqianMetrics.spacingXS)

            ColorPicker("自选颜色", selection: $draftColor, supportsOpacity: false)
                .frame(minHeight: LiqianMetrics.minTapTarget)
                .onChange(of: draftColor) { _, _ in
                    scheduleCommit()
                }

            if CustomTheme.isAdjusted(baseHex: storedBaseHex) {
                Text("所选颜色偏浅，直接用作文字会看不清，已自动略调深；色点仍是你选的原色。")
                    .font(.footnote)
                    .foregroundStyle(Palette.sub)
            }
        } header: {
            Text("自定义强调色")
        } footer: {
            Text("选一个颜色作强调色；送礼的黛青与它撞色时会自动避让。")
        }
    }

    // MARK: - 动作

    private func selectTheme(_ theme: AppTheme) {
        appThemeRaw = theme.rawValue
    }

    /// 提交基色：写存储（ContentView 据此重挂生效）
    private func commitBase(_ hex: UInt32) {
        let text = String(format: "%06X", hex)
        guard text != customBaseHexString else { return }
        customBaseHexString = text
    }

    /// ColorPicker 停手 1.2 秒后提交（拖动中连续变化只重置计时）
    private func scheduleCommit() {
        commitTask?.cancel()
        commitTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            guard !Task.isCancelled else { return }
            commitDraftIfNeeded()
        }
    }

    private func commitDraftIfNeeded() {
        let hex = hexValue(of: draftColor)
        if hex != storedBaseHex {
            commitBase(hex)
        }
    }

    /// Color → hex（取色器颜色恒为 sRGB，getRed 不会失败；
    /// 万一失败回当前存储值，不写坏数据）
    private func hexValue(of color: Color) -> UInt32 {
        let uiColor = UIColor(color)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard uiColor.getRed(&r, green: &g, blue: &b, alpha: &a) else {
            return storedBaseHex
        }
        return (UInt32((r * 255).rounded()) << 16)
            | (UInt32((g * 255).rounded()) << 8)
            | UInt32((b * 255).rounded())
    }
}
