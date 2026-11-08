import Foundation
import Security
import LiqianCore

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
            return "还没填 DeepSeek 的 API Key。先到「我的 → AI 管家」里填上你自己的 API Key，存在本机钥匙串里，不会上传。"
        case .notEnabled:
            return "AI 功能还没打开。先到「我的 → AI 管家」里把开关打开。"
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
    /// HTTP 状态码＋服务端返回的真实 error message（v5.4：只报状态码
    /// 定位不了问题——验证 400 假失败就是被这一层吞掉了真实原因）
    case http(Int, String?)
    case network(String)
    case badResponse(String)

    var errorDescription: String? {
        switch self {
        case .noKey:
            return "还没填 DeepSeek 的 API Key，先到「我的 → AI 管家」里填上。"
        case .http(let code, let serverMessage):
            if code == 401 || code == 403 {
                return "API Key 被拒绝，请检查是否填写正确、账户余额是否充足。"
            }
            if code == 429 {
                return "请求过于频繁，请稍后重试"
            }
            if let serverMessage, !serverMessage.isEmpty {
                return "DeepSeek 返回异常（\(code)）：\(serverMessage)"
            }
            return "DeepSeek 返回异常，请稍后重试。"
        case .network:
            return "网络连接失败，请检查网络后重试"
        case .badResponse(let detail):
            return "AI 返回内容格式异常，无法解析：\(detail)"
        }
    }

    /// 从错误响应体里挖服务端给的真实原因（DeepSeek 口径：
    /// {"error":{"message":"…","type":"…","code":"…"}}）；挖不到回 nil
    static func serverMessage(from data: Data) -> String? {
        guard
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let error = root["error"] as? [String: Any],
            let message = error["message"] as? String
        else { return nil }
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    static func httpError(statusCode: Int, data: Data) -> DeepSeekError {
        .http(statusCode, serverMessage(from: data))
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
    /// timeout 是本腿的请求超时（v5.8：问账管线按全链总预算分腿传入，
    /// 缺省 30 秒与旧口径一致，其他调用方不变）。
    func chatJSON(system: String, user: String, timeout: TimeInterval = 30) async throws -> Data {
        let content = try await chat(system: system, user: user, jsonMode: true, timeout: timeout)
        return Data(content.utf8)
    }

    /// 普通文本对话（贺词生成用）；timeout 口径同 chatJSON
    func chatText(system: String, user: String, timeout: TimeInterval = 30) async throws -> String {
        try await chat(system: system, user: user, jsonMode: false, timeout: timeout)
    }

    private func chat(system: String, user: String, jsonMode: Bool, timeout: TimeInterval) async throws -> String {
        var request = URLRequest(url: URL(string: "https://api.deepseek.com/chat/completions")!)
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
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
                throw DeepSeekError.network("请求超时（\(Int(timeout.rounded())) 秒）")
            }
            throw DeepSeekError.network(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw DeepSeekError.badResponse("没有收到有效的服务器响应")
        }
        guard http.statusCode == 200 else {
            throw DeepSeekError.httpError(statusCode: http.statusCode, data: data)
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

// MARK: - 工具调用（v5.2，DeepSeek 官方 function calling 口径）
//
// 请求体在 messages 之外多带 tools（AdvisorTools.definitionsJSON 的数组）
// 与 tool_choice:"auto"；模型要查数据时，返回 message.tool_calls
// （每条含 id＋function.name＋function.arguments 字符串），App 本地执行
// 后把结果以 role:"tool"＋tool_call_id 回填，再请求一次，如此往返。

/// 一次工具调用引用（模型给出，App 按 name 在本地执行）
struct DeepSeekToolCallRef: Equatable {
    var id: String
    var name: String
    /// 参数 JSON 原文（解码在 AdvisorToolEngine 里宽容处理）
    var arguments: String
}

/// 工具对话里的一条消息（system/user/assistant/tool 四种角色的多轮拼装）
struct DeepSeekChatMessage {
    var role: String
    var content: String? = nil
    /// 仅 assistant：模型本轮要调的工具
    var toolCalls: [DeepSeekToolCallRef]? = nil
    /// 仅 tool：回填结果对应哪次调用
    var toolCallID: String? = nil

    func jsonObject() -> [String: Any] {
        var obj: [String: Any] = ["role": role]
        if let toolCalls {
            obj["content"] = content ?? ""
            obj["tool_calls"] = toolCalls.map { call in
                [
                    "id": call.id,
                    "type": "function",
                    "function": ["name": call.name, "arguments": call.arguments],
                ] as [String: Any]
            }
        } else if role == "tool" {
            obj["content"] = content ?? ""
            obj["tool_call_id"] = toolCallID ?? ""
        } else {
            obj["content"] = content ?? ""
        }
        return obj
    }
}

/// 一轮工具对话的结果：模型直接给了文字，或要求先调工具
enum DeepSeekTurn {
    case text(String)
    case toolCalls([DeepSeekToolCallRef])
}

extension DeepSeekClient {
    /// 工具对话一轮：带 tools 定义请求，回来或文字或工具调用。
    /// 任何协议异常都抛 DeepSeekError，由调用方决定降级路径。
    /// timeout 口径同 chatJSON（v5.8 分腿预算，缺省 30 秒）。
    func chatTurn(messages: [DeepSeekChatMessage], toolsJSON: String, timeout: TimeInterval = 30) async throws -> DeepSeekTurn {
        var request = URLRequest(url: URL(string: "https://api.deepseek.com/chat/completions")!)
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        guard let toolsData = toolsJSON.data(using: .utf8),
              let tools = try? JSONSerialization.jsonObject(with: toolsData) else {
            throw DeepSeekError.badResponse("工具定义序列化失败")
        }
        let body: [String: Any] = [
            "model": "deepseek-chat",
            "temperature": 0.2,
            "messages": messages.map { $0.jsonObject() },
            "tools": tools,
            "tool_choice": "auto",
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch let error as URLError {
            if error.code == .timedOut {
                throw DeepSeekError.network("请求超时（\(Int(timeout.rounded())) 秒）")
            }
            throw DeepSeekError.network(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else {
            throw DeepSeekError.badResponse("没有收到有效的服务器响应")
        }
        guard http.statusCode == 200 else {
            throw DeepSeekError.httpError(statusCode: http.statusCode, data: data)
        }
        guard
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let choices = root["choices"] as? [[String: Any]],
            let message = choices.first?["message"] as? [String: Any]
        else {
            throw DeepSeekError.badResponse("返回里没有可用的内容")
        }
        if let rawCalls = message["tool_calls"] as? [[String: Any]], !rawCalls.isEmpty {
            let calls = rawCalls.compactMap { raw -> DeepSeekToolCallRef? in
                guard
                    let id = raw["id"] as? String,
                    let function = raw["function"] as? [String: Any],
                    let name = function["name"] as? String
                else { return nil }
                return DeepSeekToolCallRef(
                    id: id, name: name, arguments: function["arguments"] as? String ?? "{}"
                )
            }
            if !calls.isEmpty { return .toolCalls(calls) }
        }
        let content = (message["content"] as? String ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else {
            throw DeepSeekError.badResponse("模型既没给回答也没调工具")
        }
        return .text(content)
    }

    /// Key 验证探活（v5.4）：走与正式问账完全同一条 chatTurn 路径
    /// （同端点、同模型、同 tools 形状）发一次极小真实请求。
    /// v5.2.1 的旧验证走 chatJSON 自造了第二种请求形状（response_format
    /// json_object＋提示词里没有 "json" 字样），被接口按 400 打回——
    /// Key 与问账链路其实没事，验证却报失败（用户实锤）。探活只认
    /// 「链路通没通」：回来文字或工具调用都算通；失败抛 DeepSeekError，
    /// 其中 http 带服务端真实 error message，设置页原样呈现。
    func verifyKey() async throws {
        let turn = try await chatTurn(
            messages: [
                DeepSeekChatMessage(
                    role: "system",
                    content: "你是「礼记」的问账管家。这是一次连通性确认，用户没有问账目问题，请只回复一个字：好。不要调用任何工具。"
                ),
                DeepSeekChatMessage(role: "user", content: "在吗"),
            ],
            toolsJSON: AdvisorTools.definitionsJSON()
        )
        switch turn {
        case .text, .toolCalls:
            return // 能按正式协议应答即链路通、Key 可用
        }
    }
}
