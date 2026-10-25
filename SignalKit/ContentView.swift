import SwiftUI

struct ContentView: View {
    @StateObject private var model = MonitorViewModel()
    @State private var firstRegion = false
    var body: some View {
        Group {
            if model.connected {
                TabView {
                    OffersView(model: model).tabItem { Label("Observations", systemImage: "list.bullet.rectangle") }
                    SubscriptionsView(model: model).tabItem { Label("Watchlist", systemImage: "star") }
                    EventsView(model: model).tabItem { Label("Events", systemImage: "bell") }
                    SettingsView(model: model).tabItem { Label("Settings", systemImage: "gear") }
                }
            } else { ConnectionView(model: model) }
        }
        .task { await model.restore() }
        .onChange(of: model.connected) { _, connected in
            if connected && model.settings.postalCode == nil { firstRegion = true }
        }
        .sheet(isPresented: $firstRegion) { RegionEditor(model: model) }
        .alert("Request failed", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
            Button("OK") { model.error = nil }
        } message: { Text(model.error ?? "") }
    }
}
struct ConnectionView: View {
    @ObservedObject var model: MonitorViewModel
    @State private var address = ""
    @State private var token = ""
    var body: some View {
        NavigationStack {
            Form {
                Section("Private connection") {
                    TextField("HTTPS backend URL", text: $address).textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL).accessibilityIdentifier("backendAddress")
                    SecureField("Credential (blank uses stored credential)", text: $token).textInputAutocapitalization(.never).autocorrectionDisabled()
                    Button("Connect") { Task { await model.connect(address, token: token); token = "" } }.disabled(model.busy)
                }
                Section {
                    Text("Connect to your own authenticated service. No account, analytics or bundled server credentials are included.")
                    Text("Notifications are delivered separately by the configured companion service; this client does not register for native push.")
                }
                if model.busy { ProgressView("Connecting") }
            }
            .navigationTitle("Signal Kit")
            .onAppear { address = model.savedAddress }
        }
    }
}
struct OffersView: View {
    @ObservedObject var model: MonitorViewModel
    var body: some View {
        NavigationStack {
            List {
                if model.settings.postalCode == nil {
                    Section { Text("Open Settings to configure your region and select nearby locations.") }
                }
                Section {
                    HStack {
                        TextField("Search product labels", text: $model.query).onSubmit { Task { await model.search() } }
                        Button { Task { await model.search() } } label: { Image(systemName: "magnifyingglass") }.accessibilityLabel("Search")
                    }
                    Text("Showing \(model.offers.count) of \(model.offerTotal). Coverage is partial. Search to narrow results.").font(.caption)
                    Text("Includes current and upcoming advertising. Availability and stock are not verified; packages and price conditions may differ.").font(.caption).foregroundStyle(.secondary)
                }
                ForEach(model.offers) { offer in
                    NavigationLink { OfferDetail(offer: offer, model: model) } label: {
                        VStack(alignment: .leading, spacing: 5) {
                            HStack { Text(offer.title).font(.headline); Spacer(); Text(Money.format(offer.priceCents)).monospacedDigit() }
                            Text("\(offer.provider) · \(offer.package)").font(.subheadline)
                            Text("\(offer.validFrom) – \(offer.validUntil)").font(.caption)
                            Text("\(offer.scope) · \(offer.variantScope) · \(offer.eligibility)").font(.caption).foregroundStyle(.secondary)
                            if offer.stale == true { Label("Outdated observation", systemImage: "exclamationmark.triangle").foregroundStyle(.orange) }
                        }
                    }
                }
                if model.offers.isEmpty { Text("No matching observations in the available data. This does not mean there are no promotions.") }
            }
            .navigationTitle("Observations")
            .refreshable { await model.refresh() }
            .toolbar { Button { Task { await model.refresh() } } label: { Image(systemName: "arrow.clockwise") }.accessibilityLabel("Refresh") }
        }
    }
}
struct OfferDetail: View {
    let offer: SignalOffer
    @ObservedObject var model: MonitorViewModel
    @State private var history: [HistoryPoint] = []
    @State private var historyError: String?
    @State private var creating = false
    var body: some View {
        List {
            Section(offer.title) {
                LabeledContent("Advertised goods price", value: Money.format(offer.priceCents))
                LabeledContent("Package", value: offer.package)
                LabeledContent("Deposit", value: offer.depositCents.map(Money.format) ?? "Unknown")
                if let deposit = offer.depositCents { LabeledContent("Checkout total", value: Money.format(offer.priceCents + deposit)) }
                if let perUnit = offer.unitPriceCents { LabeledContent("Per litre / kilogram", value: Money.format(perUnit)) }
                if let reference = offer.referenceCents { LabeledContent("Reference (\(offer.referenceType))", value: Money.format(reference)) }
                LabeledContent("Price conditions", value: offer.eligibility)
                LabeledContent("Variant identification", value: offer.variantScope)
                LabeledContent("Regional scope", value: offer.scope)
                LabeledContent("Location", value: offer.storeId ?? "National — no verified branch")
                Text("Valid \(offer.validFrom) through \(offer.validUntil)")
                Text("Observed \(offer.fetchedAt)").font(.caption)
                Text(offer.description)
                if let url = URL(string: offer.sourceUrl), url.scheme == "https" { Link("View source (opens external site)", destination: url) }
                Button("Create watch") { creating = true }
            }
            Section("Observed price history") {
                Text("Observed promotional prices only; absence of history is not evidence of an ordinary shelf price.").font(.caption)
                ForEach(Array(history.enumerated()), id: \.offset) { _, point in
                    VStack(alignment: .leading) { Text(Money.format(point.priceCents)); Text("\(point.observedAt) · \(point.offer.package) · \(point.offer.storeId ?? point.offer.scope)").font(.caption) }
                }
                if history.isEmpty { Text(historyError ?? "No earlier observations recorded.") }
            }
        }
        .navigationTitle("Details")
        .sheet(isPresented: $creating) { SubscriptionEditor(model: model, initial: draft) }
        .task {
            guard let api = model.client else { return }
            do {
                var query = [URLQueryItem(name: "product_id", value: offer.productId)]
                if let location = offer.storeId { query.append(URLQueryItem(name: "store_id", value: location)) }
                history = try await api.get("v1/history", query: query)
            } catch { historyError = "History could not be loaded." }
        }
    }
    private var draft: Subscription {
        var result = Subscription(); result.name = offer.title
        result.requiredTerms = ((offer.brand ?? "") + " " + offer.title).split(whereSeparator: { $0.isWhitespace }).map(String.init)
        result.amount = offer.amount ?? 500; result.unit = offer.unit ?? "ml"; result.count = offer.count ?? 1
        result.container = offer.container; result.targetCents = offer.priceCents
        return result
    }
}
struct SubscriptionsView: View {
    @ObservedObject var model: MonitorViewModel
    @State private var editing: Subscription?
    var body: some View {
        NavigationStack {
            List {
                Section { Text("Only fresh, active, exact matches can create target-price events. Grouped varieties and unknown package details are not confirmed matches.").font(.caption) }
                ForEach(model.subscriptions) { subscription in
                    NavigationLink { SubscriptionComparison(model: model, subscription: subscription) } label: {
                        VStack(alignment: .leading) {
                            Text(subscription.name).font(.headline)
                            Text("\(subscription.count) × \(subscription.amount) \(subscription.unit) · target \(Money.format(subscription.targetCents))").font(.subheadline)
                            Text(subscription.enabled ? "Enabled" : "Paused").font(.caption)
                        }
                    }.tint(.primary)
                    .swipeActions(edge: .leading) { Button("Edit") { editing = subscription } }
                    .swipeActions { Button("Remove", role: .destructive) { Task { await model.remove(subscription) } } }
                }
                if model.subscriptions.isEmpty { Text("No watchlist items. Add the exact product label and variant you want.") }
            }
            .navigationTitle("Watchlist")
            .toolbar { Button { editing = Subscription() } label: { Image(systemName: "plus") }.accessibilityLabel("Add watch") }
            .sheet(item: $editing) { SubscriptionEditor(model: model, initial: $0) }
            .refreshable { await model.refresh() }
        }
    }
}
struct SubscriptionComparison: View {
    @ObservedObject var model: MonitorViewModel
    let subscription: Subscription
    @State private var page: OfferPage?
    @State private var failure: String?
    var body: some View {
        List {
            Section {
                Text("Current advertised matches for the specified package. Scope and price conditions still apply; this is not a stock check.").font(.caption)
            }
            ForEach(page?.data ?? []) { offer in
                NavigationLink { OfferDetail(offer: offer, model: model) } label: {
                    VStack(alignment: .leading) {
                        HStack { Text(offer.provider); Spacer(); Text(Money.format(offer.priceCents)) }
                        Text("\(offer.package) · \(offer.match ?? "uncertain") · \(offer.eligibility)").font(.caption)
                        Text(offer.storeId ?? "National — branch applicability unknown").font(.caption)
                        if offer.stale == true { Text("Outdated").foregroundStyle(.orange) }
                    }
                }
            }
            if page?.data.isEmpty == true { Text("No current matches in the available partial data.") }
            if let failure { Text(failure) }
        }
        .navigationTitle(subscription.name)
        .task {
            guard let api = model.client else { return }
            do { page = try await api.get("v1/offers", query: [URLQueryItem(name: "watch_id", value: subscription.id), URLQueryItem(name: "period", value: "current"), URLQueryItem(name: "limit", value: "200")]) }
            catch { failure = "Comparison could not be loaded." }
        }
    }
}
struct SubscriptionEditor: View {
    @ObservedObject var model: MonitorViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var value: Subscription
    @State private var required: String
    @State private var excluded: String
    @State private var target: String
    @State private var validation: String?
    init(model: MonitorViewModel, initial: Subscription) {
        self.model = model; _value = State(initialValue: initial)
        _required = State(initialValue: initial.requiredTerms.joined(separator: ", "))
        _excluded = State(initialValue: initial.excludedTerms.joined(separator: ", "))
        _target = State(initialValue: String(format: "%d,%02d", initial.targetCents / 100, initial.targetCents % 100))
    }
    var body: some View {
        NavigationStack {
            Form {
                Section("Exact identity") {
                    TextField("Display name", text: $value.name)
                    TextField("Required terms, comma separated", text: $required)
                    TextField("Excluded variants, comma separated", text: $excluded)
                    Text("Include the brand and exact variant. The service cannot infer a flavor from an unspecified assortment.").font(.caption)
                }
                Section("Package and target") {
                    TextField("Amount per item", value: $value.amount, format: .number).keyboardType(.numberPad)
                    Picker("Unit", selection: $value.unit) { Text("ml").tag("ml"); Text("g").tag("g") }
                    Stepper("Pack count: \(value.count)", value: $value.count, in: 1...1000)
                    Picker("Container", selection: Binding(get: { value.container ?? "" }, set: { value.container = $0.isEmpty ? nil : $0 })) {
                        Text("Not specified").tag(""); Text("Can").tag("can"); Text("Bottle").tag("bottle"); Text("Other").tag("other")
                    }
                    TextField("Target goods price (€)", text: $target).keyboardType(.decimalPad)
                    Toggle("Accept conditional / unknown price eligibility", isOn: $value.allowConditional)
                    Text("Target applies to the whole specified pack, excluding deposit. Conditional prices may require membership or coupons.").font(.caption)
                    Toggle("Enabled", isOn: $value.enabled)
                }
                if let validation { Text(validation).foregroundStyle(.red) }
            }
            .navigationTitle(value.id.isEmpty ? "New watch" : "Edit watch")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") {
                    guard let cents = Money.parse(target), !value.name.trimmingCharacters(in: .whitespaces).isEmpty else { validation = "Enter a name and valid target price."; return }
                    value.requiredTerms = terms(required); value.excludedTerms = terms(excluded); value.targetCents = cents
                    guard !value.requiredTerms.isEmpty, value.amount > 0 else { validation = "Specify required terms and a positive amount."; return }
                    Task { if await model.save(value) { dismiss() } }
                } }
            }
        }
    }
    private func terms(_ text: String) -> [String] { text.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty } }
}
struct EventsView: View {
    @ObservedObject var model: MonitorViewModel
    var body: some View {
        NavigationStack {
            List {
                Section { Text("Relay acceptance is not proof that a notification appeared on your phone. Set up the companion notification app separately.").font(.caption) }
                ForEach(model.notifications) { event in
                    VStack(alignment: .leading) {
                        Text(event.title).font(.headline)
                        Text("\(Money.format(event.priceCents)) · \(event.reason)")
                        Text(event.createdAt).font(.caption)
                        Text(event.deliveredAt == nil ? "Pending / not accepted by relay" : "Accepted by relay").font(.caption)
                        if let error = event.error { Text(error).font(.caption).foregroundStyle(.orange) }
                    }
                }
                if model.notifications.isEmpty { Text("No target-price events recorded.") }
            }
            .navigationTitle("Events").refreshable { await model.refresh() }
        }
    }
}
struct SettingsView: View {
    @ObservedObject var model: MonitorViewModel
    @State private var region = false
    @State private var connection = false
    var body: some View {
        NavigationStack {
            List {
                Section("Region") {
                    Text(model.settings.postalCode == nil ? "Not configured" : "Postcode configured").privacySensitive()
                    Text("Radius: \(Int(model.settings.radiusKm)) km from a representative postal point")
                    Button("Configure region and providers") { region = true }
                }
                Section("Nearby locations") {
                    Text("Enable the locations to monitor. National observations are not verified branch prices.").font(.caption)
                    ForEach(model.locations.filter { model.settings.enabledProviders.contains($0.provider) }) { store in locationToggle(store) }
                    if model.locations.isEmpty { Text("No nearby catalogue locations loaded. Check region, collector status and data import.") }
                }
                if !model.unlocated.isEmpty {
                    Section("Configured locations — distance unverified") {
                        ForEach(model.unlocated) { store in locationToggle(store) }
                    }
                }
                Section("Service status") {
                    if let status = model.status {
                        Text(status.collectionEnabled ? "Collection enabled" : "Collection disabled by server operator")
                        Text(status.notificationConfigured ? "Notification relay configured — phone receipt unverified" : "Notification relay not configured")
                        ForEach(status.providers) { provider in
                            VStack(alignment: .leading) {
                                Text("\(provider.provider): \(provider.status)")
                                Text(provider.error ?? "Partial source coverage").font(.caption)
                                Text("Last success: \(provider.lastSuccessAt ?? "never")").font(.caption)
                            }
                        }
                    }
                }
                Section("Data attribution") {
                    ForEach(model.status?.datasets ?? []) { dataset in Text(dataset.attribution).font(.caption) }
                }
                Section { Button("Change connection") { connection = true }; Button("Refresh") { Task { await model.refresh() } } }
            }
            .navigationTitle("Settings")
            .sheet(isPresented: $region) { RegionEditor(model: model) }
            .sheet(isPresented: $connection) { ConnectionView(model: model) }
            .refreshable { await model.refresh() }
        }
    }
    private func locationToggle(_ store: LocationInfo) -> some View {
        Toggle(isOn: Binding(get: { model.settings.selectedStoreIds.contains(store.id) }, set: { selected in
            var updated = model.settings
            if selected { updated.selectedStoreIds.append(store.id) } else { updated.selectedStoreIds.removeAll { $0 == store.id } }
            Task { _ = await model.saveSettings(updated) }
        })) {
            VStack(alignment: .leading) {
                Text(store.name)
                Text("\(store.provider) · \(store.distanceKm.map { String(format: "%.1f km", $0) } ?? "distance unknown")").font(.caption)
            }
        }
    }
}
struct RegionEditor: View {
    @ObservedObject var model: MonitorViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var code = ""
    @State private var radius = 10.0
    @State private var enabled: Set<String> = []
    var body: some View {
        NavigationStack {
            Form {
                TextField("Five-digit postcode", text: $code).keyboardType(.numberPad).privacySensitive().textContentType(.postalCode)
                Stepper("Radius: \(Int(radius)) km", value: $radius, in: 1...100)
                Text("Validation and distance lookup happen on your private backend using its local dataset. The app does not contact an external geocoder.").font(.caption)
                ForEach(model.providers) { provider in
                    Toggle(isOn: Binding(get: { enabled.contains(provider.id) }, set: { if $0 { enabled.insert(provider.id) } else { enabled.remove(provider.id) } })) {
                        VStack(alignment: .leading) { Text(provider.name); Text(provider.limitation).font(.caption) }
                    }
                }
                Text("Saving a region clears selected locations; select nearby locations afterward. Distances are approximate, not driving distances.").font(.caption)
            }
            .navigationTitle("Region")
            .onAppear { code = model.settings.postalCode ?? ""; radius = model.settings.radiusKm; enabled = Set(model.settings.enabledProviders) }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") {
                    guard code.range(of: #"^[0-9]{5}\z"#, options: .regularExpression) != nil else { model.error = "Enter exactly five digits."; return }
                    var value = model.settings; value.postalCode = code; value.radiusKm = radius; value.enabledProviders = enabled.sorted(); value.selectedStoreIds = []
                    Task { if await model.saveSettings(value) { dismiss() } }
                } }
            }
        }
    }
}
