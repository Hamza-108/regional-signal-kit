import Foundation

struct MonitorSettings: Codable, Equatable {
    var postalCode: String?
    var radiusKm: Double = 10
    var selectedStoreIds: [String] = []
    var enabledProviders: [String] = []
}
struct ProviderInfo: Codable, Identifiable {
    let id: String
    let name: String
    let scope: String
    let limitation: String
}
struct LocationInfo: Codable, Identifiable {
    let id: String
    let provider: String
    let name: String
    let postalCode: String
    let distanceKm: Double?
    let scope: String
}
struct SignalOffer: Codable, Identifiable {
    let id: String
    let provider: String
    let productId: String
    let storeId: String?
    let title: String
    let brand: String?
    let description: String
    let package: String
    let amount: Int?
    let unit: String?
    let count: Int?
    let container: String?
    let priceCents: Int
    let depositCents: Int?
    let referenceCents: Int?
    let referenceType: String
    let eligibility: String
    let variantScope: String
    let scope: String
    let validFrom: String
    let validUntil: String
    let fetchedAt: String
    let sourceUrl: String
    let gtin: String?
    let stale: Bool?
    let unitPriceCents: Int?
    func outdated(at now: Date = Date()) -> Bool {
        guard let checked = OfferWindow.timestamp(fetchedAt) else { return true }
        return now.timeIntervalSince(checked) > 36 * 3600 || checked.timeIntervalSince(now) > 300
    }
}
struct Subscription: Codable, Identifiable, Equatable {
    var id = ""
    var name = ""
    var requiredTerms: [String] = []
    var excludedTerms: [String] = []
    var amount = 500
    var unit = "ml"
    var count = 1
    var container: String?
    var targetCents = 0
    var allowConditional = false
    var enabled = true
}
struct WatchMatch: Codable {
    let watchId: String
    let offerId: String
    let match: String
    let reason: String
    let targetMet: Bool
}
struct ProviderStatus: Codable, Identifiable {
    let id: String
    let provider: String
    let status: String
    let error: String?
    let lastSuccessAt: String?
    let lastAttemptAt: String
    let records: Int?
}
struct DatasetInfo: Codable, Identifiable {
    let id: String
    let fetchedAt: String
    let attribution: String
}
struct HistoryPoint: Codable {
    let observedAt: String
    let priceCents: Int
    let offer: SignalOffer
}
struct RefreshJob: Codable, Identifiable {
    let id: String
    let state: String
    let createdAt: String
    let startedAt: String?
    let finishedAt: String?
    let error: String?
    let results: [ProviderStatus]
    var active: Bool { ["queued", "running"].contains(state) }
}
struct OfflineSnapshot: Codable {
    let schemaVersion: Int
    let instanceId: String
    let revision: Int
    let generatedAt: String
    let coverageFrom: String
    let coverageUntil: String
    let settings: MonitorSettings
    let providers: [ProviderInfo]
    let locations: [LocationInfo]
    let unlocatedStores: [LocationInfo]
    let watchlist: [Subscription]
    let offers: [SignalOffer]
    let matches: [WatchMatch]
    let history: [HistoryPoint]
    let historyTruncated: Bool
    let providerStatus: [ProviderStatus]
    let datasets: [DatasetInfo]
    let collectionEnabled: Bool
    let lastRefresh: RefreshJob?
    let coverage: String
    let inventoryVerified: Bool
    func validate() throws {
        guard schemaVersion == 1, !instanceId.isEmpty, instanceId.count <= 128, revision >= 0,
              OfferWindow.day(coverageFrom) != nil, OfferWindow.day(coverageUntil) != nil,
              coverageFrom <= coverageUntil, Set(offers.map(\.id)).count == offers.count,
              Set(watchlist.map(\.id)).count == watchlist.count else { throw ClientFailure.invalidResponse }
        let ids = Set(offers.map(\.id)); let watches = Set(watchlist.map(\.id))
        guard matches.allSatisfy({ ids.contains($0.offerId) && watches.contains($0.watchId) }),
              offers.allSatisfy({ (0...100_000_000).contains($0.priceCents) && ($0.depositCents == nil || (0...100_000_000).contains($0.depositCents!)) && ($0.referenceCents == nil || (0...100_000_000).contains($0.referenceCents!)) && ($0.unitPriceCents == nil || (0...100_000_000_000).contains($0.unitPriceCents!)) && $0.validFrom <= $0.validUntil && OfferWindow.day($0.validFrom) != nil && OfferWindow.day($0.validUntil) != nil && OfferWindow.timestamp($0.fetchedAt) != nil }) else { throw ClientFailure.invalidResponse }
    }
}
enum Money {
    static func format(_ cents: Int) -> String { String(format: "%lld,%02lld €", Int64(cents / 100), Int64(cents % 100)) }
    static func parse(_ text: String) -> Int? {
        guard text.range(of: #"^[0-9]{1,6}([.,][0-9]{1,2})?\z"#, options: .regularExpression) != nil,
              let value = Decimal(string: text.replacingOccurrences(of: ",", with: "."), locale: Locale(identifier: "en_US_POSIX")) else { return nil }
        return NSDecimalNumber(decimal: value * 100).intValue
    }
}
