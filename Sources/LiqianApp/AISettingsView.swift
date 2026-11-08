import SwiftUI
import LiqianCore
import LiqianDesign

/// AI 管家设置：填自己的 DeepSeek API Key（只存本机钥匙串）、启停开关、
/// Key 健康验证。验证结论落盘（AIVerificationStore）：重进页面能还原，
/// 换 Key 自动回未验证；验证只是健康提示，不拦使用——可用性门控只看
/// 「已保存 Key＋开关打开」（AIAccess.readiness 同口径）。
struct AISettingsView: View {
    @AppStorage(AIAccess.enabledKey) private var aiEnabled = false
    @State private var keyInput = ""
    @State private var savedLast4: String?
    @State private var status: AIVerificationStatus = .noKey
    @State private var verifying = false
    @State private var showDeleteConfirm = false

    var body: some View {
        Form {
            if savedLast4 != nil {
                Section {
                    LabeledContent("当前 API Key") {
                        Text("已保存（尾号 \(savedLast4 ?? "")）")
                            .font(.subheadline)
                            .foregroundStyle(Palette.stone)
                    }
                    HStack(spacing: LiqianMetrics.spacingSM) {
                        Text("验证状态")
                        Spacer()
                        statusPill
                    }
                    if case .failed(let reason, _) = status {
                        Text(reason)
                            .font(.footnote)
                            .foregroundStyle(Palette.danger)
                    }
                    if !isVerified {
                        Button {
                            verifyNow()
                        } label: {
                            HStack(spacing: LiqianMetrics.spacingXS) {
                                if verifying {
                                    ProgressView()
                                }
                                Text(isFailed ? "重新验证" : "验证一次")
                            }
                            .frame(minHeight: LiqianMetrics.minTapTarget)
                        }
                        .disabled(verifying)
                    }
                } footer: {
                    Text("验证只发一次极小的接口调用，确认 Key 真能用。验证状态是健康提示：没验过或没验过都不拦你使用 AI。")
                }
            }

            Section {
                SecureField("DeepSeek API Key", text: $keyInput, prompt: Text("sk-…"))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button {
                    saveKey()
                } label: {
                    Text("保存并验证")
                        .frame(maxWidth: .infinity, minHeight: LiqianMetrics.minTapTarget)
                }
                .buttonStyle(.glassProminent)
                .tint(Palette.primary)
                .disabled(keyInput.trimmingCharacters(in: .whitespaces).isEmpty || verifying)
                if savedLast4 != nil {
                    Button("删除 API Key", role: .destructive) {
                        showDeleteConfirm = true
                    }
                    .frame(minHeight: LiqianMetrics.minTapTarget)
                }
            } header: {
                Text("API Key")
            } footer: {
                Text(savedLast4 == nil
                    ? "在 platform.deepseek.com 申请 API Key，费用计入你的 DeepSeek 账户。输入后点「保存并验证」。"
                    : "要换 Key 就在上面输入新的，再点「保存并验证」；新 Key 验证后旧记录自动作废。")
            }

            Section {
                Toggle("启用 AI 功能", isOn: $aiEnabled)
                    .tint(Palette.primary)
                    .frame(minHeight: LiqianMetrics.minTapTarget)
            } footer: {
                Text("开关打开、且已保存 API Key，AI 功能即可用。")
            }

            Section {
                VStack(alignment: .leading, spacing: LiqianMetrics.spacingSM) {
                    Label("Key 只存这台手机的钥匙串，不进备份、不上传到我们的服务器。", systemImage: "key.fill")
                    Label("用的时候 App 直连 DeepSeek 官方接口；问账只发你的问题和本次查到的账目子集，不发全量账本。", systemImage: "network")
                    Label("金额和往来差额永远是本地算的，AI 只负责听懂问题、组织回答。", systemImage: "function")
                }
                .font(.subheadline)
                .foregroundStyle(Palette.stone)
            } header: {
                Text("说明")
            }
        }
        .scrollContentBackground(.hidden)
        .background(Palette.pageBG.ignoresSafeArea())
        .navigationTitle("AI 管家")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(
            "删除 API Key？",
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("删除", role: .destructive) { deleteKey() }
            Button("取消", role: .cancel) {}
        } message: {
            Text("Key 会从钥匙串里删掉，AI 功能同时停用。之后重新填入即可恢复。")
        }
        .onAppear { refreshState() }
    }

    // MARK: - 状态丸（色点＋短文案，四态齐全）

    private var isFailed: Bool {
        if case .failed = status { return true }
        return false
    }

    private var isVerified: Bool {
        if case .verified = status { return true }
        return false
    }

    @ViewBuilder
    private var statusPill: some View {
        let (text, color): (String, Color) = {
            if verifying { return ("验证中…", Palette.warning) }
            switch status {
            case .verified(let at):
                return ("已验证 · \(at.formatted(date: .abbreviated, time: .shortened))", Palette.success)
            case .failed:
                return ("验证失败", Palette.danger)
            case .unverified, .noKey:
                return ("未验证", Palette.warning)
            }
        }()
        HStack(spacing: LiqianMetrics.spacingXS) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(text)
                .font(.footnote.weight(.medium))
                .foregroundStyle(Palette.ink)
        }
        .padding(.horizontal, LiqianMetrics.spacingSM)
        .padding(.vertical, LiqianMetrics.spacingXS)
        .background(color.opacity(0.14), in: Capsule())
        .accessibilityLabel("验证状态：\(text)")
    }

    // MARK: - 动作

    private func refreshState() {
        savedLast4 = KeychainStore.read().map { String($0.suffix(4)) }
        status = AIVerificationStore.status(currentKeyLast4: savedLast4)
    }

    private func saveKey() {
        let trimmed = keyInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        KeychainStore.save(trimmed)
        keyInput = ""
        aiEnabled = true // 填了 key 保存时自动打开开关，少一步操作
        refreshState() // 新 Key 尾号与旧记录对不上时状态自动回未验证
        verifyNow()
    }

    private func deleteKey() {
        KeychainStore.delete()
        AIVerificationStore.clear()
        savedLast4 = nil
        keyInput = ""
        aiEnabled = false // 开关与真实状态对齐：没 Key 时开关同步关
        status = .noKey
    }

    /// 一次极小接口调用探活：走正式问账同一条 chatTurn 路径（v5.4，
    /// 不再自造请求形状）；结果无论成败都落盘，失败带人话原因、不静默。
    private func verifyNow() {
        guard let last4 = savedLast4, !verifying else { return }
        verifying = true
        Task {
            defer { verifying = false }
            do {
                try await DeepSeekClient().verifyKey()
                let record = AIVerificationRecord(
                    outcome: .verified, keyLast4: last4, at: Date()
                )
                AIVerificationStore.save(record)
                status = .verified(at: record.at)
            } catch {
                let reason = Self.failureReason(for: error)
                let record = AIVerificationRecord(
                    outcome: .failed, keyLast4: last4, at: Date(),
                    failureReason: reason
                )
                AIVerificationStore.save(record)
                status = .failed(reason: reason, at: record.at)
            }
        }
    }

    /// 验证失败的人话原因（按 HTTP 码分档，不许笼统吞掉）
    static func failureReason(for error: Error) -> String {
        guard let error = error as? DeepSeekError else {
            return "网络连接失败，请检查网络后重试。"
        }
        switch error {
        case .noKey:
            return "还没有保存 API Key。"
        case .http(let code, let serverMessage):
            switch code {
            case 401, 403:
                return "API Key 被拒绝：可能填错了，请核对后重新保存。"
            case 402:
                return "DeepSeek 账户余额不足，充值后重新验证。"
            case 429:
                return "请求过于频繁，请稍后再验证。"
            default:
                // v5.4：带上服务端返回的真实原因，不只报一个状态码
                if let serverMessage, !serverMessage.isEmpty {
                    return "DeepSeek 接口返回异常（\(code)）：\(serverMessage)"
                }
                return "DeepSeek 接口返回异常（\(code)），请稍后再验证。"
            }
        case .network:
            return "网络连接失败，请检查网络后重试。"
        case .badResponse:
            return "接口返回内容异常，请稍后再验证。"
        }
    }
}
