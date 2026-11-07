import Foundation
import Security

// MARK: - API Key 钥匙串存取（最小实现，不引第三方库）

/// DeepSeek API Key 只存本机 Keychain，不进 UserDefaults、不进备份。
enum KeychainStore {
    private static let service = "site.didichou.liqian.deepseek"
    private static let account = "apiKey"

    private static var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    static func read() -> String? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        let value = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (value?.isEmpty == false) ? value : nil
    }

    /// 保存（已有则更新，没有则新增）
    static func save(_ value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let data = trimmed.data(using: .utf8) else { return }
        let attributes: [String: Any] = [kSecValueData as String: data]
        let status = SecItemUpdate(baseQuery as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var query = baseQuery
            query[kSecValueData as String] = data
            SecItemAdd(query as CFDictionary, nil)
        }
    }

    static func delete() {
        SecItemDelete(baseQuery as CFDictionary)
    }
}

// MARK: - AI 可用性（入口点了先判断，给引导而不是白屏报错）

enum AIReadiness {
    case ready
    case noKey
    case notEnabled

    var guideMessage: String {
        switch self {
        case .ready:
            return ""
        case .noKey:
            return "还没填 DeepSeek 的 API Key。先到「我的 → AI 智能助手」里填上你自己的 API Key，存在本机钥匙串里，不会上传。"
        case .notEnabled:
            return "AI 功能还没打开。先到「我的 → AI 智能助手」里把开关打开。"
        }
    }
}

extension Notification.Name {
    /// AI 引导 alert 的「去设置」动作：ContentView 收到后切到「我的」Tab
    static let liqianOpenAISettings = Notification.Name("liqianOpenAISettings")
}

enum AIAccess {
    /// aiEnabled 与 RecordForm/AISettings 里的 @AppStorage 用同一个键
    static let enabledKey = "aiEnabled"

    static func readiness() -> AIReadiness {
        if KeychainStore.read() == nil { return .noKey }
        if !UserDefaults.standard.bool(forKey: enabledKey) { return .notEnabled }
        return .ready
    }
}

// MARK: - DeepSeek 客户端

enum DeepSeekError: LocalizedError {
    case noKey
    case http(Int)
    case network(String)
    case badResponse(String)

    var errorDescription: String? {
        switch self {
        case .noKey:
            return "还没填 DeepSeek 的 API Key，先到「我的 → AI 智能助手」里填上。"
        case .http(let code):
            if code == 401 || code == 403 {
                return "API Key 被拒绝，请检查是否填写正确、账户余额是否充足。"
            }
            if code == 429 {
                return "请求过于频繁，请稍后重试"
            }
            return "DeepSeek 返回异常，请稍后重试。"
        case .network:
            return "网络连接失败，请检查网络后重试"
        case .badResponse(let detail):
            return "AI 返回内容格式异常，无法解析：\(detail)"
        }
    }
}

/// 无共享可变状态的 struct 客户端：每次用时现取 Keychain 里的 key。
struct DeepSeekClient {
    private let apiKey: String

    init() throws {
        guard let key = KeychainStore.read() else { throw DeepSeekError.noKey }
        apiKey = key
    }

    /// JSON 模式对话：返回模型输出的 content 原始字节（调用方再做结构校验）
    func chatJSON(system: String, user: String) async throws -> Data {
        let content = try await chat(system: system, user: user, jsonMode: true)
        return Data(content.utf8)
    }

    /// 普通文本对话（贺词生成用）
    func chatText(system: String, user: String) async throws -> String {
        try await chat(system: system, user: user, jsonMode: false)
    }

    private func chat(system: String, user: String, jsonMode: Bool) async throws -> String {
        var request = URLRequest(url: URL(string: "https://api.deepseek.com/chat/completions")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        var body: [String: Any] = [
            "model": "deepseek-chat",
            "temperature": 0.2,
            "messages": [
                ["role": "system", "content": system],
                ["role": "user", "content": user],
            ],
        ]
        if jsonMode {
            body["response_format"] = ["type": "json_object"]
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch let error as URLError {
            if error.code == .timedOut {
                throw DeepSeekError.network("请求超时（30 秒）")
            }
            throw DeepSeekError.network(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw DeepSeekError.badResponse("没有收到有效的服务器响应")
        }
        guard http.statusCode == 200 else {
            throw DeepSeekError.http(http.statusCode)
        }

        guard
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let choices = root["choices"] as? [[String: Any]],
            let message = choices.first?["message"] as? [String: Any],
            let content = message["content"] as? String,
            !content.isEmpty
        else {
            throw DeepSeekError.badResponse("返回里没有可用的内容")
        }
        return content
    }
}
