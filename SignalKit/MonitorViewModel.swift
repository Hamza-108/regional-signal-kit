import Foundation
import SwiftUI

@MainActor final class MonitorViewModel: ObservableObject {
    @Published private(set) var saved: SavedSnapshot?
    @Published private(set) var connected = false
    @Published private(set) var busy = false
    @Published private(set) var restoring = true
    @Published private(set) var job: RefreshJob?
    @Published var error: String?
    @Published var notice: String?
    @Published var query = ""
    private let store: SnapshotStore
    private let session: URLSession?
    private let testCredentials: Bool
    private var polling: Task<Void, Never>?
    private(set) var client: APIClient?
    var savedAddress: String { UserDefaults.standard.string(forKey: "backendAddress") ?? "" }
    var settings: MonitorSettings { saved?.snapshot.settings ?? MonitorSettings() }
    var providers: [ProviderInfo] { saved?.snapshot.providers ?? [] }
    var locations: [LocationInfo] { saved?.snapshot.locations ?? [] }
    var unlocated: [LocationInfo] { saved?.snapshot.unlocatedStores ?? [] }
    var subscriptions: [Subscription] { saved?.snapshot.watchlist ?? [] }
    var offers: [SignalOffer] { saved?.snapshot.offers ?? [] }
    var canEdit: Bool { connected && !busy && saved?.requestKey == nil }
    var filteredOffers: [SignalOffer] {
        let terms = query.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        return offers.filter { offer in
            OfferWindow.visible(offer) && terms.allSatisfy { (offer.title + " " + (offer.brand ?? "")).localizedCaseInsensitiveContains($0) }
        }.sorted { ($0.validFrom, $0.title, $0.id) < ($1.validFrom, $1.title, $1.id) }
    }
    init(store: SnapshotStore? = nil, session: URLSession? = nil) {
        #if DEBUG
        if UITestSupport.enabled {
            self.store = store ?? SnapshotStore(root: UITestSupport.cacheRoot)
            self.session = session ?? UITestSupport.session()
            self.testCredentials = true
            return
        }
        #endif
        self.store = store ?? SnapshotStore(); self.session = session; self.testCredentials = false
    }
    func restore() async {
        defer { restoring = false }
        guard !savedAddress.isEmpty else { return }
        do { saved = try await store.load(address: savedAddress); job = saved?.snapshot.lastRefresh }
        catch { self.error = message(error) }
        // Loading saved data never contacts a server or starts collection.
    }
    private func credential(for address: String) -> String? {
        testCredentials ? "synthetic-only" : Credentials.read(for: address)
    }
    private func api() throws -> APIClient {
        let url = try APIClient.validatedAddress(savedAddress)
        guard let token = credential(for: url.absoluteString), !token.isEmpty else { throw ClientFailure.authentication }
        let value = APIClient(baseURL: url, token: token, session: session); client = value; return value
    }
    func connect(_ address: String, token input: String) async -> Bool {
        guard !busy else { return false }
        busy = true; defer { busy = false }
        do {
            let url = try APIClient.validatedAddress(address)
            let token = input.isEmpty ? credential(for: url.absoluteString) ?? "" : input
            guard !token.isEmpty else { throw ClientFailure.authentication }
            let api = APIClient(baseURL: url, token: token, session: session)
            let snapshot: OfflineSnapshot = try await api.get("v1/snapshot"); try snapshot.validate()
            if !testCredentials { try Credentials.save(token, for: url.absoluteString) }
            let stored = try await store.save(snapshot, address: url.absoluteString, allowNewInstance: true)
            UserDefaults.standard.set(url.absoluteString, forKey: "backendAddress")
            saved = stored; client = api; job = snapshot.lastRefresh; connected = true; error = nil
            notice = "Home server connected. Refresh offers to request collection."
            return true
        } catch { connected = false; self.error = message(error); return false }
    }
    private func syncSnapshot(using api: APIClient) async throws {
        let snapshot: OfflineSnapshot = try await api.get("v1/snapshot")
        let stored = try await store.save(snapshot, address: api.baseURL.absoluteString)
        saved = stored; job = snapshot.lastRefresh; connected = true
    }
    func refreshOffers() async {
        if let polling { await polling.value; return }
        let task = Task { await performRefresh() }; polling = task
        await task.value; polling = nil
    }
    private func performRefresh() async {
        guard !busy else { return }
        busy = true; error = nil; defer { busy = false }
        do {
            let api = try api()
            let key = saved?.requestKey ?? UUID().uuidString
            saved = try await store.pending(address: api.baseURL.absoluteString, key: key, jobId: saved?.jobId)
            var operation: RefreshJob
            if let jobId = saved?.jobId { operation = try await api.get("v1/refresh/\(jobId)") }
            else {
                operation = try await api.refresh(key: key)
                saved = try await store.pending(address: api.baseURL.absoluteString, key: key, jobId: operation.id)
            }
            connected = true; job = operation
            for _ in 0..<300 {
                try Task.checkCancellation()
                if !operation.active {
                    try await syncSnapshot(using: api)
                    notice = operation.state == "completed" ? "Saved on this iPhone. Advertising coverage remains partial." : "Refresh \(operation.state). Review source warnings; earlier data was retained."
                    return
                }
                try await Task.sleep(nanoseconds: 2_000_000_000)
                operation = try await api.get("v1/refresh/\(operation.id)"); job = operation
            }
            notice = "The server may still be working. Tap Resume refresh later to check and download."
        } catch {
            connected = false
            if Task.isCancelled { notice = "Polling paused. The home server can finish; resume later to download." }
            else { self.error = message(error) }
        }
    }
    func pauseNetwork() { polling?.cancel(); connected = false }
    func saveSettings(_ value: MonitorSettings) async -> Bool {
        await mutate {
            let api = try self.api(); let _: MonitorSettings = try await api.send("v1/settings", method: "PUT", value: value)
            try await self.syncSnapshot(using: api)
        }
    }
    func save(_ value: Subscription) async -> Bool {
        await mutate {
            let api = try self.api(); let path = value.id.isEmpty ? "v1/watchlist" : "v1/watchlist/\(value.id)"
            let _: Subscription = try await api.send(path, method: value.id.isEmpty ? "POST" : "PUT", value: value)
            try await self.syncSnapshot(using: api)
        }
    }
    func remove(_ subscription: Subscription) async {
        _ = await mutate { let api = try self.api(); _ = try await api.data("v1/watchlist/\(subscription.id)", method: "DELETE"); try await self.syncSnapshot(using: api) }
    }
    private func mutate(_ operation: () async throws -> Void) async -> Bool {
        guard canEdit else { error = "Connect at home and finish any refresh before changing settings or watches."; return false }
        busy = true; defer { busy = false }
        do { try await operation(); return true } catch { connected = false; self.error = message(error); return false }
    }
    func comparison(_ watch: Subscription) -> [(SignalOffer, WatchMatch)] {
        let matches = saved?.snapshot.matches.filter { $0.watchId == watch.id } ?? []
        return matches.compactMap { match in
            guard let offer = offers.first(where: { $0.id == match.offerId }), OfferWindow.visible(offer) else { return nil }
            return (offer, match)
        }.sorted { ($0.0.priceCents, $0.0.validFrom, $0.0.id) < ($1.0.priceCents, $1.0.validFrom, $1.0.id) }
    }
    func history(_ offer: SignalOffer) -> [HistoryPoint] {
        (saved?.snapshot.history ?? []).filter { $0.offer.provider == offer.provider && $0.offer.productId == offer.productId && $0.offer.storeId == offer.storeId }
    }
    private func message(_ error: Error) -> String {
        (error as? ClientFailure)?.errorDescription ?? "Home server unavailable or local save failed. Check trusted home Wi-Fi and Local Network permission. Previous saved data was not cleared."
    }
}
