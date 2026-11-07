import SwiftUI
import UIKit
import UniformTypeIdentifiers
import LiqianCore

// MARK: - 分享导入通道（键与主 App WidgetSummaryWriter 对齐，改键两边同步）
// - 礼簿清单快照：主 App 维护，key "ledgerList"，JSON [{id,title,date}]
// - 暂存区：key "shareImportText"（分享文本）、"shareImportLedgerID"（目标礼簿）
// 扩展只负责「选礼簿 + 暂存 + 唤起主 App」，解析与落库都在主 App 的
// 批量解析待确认流里做，扩展绝不直接写 SwiftData。

enum ShareChannel {
    /// suite 名走 AppGroupResolver（v4.6，与主 App WidgetSummaryWriter 同口径）：
    /// AltSign 重签后真实组名带 TeamID 后缀，硬编码原组名会让 containerURL 判据失效
    static var suiteName: String { AppGroupResolver.groupID }
    static let ledgerListKey = "ledgerList"
    static let textKey = "shareImportText"
    static let ledgerIDKey = "shareImportLedgerID"
    static let deepLink = "liqian://share-import"

    struct LedgerItem: Codable, Identifiable {
        var id: UUID
        var title: String
        var date: String
    }

    /// App Group 真可用才返回共享 defaults。判据用 containerURL：
    /// UserDefaults(suiteName:) 本身永远非 nil，重签剥掉 group
    /// entitlement 时它读不到共享数据也只会静默返回空，不能当判据。
    static var groupDefaults: UserDefaults? {
        guard FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: suiteName
        ) != nil else { return nil }
        return UserDefaults(suiteName: suiteName)
    }

    static func loadLedgers(from defaults: UserDefaults) -> [LedgerItem] {
        guard let data = defaults.data(forKey: ledgerListKey),
              let items = try? JSONDecoder().decode([LedgerItem].self, from: data)
        else { return [] }
        return items
    }
}

// MARK: - 状态与动作

@MainActor
final class ShareImportModel: ObservableObject {
    enum Phase {
        case loading
        /// App Group 不可用（侧载重签剥掉了 group）：明示降级，不假装成功
        case unsupported
        /// 已激活进来却没读到文本（激活规则理论上拦得住，留个安全口）
        case noText
        case ready
    }

    @Published var phase: Phase = .loading
    @Published var text = ""
    @Published var ledgers: [ShareChannel.LedgerItem] = []
    @Published var selectedLedgerID: UUID?
    /// 已暂存但自动打开主 App 失败：提示用户手动打开礼记完成导入
    @Published var openFailed = false

    weak var extensionContext: NSExtensionContext?
    /// 由宿主 VC 注入：结束本次分享（completeRequest）
    var onFinish: (() -> Void)?
    var onCancel: (() -> Void)?

    /// 朱砂（与 App 品牌色同值；扩展不链 LiqianDesign，镜像一处常量）
    static let brand = Color(red: 166.0 / 255, green: 43.0 / 255, blue: 31.0 / 255)

    func load() async {
        guard let defaults = ShareChannel.groupDefaults else {
            phase = .unsupported
            return
        }
        ledgers = ShareChannel.loadLedgers(from: defaults)
        // 快照顺序即主 App 的日期倒序，第一本＝最近一本，默认选中
        selectedLedgerID = ledgers.first?.id
        let collected = await Self.collectText(from: extensionContext)
        guard !collected.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            phase = .noText
            return
        }
        text = collected
        phase = .ready
    }

    /// 从全部 inputItems 里收齐纯文本（微信接龙通常就一段，多段以换行拼）
    private static func collectText(from context: NSExtensionContext?) async -> String {
        let items = (context?.inputItems as? [NSExtensionItem]) ?? []
        let providers = items.flatMap { $0.attachments ?? [] }
            .filter { $0.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) }
        var parts: [String] = []
        for provider in providers {
            if let piece = await loadText(provider), !piece.isEmpty {
                parts.append(piece)
            }
        }
        return parts.joined(separator: "\n")
    }

    private static func loadText(_ provider: NSItemProvider) async -> String? {
        await withCheckedContinuation { continuation in
            provider.loadItem(
                forTypeIdentifier: UTType.plainText.identifier, options: nil
            ) { item, _ in
                switch item {
                case let string as String:
                    continuation.resume(returning: string)
                case let data as Data:
                    continuation.resume(
                        returning: String(data: data, encoding: .utf8)
                    )
                case let url as URL:
                    // 文件形态的文本：读进来（接龙场景罕见，兜底）
                    continuation.resume(
                        returning: try? String(contentsOf: url, encoding: .utf8)
                    )
                default:
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    /// 暂存 → 尝试打开主 App。打开成功由主 App 接管，本扩展随即结束；
    /// 打不开（分享扩展 open 常被系统拒）就明示让用户手动打开礼记。
    func stageAndOpen() {
        guard let defaults = ShareChannel.groupDefaults else {
            phase = .unsupported
            return
        }
        defaults.set(text, forKey: ShareChannel.textKey)
        if let selectedLedgerID {
            defaults.set(selectedLedgerID.uuidString, forKey: ShareChannel.ledgerIDKey)
        } else {
            defaults.removeObject(forKey: ShareChannel.ledgerIDKey)
        }
        guard let url = URL(string: ShareChannel.deepLink) else { return }
        extensionContext?.open(url) { [weak self] success in
            Task { @MainActor in
                guard let self else { return }
                if success {
                    self.onFinish?()
                } else {
                    self.openFailed = true
                }
            }
        }
    }
}

// MARK: - 界面（极简：预览 + 选礼簿 + 一个动作按钮）

struct ShareImportView: View {
    @ObservedObject var model: ShareImportModel

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("导入到礼记")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("取消") { model.onCancel?() }
                    }
                }
        }
        .task { await model.load() }
    }

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .loading:
            ProgressView("正在读取分享的文字…")
        case .unsupported:
            messageView(
                icon: "exclamationmark.triangle",
                text: "当前安装方式不支持分享导入，请复制文本后在 App 内用批量补录"
            )
        case .noText:
            messageView(
                icon: "text.badge.xmark",
                text: "没收到可导入的文字。把接龙文字复制好，用系统分享再试一次。"
            )
        case .ready:
            readyForm
        }
    }

    private func messageView(icon: String, text: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: icon)
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text(text)
                .font(.callout)
                .multilineTextAlignment(.center)
            Button("关闭") { model.onFinish?() }
                .buttonStyle(.bordered)
        }
        .padding(24)
    }

    private var readyForm: some View {
        Form {
            Section("分享的文字") {
                Text(previewText)
                    .font(.callout)
                    .lineLimit(10)
                Text("共 \(model.text.count) 字，进礼记后逐笔核对再入账")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            if !model.ledgers.isEmpty {
                Section("记到哪本礼簿") {
                    Picker("礼簿", selection: $model.selectedLedgerID) {
                        ForEach(model.ledgers) { ledger in
                            Text(ledger.title).tag(Optional(ledger.id))
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }
            } else {
                Section {
                    Text("还没读到礼簿清单，导入后会记到最近一本礼簿，进 App 时可以再改。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            Section {
                if model.openFailed {
                    Text("已经存好了。打开「礼记」就会接着让你核对导入。")
                        .font(.callout)
                    Button("完成") { model.onFinish?() }
                        .font(.body.weight(.semibold))
                } else {
                    Button {
                        model.stageAndOpen()
                    } label: {
                        Text("存入并打开礼记")
                            .font(.body.weight(.semibold))
                            .frame(maxWidth: .infinity)
                    }
                    .tint(ShareImportModel.brand)
                }
            }
        }
    }

    /// 预览截断：前 400 字足够认出是不是那段接龙，全文在暂存里不丢
    private var previewText: String {
        if model.text.count > 400 {
            return String(model.text.prefix(400)) + "…"
        }
        return model.text
    }
}

// MARK: - 宿主控制器（NSExtensionPrincipalClass）
// 标 @MainActor：要初始化同为 @MainActor 的 model，UIKit 回调本就都在主线程。

@MainActor
final class ShareViewController: UIViewController {
    private let model = ShareImportModel()

    override func viewDidLoad() {
        super.viewDidLoad()
        model.extensionContext = extensionContext
        model.onFinish = { [weak self] in
            self?.extensionContext?.completeRequest(
                returningItems: [], completionHandler: nil
            )
        }
        model.onCancel = { [weak self] in
            let error = NSError(
                domain: "site.didichou.liqian.share",
                code: NSUserCancelledError, userInfo: nil
            )
            self?.extensionContext?.cancelRequest(withError: error)
        }
        let host = UIHostingController(rootView: ShareImportView(model: model))
        addChild(host)
        host.view.frame = view.bounds
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(host.view)
        host.didMove(toParent: self)
    }
}
