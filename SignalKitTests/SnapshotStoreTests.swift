import XCTest
@testable import SignalKit

final class SnapshotStoreTests: XCTestCase {
    private let address = "https://example.invalid"
    private func root() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent("SignalKit-test-\(UUID().uuidString)",isDirectory:true) }
    private func modified(_ snapshot:OfflineSnapshot, revision:Int = 2, instance:String? = nil) throws -> OfflineSnapshot {
        var json = try JSONSerialization.jsonObject(with:APIClient.encode(snapshot)) as! [String:Any]
        json["revision"] = revision
        if let instance { json["instance_id"] = instance }
        return try APIClient.decode(JSONSerialization.data(withJSONObject:json))
    }
    func testPersistentRoundTripPendingOperationAndProtection() async throws {
        let path = root(); let first = SnapshotStore(root:path)
        let empty = try await first.load(address:address); XCTAssertNil(empty)
        let initial = try await first.save(UITestSupport.fixture(),address:address)
        let pending = try await first.pending(address:address,key:"synthetic-key",jobId:"synthetic-job")
        XCTAssertEqual(pending.snapshot.revision,initial.snapshot.revision)
        let reopened = SnapshotStore(root:path); let saved = try await reopened.load(address:address)
        XCTAssertEqual(saved?.jobId,"synthetic-job"); XCTAssertEqual(saved?.snapshot.offers.count,1)
        let dirs = try FileManager.default.contentsOfDirectory(at:path,includingPropertiesForKeys:[.isExcludedFromBackupKey])
        XCTAssertEqual(try dirs[0].resourceValues(forKeys:[.isExcludedFromBackupKey]).isExcludedFromBackup,true)
    }
    func testOldRevisionAndDifferentServerCannotReplaceSavedData() async throws {
        let store = SnapshotStore(root:root()); let original = try UITestSupport.fixture()
        _ = try await store.save(modified(original,revision:3),address:address)
        do { _ = try await store.save(original,address:address); XCTFail("Stale revision accepted") } catch ClientFailure.staleSnapshot {}
        do { _ = try await store.save(modified(original,instance:"different-instance"),address:address); XCTFail("Server switch accepted implicitly") } catch ClientFailure.serverChanged {}
        let unchanged = try await store.load(address:address); XCTAssertEqual(unchanged?.snapshot.revision,3)
        _ = try await store.save(modified(original,instance:"different-instance"),address:address,allowNewInstance:true)
        let switched = try await store.load(address:address); XCTAssertEqual(switched?.snapshot.instanceId,"different-instance")
    }
    func testCorruptPrimaryRecoversLastKnownGoodWithoutClearingFiles() async throws {
        let path = root(); let store = SnapshotStore(root:path);let snapshot = try UITestSupport.fixture()
        _ = try await store.save(snapshot,address:address)
        _ = try await store.save(modified(snapshot),address:address)
        let files = try FileManager.default.subpathsOfDirectory(atPath:path.path)
        let current = path.appendingPathComponent(files.first { $0.hasSuffix("/snapshot.json") }!)
        try Data("corrupt".utf8).write(to:current,options:.atomic)
        let recovered = try await store.load(address:address)
        XCTAssertEqual(recovered?.snapshot.revision,1)
        XCTAssertEqual(try String(contentsOf:current,encoding:.utf8),"corrupt")
    }
    func testConnectionCacheIsSeparateAndUnknownSchemaIsNotErased() async throws {
        let path = root();let store = SnapshotStore(root:path)
        _ = try await store.save(UITestSupport.fixture(),address:address)
        let other = try await store.load(address:"https://other.invalid");XCTAssertNil(other)
        let file = try FileManager.default.subpathsOfDirectory(atPath:path.path).first { $0.hasSuffix("/snapshot.json") }!
        let url = path.appendingPathComponent(file)
        var object = try JSONSerialization.jsonObject(with:Data(contentsOf:url)) as! [String:Any];object["schema_version"] = 99
        let future = try JSONSerialization.data(withJSONObject:object);try future.write(to:url,options:.atomic)
        do { _ = try await store.load(address:address);XCTFail("Future cache accepted") } catch ClientFailure.cacheUnavailable {}
        XCTAssertEqual(try Data(contentsOf:url),future)
    }
}

extension SnapshotStoreTests {
    func testExplicitReconnectArchivesUnreadableCacheAndRestoredOlderRevision() async throws {
        let path = root();let store = SnapshotStore(root:path);let snapshot = try UITestSupport.fixture()
        _ = try await store.save(modified(snapshot,revision:3),address:address)
        _ = try await store.save(snapshot,address:address,allowNewInstance:true)
        let restored = try await store.load(address:address);XCTAssertEqual(restored?.snapshot.revision,1)
        let files = try FileManager.default.subpathsOfDirectory(atPath:path.path)
        let primary = path.appendingPathComponent(files.first { $0.hasSuffix("/snapshot.json") }!)
        let previous = path.appendingPathComponent(files.first { $0.hasSuffix("/previous.json") }!)
        try Data("corrupt-primary".utf8).write(to:primary,options:.atomic)
        try Data("corrupt-backup".utf8).write(to:previous,options:.atomic)
        _ = try await store.save(snapshot,address:address,allowNewInstance:true)
        let names = try FileManager.default.subpathsOfDirectory(atPath:path.path)
        XCTAssertEqual(names.filter { $0.contains("unreadable-") }.count,2)
        XCTAssertEqual(names.filter { $0.contains("revision-") }.count,1)
    }
}
