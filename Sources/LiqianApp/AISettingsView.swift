import SwiftUI
import LiqianDesign

/// AI 智能助手设置：填自己的 DeepSeek API Key（只存本机钥匙串）、启停开关。
/// AI 只做「理解」与「生成」：智能粘贴解析、一句话记账、贺词生成；
/// 金额与往来差额永远是本地规则算的，AI 结果也要用户当面确认才落库。
struct AISettingsView: View {
    @AppStorage(AIAccess.enabledKey) private var aiEnabled = false
    @State private var keyInput = ""
    @State private var savedLast4: String?
    @State private var message: String?

    var body: some View {
        Form {
            Section {
                if let savedLast4 {
                    LabeledContent("当前 Key") {
                        Text("已保存（尾号 \(savedLast4)）")
                            .foregroundStyle(Palette.stone)
                    }
                }
                SecureField("DeepSeek API Key", text: $keyInput, prompt: Text("sk-…"))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button {
                    saveKey()
                } label: {
                    Text(savedLast4 == nil ? "保存 Key" : "换一个 Key")
                        .frame(minHeight: LiqianMetrics.minTapTarget)
                }
                .disabled(keyInput.trimmingCharacters(in: .whitespaces).isEmpty)
                if savedLast4 != nil {
                    Button("删除 Key", role: .destructive) {
                        KeychainStore.delete()
                        savedLast4 = nil
                        keyInput = ""
                        message = "Key 已从钥匙串删掉，AI 功能停用。"
                    }
                    .frame(minHeight: LiqianMetrics.minTapTarget)
                }
                if let message {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(Palette.stone)
                }
            } header: {
                Text("API Key")
            } footer: {
                Text("去 platform.deepseek.com 申请，费用走你自己的 DeepSeek 账户。")
            }

            Section {
                Toggle("启用 AI 功能", isOn: $aiEnabled)
                    .tint(Palette.primary)
                    .frame(minHeight: LiqianMetrics.minTapTarget)
            } footer: {
                Text("关掉后，智能解析、一句话记账、贺词生成的入口点了会先提醒，不会偷偷调用。")
            }

            Section {
                Text("Key 只存在这台手机的钥匙串里，不进备份、不上传到我们的服务器；用的时候 App 直接连 DeepSeek 官方接口。每次调用都由你当面点按钮触发，发送前界面会写清楚要发什么。AI 只帮忙读懂文字、写贺词——解析结果先进预览或表单，你核对了才保存；金额和往来差额永远是本地算的。")
                    .font(.system(size: 13.5))
                    .foregroundStyle(Palette.stone)
                    .lineSpacing(5)
            } header: {
                Text("说明")
            }
        }
        .scrollContentBackground(.hidden)
        .background(Palette.paper.ignoresSafeArea())
        .navigationTitle("AI 智能助手")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { refreshSavedHint() }
    }

    private func refreshSavedHint() {
        savedLast4 = KeychainStore.read().map { String($0.suffix(4)) }
    }

    private func saveKey() {
        let trimmed = keyInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        KeychainStore.save(trimmed)
        keyInput = ""
        aiEnabled = true // 填了 key 保存时自动打开开关，少一步操作
        refreshSavedHint()
        message = "已保存，AI 功能一并打开了。"
    }
}
