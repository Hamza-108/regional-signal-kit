import Foundation

struct MonitorSettings: Codable, Equatable {
    var postalCode: String?
    var radiusKm: Double = 10
    var selectedStoreIds: [String] = []
    var enabledProviders: [String] = []
}
struct ProviderInfo: Decodable, Identifiable {
    let id: String
    let name: String
    let scope: String
    let limitation: String
}
struct LocationInfo: Decodable, Identifiable {
    let id: String
    let provider: String
    let name: String
    let postalCode: String
    let distanceKm: Double?
    let scope: String
}
struct LocationPage: Decodable {
    let stores: [LocationInfo]
    let unlocatedStores: [LocationInfo]
}
struct SignalOffer: Decodable, Identifiable {
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
    let stale: Bool?
    let unitPriceCents: Int?
    let match: String?
    let matchReason: String?
}
struct OfferPage: Decodable {
    let data: [SignalOffer]
    let total: Int
    let coverage: String
    let inventoryVerified: Bool
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
struct SignalNotification: Decodable, Identifiable {
    let id: String
    let title: String
    let priceCents: Int
    let reason: String
    let createdAt: String
    let deliveredAt: String?
    let attempts: Int
    let error: String?
}
struct ProviderStatus: Decodable, Identifiable {
    let id: String
    let provider: String
    let status: String
    let error: String?
    let lastSuccessAt: String?
    let lastAttemptAt: String
    let records: Int?
}
struct DatasetInfo: Decodable, Identifiable {
    let id: String
    let fetchedAt: String
    let attribution: String
}
struct ServiceStatus: Decodable {
    let collectionEnabled: Bool
    let notificationConfigured: Bool
    let providers: [ProviderStatus]
    let datasets: [DatasetInfo]
    let at: String
}
struct HistoryPoint: Decodable {
    let observedAt: String
    let priceCents: Int
    let offer: SignalOffer
}
enum Money {
    static func format(_ cents: Int) -> String {
        String(format: "%d,%02d €", cents / 100, cents % 100)
    }
    static func parse(_ text: String) -> Int? {
        guard text.range(of: #"^[0-9]{1,6}([.,][0-9]{1,2})?\z"#, options: .regularExpression) != nil,
              let value = Decimal(string: text.replacingOccurrences(of: ",", with: "."), locale: Locale(identifier: "en_US_POSIX")) else { return nil }
        return NSDecimalNumber(decimal: value * 100).intValue
    }
}
