import XCTest
@testable import SignalKit

@MainActor final class MonitorViewModelTests: XCTestCase {
    private func setup() -> (SnapshotStore, MonitorViewModel) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("SignalKit-model-\(UUID().uuidString)")
        let store = SnapshotStore(root:root)
        return (store,MonitorViewModel(testStore:store,testSession:UITestSupport.session()))
    }
    private func response(_ request:URLRequest,_ data:Data,_ status:Int = 200) -> (HTTPURLResponse,Data) {
        (HTTPURLResponse(url:request.url!,statusCode:status,httpVersion:nil,headerFields:["Content-Type":"application/json"])!,data)
    }
    private func job(_ state:String) throws -> Data {
        try APIClient.encode(RefreshJob(id:"11111111-1111-4111-8111-111111111111",state:state,createdAt:Date().ISO8601Format(),startedAt:nil,finishedAt:nil,error:nil,results:[]))
    }
    func testRelaunchResumesSavedJobWithoutAnotherPOSTOrNetworkDuringSearch() async throws {
        let oldAddress = UserDefaults.standard.string(forKey:"backendAddress")
        defer { UserDefaults.standard.set(oldAddress,forKey:"backendAddress");SyntheticURLProtocol.handler = nil }
        let (store,model) = setup();let snapshot = try APIClient.encode(UITestSupport.fixture())
        let running = try job("running"),completed = try job("completed")
        var posts = 0, polls = 0, reads = 0
        SyntheticURLProtocol.handler = { request in
            if request.url!.path == "/v1/snapshot" { reads += 1;return self.response(request,snapshot) }
            if request.httpMethod == "POST" { posts += 1;return self.response(request,running,202) }
            polls += 1
            if polls == 1 { throw URLError(.networkConnectionLost) }
            return self.response(request,completed)
        }
        let connected = await model.connect("https://example.invalid",token:"synthetic-only");XCTAssertTrue(connected)
        await model.refreshOffers()
        XCTAssertNotNil(model.saved?.jobId);XCTAssertEqual(posts,1);XCTAssertNotNil(model.error)
        let reopened = MonitorViewModel(testStore:store,testSession:UITestSupport.session());await reopened.restore()
        XCTAssertEqual(reads,1);XCTAssertFalse(reopened.canEdit)
        reopened.query = "not-present";XCTAssertTrue(reopened.filteredOffers.isEmpty);XCTAssertEqual(reads,1)
        await reopened.refreshOffers()
        XCTAssertNil(reopened.saved?.requestKey);XCTAssertEqual(posts,1);XCTAssertEqual(polls,2);XCTAssertEqual(reads,2)
        XCTAssertEqual(reopened.offers.count,1)
    }
    func testIncompleteDownloadPreservesDataAndRetryOnlyDownloadsCompletedJob() async throws {
        let oldAddress = UserDefaults.standard.string(forKey:"backendAddress")
        defer { UserDefaults.standard.set(oldAddress,forKey:"backendAddress");SyntheticURLProtocol.handler = nil }
        let (_,model) = setup();let snapshot = try APIClient.encode(UITestSupport.fixture());let completed = try job("completed")
        var reads = 0, posts = 0
        SyntheticURLProtocol.handler = { request in
            if request.url!.path == "/v1/snapshot" {
                reads += 1;return self.response(request,reads == 2 ? Data("{".utf8) : snapshot)
            }
            if request.httpMethod == "POST" { posts += 1 }
            return self.response(request,completed,request.httpMethod == "POST" ? 202 : 200)
        }
        let connected = await model.connect("https://example.invalid",token:"synthetic-only");XCTAssertTrue(connected)
        let downloaded = model.saved?.downloadedAt
        await model.refreshOffers()
        XCTAssertNotNil(model.error);XCTAssertEqual(model.saved?.downloadedAt,downloaded);XCTAssertEqual(model.offers[0].priceCents,88)
        XCTAssertNotNil(model.saved?.jobId)
        await model.refreshOffers()
        XCTAssertEqual(posts,1);XCTAssertEqual(reads,3);XCTAssertNil(model.saved?.requestKey)
    }
}
