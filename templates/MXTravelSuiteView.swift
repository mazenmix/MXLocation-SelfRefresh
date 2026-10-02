import CoreLocation
import MapKit
import SwiftUI

struct MXTravelSuiteView: View {
    @AppStorage("mx.selectedCity") private var selectedCity = "Manila"

    var body: some View {
        TabView {
            NavigationStack { MXQuickDashboardView(selectedCity: $selectedCity) }
                .tabItem { Label("Quick", systemImage: "bolt.fill") }
            NavigationStack { MXDatingModeView(selectedCity: $selectedCity) }
                .tabItem { Label("Dating", systemImage: "heart.fill") }
            NavigationStack { MXTripPlannerView(selectedCity: $selectedCity) }
                .tabItem { Label("Travel", systemImage: "airplane") }
            NavigationStack { MXNearbyHotspotsView() }
                .tabItem { Label("Nearby", systemImage: "scope") }
            NavigationStack { MXHistoryTimelineView() }
                .tabItem { Label("History", systemImage: "clock.arrow.circlepath") }
        }
        .tint(LocusTheme.accent)
    }
}

struct MXCityPicker: View {
    @Binding var selectedCity: String

    var body: some View {
        Picker("City", selection: $selectedCity) {
            ForEach(MXCityProfile.all) { city in
                Text(city.name).tag(city.name)
            }
        }
        .pickerStyle(.menu)
    }
}

struct MXQuickDashboardView: View {
    @EnvironmentObject private var session: SpoofSession
    @EnvironmentObject private var pairing: PairingStore
    @Binding var selectedCity: String
    @AppStorage("mx.locationLocked") private var locationLocked = false
    @AppStorage("mx.distanceRingKm") private var distanceRingKm = 0.0
    @State private var showManage = false

    private var current: CLLocationCoordinate2D? {
        session.simulated ?? session.pin ?? session.realCoordinate
    }

    var body: some View {
        List {
            Section("City") {
                MXCityPicker(selectedCity: $selectedCity)
            }

            Section("Current") {
                if let current {
                    LabeledContent(
                        "Coordinates",
                        value: String(format: "%.5f, %.5f", current.latitude, current.longitude)
                    )

                    Menu {
                        ForEach(MXPlaceCategory.allCases) { category in
                            Button {
                                saveFavorite(category, current)
                            } label: {
                                Label(category.title, systemImage: category.icon)
                            }
                        }
                    } label: {
                        Label("Save Smart Favorite", systemImage: "star.circle.fill")
                    }
                } else {
                    Text("Choose a place on the map first.")
                        .foregroundStyle(.secondary)
                }

                Toggle(isOn: $locationLocked) {
                    Label(
                        "Lock map location",
                        systemImage: locationLocked ? "lock.fill" : "lock.open"
                    )
                }
            }

            Section("Distance Ring") {
                Picker("Radius", selection: $distanceRingKm) {
                    Text("Off").tag(0.0)
                    Text("1 km").tag(1.0)
                    Text("5 km").tag(5.0)
                    Text("10 km").tag(10.0)
                    Text("25 km").tag(25.0)
                }
                .pickerStyle(.segmented)
            }

            Section("Favorites") {
                if session.favorites.isEmpty {
                    Text("No favorites yet.")
                        .foregroundStyle(.secondary)
                }

                ForEach(session.favorites.prefix(8)) { place in
                    let meta = MXTravelData.meta(for: place.id)
                    Button {
                        session.teleport(to: place.coordinate, pairing: pairing)
                    } label: {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(place.name)
                                    .foregroundStyle(.primary)
                                if let meta {
                                    Text("\(meta.city) • \(meta.category.title)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        } icon: {
                            Image(systemName: meta?.category.icon ?? "star.fill")
                        }
                    }
                }

                Button("Manage all places") {
                    showManage = true
                }
            }

            Section("Back 3 Locations") {
                let history = Array(MXTravelData.loadHistory().prefix(4).dropFirst())
                if history.isEmpty {
                    Text("No earlier locations yet.")
                        .foregroundStyle(.secondary)
                }

                ForEach(history.prefix(3)) { item in
                    Button {
                        session.teleport(to: item.coordinate, pairing: pairing)
                    } label: {
                        HStack {
                            Image(systemName: "arrow.uturn.backward.circle")
                            Text(String(format: "%.5f, %.5f", item.latitude, item.longitude))
                                .font(.subheadline.monospaced())
                            Spacer()
                            Text(item.date, style: .time)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle("MX Quick")
        .sheet(isPresented: $showManage) {
            QuickPlacesView()
        }
    }

    private func saveFavorite(_ category: MXPlaceCategory, _ coordinate: CLLocationCoordinate2D) {
        let name = "\(category.title) • \(selectedCity)"
        session.addFavorite(name: name, coordinate: coordinate)
        let id = SavedPlace(
            name: name,
            latitude: coordinate.latitude,
            longitude: coordinate.longitude
        ).id
        MXTravelData.setFavoriteMeta(id: id, category: category, city: selectedCity)
    }
}

struct MXDatingModeView: View {
    @EnvironmentObject private var session: SpoofSession
    @EnvironmentObject private var pairing: PairingStore
    @Binding var selectedCity: String

    var body: some View {
        List {
            Section("City") {
                MXCityPicker(selectedCity: $selectedCity)
            }

            Section("Dating Areas") {
                ForEach(MXCityProfile.named(selectedCity).areas) { area in
                    Button {
                        session.teleport(to: area.coordinate, pairing: pairing)
                    } label: {
                        HStack {
                            Label(area.name, systemImage: area.category.icon)
                            Spacer()
                            Text("Go")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(LocusTheme.accent)
                        }
                    }
                }
            }

            Section {
                Text("Tip: use the distance ring to compare 1–25 km around the chosen area.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Dating Mode")
    }
}

struct MXTripPlannerView: View {
    @EnvironmentObject private var session: SpoofSession
    @EnvironmentObject private var pairing: PairingStore
    @Binding var selectedCity: String
    @State private var stops = MXTravelData.loadTripStops()
    @State private var name = ""
    @State private var category: MXPlaceCategory = .hotel

    private var current: CLLocationCoordinate2D? {
        session.simulated ?? session.pin ?? session.realCoordinate
    }

    var body: some View {
        List {
            Section("City") {
                MXCityPicker(selectedCity: $selectedCity)
            }

            Section("Ready Preset") {
                ForEach(MXCityProfile.named(selectedCity).travelStops) { stop in
                    Button {
                        session.teleport(to: stop.coordinate, pairing: pairing)
                    } label: {
                        Label(stop.name, systemImage: stop.category.icon)
                    }
                }
            }

            Section("Save Current Stop") {
                TextField("Name", text: $name)
                Picker("Type", selection: $category) {
                    ForEach(MXPlaceCategory.allCases) { item in
                        Text(item.title).tag(item)
                    }
                }

                Button {
                    guard let current else { return }
                    let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
                    stops.insert(
                        MXTripStop(
                            id: UUID(),
                            name: clean.isEmpty ? category.title : clean,
                            category: category,
                            city: selectedCity,
                            latitude: current.latitude,
                            longitude: current.longitude,
                            createdAt: Date()
                        ),
                        at: 0
                    )
                    MXTravelData.saveTripStops(stops)
                    name = ""
                } label: {
                    Label("Add to My Trip", systemImage: "plus.circle.fill")
                }
                .disabled(current == nil)
            }

            Section("My Trip") {
                let cityStops = stops.filter { $0.city == selectedCity }
                if cityStops.isEmpty {
                    Text("No custom stops for \(selectedCity).")
                        .foregroundStyle(.secondary)
                }

                ForEach(cityStops) { stop in
                    Button {
                        session.teleport(to: stop.coordinate, pairing: pairing)
                    } label: {
                        Label(stop.name, systemImage: stop.category.icon)
                    }
                    .swipeActions {
                        Button(role: .destructive) {
                            stops.removeAll { $0.id == stop.id }
                            MXTravelData.saveTripStops(stops)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
        }
        .navigationTitle("Travel Presets")
    }
}

struct MXNearbyResult: Identifiable {
    let id = UUID()
    let name: String
    let subtitle: String
    let coordinate: CLLocationCoordinate2D
}

struct MXNearbyHotspotsView: View {
    @EnvironmentObject private var session: SpoofSession
    @EnvironmentObject private var pairing: PairingStore
    @State private var results: [MXNearbyResult] = []
    @State private var loading = false
    @State private var selectedQuery = "Cafés"

    private let categories: [(String, String, String)] = [
        ("Cafés", "Cafe", "cup.and.saucer.fill"),
        ("Restaurants", "Restaurant", "fork.knife"),
        ("Malls", "Shopping Mall", "bag.fill"),
        ("Hotels", "Hotel", "bed.double.fill"),
        ("Airports", "Airport", "airplane"),
        ("Nightlife", "Nightclub Bar", "moon.stars.fill")
    ]

    var body: some View {
        List {
            Section("Search Around Current Location") {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        ForEach(categories, id: \.0) { item in
                            Button {
                                selectedQuery = item.0
                                search(item.1)
                            } label: {
                                Label(item.0, systemImage: item.2)
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                    .padding(.vertical, 2)
                }

                if loading {
                    ProgressView("Searching…")
                }
            }

            Section(selectedQuery) {
                if !loading && results.isEmpty {
                    Text("Choose a category above.")
                        .foregroundStyle(.secondary)
                }

                ForEach(results) { result in
                    Button {
                        session.teleport(to: result.coordinate, pairing: pairing)
                    } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(result.name)
                                .foregroundStyle(.primary)
                            if !result.subtitle.isEmpty {
                                Text(result.subtitle)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Nearby Hotspots")
    }

    private func search(_ query: String) {
        guard let center = session.simulated ?? session.pin ?? session.realCoordinate else {
            session.lastError = "Choose or spoof a location first."
            return
        }

        loading = true
        results = []

        Task {
            var request = MKLocalSearch.Request()
            request.naturalLanguageQuery = query
            request.region = MKCoordinateRegion(
                center: center,
                latitudinalMeters: 12000,
                longitudinalMeters: 12000
            )

            do {
                let response = try await MKLocalSearch(request: request).start()
                let mapped = response.mapItems.prefix(15).map { item in
                    MXNearbyResult(
                        name: item.name ?? "Place",
                        subtitle: item.placemark.title ?? "",
                        coordinate: item.placemark.coordinate
                    )
                }
                await MainActor.run {
                    results = mapped
                    loading = false
                }
            } catch {
                await MainActor.run {
                    loading = false
                    session.lastError = error.localizedDescription
                }
            }
        }
    }
}

struct MXHistoryTimelineView: View {
    @EnvironmentObject private var session: SpoofSession
    @EnvironmentObject private var pairing: PairingStore
    @State private var records = MXTravelData.loadHistory()

    var body: some View {
        List {
            Section {
                Button(role: .destructive) {
                    MXTravelData.clearHistory()
                    records = []
                } label: {
                    Label("Clear History", systemImage: "trash")
                }
            }

            Section("Timeline") {
                if records.isEmpty {
                    Text("Your location changes will appear here.")
                        .foregroundStyle(.secondary)
                }

                ForEach(records) { record in
                    Button {
                        session.teleport(to: record.coordinate, pairing: pairing)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "clock.fill")
                                .foregroundStyle(LocusTheme.accent)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(String(format: "%.5f, %.5f", record.latitude, record.longitude))
                                    .font(.subheadline.monospaced())
                                    .foregroundStyle(.primary)
                                Text(
                                    record.date,
                                    format: .dateTime.month().day().year().hour().minute()
                                )
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Trip History")
        .toolbar {
            Button {
                records = MXTravelData.loadHistory()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
        }
    }
}
