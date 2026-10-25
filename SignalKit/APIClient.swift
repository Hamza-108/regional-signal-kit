import Foundation

enum ClientFailure: LocalizedError {
    case invalidAddress, authentication, rejected(Int), invalidResponse
    var errorDescription: String? {
        switch self {
        case .invalidAddress: return "Enter an HTTPS backend URL without credentials, query or fragment."
        case .authentication: return "Authentication failed. Check your backend credential."
        case .rejected(let status): return "The server rejected this request (HTTP \(status)). Check the inputs and server configuration."
        case .invalidResponse: return "The server returned an incompatible response."
        }
    }
}
final class NoRedirect: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}
struct APIClient {
    let baseURL: URL
    private let token: String
    private let session: URLSession
    static func validatedAddress(_ text: String) throws -> URL {
        guard let parts = URLComponents(string: text.trimmingCharacters(in: .whitespacesAndNewlines)),
              parts.scheme?.lowercased() == "https", let host = parts.host, !host.isEmpty,
              parts.user == nil, parts.password == nil, parts.query == nil, parts.fragment == nil,
              let url = parts.url else { throw ClientFailure.invalidAddress }
        return url
    }
    init(baseURL: URL, token: String, session: URLSession? = nil) {
        self.baseURL = baseURL; self.token = token
        let config = URLSessionConfiguration.ephemeral
        config.httpShouldSetCookies = false
        config.httpCookieStorage = nil
        config.urlCache = nil
        config.timeoutIntervalForRequest = 25
        self.session = session ?? URLSession(configuration: config, delegate: NoRedirect(), delegateQueue: nil)
    }
    func makeRequest(_ path: String, method: String = "GET", body: Data? = nil, query: [URLQueryItem] = []) throws -> URLRequest {
        var parts = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)!
        parts.path = parts.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        parts.path = "/" + ([parts.path, path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))].filter { !$0.isEmpty }.joined(separator: "/"))
        parts.queryItems = query.isEmpty ? nil : query
        guard let url = parts.url else { throw ClientFailure.invalidAddress }
        var request = URLRequest(url: url)
        request.httpMethod = method; request.httpBody = body
        request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if body != nil { request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        return request
    }
    func data(_ path: String, method: String = "GET", body: Data? = nil, query: [URLQueryItem] = []) async throws -> Data {
        let request = try makeRequest(path, method: method, body: body, query: query)
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ClientFailure.invalidResponse }
        if http.statusCode == 401 { throw ClientFailure.authentication }
        guard (200...299).contains(http.statusCode) else { throw ClientFailure.rejected(http.statusCode) }
        return data
    }
    func get<T: Decodable>(_ path: String, query: [URLQueryItem] = []) async throws -> T {
        try Self.decode(await data(path, query: query))
    }
    func send<T: Encodable, R: Decodable>(_ path: String, method: String, value: T) async throws -> R {
        let encoder = JSONEncoder(); encoder.keyEncodingStrategy = .convertToSnakeCase
        return try Self.decode(await data(path, method: method, body: encoder.encode(value)))
    }
    static func decode<T: Decodable>(_ data: Data) throws -> T {
        let decoder = JSONDecoder(); decoder.keyDecodingStrategy = .convertFromSnakeCase
        do { return try decoder.decode(T.self, from: data) }
        catch { throw ClientFailure.invalidResponse }
    }
}
