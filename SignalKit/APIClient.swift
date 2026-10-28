import Foundation

enum ClientFailure: LocalizedError {
    case invalidAddress, authentication, rejected(Int), invalidResponse, payloadTooLarge, cacheUnavailable, serverChanged, staleSnapshot
    var errorDescription: String? {
        switch self {
        case .invalidAddress: return "Use HTTPS, or HTTP with a canonical private home IPv4 address. No embedded credentials, query or fragment."
        case .authentication: return "Authentication failed. Check your dedicated home-server credential. Saved data is unchanged."
        case .rejected(403): return "Collection is disabled by the server operator. Saved data is still available."
        case .rejected(409): return "The server is refreshing. Finish or resume that operation before editing or downloading."
        case .rejected(404): return "This operation is unavailable. Check that the backend supports manual refresh and snapshots."
        case .rejected(let status): return "Home server rejected the request (HTTP \(status)). Saved data is unchanged."
        case .invalidResponse: return "Incompatible or incomplete snapshot. Update the app/backend; saved data is unchanged."
        case .payloadTooLarge: return "Snapshot exceeds the supported size. Saved data is unchanged."
        case .cacheUnavailable: return "Saved data could not be read or written. It has not been cleared."
        case .serverChanged: return "Backend identity changed. Explicitly reconnect in Settings to select that server."
        case .staleSnapshot: return "An older server revision was rejected. Saved data is unchanged."
        }
    }
}
final class NoRedirect: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}
struct APIClient {
    let baseURL: URL
    private let token: String
    private let session: URLSession
    static let maximumBytes = 16 * 1024 * 1024
    static func privateIPv4(_ host: String) -> Bool {
        let parts = host.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return false }
        let values = parts.compactMap { Int($0) }
        guard values.count == 4, zip(parts, values).allSatisfy({ String($0.1) == String($0.0) && (0...255).contains($0.1) }) else { return false }
        return values[0] == 10 || (values[0] == 172 && (16...31).contains(values[1])) || (values[0] == 192 && values[1] == 168)
    }
    static func validatedAddress(_ text: String) throws -> URL {
        guard let parts = URLComponents(string: text.trimmingCharacters(in: .whitespacesAndNewlines)),
              let scheme = parts.scheme?.lowercased(), let host = parts.host, !host.isEmpty,
              scheme == "https" || (scheme == "http" && privateIPv4(host)),
              parts.user == nil, parts.password == nil, parts.query == nil, parts.fragment == nil,
              parts.port == nil || (1...65535).contains(parts.port!), let url = parts.url else { throw ClientFailure.invalidAddress }
        return url
    }
    init(baseURL: URL, token: String, session: URLSession? = nil) {
        self.baseURL = baseURL; self.token = token
        let config = URLSessionConfiguration.ephemeral
        config.httpShouldSetCookies = false; config.httpCookieStorage = nil; config.urlCache = nil
        config.timeoutIntervalForRequest = 25; config.timeoutIntervalForResource = 45
        self.session = session ?? URLSession(configuration: config, delegate: NoRedirect(), delegateQueue: nil)
    }
    func makeRequest(_ path: String, method: String = "GET", body: Data? = nil, key: String? = nil) throws -> URLRequest {
        var parts = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)!
        parts.path = "/" + ([parts.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")), path].filter { !$0.isEmpty }.joined(separator: "/"))
        guard let url = parts.url else { throw ClientFailure.invalidAddress }
        var request = URLRequest(url: url); request.httpMethod = method; request.httpBody = body
        request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if body != nil { request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        if let key { request.setValue(key, forHTTPHeaderField: "Idempotency-Key") }
        return request
    }
    func data(_ path: String, method: String = "GET", body: Data? = nil, key: String? = nil) async throws -> Data {
        let (bytes, response) = try await session.bytes(for: makeRequest(path, method: method, body: body, key: key))
        guard let http = response as? HTTPURLResponse else { throw ClientFailure.invalidResponse }
        if http.statusCode == 401 { throw ClientFailure.authentication }
        guard (200...299).contains(http.statusCode) else { throw ClientFailure.rejected(http.statusCode) }
        guard response.expectedContentLength <= Self.maximumBytes else { throw ClientFailure.payloadTooLarge }
        var result = Data()
        for try await byte in bytes {
            if result.count >= Self.maximumBytes { throw ClientFailure.payloadTooLarge }
            result.append(byte)
        }
        return result
    }
    func get<T: Decodable>(_ path: String) async throws -> T { try Self.decode(await data(path)) }
    func refresh(key: String) async throws -> RefreshJob { try Self.decode(await data("v1/refresh", method: "POST", body: Data("{}".utf8), key: key)) }
    func send<T: Encodable, R: Decodable>(_ path: String, method: String, value: T) async throws -> R { try Self.decode(await data(path, method: method, body: Self.encode(value))) }
    static func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder(); encoder.keyEncodingStrategy = .convertToSnakeCase
        return try encoder.encode(value)
    }
    static func decode<T: Decodable>(_ data: Data) throws -> T {
        let decoder = JSONDecoder(); decoder.keyDecodingStrategy = .convertFromSnakeCase
        do { return try decoder.decode(T.self, from: data) }
        catch { throw ClientFailure.invalidResponse }
    }
}
