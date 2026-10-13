import SwiftUI
import MapKit
import CoreLocation
import LocalAuthentication
import Security
import UserNotifications

private struct MXPremiumMenuRow: View {
    let title: String
    let subtitle: String
    let symbol: String
    let tint: Color

    var body: some View {
        HStack(spacing: 13) {
            Image(systemName: symbol)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 49, height: 49)
                .background(tint.gradient, in: RoundedRectangle(cornerRadius: 13))
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.subheadline.weight(.bold)).foregroundStyle(.white)
                Text(subtitle).font(.caption2).foregroundStyle(MXPremiumStyle.muted)
                    .lineLimit(2)
            }
            Spacer(minLength: 6)
            Image(systemName: "chevron.right").font(.caption.weight(.semibold))
                .foregroundStyle(MXPremiumStyle.muted)
        }
        .padding(13)
        .background(MXPremiumStyle.panel, in: RoundedRectangle(cornerRadius: 18))
        .contentShape(Rectangle())
    }
}

enum MXPremiumPlanChoice: String, Hashable {
    case smartRoute, itinerary, budget, saved, calendar

    var title: String {
        switch self {
        case .smartRoute: "Smart Date Route"
        case .itinerary: "Itinerary Builder"
        case .budget: "Trip Cost Estimator"
        case .saved: "Saved Places"
        case .calendar: "Calendar & Reminders"
        }
    }
    var subtitle: String {
        switch self {
        case .smartRoute: "A real 3-stop café → activity → dinner plan"
        case .itinerary: "Store and share your planned stops"
        case .budget: "Manage spending with your own estimates"
        case .saved: "Your favorites and recent places"
        case .calendar: "Never miss a planned meeting"
        }
    }
    var symbol: String {
        switch self {
        case .smartRoute: "heart.circle.fill"
        case .itinerary: "airplane"
        case .budget: "calculator.fill"
        case .saved: "bookmark.fill"
        case .calendar: "calendar.badge.clock"
        }
    }
    var tint: Color {
        switch self {
        case .smartRoute: .pink
        case .itinerary: MXPremiumStyle.cyan
        case .budget: .green
        case .saved: .orange
        case .calendar: .red
        }
    }
}

struct MXPremiumPlanScreen: View {
    @EnvironmentObject private var navigation: MXPremiumNavigation

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Plan your dates, trips and activities")
                        .foregroundStyle(MXPremiumStyle.muted).font(.subheadline)
                    ForEach([MXPremiumPlanChoice.smartRoute, .itinerary, .budget,
                             .saved, .calendar], id: \.self) { choice in
                        NavigationLink(value: choice) {
                            MXPremiumMenuRow(title: choice.title, subtitle: choice.subtitle,
                                             symbol: choice.symbol, tint: choice.tint)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(16)
            }
            .background(MXPremiumStyle.background)
            .navigationTitle("Plan")
            .navigationDestination(for: MXPremiumPlanChoice.self) { choice in
                switch choice {
                case .smartRoute: MXPremiumSmartRouteView()
                case .itinerary: MXPremiumItineraryView()
                case .budget: MXPremiumBudgetView()
                case .saved:
                    MXPremiumSavedShortcut()
                case .calendar: MXPremiumReminderView()
                }
            }
        }
    }
}

struct MXPremiumSavedShortcut: View {
    @EnvironmentObject private var navigation: MXPremiumNavigation
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "bookmark.fill").font(.largeTitle)
                .foregroundStyle(MXPremiumStyle.cyan)
            Text("Your favorite locations stay in the Saved tab.")
                .multilineTextAlignment(.center)
            Button("Open Saved Places") { navigation.tab = 4 }
                .buttonStyle(.borderedProminent)
        }
        .padding(25).frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(MXPremiumStyle.background)
        .navigationTitle("Saved Places")
    }
}

@MainActor
final class MXPremiumDateRouteModel: ObservableObject {
    @Published var stops: [MKMapItem] = []
    @Published var loading = false
    @Published var message = "Choose a time and generate a route from real nearby places."
    private var requestId = UUID()

    func generate(center: CLLocationCoordinate2D, style: String) async {
        let id = UUID()
        requestId = id
        loading = true
        stops = []
        message = "Finding a café, an activity, and a restaurant near your pin…"
        let terms = style == "Relaxed"
            ? ["quiet cafe", "art gallery", "restaurant"]
            : style == "Night Out"
                ? ["coffee bar", "live music venue", "rooftop restaurant"]
                : ["cafe", "attraction", "restaurant"]
        var found: [MKMapItem] = []
        var identities = Set<String>()
        for query in terms {
            guard requestId == id else { return }
            let search = MKLocalSearch.Request()
            search.naturalLanguageQuery = query
            search.region = MKCoordinateRegion(center: center,
                                               latitudinalMeters: 10000,
                                               longitudinalMeters: 10000)
            search.resultTypes = .pointOfInterest
            if let response = try? await MKLocalSearch(request: search).start() {
                let centerLoc = CLLocation(latitude: center.latitude, longitude: center.longitude)
                let best = response.mapItems.first { item in
                    let coordinate = item.placemark.coordinate
                    let loc = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
                    let key = (item.name ?? "").lowercased()
                    return centerLoc.distance(from: loc) < 6500 && !identities.contains(key)
                }
                if let best {
                    identities.insert((best.name ?? "").lowercased())
                    found.append(best)
                }
            }
        }
        guard requestId == id else { return }
        stops = found
        loading = false
        message = found.count == 3
            ? "Three real locations found. Review details before visiting."
            : "Found \(found.count) matching locations. Expand your search or try another vibe."
    }
}

struct MXPremiumSmartRouteView: View {
    @EnvironmentObject private var session: SpoofSession
    @StateObject private var model = MXPremiumDateRouteModel()
    @State private var date = Date().addingTimeInterval(3600)
    @State private var style = "Romantic"
    @State private var totalBudget = 2000.0
    @AppStorage("mxpro.premium.route.summary") private var savedSummary = ""

    private var center: CLLocationCoordinate2D? {
        session.pin ?? session.simulated ?? session.realCoordinate
    }
    private let labels = ["Coffee", "Activity", "Dinner"]
    private let shades: [Color] = [MXPremiumStyle.cyan, .purple, .orange]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("A 3-stop date plan based on your time, vibe, and selected location.")
                    .font(.subheadline).foregroundStyle(MXPremiumStyle.muted)

                VStack(spacing: 15) {
                    DatePicker("Date & Time", selection: $date)
                        .datePickerStyle(.compact)
                    HStack {
                        Text("Budget")
                        Spacer()
                        TextField("Budget", value: $totalBudget, format: .number)
                            .multilineTextAlignment(.trailing)
                            .keyboardType(.decimalPad)
                            .frame(width: 110)
                    }
                    Text("Budget is your own estimate, not live venue pricing.")
                        .font(.caption2).foregroundStyle(MXPremiumStyle.muted)
                    Picker("Style", selection: $style) {
                        Text("Romantic").tag("Romantic")
                        Text("Relaxed").tag("Relaxed")
                        Text("Night Out").tag("Night Out")
                    }.pickerStyle(.segmented)
                }
                .padding(15)
                .background(MXPremiumStyle.panel, in: RoundedRectangle(cornerRadius: 18))

                Button {
                    guard let c = center else { return }
                    Task { await model.generate(center: c, style: style) }
                } label: {
                    HStack {
                        Spacer()
                        if model.loading { ProgressView().tint(.white) }
                        Image(systemName: "sparkles")
                        Text("Generate Plan").fontWeight(.bold)
                        Spacer()
                    }
                    .padding(15)
                    .background(MXPremiumStyle.cyan, in: RoundedRectangle(cornerRadius: 15))
                    .foregroundStyle(.white)
                }
                .disabled(center == nil || model.loading || totalBudget < 0)
                .buttonStyle(.plain)

                if center == nil {
                    Text("Select a destination from Map first.")
                        .font(.caption).foregroundStyle(.orange)
                }
                Text(model.message).font(.caption)
                    .foregroundStyle(MXPremiumStyle.muted)

                if !model.stops.isEmpty {
                    MXPremiumPanel {
                        VStack(alignment: .leading, spacing: 16) {
                            Text("Suggested Route").font(.headline)
                            ForEach(Array(model.stops.enumerated()), id: \.offset) { idx, item in
                                HStack(alignment: .top, spacing: 12) {
                                    Text("\(idx + 1)")
                                        .font(.caption.weight(.heavy))
                                        .frame(width: 30, height: 30)
                                        .background(shades[min(idx, 2)], in: Circle())
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(labels[min(idx, 2)])
                                            .font(.caption.weight(.semibold))
                                            .foregroundStyle(shades[min(idx, 2)])
                                        Text(item.name ?? "Venue").font(.subheadline.weight(.semibold))
                                        Text(item.placemark.title ?? "Address unavailable")
                                            .font(.caption2).foregroundStyle(MXPremiumStyle.muted)
                                    }
                                }
                            }
                        }
                    }
                    if let c = center {
                        Map(initialPosition: .region(MKCoordinateRegion(
                            center: c, latitudinalMeters: 12000, longitudinalMeters: 12000
                        ))) {
                            Marker("Start", coordinate: c).tint(MXPremiumStyle.cyan)
                            ForEach(Array(model.stops.enumerated()), id: \.offset) { idx, item in
                                Marker(labels[min(idx, 2)], coordinate: item.placemark.coordinate)
                                    .tint(shades[min(idx, 2)])
                            }
                        }
                        .frame(height: 210)
                        .clipShape(RoundedRectangle(cornerRadius: 18))
                    }
                    Button("Save 3-stop itinerary") {
                        savedSummary = model.stops.map { $0.name ?? "Venue" }.joined(separator: "\n")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(MXPremiumStyle.cyan)
                    Button("Open stops in Apple Maps") {
                        guard let c = center else { return }
                        let origin = MKMapItem(placemark: MKPlacemark(coordinate: c))
                        MKMapItem.openMaps(with: [origin] + model.stops,
                                           launchOptions: [MKLaunchOptionsDirectionsModeKey:
                                                           MKLaunchOptionsDirectionsModeWalking])
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding(16)
        }
        .background(MXPremiumStyle.background)
        .navigationTitle("Smart Date Route")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct MXPremiumItineraryView: View {
    @AppStorage("mxpro.premium.route.summary") private var summary = ""
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Saved Itinerary").font(.headline)
                if summary.isEmpty {
                    Text("Generate and save a plan using Smart Date Route.")
                        .foregroundStyle(MXPremiumStyle.muted)
                } else {
                    ForEach(Array(summary.components(separatedBy: "\n").enumerated()), id: \.offset) { idx, name in
                        MXPremiumPanel {
                            Label("\(idx + 1). \(name)",
                                  systemImage: idx == 0 ? "cup.and.saucer.fill" :
                                               idx == 1 ? "figure.walk" : "fork.knife")
                        }
                    }
                    ShareLink(item: summary) {
                        Label("Share itinerary", systemImage: "square.and.arrow.up")
                    }
                    Button("Clear saved itinerary", role: .destructive) { summary = "" }
                }
            }
            .padding(16)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MXPremiumStyle.background)
        .navigationTitle("Itinerary Builder")
    }
}

struct MXPremiumBudgetView: View {
    @AppStorage("mxpro.premium.budget.transport") private var transport = 0.0
    @AppStorage("mxpro.premium.budget.food") private var food = 0.0
    @AppStorage("mxpro.premium.budget.activities") private var activities = 0.0
    @State private var currency = "PHP"

    private var total: Double {
        max(0, transport) + max(0, food) + max(0, activities)
    }
    var body: some View {
        Form {
            Section("Your Currency") {
                Picker("Currency", selection: $currency) {
                    Text("PHP").tag("PHP")
                    Text("USD").tag("USD")
                    Text("IDR").tag("IDR")
                    Text("IQD").tag("IQD")
                }
            }
            Section("Estimated Expenses") {
                TextField("Transport", value: $transport, format: .number).keyboardType(.decimalPad)
                TextField("Food & Drinks", value: $food, format: .number).keyboardType(.decimalPad)
                TextField("Activities", value: $activities, format: .number).keyboardType(.decimalPad)
            }
            Section("Total — manual estimates") {
                Text("\(total, specifier: "%.0f") \(currency)")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(MXPremiumStyle.cyan)
                Text("No unverified real-time venue prices or currency conversion rates.")
                    .font(.caption).foregroundStyle(MXPremiumStyle.muted)
            }
        }
        .scrollContentBackground(.hidden)
        .background(MXPremiumStyle.background)
        .navigationTitle("Trip Cost Estimator")
    }
}

struct MXPremiumReminderView: View {
    @State private var date = Date().addingTimeInterval(3600)
    @State private var note = ""
    @State private var status = ""

    var body: some View {
        Form {
            Section("Your plan") {
                DatePicker("When", selection: $date, in: Date()...)
                TextField("Meeting or activity", text: $note)
            }
            Section {
                Button("Schedule Reminder") { schedule() }
                    .disabled(note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                if !status.isEmpty {
                    Text(status).font(.caption).foregroundStyle(MXPremiumStyle.muted)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(MXPremiumStyle.background)
        .navigationTitle("Calendar & Reminders")
    }
    private func schedule() {
        let message = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let requestedDate = date
        UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
                guard granted else {
                    DispatchQueue.main.async { status = "Allow notifications in Settings." }
                    return
                }
                let content = UNMutableNotificationContent()
                content.title = "MX Location Pro · Plan"
                content.body = message
                content.sound = .default
                let parts = Calendar.current.dateComponents(
                    [.year, .month, .day, .hour, .minute], from: requestedDate
                )
                let request = UNNotificationRequest(identifier: UUID().uuidString,
                     content: content,
                     trigger: UNCalendarNotificationTrigger(dateMatching: parts, repeats: false))
                UNUserNotificationCenter.current().add(request) { error in
                    DispatchQueue.main.async {
                        status = error == nil ? "Reminder scheduled." : "Could not schedule reminder."
                    }
                }
            }
    }
}

enum MXPremiumEssentialChoice: String, Hashable {
    case location, favorites, privacy, travel, offline, settings
    var title: String {
        switch self {
        case .location: "Location Control"
        case .favorites: "Favorites & Collections"
        case .privacy: "Privacy Tools"
        case .travel: "Travel Utilities"
        case .offline: "Offline Trip Notes"
        case .settings: "Settings"
        }
    }
    var subtitle: String {
        switch self {
        case .location: "Change or restore your simulated location"
        case .favorites: "Manage your saved and recent places"
        case .privacy: "Face ID protected private notes"
        case .travel: "Local weather and time at the chosen pin"
        case .offline: "Export notes for use without an internet connection"
        case .settings: "Pairing, GPS engine and app preferences"
        }
    }
    var symbol: String {
        switch self {
        case .location: "location.fill"
        case .favorites: "star.fill"
        case .privacy: "checkmark.shield.fill"
        case .travel: "suitcase.fill"
        case .offline: "map.fill"
        case .settings: "gearshape.fill"
        }
    }
    var tint: Color {
        switch self {
        case .location: MXPremiumStyle.cyan
        case .favorites: .orange
        case .privacy: .indigo
        case .travel: .purple
        case .offline: .green
        case .settings: .gray
        }
    }
}

struct MXPremiumEssentialsScreen: View {
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Core tools and controls")
                        .foregroundStyle(MXPremiumStyle.muted)
                        .font(.subheadline)
                    ForEach([MXPremiumEssentialChoice.location, .favorites,
                             .privacy, .travel, .offline, .settings], id: \.self) { option in
                        NavigationLink(value: option) {
                            MXPremiumMenuRow(title: option.title, subtitle: option.subtitle,
                                             symbol: option.symbol, tint: option.tint)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(16)
            }
            .background(MXPremiumStyle.background)
            .navigationTitle("Essentials")
            .navigationDestination(for: MXPremiumEssentialChoice.self) { option in
                switch option {
                case .location: MXPremiumLocationControl()
                case .favorites: MXPremiumSavedShortcut()
                case .privacy: MXPremiumVaultView()
                case .travel: MXPremiumTravelView()
                case .offline: MXPremiumOfflineView()
                case .settings: MXPremiumSettingsScreen()
                }
            }
        }
    }
}

struct MXPremiumLocationControl: View {
    @EnvironmentObject private var session: SpoofSession
    @EnvironmentObject private var pairing: PairingStore
    @EnvironmentObject private var navigation: MXPremiumNavigation

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                MXPremiumPanel {
                    HStack {
                        Label(session.isSpoofing ? "Simulation Active" : "Simulation Inactive",
                              systemImage: "location.circle.fill")
                            .foregroundStyle(session.isSpoofing ? .green : MXPremiumStyle.muted)
                        Spacer()
                    }
                    .font(.headline)
                    if let c = session.pin ?? session.simulated {
                        Text(String(format: "%.5f, %.5f", c.latitude, c.longitude))
                            .font(.caption.monospaced())
                            .foregroundStyle(MXPremiumStyle.muted)
                    }
                    Text(pairing.hasPairingFile ? "Pairing file available in Pro" : "Import pairing in Pro Settings")
                        .font(.caption2).foregroundStyle(MXPremiumStyle.muted)
                }
                Button("Choose or change location on Map") { navigation.tab = 0 }
                    .buttonStyle(.borderedProminent).tint(MXPremiumStyle.cyan)
                if let c = session.pin {
                    Button("Teleport to selected pin") {
                        session.teleport(to: c, pairing: pairing)
                    }
                    .buttonStyle(.bordered)
                }
                if session.isSpoofing {
                    Button(role: .destructive) { session.stop(pairing: pairing) } label: {
                        Label("Stop simulation & restore GPS", systemImage: "stop.circle.fill")
                    }
                    .buttonStyle(.borderedProminent)
                }
                Text("This reports the app's location engine status. Force-quitting iOS apps may end simulation.")
                    .font(.caption).foregroundStyle(MXPremiumStyle.muted)
            }
            .padding(16)
        }
        .background(MXPremiumStyle.background)
        .navigationTitle("Location Control")
    }
}

struct MXPremiumVaultView: View {
    @State private var unlocked = false
    @State private var secret = ""
    @State private var status = "Locked"
    private let account = "com.mazenmix.mxlocationpro.premium.vault"

    var body: some View {
        Form {
            Section("Private Notes") {
                if unlocked {
                    TextEditor(text: $secret).frame(height: 180)
                    Button("Save encrypted note") { save() }
                    Button("Lock now") { lock() }
                } else {
                    Button("Unlock with Face ID / device passcode") { unlock() }
                }
                Text(status).font(.caption).foregroundStyle(MXPremiumStyle.muted)
            }
        }
        .scrollContentBackground(.hidden)
        .background(MXPremiumStyle.background)
        .navigationTitle("Privacy Tools")
        .onDisappear { lock() }
    }

    private func lock() {
        unlocked = false
        secret = ""
        status = "Locked"
    }
    private func unlock() {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            status = "Set a device passcode or Face ID to use the vault."
            return
        }
        context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Unlock MX Pro private notes") {
            passed, _ in
            DispatchQueue.main.async {
                if passed {
                    secret = read()
                    unlocked = true
                    status = "Unlocked"
                } else {
                    status = "Authentication cancelled or failed."
                }
            }
        }
    }
    private func save() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
        var add = query
        add[kSecValueData as String] = Data(secret.utf8)
        add[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let result = SecItemAdd(add as CFDictionary, nil)
        status = result == errSecSuccess ? "Saved in device Keychain." : "Unable to save note."
    }
    private func read() -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }
}

@MainActor
final class MXPremiumTravelModel: ObservableObject {
    @Published var region = "Destination not selected"
    @Published var clock = "—"
    @Published var temperature = "—"
    func load(coordinate: CLLocationCoordinate2D) async {
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        if let mark = try? await CLGeocoder().reverseGeocodeLocation(location).first {
            region = [mark.locality, mark.country].compactMap { $0 }.joined(separator: ", ")
            if let zone = mark.timeZone {
                let formatter = DateFormatter()
                formatter.dateStyle = .medium
                formatter.timeStyle = .short
                formatter.timeZone = zone
                clock = formatter.string(from: Date())
            }
        }
        var url = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        url.queryItems = [
            URLQueryItem(name: "latitude", value: String(coordinate.latitude)),
            URLQueryItem(name: "longitude", value: String(coordinate.longitude)),
            URLQueryItem(name: "current", value: "temperature_2m")
        ]
        guard let endpoint = url.url,
              let (data, _) = try? await URLSession.shared.data(from: endpoint),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let current = json["current"] as? [String: Any],
              let temp = current["temperature_2m"] as? Double else { return }
        temperature = String(format: "%.0f °C", temp)
    }
}

struct MXPremiumTravelView: View {
    @EnvironmentObject private var session: SpoofSession
    @StateObject private var context = MXPremiumTravelModel()
    private var current: CLLocationCoordinate2D? {
        session.pin ?? session.simulated ?? session.realCoordinate
    }
    private var key: String {
        guard let c = current else { return "none" }
        return String(format: "%.5f:%.5f", c.latitude, c.longitude)
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                MXPremiumPanel {
                    Text(context.region).font(.headline)
                    Label(context.clock, systemImage: "clock.fill").padding(.top, 8)
                    Label(context.temperature, systemImage: "cloud.sun.fill").padding(.top, 8)
                }
                Text("Local date/time and a current weather reading for the selected pin. Internet required for live weather.")
                    .font(.caption).foregroundStyle(MXPremiumStyle.muted)
            }
            .padding(16)
        }
        .background(MXPremiumStyle.background)
        .navigationTitle("Travel Utilities")
        .task(id: key) {
            if let c = current { await context.load(coordinate: c) }
        }
    }
}

struct MXPremiumOfflineView: View {
    @EnvironmentObject private var session: SpoofSession
    @AppStorage("mxpro.premium.route.summary") private var route = ""
    private var textToExport: String {
        let favorites = session.favorites.map {
            "\($0.name): \($0.latitude), \($0.longitude)"
        }.joined(separator: "\n")
        return "MX Location Pro — Trip Notes\n\nSaved Locations\n\(favorites)\n\nDate Route\n\(route)"
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                MXPremiumPanel {
                    Label("Offline Trip Notes", systemImage: "doc.text.fill")
                        .font(.headline).foregroundStyle(.green)
                    Text("Export a compact list of your saved coordinates and route. This is not offline map tiles.")
                        .font(.caption).foregroundStyle(MXPremiumStyle.muted)
                }
                ShareLink(item: textToExport) {
                    Label("Export Travel Notes", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.borderedProminent).tint(.green)
                Text(textToExport).font(.caption.monospaced())
                    .foregroundStyle(MXPremiumStyle.muted)
            }.padding(16)
        }
        .background(MXPremiumStyle.background)
        .navigationTitle("Offline Travel Pack")
    }
}

struct MXPremiumSettingsScreen: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                MXPremiumPanel {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("MX Location Pro", systemImage: "location.north.circle.fill")
                            .font(.headline)
                        Text("Version 4.2 · Independent from MX Location")
                            .font(.caption).foregroundStyle(MXPremiumStyle.muted)
                        Text("All signing, GPS pairing and permissions remain managed by the original Settings controls.")
                            .font(.caption).foregroundStyle(MXPremiumStyle.muted)
                    }
                }
                NavigationLink {
                    SettingsView()
                } label: {
                    MXPremiumMenuRow(title: "Advanced Location & Pairing Settings",
                                     subtitle: "Import pairing file, review GPS and certificate details",
                                     symbol: "gearshape.2.fill", tint: MXPremiumStyle.cyan)
                }.buttonStyle(.plain)
            }
            .padding(16)
        }
        .background(MXPremiumStyle.background)
        .navigationTitle("Settings")
    }
}
