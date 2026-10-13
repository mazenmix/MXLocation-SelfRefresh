import SwiftUI
import MapKit
import CoreLocation
import UIKit

// MX Location Pro Premium — map-first visual shell.
// All recommendations are real MapKit POIs around the user-selected pin.
// No fabricated ratings, attendance, live singles, or venue photos.

enum MXPremiumStyle {
    static let background = Color(red: 0.027, green: 0.055, blue: 0.105)
    static let panel = Color(red: 0.057, green: 0.104, blue: 0.18)
    static let panelRaised = Color(red: 0.080, green: 0.137, blue: 0.22)
    static let cyan = Color(red: 0.20, green: 0.69, blue: 1.0)
    static let muted = Color(red: 0.62, green: 0.71, blue: 0.83)
}

@MainActor
final class MXPremiumNavigation: ObservableObject {
    @Published var tab = 0
    @Published var category: MXPremiumCategory = .dateSpots
    @Published var openCategory = false
}

enum MXPremiumCategory: String, CaseIterable, Identifiable, Hashable {
    case dateSpots, socialRadar, nightlife, cafes, activities, jazz

    var id: String { rawValue }
    var title: String {
        switch self {
        case .dateSpots: "Date Spots"
        case .socialRadar: "Social Radar"
        case .nightlife: "Nightlife"
        case .cafes: "Cafés"
        case .activities: "Activities"
        case .jazz: "Jazz & Live Music"
        }
    }
    var shortTitle: String {
        switch self {
        case .jazz: "Jazz"
        default: title
        }
    }
    var symbol: String {
        switch self {
        case .dateSpots: "heart.fill"
        case .socialRadar: "person.2.fill"
        case .nightlife: "wineglass.fill"
        case .cafes: "cup.and.saucer.fill"
        case .activities: "figure.walk"
        case .jazz: "music.note"
        }
    }
    var tint: Color {
        switch self {
        case .dateSpots: Color(red: 1.0, green: 0.34, blue: 0.55)
        case .socialRadar: Color(red: 0.25, green: 0.70, blue: 1)
        case .nightlife: Color(red: 0.98, green: 0.31, blue: 0.84)
        case .cafes: Color(red: 1.0, green: 0.60, blue: 0.25)
        case .activities: Color(red: 0.23, green: 0.88, blue: 0.62)
        case .jazz: Color(red: 0.70, green: 0.46, blue: 1.0)
        }
    }
    var subtitle: String {
        switch self {
        case .dateSpots: "Romantic venues & cafés"
        case .socialRadar: "Public social gathering places"
        case .nightlife: "Lounges, clubs & evening venues"
        case .cafes: "Coffee shops & casual meetups"
        case .activities: "Public activities & attractions"
        case .jazz: "Live jazz & music venues"
        }
    }
    var searchTerms: [String] {
        switch self {
        case .dateSpots: ["romantic restaurant", "rooftop restaurant", "date cafe"]
        case .socialRadar: ["social club", "community events venue", "popular cafe"]
        case .nightlife: ["nightlife", "cocktail lounge", "nightclub"]
        case .cafes: ["coffee shop", "cafe", "coffee bar"]
        case .activities: ["museum", "activity center", "attraction"]
        case .jazz: ["jazz bar", "live music", "music lounge"]
        }
    }
}

@MainActor
final class MXPremiumPlacesModel: ObservableObject {
    @Published var places: [MKMapItem] = []
    @Published var loading = false
    @Published var error: String?
    @Published var areaName = "Selected destination"

    private var activeRequest = UUID()
    func search(around center: CLLocationCoordinate2D, category: MXPremiumCategory, radiusKm: Double) async {
        guard CLLocationCoordinate2DIsValid(center) else { return }
        let marker = UUID()
        activeRequest = marker
        loading = true
        places = []
        error = nil
        areaName = String(format: "%.4f, %.4f", center.latitude, center.longitude)

        async let namedArea: Void = resolveName(center, token: marker)
        let origin = CLLocation(latitude: center.latitude, longitude: center.longitude)
        var gathered: [MKMapItem] = []
        for term in category.searchTerms {
            guard activeRequest == marker else { return }
            let request = MKLocalSearch.Request()
            request.naturalLanguageQuery = term
            request.region = MKCoordinateRegion(
                center: center,
                latitudinalMeters: max(1500, radiusKm * 2400),
                longitudinalMeters: max(1500, radiusKm * 2400)
            )
            request.resultTypes = .pointOfInterest
            if let response = try? await MKLocalSearch(request: request).start() {
                gathered.append(contentsOf: response.mapItems)
            }
        }
        guard activeRequest == marker else { return }
        var seen = Set<String>()
        places = gathered.filter { place in
            let coordinate = place.placemark.coordinate
            let distance = origin.distance(from: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude))
            let key = (place.name ?? "") + String(format: ":%.4f:%.4f", coordinate.latitude, coordinate.longitude)
            return distance <= radiusKm * 1000 && seen.insert(key).inserted
        }.sorted {
            origin.distance(from: CLLocation(latitude: $0.placemark.coordinate.latitude, longitude: $0.placemark.coordinate.longitude)) <
            origin.distance(from: CLLocation(latitude: $1.placemark.coordinate.latitude, longitude: $1.placemark.coordinate.longitude))
        }
        if places.isEmpty {
            error = "No matching venues found here. Try a larger radius or another category."
        }
        loading = false
        _ = await namedArea
    }

    private func resolveName(_ center: CLLocationCoordinate2D, token: UUID) async {
        let location = CLLocation(latitude: center.latitude, longitude: center.longitude)
        guard let place = try? await CLGeocoder().reverseGeocodeLocation(location).first,
              token == activeRequest else { return }
        let name = [place.subLocality, place.locality, place.country]
            .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", ")
        if !name.isEmpty { areaName = name }
    }
}

struct MXPremiumPanel<Content: View>: View {
    let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }
    var body: some View {
        content
            .padding(15)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(MXPremiumStyle.panel, in: RoundedRectangle(cornerRadius: 19))
            .overlay(RoundedRectangle(cornerRadius: 19).stroke(.white.opacity(0.055)))
    }
}

struct MXProPremiumRoot: View {
    @EnvironmentObject private var session: SpoofSession
    @StateObject private var navigation = MXPremiumNavigation()

    var body: some View {
        TabView(selection: $navigation.tab) {
            MapHomeView()
                .tabItem { Label("Map", systemImage: "map") }.tag(0)
            MXPremiumExploreScreen()
                .tabItem { Label("Explore", systemImage: "magnifyingglass") }.tag(1)
            MXPremiumPlanScreen()
                .tabItem { Label("Plan", systemImage: "calendar") }.tag(2)
            MXPremiumEssentialsScreen()
                .tabItem { Label("Essentials", systemImage: "square.grid.2x2") }.tag(3)
            MXPremiumSavedScreen()
                .tabItem { Label("Saved", systemImage: "bookmark") }.tag(4)
        }
        .environmentObject(navigation)
        .tint(MXPremiumStyle.cyan)
        .preferredColorScheme(.dark)
        .alert("MX Location Pro", isPresented: Binding(
            get: { session.lastError != nil },
            set: { if !$0 { session.lastError = nil } }
        )) {
            Button("OK", role: .cancel) { session.lastError = nil }
        } message: {
            Text(session.lastError ?? "")
        }
    }
}

// Look Around imagery is licensed by MapKit and may be unavailable at some venues.
// A graceful gradient placeholder is used when no photo is offered.
struct MXPremiumVenueImage: View {
    let coordinate: CLLocationCoordinate2D
    var symbol = "mappin.and.ellipse"
    var color = MXPremiumStyle.cyan
    @State private var image: UIImage?

    private var requestKey: String {
        String(format: "%.5f:%.5f", coordinate.latitude, coordinate.longitude)
    }

    var body: some View {
        ZStack {
            LinearGradient(colors: [color.opacity(0.58), MXPremiumStyle.panel, MXPremiumStyle.background],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Image(systemName: symbol)
                    .font(.system(size: 26, weight: .medium))
                    .foregroundStyle(.white.opacity(0.9))
            }
        }
        .clipped()
        .task(id: requestKey) {
            image = nil
            guard let scene = try? await MKLookAroundSceneRequest(coordinate: coordinate).scene else { return }
            let options = MKLookAroundSnapshotter.Options()
            options.size = CGSize(width: 260, height: 260)
            let snapshotter = MKLookAroundSnapshotter(scene: scene, options: options)
            if let result = try? await snapshotter.snapshot {
                image = result.image
            }
        }
    }
}

struct MXPremiumVenueCard: View {
    let item: MKMapItem
    let center: CLLocationCoordinate2D
    let category: MXPremiumCategory
    var compact = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                MXPremiumVenueImage(coordinate: item.placemark.coordinate,
                                     symbol: category.symbol, color: category.tint)
                    .frame(width: compact ? 72 : 90, height: compact ? 72 : 92)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                VStack(alignment: .leading, spacing: 5) {
                    Text(item.name ?? "Nearby venue").font(.subheadline.weight(.bold))
                        .foregroundStyle(.white).lineLimit(2)
                    Text(item.placemark.title ?? "Location details")
                        .font(.caption2).foregroundStyle(MXPremiumStyle.muted)
                        .lineLimit(2)
                    HStack(spacing: 5) {
                        Image(systemName: "location.fill")
                            .foregroundStyle(category.tint)
                        Text(String(format: "%.1f km", distanceKm))
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                    }
                    .font(.caption.weight(.medium))
                    .foregroundStyle(MXPremiumStyle.muted)
                }
                Spacer(minLength: 0)
            }
            .padding(9)
            .background(MXPremiumStyle.panel, in: RoundedRectangle(cornerRadius: 18))
        }
        .buttonStyle(.plain)
    }
    private var distanceKm: Double {
        let origin = CLLocation(latitude: center.latitude, longitude: center.longitude)
        let loc = item.placemark.coordinate
        return origin.distance(from: CLLocation(latitude: loc.latitude, longitude: loc.longitude)) / 1000
    }
}

struct MXPremiumVenueDetails: View {
    let item: MKMapItem
    @EnvironmentObject private var session: SpoofSession
    @EnvironmentObject private var pairing: PairingStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 15) {
                    MXPremiumVenueImage(coordinate: item.placemark.coordinate)
                        .frame(height: 210).clipShape(RoundedRectangle(cornerRadius: 20))
                    Text(item.name ?? "Venue").font(.title2.weight(.bold))
                    Text(item.placemark.title ?? "No address supplied")
                        .foregroundStyle(MXPremiumStyle.muted)
                    MXPremiumPanel {
                        VStack(alignment: .leading, spacing: 12) {
                            Button { item.openInMaps() } label: {
                                Label("Open in Apple Maps — details & directions",
                                      systemImage: "map.fill")
                            }
                            if let url = item.url {
                                Link(destination: url) {
                                    Label("Venue website", systemImage: "link")
                                }
                            }
                            Button {
                                session.addFavorite(name: item.name ?? "Saved place",
                                                    coordinate: item.placemark.coordinate)
                            } label: {
                                Label("Save location", systemImage: "bookmark")
                            }
                            Button {
                                session.pin = item.placemark.coordinate
                                dismiss()
                            } label: {
                                Label("Select location on Map", systemImage: "mappin")
                            }
                            Button {
                                session.teleport(to: item.placemark.coordinate, pairing: pairing)
                                dismiss()
                            } label: {
                                Label("Set simulated location", systemImage: "location.fill")
                            }
                        }
                        .tint(MXPremiumStyle.cyan)
                    }
                    Text("Photos depend on Apple Look Around availability. No ratings, prices, or live attendance are inferred.")
                        .font(.caption2).foregroundStyle(MXPremiumStyle.muted)
                }
                .padding(16)
            }
            .background(MXPremiumStyle.background)
            .navigationTitle("Place Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) {
                Button("Done") { dismiss() }
            }}
        }.preferredColorScheme(.dark)
    }
}

struct MXPremiumExploreScreen: View {
    @EnvironmentObject private var session: SpoofSession
    @EnvironmentObject private var navigation: MXPremiumNavigation
    @StateObject private var model = MXPremiumPlacesModel()
    @State private var radius = 5.0
    @State private var selectedVenue: MKMapItem?

    private var center: CLLocationCoordinate2D? {
        session.pin ?? session.simulated ?? session.realCoordinate
    }
    private var searchKey: String {
        guard let c = center else { return "none" }
        return String(format: "%.5f-%.5f-%@-%.0f",
                      c.latitude, c.longitude, navigation.category.rawValue, radius)
    }
    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Discover the best places around your selected location")
                        .font(.subheadline).foregroundStyle(MXPremiumStyle.muted)

                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(MXPremiumCategory.allCases) { cat in
                            NavigationLink(value: cat) {
                                categoryTile(cat)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Nearby Recommendations")
                                .font(.headline.weight(.bold))
                            Text(model.areaName).font(.caption2)
                                .foregroundStyle(MXPremiumStyle.muted).lineLimit(1)
                        }
                        Spacer()
                        Button("See All") {
                            navigation.openCategory = true
                        }.font(.caption.weight(.semibold))
                    }
                    .tint(MXPremiumStyle.cyan)

                    categoryPicker
                    HStack {
                        Text("Search radius")
                            .font(.caption).foregroundStyle(MXPremiumStyle.muted)
                        Spacer()
                        Text("\(Int(radius)) km").font(.caption.monospacedDigit())
                    }
                    Slider(value: $radius, in: 1...25, step: 1).tint(MXPremiumStyle.cyan)

                    if model.loading { ProgressView("Finding real venues…") }
                    if let error = model.error {
                        Text(error).font(.footnote).foregroundStyle(MXPremiumStyle.muted)
                    }
                    if let c = center {
                        ForEach(Array(model.places.prefix(8).enumerated()), id: \.offset) { _, place in
                            MXPremiumVenueCard(item: place, center: c, category: navigation.category) {
                                selectedVenue = place
                            }
                        }
                    } else {
                        MXPremiumPanel {
                            Label("Choose a destination on Map to start exploring.",
                                  systemImage: "map.fill")
                                .foregroundStyle(MXPremiumStyle.muted)
                        }
                    }
                }
                .padding(16)
            }
            .background(MXPremiumStyle.background)
            .navigationTitle("Explore")
            .navigationBarTitleDisplayMode(.large)
            .toolbar { ToolbarItem(placement: .topBarTrailing) {
                Button { navigation.tab = 0 } label: {
                    Image(systemName: "location.magnifyingglass")
                }
            }}
            .navigationDestination(for: MXPremiumCategory.self) { category in
                MXPremiumCategoryScreen(category: category)
            }
            .navigationDestination(isPresented: $navigation.openCategory) {
                MXPremiumCategoryScreen(category: navigation.category)
            }
            .sheet(isPresented: Binding(
                get: { selectedVenue != nil },
                set: { if !$0 { selectedVenue = nil } }
            )) {
                if let item = selectedVenue { MXPremiumVenueDetails(item: item) }
            }
            .task(id: searchKey) {
                if let c = center {
                    await model.search(around: c, category: navigation.category, radiusKm: radius)
                }
            }
        }
    }

    private func categoryTile(_ category: MXPremiumCategory) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: category.symbol)
                .font(.system(size: 29, weight: .semibold))
                .foregroundStyle(category.tint)
                .shadow(color: category.tint.opacity(0.45), radius: 11)
            Spacer(minLength: 0)
            Text(category.title).font(.subheadline.weight(.bold))
                .foregroundStyle(.white)
            Text(category.subtitle).font(.caption2)
                .foregroundStyle(MXPremiumStyle.muted).lineLimit(2)
        }
        .padding(14).frame(maxWidth: .infinity, minHeight: 135, alignment: .leading)
        .background(
            LinearGradient(colors: [category.tint.opacity(0.26), MXPremiumStyle.panel],
                           startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 19)
        )
        .overlay(RoundedRectangle(cornerRadius: 19).stroke(category.tint.opacity(0.18)))
    }

    private var categoryPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(MXPremiumCategory.allCases) { cat in
                    Button {
                        navigation.category = cat
                    } label: {
                        Text(cat.shortTitle)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(navigation.category == cat ? .white : MXPremiumStyle.muted)
                            .padding(.horizontal, 12).padding(.vertical, 8)
                            .background(navigation.category == cat ? cat.tint.opacity(0.35) : MXPremiumStyle.panel,
                                        in: Capsule())
                    }.buttonStyle(.plain)
                }
            }
        }
    }
}

struct MXPremiumCategoryScreen: View {
    let category: MXPremiumCategory
    @EnvironmentObject private var session: SpoofSession
    @StateObject private var model = MXPremiumPlacesModel()
    @State private var radius = 5.0
    @State private var selectedVenue: MKMapItem?

    private var center: CLLocationCoordinate2D? {
        session.pin ?? session.simulated ?? session.realCoordinate
    }
    private var key: String {
        guard let c = center else { return "none" }
        return String(format: "%.5f:%.5f:%@:%.0f", c.latitude, c.longitude, category.rawValue, radius)
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 15) {
                HStack(spacing: 12) {
                    Image(systemName: category.symbol)
                        .font(.title).foregroundStyle(category.tint)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(category.title).font(.title2.weight(.bold))
                        Text(category.subtitle)
                            .font(.caption).foregroundStyle(MXPremiumStyle.muted)
                    }
                }
                MXPremiumPanel {
                    HStack {
                        Label(model.areaName, systemImage: "mappin.circle")
                            .font(.caption).lineLimit(2)
                        Spacer()
                        Text("\(Int(radius)) km").font(.caption.monospacedDigit())
                    }
                    Slider(value: $radius, in: 1...25, step: 1)
                        .tint(category.tint)
                }
                if let c = center {
                    Map(initialPosition: .region(MKCoordinateRegion(
                        center: c, latitudinalMeters: radius * 2000,
                        longitudinalMeters: radius * 2000
                    ))) {
                        Marker("Selected", coordinate: c).tint(MXPremiumStyle.cyan)
                        ForEach(Array(model.places.enumerated()), id: \.offset) { _, item in
                            Marker(item.name ?? "Venue", coordinate: item.placemark.coordinate)
                                .tint(category.tint)
                        }
                    }
                    .id(key)
                    .frame(height: 215)
                    .clipShape(RoundedRectangle(cornerRadius: 19))
                    if category == .socialRadar {
                        Text("Social Radar maps public gathering venues—not crowds, gender, or singles locations.")
                            .font(.caption2).foregroundStyle(MXPremiumStyle.muted)
                    }
                    if model.loading { ProgressView("Updating real nearby places…") }
                    if let error = model.error { Text(error).font(.caption).foregroundStyle(MXPremiumStyle.muted) }
                    ForEach(Array(model.places.enumerated()), id: \.offset) { _, item in
                        MXPremiumVenueCard(item: item, center: c, category: category) {
                            selectedVenue = item
                        }
                    }
                } else {
                    Text("Select a location using the Map tab.")
                        .foregroundStyle(MXPremiumStyle.muted)
                }
            }.padding(16)
        }
        .background(MXPremiumStyle.background)
        .navigationTitle(category.title)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: Binding(get: { selectedVenue != nil },
                                    set: { if !$0 { selectedVenue = nil } })) {
            if let item = selectedVenue { MXPremiumVenueDetails(item: item) }
        }
        .task(id: key) {
            if let c = center { await model.search(around: c, category: category, radiusKm: radius) }
        }
    }
}

struct MXPremiumSavedScreen: View {
    @EnvironmentObject private var session: SpoofSession
    @EnvironmentObject private var navigation: MXPremiumNavigation
    @State private var search = ""
    @State private var showingRecent = false

    private var filtered: [SavedPlace] {
        let entries = showingRecent ? session.recents : session.favorites
        guard !search.isEmpty else { return entries }
        return entries.filter { $0.name.localizedCaseInsensitiveContains(search) }
    }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    TextField("Search your places", text: $search)
                        .padding(13).background(MXPremiumStyle.panel,
                                                 in: RoundedRectangle(cornerRadius: 13))
                    Picker("Saved", selection: $showingRecent) {
                        Text("Favorites").tag(false)
                        Text("Recent").tag(true)
                    }.pickerStyle(.segmented)
                    if filtered.isEmpty {
                        MXPremiumPanel {
                            Label("No saved locations in this section yet.", systemImage: "bookmark")
                                .foregroundStyle(MXPremiumStyle.muted)
                        }
                    }
                    ForEach(filtered) { place in
                        HStack(spacing: 12) {
                            MXPremiumVenueImage(coordinate: place.coordinate,
                                                 symbol: "mappin.and.ellipse",
                                                 color: MXPremiumStyle.cyan)
                                .frame(width: 80, height: 74)
                                .clipShape(RoundedRectangle(cornerRadius: 13))
                            Button {
                                session.pin = place.coordinate
                                navigation.tab = 0
                            } label: {
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(place.name).font(.subheadline.weight(.bold))
                                        .foregroundStyle(.white).lineLimit(2)
                                    Text(String(format: "%.5f, %.5f", place.latitude, place.longitude))
                                        .font(.caption2.monospaced())
                                        .foregroundStyle(MXPremiumStyle.muted)
                                    Text("Open on Map").font(.caption2)
                                        .foregroundStyle(MXPremiumStyle.cyan)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .buttonStyle(.plain)
                            Menu {
                                if showingRecent {
                                    Button("Add to Favorites") {
                                        session.addFavorite(name: place.name, coordinate: place.coordinate)
                                    }
                                    Button("Remove from History", role: .destructive) {
                                        session.removeRecent(place)
                                    }
                                } else {
                                    Button("Remove Favorite", role: .destructive) {
                                        session.removeFavorite(place)
                                    }
                                }
                            } label: {
                                Image(systemName: "ellipsis").foregroundStyle(.white)
                            }
                        }
                        .padding(10)
                        .background(MXPremiumStyle.panel, in: RoundedRectangle(cornerRadius: 17))
                    }
                }
                .padding(16)
            }
            .background(MXPremiumStyle.background)
            .navigationTitle("Saved Places")
        }
    }
}
