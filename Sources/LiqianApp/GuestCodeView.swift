import CoreImage
import SwiftData
import SwiftUI
import LiqianCore
import LiqianDesign

/// 宾客码（v5.12 扫码随礼）：一本礼簿一个码，绑这本簿的云端场次。
/// 宾客扫码自填的回执先落待确认区（见 GuestReceiptsView），不直写账本。
/// 无场次时一键生成；有场次时展示码、收集状态与同步状态；
/// 关闭收集后宾客页只剩「已结束」；重新生成＝关旧建新，旧回执本地保留。
struct GuestCodeView: View {
    let ledger: Ledger

    @Environment(\.modelContext) private var modelContext
    @Query private var allBindings: [GuestEventBinding]
    @ObservedObject private var center = GuestSyncCenter.shared

    @State private var working = false
    @State private var errorText: String?
    @State private var confirmClose = false
    @State private var confirmRegenerate = false

    private var binding: GuestEventBinding? {
        allBindings.first { $0.ledgerID == ledger.id }
    }

    private var isBai: Bool { ledger.isBai }

    var body: some View {
        List {
            if !GuestKeyBox.isAvailable {
                Section {
                    ContentUnavailableView {
                        Label("宾客码暂未开通", systemImage: "qrcode")
                    } description: {
                        Text("这个版本还没有配好开通凭证。")
                    }
                    .padding(.vertical, LiqianMetrics.spacingL)
                    .listRowBackground(Color.clear)
                }
            } else if let binding {
                qrSection(binding)
                statusSection(binding)
                manageSection(binding)
            } else {
                Section {
                    Text("把这个码分享给宾客，宾客扫码填下的祝福和随礼，会先回到这本礼簿的待确认区，你点头之后才入账。")
                        .font(.footnote)
                        .foregroundStyle(Palette.stone)
                    Button {
                        Task { await create() }
                    } label: {
                        HStack {
                            Text("生成宾客码")
                            if working { ProgressView() }
                        }
                    }
                    .disabled(working)
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Palette.pageBG.ignoresSafeArea())
        .navigationTitle("宾客码")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await center.sync(ledgerID: ledger.id, in: modelContext)
        }
        .alert("没能办成", isPresented: Binding(
            get: { errorText != nil },
            set: { if !$0 { errorText = nil } }
        )) {
            Button("好") { errorText = nil }
        } message: {
            Text(errorText ?? "")
        }
        .confirmationDialog("关闭收集？", isPresented: $confirmClose, titleVisibility: .visible) {
            Button("关闭收集", role: .destructive) {
                Task { await close() }
            }
            Button("先不关", role: .cancel) {}
        } message: {
            Text("关了之后宾客再扫码只会看到「本场次已结束」，已经收到的回执不受影响。之后想再收，重新生成一个码即可。")
        }
        .confirmationDialog("重新生成宾客码？", isPresented: $confirmRegenerate, titleVisibility: .visible) {
            Button("重新生成") {
                Task { await regenerate() }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("会关掉现在这个码、换一个新码；已经收到的回执还留在这本礼簿里，照常确认。印出去的旧码将不能再填。")
        }
    }

    // MARK: - 码与分享

    @ViewBuilder
    private func qrSection(_ binding: GuestEventBinding) -> some View {
        Section {
            VStack(spacing: LiqianMetrics.spacingSM) {
                if let image = Self.qrImage(for: binding.guestURL) {
                    Image(uiImage: image)
                        .interpolation(.none)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 216, height: 216)
                        .accessibilityLabel("宾客码二维码")
                }
                Text(binding.guestURL)
                    .font(.footnote)
                    .foregroundStyle(Palette.stone)
                    .textSelection(.enabled)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, LiqianMetrics.spacingSM)
        }
        Section {
            ShareLink(item: URL(string: binding.guestURL)!) {
                Label("分享链接", systemImage: "link")
                    .foregroundStyle(Palette.ink)
            }
            if let image = Self.qrImage(for: binding.guestURL) {
                ShareLink(
                    item: Image(uiImage: image),
                    preview: SharePreview("宾客码", image: Image(uiImage: image))
                ) {
                    Label("分享二维码图", systemImage: "qrcode")
                        .foregroundStyle(Palette.ink)
                }
            }
        }
    }

    // MARK: - 状态与管理

    @ViewBuilder
    private func statusSection(_ binding: GuestEventBinding) -> some View {
        Section {
            HStack {
                Text("收集状态")
                    .foregroundStyle(Palette.ink)
                Spacer()
                Text(binding.closed ? "已关闭" : "收集中")
                    .foregroundStyle(Palette.stone)
            }
            HStack {
                Text("回执同步")
                    .foregroundStyle(Palette.ink)
                Spacer()
                if center.isSyncing(ledger.id) {
                    ProgressView()
                } else {
                    Text(center.status(for: ledger.id) ?? "还没同步过")
                        .font(.footnote)
                        .foregroundStyle(Palette.stone)
                        .multilineTextAlignment(.trailing)
                }
            }
            Button {
                Task { await center.sync(ledgerID: ledger.id, in: modelContext) }
            } label: {
                Label("立即同步", systemImage: "arrow.clockwise")
                    .foregroundStyle(Palette.ink)
            }
            .disabled(center.isSyncing(ledger.id))
        }
    }

    @ViewBuilder
    private func manageSection(_ binding: GuestEventBinding) -> some View {
        Section {
            if !binding.closed {
                Button {
                    confirmClose = true
                } label: {
                    Label("关闭收集", systemImage: "lock")
                        .foregroundStyle(Palette.ink)
                }
                .disabled(working)
            }
            Button {
                confirmRegenerate = true
            } label: {
                HStack {
                    Label("重新生成", systemImage: "arrow.triangle.2.circlepath")
                        .foregroundStyle(Palette.ink)
                    if working { ProgressView() }
                }
            }
            .disabled(working)
        }
    }

    // MARK: - 动作

    private func create() async {
        working = true
        defer { working = false }
        do {
            _ = try await center.createEvent(for: ledger, in: modelContext)
        } catch let error as GuestAPIError {
            errorText = error.userMessage
        } catch {
            errorText = GuestAPIError.network.userMessage
        }
    }

    private func close() async {
        guard let binding else { return }
        working = true
        defer { working = false }
        do {
            try await center.closeEvent(binding: binding, in: modelContext)
        } catch let error as GuestAPIError {
            errorText = error.userMessage
        } catch {
            errorText = GuestAPIError.network.userMessage
        }
    }

    private func regenerate() async {
        working = true
        defer { working = false }
        do {
            _ = try await center.regenerate(for: ledger, in: modelContext)
        } catch let error as GuestAPIError {
            errorText = error.userMessage
        } catch {
            errorText = GuestAPIError.network.userMessage
        }
    }

    // MARK: - 二维码生成（CoreImage，不引第三方库）

    static func qrImage(for string: String) -> UIImage? {
        guard let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        filter.setValue(Data(string.utf8), forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")
        guard let output = filter.outputImage else { return nil }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 12, y: 12))
        guard let cgImage = CIContext().createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}
