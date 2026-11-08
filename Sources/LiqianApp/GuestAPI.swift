import Foundation
import Security
import LiqianCore

// MARK: - hostSecret 钥匙串（按场次一把，account = eventId）

/// 主家凭证只存本机 Keychain：不进 SwiftData、不进备份、不写日志
/// （契约明示：丢了不可恢复，只能重新生成场次）。形态与 DeepSeek 的
/// KeychainStore 同构，只是 account 按场次分开。
enum GuestKeychain {
    private static let service = "site.didichou.liqian.guest"

    private static func baseQuery(eventID: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: eventID,
        ]
    }

    static func read(eventID: String) -> String? {
        var query = baseQuery(eventID: eventID)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        let value = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (value?.isEmpty == false) ? value : nil
    }

    static func save(_ value: String, eventID: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let data = trimmed.data(using: .utf8) else { return }
        let attributes: [String: Any] = [kSecValueData as String: data]
        let status = SecItemUpdate(baseQuery(eventID: eventID) as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var query = baseQuery(eventID: eventID)
            query[kSecValueData as String] = data
            SecItemAdd(query as CFDictionary, nil)
        }
    }

    static func delete(eventID: String) {
        SecItemDelete(baseQuery(eventID: eventID) as CFDictionary)
    }
}

// MARK: - 错误口径（给人看的状态行，不静默吞、不抛英文原文）

enum GuestAPIError: Error, Equatable {
    /// 无配发键构建：功能未开通
    case notConfigured
    /// 401：配发键/hostSecret 不对或已失效
    case unauthorized
    /// 429：操作太频繁
    case rateLimited
    /// 服务端给的中文原因（400/404/410 等）
    case server(String)
    /// 网络层失败
    case network
    /// 响应不是契约形状
    case badResponse

    var userMessage: String {
        switch self {
        case .notConfigured:
            return "宾客码暂未开通"
        case .unauthorized:
            return "凭证对不上，没能连上云端"
        case .rateLimited:
            return "操作太频繁，过一会儿再试"
        case .server(let message):
            return message
        case .network:
            return "网络不通，没能连上云端"
        case .badResponse:
            return "云端返回异常，请稍后再试"
        }
    }
}

// MARK: - 契约客户端（URLSession 直连，无第三方库）

/// Base 与端点见 liqian-guest/API.md；since 编码走 Core 的
/// GuestSyncPlanner.encodeSince（+ 必须 %2B，手工拼 URL 保证编码不被二次处理）。
struct GuestAPIClient {
    static let baseURL = "https://sui.inkroot.cn"

    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    /// 建场次（配发键鉴权）。title/date/type 由调用方按礼簿给出。
    func createEvent(title: String, date: String, type: String) async throws -> GuestEventCreatedDTO {
        guard let key = GuestKeyBox.issueKey else { throw GuestAPIError.notConfigured }
        var request = URLRequest(url: URL(string: "\(Self.baseURL)/api/events")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(
            CreateEventBody(title: title, date: date, type: type)
        )
        let decoded: GuestEventCreatedDTO = try await send(request)
        return decoded
    }

    /// 增量拉取（hostSecret 鉴权）；since 为 nil 时全量。
    func fetchSubmissions(
        eventID: String, hostSecret: String, since: String?
    ) async throws -> GuestSubmissionsResponseDTO {
        var urlString = "\(Self.baseURL)/api/events/\(eventID)/submissions"
        if let since {
            urlString += "?since=\(GuestSyncPlanner.encodeSince(since))"
        }
        var request = URLRequest(url: URL(string: urlString)!)
        request.setValue("Bearer \(hostSecret)", forHTTPHeaderField: "Authorization")
        let decoded: GuestSubmissionsResponseDTO = try await send(request)
        return decoded
    }

    /// 关闭收集（幂等，无重开；重开走新建场次）
    func closeEvent(eventID: String, hostSecret: String) async throws {
        var request = URLRequest(url: URL(string: "\(Self.baseURL)/api/events/\(eventID)/close")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(hostSecret)", forHTTPHeaderField: "Authorization")
        let _: OKResponse = try await send(request)
    }

    /// 删除一条提交（主家忽略回执时同步删云端，best-effort 由调用方定）
    func deleteSubmission(eventID: String, hostSecret: String, submissionID: Int) async throws {
        var request = URLRequest(
            url: URL(string: "\(Self.baseURL)/api/events/\(eventID)/submissions/\(submissionID)")!
        )
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(hostSecret)", forHTTPHeaderField: "Authorization")
        let _: OKResponse = try await send(request)
    }

    // MARK: - 传输与错误归一

    private struct CreateEventBody: Encodable {
        var title: String
        var date: String
        var type: String
    }

    private struct OKResponse: Decodable {
        var ok: Bool
    }

    private struct ErrorBody: Decodable {
        var ok: Bool?
        var error: String?
    }

    private func send<T: Decodable>(_ request: URLRequest) async throws -> T {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw GuestAPIError.network
        }
        guard let http = response as? HTTPURLResponse else { throw GuestAPIError.badResponse }
        switch http.statusCode {
        case 200...299:
            guard let decoded = try? JSONDecoder().decode(T.self, from: data) else {
                throw GuestAPIError.badResponse
            }
            return decoded
        case 401:
            throw GuestAPIError.unauthorized
        case 429:
            throw GuestAPIError.rateLimited
        default:
            if let body = try? JSONDecoder().decode(ErrorBody.self, from: data),
               let message = body.error, !message.isEmpty {
                throw GuestAPIError.server(message)
            }
            throw GuestAPIError.badResponse
        }
    }
}
