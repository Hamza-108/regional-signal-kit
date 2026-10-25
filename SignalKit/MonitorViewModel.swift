import Foundation
import SwiftUI

@MainActor final class MonitorViewModel: ObservableObject {
    @Published var settings = MonitorSettings()
    @Published var providers: [ProviderInfo] = []
    @Published var locations: [LocationInfo] = []
    @Published var unlocated: [LocationInfo] = []
    @Published var offers: [SignalOffer] = []
    @Published var offerTotal = 0
    @Published var subscriptions: [Subscription] = []
    @Published var notifications: [SignalNotification] = []
    @Published var status: ServiceStatus?
    @Published var busy = false
    @Published var error: String?
    @Published var connected = false
    @Published var query = ""
    private(set) var client: APIClient?
    var savedAddress: String { UserDefaults.standard.string(forKey: "backendAddress") ?? "" }
    func restore() async {
        let address = savedAddress
        if !address.isEmpty { await connect(address, token: "") }
    }
    func connect(_ address: String, token input: String) async {
        busy = true; defer { busy = false }
        do {
            let url = try APIClient.validatedAddress(address)
            let token = input.isEmpty ? (Credentials.read(for: url.absoluteString) ?? "") : input
            guard !token.isEmpty else { throw ClientFailure.authentication }
            let api = APIClient(baseURL: url, token: token)
            let value: MonitorSettings = try await api.get("v1/settings")
            try Credentials.save(token, for: url.absoluteString)
            UserDefaults.standard.set(url.absoluteString, forKey: "backendAddress")
            client = api; settings = value; connected = true
            await refresh()
        } catch { self.error = error.localizedDescription }
    }
    func refresh() async {
        guard let api = client else { return }
        busy = true; defer { busy = false }
        do {
            settings = try await api.get("v1/settings")
            providers = try await api.get("v1/providers")
            subscriptions = try await api.get("v1/watchlist")
            notifications = try await api.get("v1/notifications")
            status = try await api.get("v1/status")
            if let code = settings.postalCode {
                let page: LocationPage = try await api.get("v1/stores", query: [URLQueryItem(name: "postal_code", value: code), URLQueryItem(name: "radius_km", value: String(settings.radiusKm))])
                locations = page.stores; unlocated = page.unlocatedStores
            }
            await search()
        } catch { self.error = error.localizedDescription }
    }
    func search() async {
        guard let api = client else { return }
        do {
            let page: OfferPage = try await api.get("v1/offers", query: [URLQueryItem(name: "q", value: query), URLQueryItem(name: "limit", value: "200")])
            offers = page.data; offerTotal = page.total
        } catch { self.error = error.localizedDescription }
    }
    func saveSettings(_ value: MonitorSettings) async -> Bool {
        guard let api = client else { return false }
        do {
            let saved: MonitorSettings = try await api.send("v1/settings", method: "PUT", value: value)
            settings = saved; await refresh(); return true
        } catch { self.error = error.localizedDescription; return false }
    }
    func save(_ value: Subscription) async -> Bool {
        guard let api = client else { return false }
        do {
            let path = value.id.isEmpty ? "v1/watchlist" : "v1/watchlist/\(value.id)"
            let _: Subscription = try await api.send(path, method: value.id.isEmpty ? "POST" : "PUT", value: value)
            await refresh(); return true
        } catch { self.error = error.localizedDescription; return false }
    }
    func remove(_ subscription: Subscription) async {
        guard let api = client else { return }
        do { _ = try await api.data("v1/watchlist/\(subscription.id)", method: "DELETE"); await refresh() }
        catch { self.error = error.localizedDescription }
    }
}
