#if DEBUG
import Foundation

/// Compiled out of release builds. Only explicitly launched synthetic tests use it.
enum UITestSupport {
    static var enabled: Bool { ProcessInfo.processInfo.arguments.contains("--uitest") }
    static var cacheRoot: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SyntheticUITests", isDirectory: true)
            .appendingPathComponent(ProcessInfo.processInfo.environment["SIGNAL_TEST_CACHE"] ?? "default", isDirectory: true)
    }
    static func session() -> URLSession {
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [SyntheticURLProtocol.self]
        return URLSession(configuration: config, delegate: NoRedirect(), delegateQueue: nil)
    }
    static func fixture(at now: Date = Date()) throws -> OfflineSnapshot {
        let today = OfferWindow.key(now)
        let offer: [String: Any] = ["id":"sample-offer", "provider":"example", "product_id":"sample-item", "title":"Example item", "brand":"Example", "description":"Synthetic published observation; not a real product", "package":"500 ml", "amount":500, "unit":"ml", "count":1, "container":"can", "price_cents":88, "deposit_cents":25, "reference_type":"unknown", "eligibility":"public", "variant_scope":"specific", "scope":"national", "valid_from":today, "valid_until":OfferWindow.end(now), "fetched_at":now.ISO8601Format(), "source_url":"https://example.invalid/item", "unit_price_cents":176]
        let watch: [String:Any] = ["id":"sample-watch", "name":"Example watch", "required_terms":["example","item"], "excluded_terms":[], "amount":500, "unit":"ml", "count":1, "target_cents":99, "allow_conditional":false, "enabled":true]
        let payload: [String:Any] = [
            "schema_version":1, "instance_id":"synthetic-instance", "revision":1,
            "generated_at":now.ISO8601Format(), "coverage_from":today, "coverage_until":OfferWindow.end(now),
            "settings":["postal_code":"00000","radius_km":10,"selected_store_ids":[],"enabled_providers":["example"]],
            "providers":[["id":"example","name":"Example source","scope":"national","limitation":"Synthetic test only"]],
            "locations":[], "unlocated_stores":[], "watchlist":[watch], "offers":[offer],
            "matches":[["watch_id":"sample-watch","offer_id":"sample-offer","match":"exact","reason":"explicit_label_and_package","target_met":true]],
            "history":[["observed_at":now.ISO8601Format(),"price_cents":88,"offer":offer]],
            "history_truncated":false, "provider_status":[], "datasets":[], "collection_enabled":true,
            "coverage":"partial", "inventory_verified":false,
        ]
        return try APIClient.decode(JSONSerialization.data(withJSONObject: payload))
    }
}
final class SyntheticURLProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            if ProcessInfo.processInfo.environment["SIGNAL_TEST_MODE"] == "offline" { throw URLError(.notConnectedToInternet) }
            let response: HTTPURLResponse; let body: Data
            if let handler = Self.handler { (response, body) = try handler(request) }
            else {
                let path = request.url!.path
                var status = 200
                if path == "/v1/snapshot" { body = try APIClient.encode(UITestSupport.fixture()) }
                else if path.hasPrefix("/v1/refresh") {
                    status = request.httpMethod == "POST" ? 202 : 200
                    body = try APIClient.encode(RefreshJob(id:"11111111-1111-4111-8111-111111111111",state:"completed",createdAt:Date().ISO8601Format(),startedAt:nil,finishedAt:Date().ISO8601Format(),error:nil,results:[]))
                } else { throw ClientFailure.invalidResponse }
                response = HTTPURLResponse(url:request.url!,statusCode:status,httpVersion:nil,headerFields:["Content-Type":"application/json"])!
            }
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: body)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}
#endif
