import CoreLocation
import MapKit
import SwiftUI
import UIKit

enum MXFavoriteKind: String, Codable, CaseIterable, Identifiable {
    case home = "Home"
    case hotel = "Hotel"
    case airport = "Airport"
    case date = "Date"
    case cafe = "Cafe"
    case mall = "Mall"
    case food = "Food"
    case nightlife = "Nightlife"
    case other = "Other"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .home: return "house.fill"
        case .hotel: return "bed.double.fill"
        case .airport: return "airplane"
        case .date: return "heart.fill"
        case .cafe: return "cup.and.saucer.fill"
        case .mall: return "bag.fill"
        case .food: return "fork.knife"
        case .nightlife: return "moon.stars.fill"
        case .other: return "mappin.circle.fill"
        }
    }
}

struct MXSmartPlace: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String
    var city: String
    var kind: MXFavoriteKind
    var latitude: Double
    var longitude: Double
    var createdAt = Date()

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

struct MXTripPreset: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String
    var city: String
    var placeIDs: [UUID]
    var createdAt = Date()
}

struct MXHistoryEntry: Identifiable, Codable, Equatable {
    var id = UUID()
    var date = Date()
    var latitude: Double
    var longitude: Double

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

struct MXArea: Identifiable {
    let id = UUID()
    let name: String
    let subtitle: String
    let latitude: Double
    let longitude: Double

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

struct MXCityPreset: Identifiable {
    var id: String { name }
    let name: String
    let center: CLLocationCoordinate2D
    let datingAreas: [MXArea]
}

enum MXTravelData {
    static let smartFavoritesKey = "mx.smartFavorites.v1"
    static let tripsKey = "mx.tripPresets.v1"
    static let historyKey = "mx.tripHistory.v1"

    static let cities: [MXCityPreset] = [
        MXCityPreset(
            name: "Manila",
            center: CLLocationCoordinate2D(latitude: 14.5995, longitude: 120.9842),
            datingAreas: [
                MXArea(name: "BGC", subtitle: "High Street / nightlife / cafes", latitude: 14.5507, longitude: 121.0500),
                MXArea(name: "Makati", subtitle: "Poblacion / Greenbelt", latitude: 14.5547, longitude: 121.0244),
                MXArea(name: "Quezon City", subtitle: "Tomas Morato / North EDSA", latitude: 14.6760, longitude: 121.0437),
                MXArea(name: "Malate", subtitle: "Bay / nightlife", latitude: 14.5735, longitude: 120.9899),
                MXArea(name: "Ortigas", subtitle: "Malls / business district", latitude: 14.5869, longitude: 121.0614)
            ]
        ),
        MXCityPreset(
            name: "Cebu",
            center: CLLocationCoordinate2D(latitude: 10.3157, longitude: 123.8854),
            datingAreas: [
                MXArea(name: "IT Park", subtitle: "Dining / nightlife", latitude: 10.3309, longitude: 123.9067),
                MXArea(name: "Ayala Center", subtitle: "Mall / cafes", latitude: 10.3181, longitude: 123.9054),
                MXArea(name: "Mactan", subtitle: "Resorts / airport area", latitude: 10.3099, longitude: 123.9494)
            ]
        ),
        MXCityPreset(
            name: "Jakarta",
            center: CLLocationCoordinate2D(latitude: -6.2088, longitude: 106.8456),
            datingAreas: [
                MXArea(name: "SCBD", subtitle: "Upscale / nightlife", latitude: -6.2258, longitude: 106.8090),
                MXArea(name: "Kemang", subtitle: "Cafes / nightlife", latitude: -6.2607, longitude: 106.8132),
                MXArea(name: "Grand Indonesia", subtitle: "Mall / central", latitude: -6.1950, longitude: 106.8200)
            ]
        ),
        MXCityPreset(
            name: "Bangkok",
            center: CLLocationCoordinate2D(latitude: 13.7563, longitude: 100.5018),
            datingAreas: [
                MXArea(name: "Thonglor", subtitle: "Cafes / nightlife", latitude: 13.7308, longitude: 100.5796),
                MXArea(name: "Siam", subtitle: "Malls / central", latitude: 13.7466, longitude: 100.5347),
                MXArea(name: "Asok", subtitle: "Terminal 21 / nightlife", latitude: 13.7370, longitude: 100.5605)
            ]
        ),
        MXCityPreset(
            name: "Baghdad",
            center: CLLocationCoordinate2D(latitude: 33.3152, longitude: 44.3661),
            datingAreas: [
                MXArea(name: "Mansour", subtitle: "Cafes / restaurants", latitude: 33.3157, longitude: 44.3403),
                MXArea(name: "Karrada", subtitle: "Shopping / cafes", latitude: 33.3024, longitude: 44.4255),
                MXArea(name: "Al-Jadriya", subtitle: "Restaurants / river", latitude: 33.2777, longitude: 44.3849)
            ]
        )
    ]

    static func loadSmartFavorites() -> [MXSmartPlace] {
        guard let data = UserDefaults.standard.data(forKey: smartFavoritesKey),
              let items = try? JSONDecoder().decode([MXSmartPlace].self, from: data) else { return [] }
        return items
    }

    static func saveSmartFavorites(_ items: [MXSmartPlace]) {
        if let data = try? JSONEncoder().encode(items) {
            UserDefaults.standard.set(data, forKey: smartFavoritesKey)
        }
    }

    static func loadTrips() -> [MXTripPreset] {
        guard let data = UserDefaults.standard.data(forKey: tripsKey),
              let items = try? JSONDecoder().decode([MXTripPreset].self, from: data) else { return [] }
        return items
    }

    static func saveTrips(_ items: [MXTripPreset]) {
        if let data = try? JSONEncoder().encode(items) {
            UserDefaults.standard.set(data, forKey: tripsKey)
        }
    }

    static func loadHistory() -> [MXHistoryEntry] {
        guard let data = UserDefaults.standard.data(forKey: historyKey),
              let items = try? JSONDecoder().decode([MXHistoryEntry].self, from: data) else { return [] }
        return items
    }

    static func recordHistory(_ coordinate: CLLocationCoordinate2D) {
        var items = loadHistory()
        if let first = items.first,
           abs(first.latitude - coordinate.latitude) < 0.000001,
           abs(first.longitude - coordinate.longitude) < 0.000001 {
            return
        }
        items.insert(MXHistoryEntry(latitude: coordinate.latitude, longitude: coordinate.longitude), at: 0)
        if items.count > 250 { items = Array(items.prefix(250)) }
        if let data = try? JSONEncoder().encode(items) {
            UserDefaults.standard.set(data, forKey: historyKey)
        }
    }
}

struct MXTravelSuiteView: View {
    @EnvironmentObject private var session: SpoofSession
    @EnvironmentObject private var pairing: PairingStore
    @Environment(\.dismiss) private var dismiss

    @AppStorage("mx.activeCity") private var activeCity = "Manila"
    @AppStorage("mx.locationLocked") private var locationLocked = false
    @AppStorage("mx.distanceRingKm") private var distanceRingKm = 0.0

    @State private var smartFavorites = MXTravelData.loadSmartFavorites()
    @State private var trips = MXTravelData.loadTrips()
    @State private var showQuickPlaces = false
    @State private var showNearby = false
    @State private var showAddFavorite = false
    @State private var showHistory = false
    @State private var showDating = false
    @State private var presetName = ""
    @State private var showPresetName = false

    private var currentCity: MXCityPreset {
        MXTravelData.cities.first(where: { $0.name == activeCity }) ?? MXTravelData.cities[0]
    }

    private var cityFavorites: [MXSmartPlace] {
        smartFavorites.filter { $0.city == activeCity }
    }

    private var cityTrips: [MXTripPreset] {
        trips.filter { $0.city == activeCity }
    }

    var body: some View {
        NavigationStack {
            List {
                Section("City Switcher") {
                    Picker("Active city", selection: $activeCity) {
                        ForEach(MXTravelData.cities) { city in
                            Text(city.name).tag(city.name)
                        }
                    }
                }

                Section("Quick Tools") {
                    Button { showQuickPlaces = true } label: {
                        Label("Quick Places", systemImage: "star.circle.fill")
                    }
                    Button { showNearby = true } label: {
                        Label("Nearby Hotspots", systemImage: "sparkle.magnifyingglass")
                    }
                    Button { showDating = true } label: {
                        Label("Dating Mode", systemImage: "heart.circle.fill")
                    }
                    Toggle(isOn: $locationLocked) {
                        Label("Lock Location", systemImage: locationLocked ? "lock.fill" : "lock.open")
                    }
                    Picker("Distance Ring", selection: $distanceRingKm) {
                        Text("Off").tag(0.0)
                        Text("1 km").tag(1.0)
                        Text("5 km").tag(5.0)
                        Text("10 km").tag(10.0)
                        Text("25 km").tag(25.0)
                    }
                }

                Section("Back 3 Locations") {
                    if session.recents.isEmpty {
                        Text("No recent locations yet.").foregroundStyle(.secondary)
                    }
                    ForEach(Array(session.recents.prefix(3))) { place in
                        Button {
                            session.teleport(to: place.coordinate, pairing: pairing)
                            dismiss()
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(place.name).foregroundStyle(.primary)
                                Text(String(format: "%.5f, %.5f", place.latitude, place.longitude))
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                Section("Smart Favorites") {
                    Button { showAddFavorite = true } label: {
                        Label("Save Current Location", systemImage: "plus.circle.fill")
                    }
                    if cityFavorites.isEmpty {
                        Text("Save hotel, airport, date spots, cafes and malls for this city.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(cityFavorites) { place in
                        Button {
                            session.teleport(to: place.coordinate, pairing: pairing)
                            dismiss()
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: place.kind.icon)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(place.name).foregroundStyle(.primary)
                                    Text(place.kind.rawValue).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                        .swipeActions {
                            Button(role: .destructive) {
                                smartFavorites.removeAll { $0.id == place.id }
                                MXTravelData.saveSmartFavorites(smartFavorites)
                            } label: { Label("Delete", systemImage: "trash") }
                        }
                    }
                }

                Section("Travel Presets") {
                    Button {
                        guard !cityFavorites.isEmpty else {
                            session.lastError = "Save at least one Smart Favorite in \(activeCity) first."
                            return
                        }
                        presetName = "\(activeCity) Trip"
                        showPresetName = true
                    } label: {
                        Label("Create Preset from Smart Favorites", systemImage: "airplane.circle.fill")
                    }
                    ForEach(cityTrips) { trip in
                        NavigationLink {
                            MXTripPresetView(trip: trip, smartFavorites: smartFavorites)
                                .environmentObject(session)
                                .environmentObject(pairing)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(trip.name)
                                Text("\(trip.placeIDs.count) stops").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .swipeActions {
                            Button(role: .destructive) {
                                trips.removeAll { $0.id == trip.id }
                                MXTravelData.saveTrips(trips)
                            } label: { Label("Delete", systemImage: "trash") }
                        }
                    }
                }

                Section("Trip History") {
                    Button { showHistory = true } label: {
                        Label("Open Timeline", systemImage: "clock.arrow.circlepath")
                    }
                }
            }
            .navigationTitle("MX Travel Hub")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $showQuickPlaces) {
                QuickPlacesView().environmentObject(session).environmentObject(pairing)
            }
            .sheet(isPresented: $showNearby) {
                MXNearbyHotspotsView().environmentObject(session).environmentObject(pairing)
            }
            .sheet(isPresented: $showAddFavorite) {
                MXAddSmartFavoriteView(city: activeCity) { place in
                    smartFavorites.removeAll { $0.id == place.id }
                    smartFavorites.insert(place, at: 0)
                    MXTravelData.saveSmartFavorites(smartFavorites)
                }
                .environmentObject(session)
            }
            .sheet(isPresented: $showHistory) {
                MXTripHistoryView().environmentObject(session).environmentObject(pairing)
            }
            .sheet(isPresented: $showDating) {
                MXDatingModeView(city: currentCity)
                    .environmentObject(session)
                    .environmentObject(pairing)
            }
            .alert("New Travel Preset", isPresented: $showPresetName) {
                TextField("Preset name", text: $presetName)
                Button("Cancel", role: .cancel) { }
                Button("Save") {
                    let ids = cityFavorites.map(\.id)
                    let trip = MXTripPreset(name: presetName.isEmpty ? "\(activeCity) Trip" : presetName, city: activeCity, placeIDs: ids)
                    trips.insert(trip, at: 0)
                    MXTravelData.saveTrips(trips)
                }
            } message: {
                Text("The preset will use your Smart Favorites for \(activeCity) as one-tap stops.")
            }
        }
    }
}

struct MXDatingModeView: View {
    @EnvironmentObject private var session: SpoofSession
    @EnvironmentObject private var pairing: PairingStore
    @Environment(\.dismiss) private var dismiss
    let city: MXCityPreset

    var body: some View {
        NavigationStack {
            List {
                Section("\(city.name) Dating Areas") {
                    ForEach(city.datingAreas) { area in
                        Button {
                            session.teleport(to: area.coordinate, pairing: pairing)
                            dismiss()
                        } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(area.name).font(.headline).foregroundStyle(.primary)
                                Text(area.subtitle).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                Section {
                    Text("Use these as fast area presets; exact matches still depend on each dating app's own distance and location handling.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Dating Mode")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
        }
    }
}

struct MXNearbyHotspotsView: View {
    @EnvironmentObject private var session: SpoofSession
    @EnvironmentObject private var pairing: PairingStore
    @Environment(\.dismiss) private var dismiss

    @State private var query = "Cafe"
    @State private var results: [MKMapItem] = []
    @State private var loading = false

    private let categories = ["Cafe", "Restaurant", "Mall", "Hotel", "Airport", "Bar", "Tourist attraction"]

    private var baseCoordinate: CLLocationCoordinate2D? {
        session.simulated ?? session.pin ?? session.realCoordinate
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("Category", selection: $query) {
                        ForEach(categories, id: \.self) { Text($0).tag($0) }
                    }
                    .onChange(of: query) { _, _ in search() }
                }
                Section("Nearby") {
                    if loading { ProgressView() }
                    if !loading && results.isEmpty {
                        Text("No results yet.").foregroundStyle(.secondary)
                    }
                    ForEach(Array(results.enumerated()), id: \.offset) { _, item in
                        Button {
                            session.teleport(to: item.placemark.coordinate, pairing: pairing)
                            dismiss()
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.name ?? "Place").foregroundStyle(.primary)
                                if let title = item.placemark.title {
                                    Text(title).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Nearby Hotspots")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .primaryAction) { Button { search() } label: { Image(systemName: "arrow.clockwise") } }
            }
            .onAppear { search() }
        }
    }

    private func search() {
        guard let center = baseCoordinate else {
            session.lastError = "Choose a location first."
            return
        }
        loading = true
        Task {
            let request = MKLocalSearch.Request()
            request.naturalLanguageQuery = query
            request.region = MKCoordinateRegion(center: center, latitudinalMeters: 12_000, longitudinalMeters: 12_000)
            let response = try? await MKLocalSearch(request: request).start()
            await MainActor.run {
                results = Array((response?.mapItems ?? []).prefix(20))
                loading = false
            }
        }
    }
}

struct MXAddSmartFavoriteView: View {
    @EnvironmentObject private var session: SpoofSession
    @Environment(\.dismiss) private var dismiss
    let city: String
    let onSave: (MXSmartPlace) -> Void

    @State private var name = ""
    @State private var kind: MXFavoriteKind = .date

    private var coordinate: CLLocationCoordinate2D? { session.simulated ?? session.pin }

    var body: some View {
        NavigationStack {
            Form {
                TextField("Name", text: $name)
                Picker("Type", selection: $kind) {
                    ForEach(MXFavoriteKind.allCases) { item in
                        Label(item.rawValue, systemImage: item.icon).tag(item)
                    }
                }
                if let coordinate {
                    LabeledContent("Coordinates", value: String(format: "%.5f, %.5f", coordinate.latitude, coordinate.longitude))
                } else {
                    Text("Choose or spoof a location first.").foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Smart Favorite")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        guard let coordinate else { return }
                        let finalName = name.trimmingCharacters(in: .whitespacesAndNewlines)
                        onSave(MXSmartPlace(
                            name: finalName.isEmpty ? kind.rawValue : finalName,
                            city: city,
                            kind: kind,
                            latitude: coordinate.latitude,
                            longitude: coordinate.longitude
                        ))
                        dismiss()
                    }
                    .disabled(coordinate == nil)
                }
            }
        }
    }
}

struct MXTripPresetView: View {
    @EnvironmentObject private var session: SpoofSession
    @EnvironmentObject private var pairing: PairingStore
    let trip: MXTripPreset
    let smartFavorites: [MXSmartPlace]

    private var stops: [MXSmartPlace] {
        trip.placeIDs.compactMap { id in smartFavorites.first(where: { $0.id == id }) }
    }

    var body: some View {
        List {
            ForEach(Array(stops.enumerated()), id: \.element.id) { index, place in
                Button {
                    session.teleport(to: place.coordinate, pairing: pairing)
                } label: {
                    HStack(spacing: 12) {
                        Text("\(index + 1)").font(.caption.bold()).frame(width: 24, height: 24).background(Circle().fill(Color.primary.opacity(0.1)))
                        Image(systemName: place.kind.icon)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(place.name).foregroundStyle(.primary)
                            Text(place.kind.rawValue).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle(trip.name)
    }
}

struct MXTripHistoryView: View {
    @EnvironmentObject private var session: SpoofSession
    @EnvironmentObject private var pairing: PairingStore
    @Environment(\.dismiss) private var dismiss
    @State private var items = MXTravelData.loadHistory()

    var body: some View {
        NavigationStack {
            List {
                ForEach(items) { item in
                    Button {
                        session.teleport(to: item.coordinate, pairing: pairing)
                        dismiss()
                    } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(item.date.formatted(date: .abbreviated, time: .shortened)).foregroundStyle(.primary)
                            Text(String(format: "%.5f, %.5f", item.latitude, item.longitude))
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .onDelete { offsets in
                    items.remove(atOffsets: offsets)
                    if let data = try? JSONEncoder().encode(items) {
                        UserDefaults.standard.set(data, forKey: MXTravelData.historyKey)
                    }
                }
            }
            .navigationTitle("Trip History")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .primaryAction) {
                    Button("Clear", role: .destructive) {
                        items.removeAll()
                        UserDefaults.standard.removeObject(forKey: MXTravelData.historyKey)
                    }
                    .disabled(items.isEmpty)
                }
            }
        }
    }
}
