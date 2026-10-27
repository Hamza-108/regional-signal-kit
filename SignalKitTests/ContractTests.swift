import XCTest
@testable import SignalKit

final class ContractTests: XCTestCase {
    func testExactMoney() {
        XCTAssertEqual(Money.parse("0,88"), 88); XCTAssertEqual(Money.parse("7.99"), 799)
        XCTAssertEqual(Money.format(1099), "10,99 €")
        for invalid in ["1.001", "nan", "-1", "1.00\n", "1.00abc", ""] { XCTAssertNil(Money.parse(invalid)) }
    }
    func testPrivateLANHTTPBoundary() throws {
        for valid in ["http://192.168.0.254:8000", "http://10.1.2.3", "http://172.16.0.1", "http://172.31.255.254", "https://example.invalid/api"] { XCTAssertNotNil(try APIClient.validatedAddress(valid)) }
        for invalid in ["http://example.invalid", "http://127.0.0.1", "http://0.0.0.0", "http://169.254.1.2", "http://172.32.0.1", "http://172.15.0.1", "http://192.169.0.1", "http://010.1.2.3", "http://10.1.2.999", "http://10.1.2", "http://[::1]", "https://user:secret@example.invalid", "https://example.invalid?token=x", "https://example.invalid/#x", "file:///private", ""] {
            XCTAssertThrowsError(try APIClient.validatedAddress(invalid), invalid)
        }
    }
    func testCredentialAndIdempotencyStayInHeaders() throws {
        let api = APIClient(baseURL: try APIClient.validatedAddress("https://example.invalid/api"), token:"synthetic-only")
        let request = try api.makeRequest("v1/refresh", method:"POST", body:Data("{}".utf8), key:"synthetic-operation")
        XCTAssertEqual(request.url?.path, "/api/v1/refresh")
        XCTAssertEqual(request.value(forHTTPHeaderField:"Authorization"), "Bearer synthetic-only")
        XCTAssertEqual(request.value(forHTTPHeaderField:"Idempotency-Key"), "synthetic-operation")
        XCTAssertFalse(request.url!.absoluteString.contains("synthetic-only"))
        XCTAssertEqual(request.httpBody, Data("{}".utf8))
    }
    func testCodableSnapshotContractAndWatchKeys() throws {
        let fixture = try UITestSupport.fixture(); try fixture.validate()
        let copy: OfflineSnapshot = try APIClient.decode(APIClient.encode(fixture))
        XCTAssertEqual(copy.settings.postalCode, "00000"); XCTAssertEqual(copy.offers[0].priceCents, 88)
        XCTAssertEqual(copy.matches[0].match, "exact"); XCTAssertNil(copy.offers[0].referenceCents)
        let json = try JSONSerialization.jsonObject(with: APIClient.encode(copy.watchlist[0])) as! [String:Any]
        XCTAssertEqual(json["target_cents"] as? Int, 99)
    }
    func testBerlinCalendarBoundariesAndInvalidDates() throws {
        let sundayNight = OfferWindow.timestamp("2026-10-25T23:30:00Z")!
        XCTAssertEqual(OfferWindow.key(sundayNight), "2026-10-26")
        XCTAssertEqual(OfferWindow.end(sundayNight), "2026-11-08")
        XCTAssertEqual(OfferWindow.end(OfferWindow.timestamp("2026-12-31T12:00:00Z")!), "2027-01-10")
        XCTAssertEqual(OfferWindow.end(OfferWindow.timestamp("2026-03-29T00:30:00Z")!), "2026-04-05")
        XCTAssertNil(OfferWindow.day("2026-02-30")); XCTAssertNil(OfferWindow.day("2026-1-01"))
        let fixture = try UITestSupport.fixture(at:OfferWindow.timestamp("2026-10-25T12:00:00Z")!)
        XCTAssertFalse(OfferWindow.visible(fixture.offers[0],at:OfferWindow.timestamp("2026-11-02T12:00:00Z")!))
        XCTAssertTrue(fixture.offers[0].outdated(at:OfferWindow.timestamp("2026-10-27T12:00:00Z")!))
    }
    func testSnapshotRejectsInvalidReferencesAndUnsupportedSchema() throws {
        let fixture = try UITestSupport.fixture()
        var object = try JSONSerialization.jsonObject(with: APIClient.encode(fixture)) as! [String:Any]
        object["schema_version"] = 99
        let future: OfflineSnapshot = try APIClient.decode(JSONSerialization.data(withJSONObject: object))
        XCTAssertThrowsError(try future.validate())
        object["schema_version"] = 1; object["offers"] = []
        let dangling: OfflineSnapshot = try APIClient.decode(JSONSerialization.data(withJSONObject: object))
        XCTAssertThrowsError(try dangling.validate())
    }
    func testRedirectDelegateNeverForwardsCredentialedRequest() {
        let delegate = NoRedirect()
        let request = URLRequest(url:URL(string:"https://example.invalid")!)
        let response = HTTPURLResponse(url:request.url!,statusCode:302,httpVersion:nil,headerFields:nil)!
        delegate.urlSession(.shared,task:URLSession.shared.dataTask(with:request),willPerformHTTPRedirection:response,newRequest:request) { XCTAssertNil($0) }
    }
    func testTransportAuthFailureAndIdempotentPOST() async throws {
        let key = UUID().uuidString
        SyntheticURLProtocol.handler = { request in
            XCTAssertEqual(request.value(forHTTPHeaderField:"Idempotency-Key"),key)
            XCTAssertEqual(request.httpMethod,"POST")
            return (HTTPURLResponse(url:request.url!,statusCode:401,httpVersion:nil,headerFields:nil)!,Data())
        }
        defer { SyntheticURLProtocol.handler = nil }
        let api = APIClient(baseURL:URL(string:"https://example.invalid")!,token:"synthetic-only",session:UITestSupport.session())
        do { _ = try await api.refresh(key:key); XCTFail("401 accepted") } catch ClientFailure.authentication {} catch { XCTFail("Wrong bounded error") }
    }
    func testDeclaredPayloadLimitIsEnforced() async throws {
        SyntheticURLProtocol.handler = { request in (HTTPURLResponse(url:request.url!,statusCode:200,httpVersion:nil,headerFields:["Content-Length":String(APIClient.maximumBytes+1)])!,Data("{}".utf8)) }
        defer { SyntheticURLProtocol.handler = nil }
        let api = APIClient(baseURL:URL(string:"https://example.invalid")!,token:"synthetic-only",session:UITestSupport.session())
        do { _ = try await api.data("v1/snapshot"); XCTFail("Oversize accepted") } catch ClientFailure.payloadTooLarge {} catch { XCTFail("Wrong size error") }
    }
}

extension ContractTests {
    func testUntrustedMoneyCannotOverflowCheckoutAndLargeUnitPriceFormatsExactly() throws {
        var object = try JSONSerialization.jsonObject(with: APIClient.encode(UITestSupport.fixture())) as! [String:Any]
        var offers = object["offers"] as! [[String:Any]];offers[0]["deposit_cents"] = Int.max;object["offers"] = offers
        let excessive: OfflineSnapshot = try APIClient.decode(JSONSerialization.data(withJSONObject: object))
        XCTAssertThrowsError(try excessive.validate())
        XCTAssertEqual(Money.format(100_000_000_000),"1000000000,00 €")
    }
}
