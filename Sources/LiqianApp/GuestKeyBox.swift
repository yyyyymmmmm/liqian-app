import Foundation

/// 扫码随礼配发键（ISSUE_KEY）解码盒（v5.12）。
///
/// 键以 GitHub Actions Secret 保管，CI 构建前由 scripts/gen-guest-secrets.py
/// 生成 GuestSecrets.swift（.gitignore，不进仓库）：键字节经 XOR 掩码＋base64
/// 才落进源码与 IPA，包内 grep 不到明文。掩码只是防直读，不是加密——
/// 这把键的定位是「配发门槛」（防路人裸调建场次接口），真安全靠服务端限流
/// 与 hostSecret/publicToken 两把随机令牌（契约 §5）。
/// 无键构建（占位）时 issueKey 为 nil，宾客码功能整体降级为「暂未开通」。
enum GuestKeyBox {
    private static let mask: [UInt8] = Array("liqian-guest-v1-mask".utf8)

    static var issueKey: String? {
        guard !GuestSecrets.isPlaceholder,
              let data = Data(base64Encoded: GuestSecrets.encodedIssueKeyBase64),
              !data.isEmpty else { return nil }
        let bytes = data.enumerated().map { index, byte in
            byte ^ mask[index % mask.count]
        }
        let value = String(bytes: bytes, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (value?.isEmpty == false) ? value : nil
    }

    static var isAvailable: Bool { issueKey != nil }
}
