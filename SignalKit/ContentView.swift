import SwiftUI

struct ContentView: View {
    @StateObject private var model = MonitorViewModel()
    @Environment(\.scenePhase) private var phase
    @State private var firstRegion = false
    var body: some View {
        Group {
            if model.restoring { ProgressView("Loading saved observations") }
            else if model.saved != nil {
                TabView {
                    OffersView(model: model).tabItem { Label("Offers", systemImage: "list.bullet.rectangle") }
                    SubscriptionsView(model: model).tabItem { Label("Watchlist", systemImage: "star") }
                    SettingsView(model: model).tabItem { Label("Settings", systemImage: "gear") }
                }
            } else { ConnectionView(model: model) }
        }
        .task { await model.restore() }
        .onChange(of: model.connected) { _, connected in if connected && model.settings.postalCode == nil { firstRegion = true } }
        .onChange(of: phase) { _, value in if value != .active { model.pauseNetwork() } }
        .sheet(isPresented: $firstRegion) { RegionEditor(model: model) }
        .alert("Action unavailable", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) { Button("OK") { model.error = nil } } message: { Text(model.error ?? "") }
    }
}
struct ConnectionView: View {
    @ObservedObject var model: MonitorViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var address = ""
    @State private var token = ""
    var body: some View {
        NavigationStack {
            Form {
                Section("Home connection") {
                    TextField("Home server URL", text: $address).textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL).accessibilityIdentifier("backendAddress")
                    SecureField("Dedicated credential (blank uses Keychain)", text: $token).textInputAutocapitalization(.never).autocorrectionDisabled().accessibilityIdentifier("backendToken")
                    Button("Connect") { Task { if await model.connect(address, token: token) { dismiss() }; token = "" } }.disabled(model.busy)
                }
                Section {
                    Text("First download requires your home server. Afterwards you can browse saved data away from home without a connection.")
                    Text("HTTP is allowed only for private IPv4 addresses on your trusted home LAN. It does not encrypt data or the app credential. Use a dedicated token, never an Apple or repository password.").font(.caption)
                    Text("Explicitly reconnecting selects this server's data. Prior server snapshots are preserved privately.").font(.caption)
                }
                if model.busy { ProgressView("Connecting") }
            }.navigationTitle("Signal Kit").onAppear { address = model.savedAddress }
        }
    }
}
struct SavedStatus: View {
    @ObservedObject var model: MonitorViewModel
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(model.connected ? "Home server checked this session" : "Saved data — home connection not checked").font(.subheadline)
            if let saved = model.saved {
                Text("Downloaded \(saved.downloadedAt)").font(.caption)
                Text("Downloaded window: \(saved.snapshot.coverageFrom) – \(saved.snapshot.coverageUntil)").font(.caption)
                if saved.snapshot.coverageUntil < OfferWindow.end(Date()) { Text("Part of the new week window has not been downloaded. Refresh at home; absence is not no offers.").font(.caption).foregroundStyle(.orange) }
            }
            if let notice = model.notice { Text(notice).font(.caption) }
            if model.busy { ProgressView("Refreshing / saving") }
            if let job = model.job {
                Text("Last operation: \(job.state)").font(.caption)
                ForEach(job.results) { result in Text("\(result.provider): \(result.status)\(result.error.map { " · " + $0 } ?? "")").font(.caption) }
            }
        }
    }
}
struct OffersView: View {
    @ObservedObject var model: MonitorViewModel
    var body: some View {
        NavigationStack {
            List {
                Section {
                    SavedStatus(model: model)
                    Button(model.saved?.requestKey == nil ? "Refresh offers at home" : "Resume refresh") { Task { await model.refreshOffers() } }.disabled(model.busy).accessibilityIdentifier("refreshOffers")
                    Text("Only refresh on your trusted home network. Advertising coverage is partial; stock and ordinary shelf prices are not verified.").font(.caption)
                }
                Section { TextField("Search saved product labels", text: $model.query).accessibilityIdentifier("offerSearch") }
                Section("Now / later this week") { ForEach(model.filteredOffers.filter { !OfferWindow.nextWeek($0) }) { offer in row(offer) } }
                Section("Next week") { ForEach(model.filteredOffers.filter { OfferWindow.nextWeek($0) }) { offer in row(offer) } }
                if model.filteredOffers.isEmpty { Text("No matches in the downloaded data. Check source status and the downloaded date window; this does not prove there are no promotions.") }
            }
            .navigationTitle("Offers")
            .refreshable { await model.refreshOffers() }
        }
    }
    private func row(_ offer: SignalOffer) -> some View {
        NavigationLink { OfferDetail(offer: offer, model: model) } label: { OfferRow(offer: offer) }
    }
}
struct OfferRow: View {
    let offer: SignalOffer
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack { Text(offer.title).font(.headline); Spacer(); Text(Money.format(offer.priceCents)).monospacedDigit() }
            Text("\(offer.provider) · \(offer.package)").font(.subheadline)
            Text("\(offer.validFrom) – \(offer.validUntil)").font(.caption)
            Text("\(offer.scope) · \(offer.variantScope) · \(offer.eligibility)").font(.caption).foregroundStyle(.secondary)
            if offer.outdated() { Label("Older saved observation — refresh at home", systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange) }
        }
    }
}
struct OfferDetail: View {
    let offer: SignalOffer
    @ObservedObject var model: MonitorViewModel
    @State private var creating = false
    var body: some View {
        List {
            Section(offer.title) {
                LabeledContent("Advertised goods price", value: Money.format(offer.priceCents))
                LabeledContent("Package", value: offer.package)
                LabeledContent("Deposit", value: offer.depositCents.map(Money.format) ?? "Unknown")
                if let deposit = offer.depositCents { LabeledContent("Checkout total", value: Money.format(offer.priceCents + deposit)) }
                if let value = offer.unitPriceCents { LabeledContent("Per litre / kilogram", value: Money.format(value)) }
                if let value = offer.referenceCents { LabeledContent("Reference (\(offer.referenceType))", value: Money.format(value)) }
                LabeledContent("Conditions", value: offer.eligibility)
                LabeledContent("Variant", value: offer.variantScope)
                LabeledContent("Scope", value: offer.scope)
                LabeledContent("Location", value: offer.storeId ?? "National — no verified branch")
                Text("Valid \(offer.validFrom) through \(offer.validUntil)")
                Text("Observed \(offer.fetchedAt)").font(.caption)
                if offer.outdated() { Text("This saved observation is older; its current accuracy has not been checked.").foregroundStyle(.orange) }
                Text(offer.description)
                if let url = URL(string: offer.sourceUrl), url.scheme == "https" { Link("View source (external website)", destination: url) }
                Button("Create watch") { creating = true }.disabled(!model.canEdit)
            }
            Section("Downloaded price history") {
                Text("Promotional observations, not ordinary shelf-price evidence. History is limited to downloaded products and may be truncated.").font(.caption)
                if model.saved?.snapshot.historyTruncated == true { Text("Older history was not included in this download.").font(.caption) }
                ForEach(Array(model.history(offer).enumerated()), id: \.offset) { _, point in
                    VStack(alignment: .leading) { Text(Money.format(point.priceCents)); Text("\(point.observedAt) · \(point.offer.package) · \(point.offer.storeId ?? point.offer.scope)").font(.caption) }
                }
                if model.history(offer).isEmpty { Text("No earlier observations in this saved copy.") }
            }
        }.navigationTitle("Details")
        .sheet(isPresented: $creating) { SubscriptionEditor(model: model, initial: draft) }
    }
    private var draft: Subscription {
        var value = Subscription(); value.name = offer.title
        value.requiredTerms = ((offer.brand ?? "") + " " + offer.title).split(whereSeparator: { $0.isWhitespace }).map(String.init)
        value.amount = offer.amount ?? 500; value.unit = offer.unit ?? "ml"; value.count = offer.count ?? 1
        value.container = offer.container; value.targetCents = offer.priceCents; return value
    }
}
struct SubscriptionsView: View {
    @ObservedObject var model: MonitorViewModel
    @State private var editing: Subscription?
    var body: some View {
        NavigationStack {
            List {
                Section { Text("Browse saved watches and matches offline. Connect at home to change them. Exact identity does not verify stock; eligibility and freshness still apply.").font(.caption) }
                ForEach(model.subscriptions) { subscription in
                    NavigationLink { SubscriptionComparison(model: model, subscription: subscription) } label: {
                        VStack(alignment: .leading) {
                            Text(subscription.name).font(.headline)
                            Text("\(subscription.count) × \(subscription.amount) \(subscription.unit) · target \(Money.format(subscription.targetCents))").font(.subheadline)
                            Text("\(model.comparison(subscription).count) downloaded candidates · \(subscription.enabled ? "Enabled" : "Paused")").font(.caption)
                        }
                    }
                    .swipeActions(edge: .leading) { Button("Edit") { editing = subscription }.disabled(!model.canEdit) }
                    .swipeActions { Button("Remove", role: .destructive) { Task { await model.remove(subscription) } }.disabled(!model.canEdit) }
                }
                if model.subscriptions.isEmpty { Text("No watches saved. Connect at home to add one.") }
            }.navigationTitle("Watchlist")
            .toolbar { Button { editing = Subscription() } label: { Image(systemName: "plus") }.accessibilityLabel("Add watch").disabled(!model.canEdit) }
            .sheet(item: $editing) { SubscriptionEditor(model: model, initial: $0) }
        }
    }
}
struct SubscriptionComparison: View {
    @ObservedObject var model: MonitorViewModel
    let subscription: Subscription
    var body: some View {
        List {
            Section { Text("Current and upcoming advertised packages from your saved copy. A target met here is not a live stock or price guarantee.").font(.caption) }
            ForEach(model.comparison(subscription), id: \.0.id) { offer, match in
                NavigationLink { OfferDetail(offer: offer, model: model) } label: {
                    VStack(alignment: .leading) {
                        OfferRow(offer: offer)
                        Text("\(match.match == "exact" ? "Exact identity" : "Possible — not confirmed") · \(match.targetMet ? "Within target" : "Above target")").font(.caption)
                        Text(match.reason).font(.caption)
                    }
                }
            }
            if model.comparison(subscription).isEmpty { Text("No candidates in the downloaded coverage. Missing data is not proof of no promotions.") }
        }.navigationTitle(subscription.name)
    }
}
struct SettingsView: View {
    @ObservedObject var model: MonitorViewModel
    @State private var region = false
    @State private var connection = false
    var body: some View {
        NavigationStack {
            List {
                Section("Saved / connection") { SavedStatus(model: model); Button("Connect / check home server") { connection = true } }
                Section("Region") {
                    Text(model.settings.postalCode == nil ? "Not configured" : "Postcode configured").privacySensitive()
                    Text("Radius: \(Int(model.settings.radiusKm)) km from a representative postal point")
                    Button("Configure region and providers") { region = true }.disabled(!model.canEdit)
                }
                Section("Nearby locations") {
                    Text("Connect at home to select locations. National advertising is not verified branch stock or price.").font(.caption)
                    ForEach(model.locations.filter { model.settings.enabledProviders.contains($0.provider) }) { locationToggle($0) }
                    if model.locations.isEmpty { Text("No locations saved. Configure the region, refresh catalogues at home, then select stores.") }
                }
                if !model.unlocated.isEmpty { Section("Configured locations — distance unverified") { ForEach(model.unlocated) { locationToggle($0) } } }
                Section("Saved source status") {
                    Text(model.saved?.snapshot.collectionEnabled == true ? "Manual collection enabled" : "Collection disabled by operator")
                    ForEach(model.saved?.snapshot.providerStatus ?? []) { status in
                        VStack(alignment: .leading) { Text("\(status.provider): \(status.status)"); Text(status.error ?? "Partial promotional coverage").font(.caption); Text("Last successful attempt: \(status.lastSuccessAt ?? "never")").font(.caption) }
                    }
                }
                Section("Data attribution") { ForEach(model.saved?.snapshot.datasets ?? []) { Text($0.attribution).font(.caption) } }
                Section("Privacy and storage") {
                    Text("No continuous monitoring, cloud sync or notifications. Downloaded data is protected on this device and excluded from automatic backup. Uninstalling can lose the offline copy.").font(.caption)
                    Text("The dedicated credential is in Keychain. LAN HTTP is unencrypted; intercepted traffic can expose that credential and saved preferences in transit.").font(.caption)
                }
            }.navigationTitle("Settings")
            .sheet(isPresented: $region) { RegionEditor(model: model) }
            .sheet(isPresented: $connection) { ConnectionView(model: model) }
        }
    }
    private func locationToggle(_ store: LocationInfo) -> some View {
        Toggle(isOn: Binding(get: { model.settings.selectedStoreIds.contains(store.id) }, set: { selected in
            var value = model.settings
            if selected { value.selectedStoreIds.append(store.id) } else { value.selectedStoreIds.removeAll { $0 == store.id } }
            Task { _ = await model.saveSettings(value) }
        })) {
            VStack(alignment: .leading) { Text(store.name); Text("\(store.provider) · \(store.distanceKm.map { String(format: "%.1f km", $0) } ?? "distance unknown")").font(.caption) }
        }.disabled(!model.canEdit)
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
                Text("Your private home server validates this using its local directory; no personal postcode is sent to a public geocoder.").font(.caption)
                ForEach(model.providers) { provider in
                    Toggle(isOn: Binding(get: { enabled.contains(provider.id) }, set: { if $0 { enabled.insert(provider.id) } else { enabled.remove(provider.id) } })) { VStack(alignment: .leading) { Text(provider.name); Text(provider.limitation).font(.caption) } }
                }
                Text("Saving clears selected locations. Refresh at home to load catalogues, then select the intended locations. Distances are approximate.").font(.caption)
            }.navigationTitle("Region")
            .onAppear { code = model.settings.postalCode ?? ""; radius = model.settings.radiusKm; enabled = Set(model.settings.enabledProviders) }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") {
                    guard code.range(of: #"^[0-9]{5}\z"#, options: .regularExpression) != nil else { model.error = "Enter exactly five digits."; return }
                    var value = model.settings; value.postalCode = code; value.radiusKm = radius; value.enabledProviders = enabled.sorted(); value.selectedStoreIds = []
                    Task { if await model.saveSettings(value) { dismiss() } }
                }.disabled(!model.canEdit) }
            }
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
                    Text("Include the brand and exact variant. The app cannot infer a flavor from an unspecified assortment.").font(.caption)
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
                }.disabled(!model.canEdit) }
            }
        }
    }
    private func terms(_ text: String) -> [String] { text.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty } }
}
