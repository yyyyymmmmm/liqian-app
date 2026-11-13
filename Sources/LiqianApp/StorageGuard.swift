import SwiftUI

/// 存储不安全时的记账入口阻断面（v5.14.2）：整页盖住表单，
/// 只留一句话与关闭——存不住的状态里不许把账记进黑洞。
/// 这不是可忽略的条幅：表单根本点不动，必须先处理存储问题。
struct StorageBlockedView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.regularMaterial)
                .ignoresSafeArea()
            VStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(.red)
                Text("存储异常")
                    .font(.headline)
                Text("数据现在存不住，先导出备份并联系支持。修好之前，先不要记账。")
                    .font(.footnote)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                Button("关闭") { dismiss() }
                    .buttonStyle(.bordered)
            }
            .padding(24)
        }
    }
}

private struct StorageBlockModifier: ViewModifier {
    @EnvironmentObject private var cloudSync: CloudSyncManager

    func body(content: Content) -> some View {
        content.overlay {
            if cloudSync.storageUnsafe {
                StorageBlockedView()
            }
        }
    }
}

extension View {
    /// 记账入口守卫（v5.14.2）：存储不安全（落盘自检失败/内存模式/
    /// 救援落盘失败）时整页阻断，挂在各记账表单的根视图上
    func storageBlockGuard() -> some View {
        modifier(StorageBlockModifier())
    }
}
