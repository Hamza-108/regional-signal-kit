import Foundation
import CryptoKit

struct SavedSnapshot: Codable {
    var schemaVersion = 1
    let address: String
    let downloadedAt: String
    let snapshot: OfflineSnapshot
    var requestKey: String?
    var jobId: String?
}
actor SnapshotStore {
    private let root: URL
    init(root: URL? = nil) {
        self.root = root ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("SignalKit", isDirectory: true)
    }
    private func folder(_ address: String) -> URL {
        let hash = SHA256.hash(data: Data(address.utf8)).map { String(format: "%02x", $0) }.joined()
        return root.appendingPathComponent(hash, isDirectory: true)
    }
    private func read(_ url: URL, address: String) throws -> SavedSnapshot {
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size <= APIClient.maximumBytes + 1024 * 1024 else { throw ClientFailure.cacheUnavailable }
        let saved: SavedSnapshot = try APIClient.decode(Data(contentsOf: url))
        guard saved.schemaVersion == 1, saved.address == address else { throw ClientFailure.cacheUnavailable }
        try saved.snapshot.validate(); return saved
    }
    func load(address: String) throws -> SavedSnapshot? {
        let dir = folder(address); var exists = false
        for file in ["snapshot.json", "previous.json"] {
            let url = dir.appendingPathComponent(file)
            if FileManager.default.fileExists(atPath: url.path) {
                exists = true
                if let saved = try? read(url, address: address) { return saved }
            }
        }
        if exists { throw ClientFailure.cacheUnavailable }
        return nil
    }
    private func futurePrimary(_ address: String) -> Bool {
        let url = folder(address).appendingPathComponent("snapshot.json")
        guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= APIClient.maximumBytes + 1024 * 1024,
              let data = try? Data(contentsOf: url), let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return false }
        return (object["schema_version"] as? Int ?? 0) > 1
    }
    private func write(_ saved: SavedSnapshot) throws {
        guard !futurePrimary(saved.address) else { throw ClientFailure.cacheUnavailable }
        let dir = folder(saved.address)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        var protected = dir; var values = URLResourceValues(); values.isExcludedFromBackup = true; try protected.setResourceValues(values)
        let current = dir.appendingPathComponent("snapshot.json")
        if let previous = try? read(current, address: saved.address) {
            try APIClient.encode(previous).write(to: dir.appendingPathComponent("previous.json"), options: [.atomic, .completeFileProtection])
        }
        try APIClient.encode(saved).write(to: current, options: [.atomic, .completeFileProtection])
    }
    @discardableResult func save(_ snapshot: OfflineSnapshot, address: String, allowNewInstance: Bool = false) throws -> SavedSnapshot {
        try snapshot.validate()
        let old: SavedSnapshot?
        do { old = try load(address: address) }
        catch {
            guard allowNewInstance else { throw error }
            old = nil
        }
        if allowNewInstance && (futurePrimary(address) || (old == nil && FileManager.default.fileExists(atPath: folder(address).path))) {
            for name in ["snapshot.json", "previous.json"] {
                let file = folder(address).appendingPathComponent(name)
                if FileManager.default.fileExists(atPath: file.path) {
                    try FileManager.default.moveItem(at: file, to: folder(address).appendingPathComponent("unreadable-\(UUID().uuidString)-\(name)"))
                }
            }
        }
        if let old {
            if old.snapshot.instanceId != snapshot.instanceId {
                guard allowNewInstance else { throw ClientFailure.serverChanged }
                let archive = folder(address).appendingPathComponent("server-\(UUID().uuidString).json")
                try APIClient.encode(old).write(to: archive, options: [.atomic, .completeFileProtection])
            } else if snapshot.revision < old.snapshot.revision {
                guard allowNewInstance else { throw ClientFailure.staleSnapshot }
                let archive = folder(address).appendingPathComponent("revision-\(UUID().uuidString).json")
                try APIClient.encode(old).write(to: archive, options: [.atomic, .completeFileProtection])
            }
        }
        let saved = SavedSnapshot(address: address, downloadedAt: Date().ISO8601Format(), snapshot: snapshot)
        do { try write(saved) } catch { throw ClientFailure.cacheUnavailable }
        return saved
    }
    func pending(address: String, key: String?, jobId: String?) throws -> SavedSnapshot {
        guard var saved = try load(address: address) else { throw ClientFailure.cacheUnavailable }
        saved.requestKey = key; saved.jobId = jobId
        try write(saved); return saved
    }
}
