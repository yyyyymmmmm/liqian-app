import Combine
import Foundation
import StoreKit
import LiqianCore

// MARK: - StoreKit 2 封装（v5 买断闭环）
// 职责边界：本类只与商店对话（查产品、购买、监听交易、恢复购买），
// 权益真相＝Transaction.currentEntitlements 里 .verified 且未撤销的
// 交易集合；「算不算已购」的判定不在这里，去 LiqianCore.ProEntitlement。
// 价格只读 Product.displayPrice，本文件禁止出现任何价格文案。

@MainActor
final class StoreKitManager: ObservableObject {
    /// Pro 产品（未从商店取到时为 nil，付费墙据此显示读取中/重试）
    @Published private(set) var product: Product?
    /// 已验证且未撤销的产品 id 集合（权益刷新的唯一输入）
    @Published private(set) var verifiedProductIDs: Set<String> = []
    @Published private(set) var isPurchasing = false
    @Published private(set) var isRestoring = false
    /// 最近一次商店错误（用户可见口径，付费墙原样呈现）
    @Published var lastError: String?

    private var updatesTask: Task<Void, Never>?

    init() {
        updatesTask = Task.detached { [weak self] in
            // 购买完成/续订类交易推送：验签后结束交易并刷新权益
            for await result in Transaction.updates {
                if case .verified(let transaction) = result {
                    await transaction.finish()
                    await self?.refreshEntitlements()
                }
            }
        }
        Task {
            await loadProduct()
            await refreshEntitlements()
        }
    }

    deinit { updatesTask?.cancel() }

    /// 查产品（价格在 App Store Connect 侧维护）
    func loadProduct() async {
        do {
            let products = try await Product.products(for: [LiqianConstants.proProductID])
            product = products.first
            if products.isEmpty {
                lastError = "商店暂时没有返回商品信息，请稍后再试。"
            }
        } catch {
            lastError = "无法连接商店：\(error.localizedDescription)"
        }
    }

    /// 发起购买：成功后 finish 并刷新权益；取消不报错；待批准（如家长
    /// 同意）明确提示，不假装已开通。
    func purchase() async {
        if product == nil { await loadProduct() }
        guard let product else { return }
        isPurchasing = true
        defer { isPurchasing = false }
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                if case .verified(let transaction) = verification {
                    await transaction.finish()
                    await refreshEntitlements()
                } else {
                    lastError = "购买验证未通过，未完成开通，请稍后重试。"
                }
            case .userCancelled:
                break
            case .pending:
                lastError = "购买正在等待确认，确认通过后会自动开通。"
            @unknown default:
                break
            }
        } catch {
            lastError = "购买失败：\(error.localizedDescription)"
        }
    }

    /// 恢复购买：AppStore.sync 拉回历史交易后刷新权益；与购买按钮
    /// 同级呈现（付费墙定版），恢复不到要明确告知而不是静默。
    func restore() async {
        isRestoring = true
        defer { isRestoring = false }
        do {
            try await AppStore.sync()
            await refreshEntitlements()
            if !verifiedProductIDs.contains(LiqianConstants.proProductID) {
                lastError = "没有找到可恢复的购买记录。"
            }
        } catch {
            lastError = "恢复失败：\(error.localizedDescription)"
        }
    }

    /// 刷新权益：只收 .verified 且未被撤销/退款的交易
    func refreshEntitlements() async {
        var ids: Set<String> = []
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result, transaction.revocationDate == nil {
                ids.insert(transaction.productID)
            }
        }
        verifiedProductIDs = ids
    }
}

// MARK: - 权益单点（全 App 只问它）
// 四个门控面与付费墙都只读本中心的 isPro，不许直接碰 StoreKitManager
// 的交易集合，更不许各自拼判定。机主构建旗在此收敛：CI 侧载构建经
// 环境注入 SWIFT_ACTIVE_COMPILATION_CONDITIONS=LIQIAN_OWNER_BUILD，
// 此旗开启时权益视为已购（机主自用机放行）；App Store 构建不带此旗，
// 上架前移除步骤见 docs/V5-NOTES.md。

@MainActor
final class EntitlementCenter: ObservableObject {
    let store = StoreKitManager()

    @Published private(set) var isPro: Bool

    /// 机主构建旗（编译期常量，商店构建恒 false）
    static var isOwnerBuild: Bool {
        #if LIQIAN_OWNER_BUILD
        return true
        #else
        return false
        #endif
    }

    init() {
        isPro = Self.isOwnerBuild
        store.$verifiedProductIDs
            .map { ProEntitlement.isPro(verifiedProductIDs: $0, ownerBuild: Self.isOwnerBuild) }
            .receive(on: RunLoop.main)
            .assign(to: &$isPro)
    }

    /// 门控面可用性（与 isPro 同口径，留具名入口便于日后分档）
    func canUse(_ feature: ProFeature) -> Bool {
        ProEntitlement.canUse(feature, verifiedProductIDs: store.verifiedProductIDs, ownerBuild: Self.isOwnerBuild)
    }
}
