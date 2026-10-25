import XCTest
@testable import SignalKit

final class ContractTests: XCTestCase {
    func testExactMoney() {
        XCTAssertEqual(Money.parse("0,88"), 88)
        XCTAssertEqual(Money.parse("7.99"), 799)
        XCTAssertEqual(Money.parse("1"), 100)
        XCTAssertEqual(Money.format(1099), "10,99 €")
        for invalid in ["1.001", "nan", "-1", "1.00\n", "1.00abc", ""] { XCTAssertNil(Money.parse(invalid)) }
    }
    func testConnectionBoundary() throws {
        XCTAssertEqual(try APIClient.validatedAddress("https://example.invalid/api").host, "example.invalid")
        for invalid in ["http://example.invalid", "https://user:secret@example.invalid", "https://example.invalid?token=x", "https://example.invalid/#x", "file:///private", ""] {
            XCTAssertThrowsError(try APIClient.validatedAddress(invalid))
        }
    }
    func testCredentialIsHeaderOnlyAndPathsRetainPrefix() throws {
        let api = APIClient(baseURL: try APIClient.validatedAddress("https://example.invalid/api"), token: "synthetic-only")
        let request = try api.makeRequest("v1/stores", query: [URLQueryItem(name: "postal_code", value: "00000")])
        XCTAssertEqual(request.url?.path, "/api/v1/stores")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer synthetic-only")
        XCTAssertFalse(request.url!.absoluteString.contains("synthetic-only"))
    }
    func testSettingsAndSubscriptionWireKeys() throws {
        let settings: MonitorSettings = try APIClient.decode(Data(#"{"postal_code":"00000","radius_km":10,"selected_store_ids":[],"enabled_providers":["example"]}"#.utf8))
        XCTAssertEqual(settings.postalCode, "00000")
        var subscription = Subscription(); subscription.name = "Example item"; subscription.requiredTerms = ["example"]; subscription.targetCents = 99
        let encoder = JSONEncoder(); encoder.keyEncodingStrategy = .convertToSnakeCase
        let json = try JSONSerialization.jsonObject(with: encoder.encode(subscription)) as! [String: Any]
        XCTAssertEqual(json["target_cents"] as? Int, 99)
        XCTAssertEqual(json["required_terms"] as? [String], ["example"])
    }
    func testGenericObservationDecodesUnknownsWithoutInventingZeroDeposit() throws {
        let json = #"{"id":"sample","provider":"example","product_id":"item","title":"Example item","description":"Unspecified assortment","package":"500 ml","amount":500,"unit":"ml","count":1,"price_cents":88,"reference_type":"unknown","eligibility":"unknown","variant_scope":"assortment","scope":"national","valid_from":"2026-01-01","valid_until":"2026-01-03","fetched_at":"2026-01-01T12:00:00Z","source_url":"https://example.invalid/item","stale":true}"#
        let item: SignalOffer = try APIClient.decode(Data(json.utf8))
        XCTAssertNil(item.depositCents)
        XCTAssertEqual(item.variantScope, "assortment")
        XCTAssertTrue(item.stale!)
        XCTAssertNil(item.storeId)
    }
}
