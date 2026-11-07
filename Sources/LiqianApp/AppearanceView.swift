import SwiftUI
import LiqianCore
import LiqianDesign

/// 外观主题选择（v2.4）：白天 / 夜晚 / 腾讯蓝 / 灰色 / 黄色 五选一。
/// 选择即写 @AppStorage，ContentView 据此强制外观并重挂子树，切换即时生效。
/// 深色仅「夜晚」提供，其余四主题强制浅色（用户点名定版）。
/// 主题只驱动 App 界面强调色；礼谱 PDF 与分享图卡是成品，永远朱砂，不跟随。
struct AppearanceView: View {
    @AppStorage(AppTheme.storageKey) private var appThemeRaw = AppTheme.day.rawValue

    private var current: AppTheme {
        AppTheme(rawValue: appThemeRaw) ?? .day
    }

    var body: some View {
        List {
            Section {
                ForEach(AppTheme.allCases) { theme in
                    Button {
                        appThemeRaw = theme.rawValue
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
                Text("夜晚为深色外观，其余主题为浅色。主题只影响 App 界面，导出的礼谱不变。")
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Palette.pageBG.ignoresSafeArea())
        .navigationTitle("主题")
        .navigationBarTitleDisplayMode(.inline)
    }
}
