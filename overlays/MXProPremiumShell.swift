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
    @Published var isSearchActive = false
}

enum MXPremiumCategory: String, CaseIterable, Identifiable, Hashable {
    case dateSpots, adultVenues, afterDark, romanticStays, socialRadar, nightlife, cafes, activities, jazz

    var id: String { rawValue }
    var title: String {
        switch self {
        case .dateSpots: "Date Spots"
        case .adultVenues: "Adults 18+"
        case .afterDark: "After Dark"
        case .romanticStays: "Romantic Stays"
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
        case .adultVenues: "18+"
        case .romanticStays: "Stays"
        default: title
        }
    }
    var symbol: String {
        switch self {
        case .dateSpots: "heart.fill"
        case .adultVenues: "moon.stars.fill"
        case .afterDark: "sparkles"
        case .romanticStays: "bed.double.fill"
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
        case .adultVenues: Color(red: 0.93, green: 0.22, blue: 0.54)
        case .afterDark: Color(red: 0.72, green: 0.38, blue: 0.96)
        case .romanticStays: Color(red: 0.90, green: 0.49, blue: 0.70)
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
        case .adultVenues: "Adult-only, sex-positive and nightlife venues"
        case .afterDark: "Late-night discoveries, cabaret & hidden bars"
        case .romanticStays: "Boutique and adult-only hotels"
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
        case .adultVenues: ["adult entertainment club", "burlesque cabaret", "swingers lifestyle club",
                             "strip club", "fetish nightclub", "adult cabaret show",
                             "couples lifestyle lounge", "clothing optional resort"]
        case .afterDark: ["speakeasy bar", "late night lounge", "cabaret club", "nightclub"]
        case .romanticStays: ["boutique hotel", "romantic hotel", "adults only resort"]
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
    func search(around center: CLLocationCoordinate2D, category: MXPremiumCategory, radiusKm: Double, customTerm: String? = nil) async {
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
        for term in (customTerm.map { [$0] } ?? category.searchTerms) {
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
            let title = (place.name ?? "").lowercased()
            let blocked = ["gun club", "shooting", "firearm", "rifle", "detective",
                           "private investigator", "police", "hospital", "school",
                           "dental", "clinic", "weapons", "bank"]
            let unrelated = category == .adultVenues &&
                blocked.contains(where: { title.contains($0) })
            return distance <= radiusKm * 1000 && !unrelated && seen.insert(key).inserted
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

// Full-screen, gesture-driven venue discovery. Results come only from MapKit,
// never fabricated people counts, reviews, live crowds or adult-service claims.
struct MXPremiumCategoryScreen: View {
    let category: MXPremiumCategory
    @EnvironmentObject private var session: SpoofSession
    @StateObject private var model = MXPremiumPlacesModel()
    @State private var radius = 5.0
    @State private var subfilter = "All"
    @State private var selectedVenue: MKMapItem?
    @Environment(\.dismiss) private var dismiss
    @State private var detent: NearbyDetent = .medium
    @GestureState private var draggingSheet: CGFloat = 0
    @State private var radiusVisible = false

    private enum NearbyDetent: CaseIterable {
        case collapsed, medium, expanded
    }
    @State private var mapPosition: MapCameraPosition = .automatic

    private var center: CLLocationCoordinate2D? {
        session.pin ?? session.simulated ?? session.realCoordinate
    }
    private var filters: [String] {
        switch category {
        case .dateSpots: return ["All", "Restaurants", "Rooftops", "Lounges", "Wine Bars", "Private Dining"]
        case .adultVenues: return ["All", "Adult Clubs", "Swingers Clubs", "Strip Clubs",
                                   "Kink Events", "Fetish Clubs", "Couples Lounges",
                                   "Burlesque", "Cabaret", "Erotic Shows",
                                   "Adult Stores", "Adult Cinemas", "Nudist Beaches",
                                   "18+ Resorts", "Sensual Spas", "After-hours"]
        case .afterDark: return ["All", "Speakeasies", "Rooftops", "Nightclubs", "24H Cafes", "Live Music"]
        case .romanticStays: return ["All", "Boutique Hotels", "18+ Hotels", "Luxury Hotels", "Resorts"]
        case .socialRadar: return ["All", "Cafés", "Groups", "Activities"]
        case .nightlife: return ["All", "Bars", "Clubs", "Lounges", "Live Music"]
        case .cafes: return ["All", "Coffee", "Dessert", "Quiet"]
        case .activities: return ["All", "Museums", "Outdoors", "Games"]
        case .jazz: return ["All", "Jazz", "Live Music", "Lounge"]
        }
    }
    private var customSearch: String? {
        switch subfilter {
        case "All": return nil
        case "Restaurants": return "romantic restaurant"
        case "Rooftops": return "rooftop bar"
        case "Lounges", "Lounge": return "lounge"
        case "Wine Bars": return "wine bar"
        case "Private Dining": return "private dining restaurant"
        case "Adult Clubs": return "adult entertainment club"
        case "Swingers Clubs": return "swingers lifestyle club"
        case "Kink Events": return "kink friendly event venue"
        case "Fetish Clubs": return "fetish club"
        case "Couples Lounges": return "adult couples lifestyle lounge"
        case "Erotic Shows": return "adult burlesque show venue"
        case "After-hours": return "late night adult cabaret lounge"
        case "Strip Clubs": return "strip club"
        case "Burlesque": return "burlesque show venue"
        case "Cabaret": return "cabaret club"
        case "Adult Stores": return "adult novelty store"
        case "Adult Cinemas": return "adult movie theater"
        case "Nudist Beaches": return "clothing optional beach"
        case "18+ Resorts", "18+ Hotels": return "adults only hotel"
        case "Sensual Spas": return "adult spa wellness"
        case "Speakeasies": return "speakeasy bar"
        case "Nightclubs", "Clubs": return "nightclub"
        case "24H Cafes": return "24 hour cafe"
        case "Boutique Hotels": return "boutique hotel"
        case "Luxury Hotels": return "luxury hotel"
        case "Resorts": return "resort hotel"
        case "Cafés", "Coffee": return "coffee shop"
        case "Groups": return "community event venue"
        case "Activities": return "social activity center"
        case "Bars": return "bar"
        case "Live Music": return "live music bar"
        case "Dessert": return "dessert cafe"
        case "Quiet": return "quiet cafe"
        case "Museums": return "museum"
        case "Outdoors": return "public park"
        case "Games": return "bowling arcade"
        case "Jazz": return "jazz club"
        default: return nil
        }
    }
    private var key: String {
        guard let c = center else { return "no-location" }
        return String(format: "%.5f:%.5f:%@:%.0f:%@",
                      c.latitude, c.longitude, category.rawValue, radius, subfilter)
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .top) {
                fullScreenMap.ignoresSafeArea()
                VStack(spacing: 8) {
                    floatingHeader
                    glassFilters
                    Spacer(minLength: 0)
                }
                .padding(.top, max(geometry.safeAreaInsets.top, 18) + 8)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                resultsSheet(availableHeight: geometry.size.height)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .background(MXPremiumStyle.background)
            .ignoresSafeArea()
        }
        .toolbar(.hidden, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .navigationBarBackButtonHidden(true)
        .sheet(isPresented: Binding(
            get: { selectedVenue != nil },
            set: { if !$0 { selectedVenue = nil } }
        )) {
            if let item = selectedVenue { MXPremiumVenueDetails(item: item) }
        }
        .task(id: key) {
            if let c = center {
                mapPosition = .region(MKCoordinateRegion(
                    center: c,
                    latitudinalMeters: max(1500, radius * 2200),
                    longitudinalMeters: max(1500, radius * 2200)
                ))
                await model.search(around: c, category: category,
                                   radiusKm: radius, customTerm: customSearch)
            }
        }
    }

    private var floatingHeader: some View {
        HStack(spacing: 10) {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(.black.opacity(0.42), in: Circle())
                    .overlay(Circle().stroke(.white.opacity(0.14)))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Back to Explore")
            Spacer(minLength: 0)
            Text(category.title)
                .font(.system(size: 18, weight: .bold))
                .lineLimit(1)
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.6), radius: 7)
            Spacer(minLength: 0)
            Text("\(model.places.count)")
                .font(.caption.weight(.bold).monospacedDigit())
                .foregroundStyle(.white)
                .frame(minWidth: 42, minHeight: 35)
                .background(.black.opacity(0.40), in: Capsule())
        }
        .padding(.horizontal, 15)
        .frame(height: 48)
        .accessibilityIdentifier("mxFloatingFullscreenHeader")
    }

    private var fullScreenMap: some View {
        Map(position: $mapPosition) {
            if let c = center {
                Annotation("Selected", coordinate: c) {
                    Image(systemName: "location.circle.fill")
                        .font(.system(size: 29))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, MXPremiumStyle.cyan)
                }
            }
            ForEach(Array(model.places.enumerated()), id: \.offset) { _, item in
                Annotation(item.name ?? "Venue", coordinate: item.placemark.coordinate) {
                    Button {
                        selectedVenue = item
                    } label: {
                        Image(systemName: category.symbol)
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 36, height: 36)
                            .background(category.tint, in: Circle())
                            .overlay(Circle().stroke(.white.opacity(0.8), lineWidth: 2))
                            .shadow(color: .black.opacity(0.4), radius: 5)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .mapStyle(.standard(elevation: .realistic))
        .mapControlVisibility(.hidden)
        .ignoresSafeArea()
    }

    // Floating chips keep the map visible without the former full-width grey card.
    private var glassFilters: some View {
        VStack(spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 7) {
                    ForEach(filters, id: \.self) { choice in
                        Button {
                            withAnimation(.easeInOut(duration: 0.18)) { subfilter = choice }
                        } label: {
                            Text(choice)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 13)
                                .frame(height: 34)
                                .background(
                                    subfilter == choice ? category.tint : .black.opacity(0.68),
                                    in: Capsule()
                                )
                                .overlay(Capsule().stroke(.white.opacity(0.10)))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 14)
            }

            HStack(spacing: 8) {
                Image(systemName: "mappin.circle.fill")
                    .foregroundStyle(category.tint)
                Text(model.areaName)
                    .lineLimit(1)
                    .foregroundStyle(.white)
                Spacer(minLength: 4)
                Button {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        radiusVisible.toggle()
                    }
                } label: {
                    Label("\(Int(radius)) km", systemImage: "slider.horizontal.3")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Adjust search radius")
            }
            .font(.caption)
            .padding(.horizontal, 13)
            .frame(height: 37)
            .background(.black.opacity(0.66), in: Capsule())
            .padding(.horizontal, 14)

            if radiusVisible {
                HStack(spacing: 9) {
                    Text("1")
                    Slider(value: $radius, in: 1...25, step: 1)
                        .tint(category.tint)
                    Text("25 km")
                }
                .font(.caption2.weight(.medium))
                .foregroundStyle(.white)
                .padding(.horizontal, 13)
                .frame(height: 40)
                .background(.black.opacity(0.68), in: Capsule())
                .padding(.horizontal, 14)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .accessibilityIdentifier("mxCompactFloatingVenueFilters")
    }

    private func snapHeight(_ level: NearbyDetent, available: CGFloat) -> CGFloat {
        let expanded = max(310, available * 0.76)
        switch level {
        case .collapsed: return 100
        case .medium: return min(expanded - 90, max(250, available * 0.35))
        case .expanded: return expanded
        }
    }

    private func draggedHeight(_ available: CGFloat) -> CGFloat {
        let base = snapHeight(detent, available: available)
        return min(snapHeight(.expanded, available: available),
                   max(snapHeight(.collapsed, available: available),
                       base - draggingSheet))
    }

    private func snapTarget(_ projectedHeight: CGFloat, available: CGFloat) -> NearbyDetent {
        NearbyDetent.allCases.min {
            abs(snapHeight($0, available: available) - projectedHeight) <
            abs(snapHeight($1, available: available) - projectedHeight)
        } ?? .medium
    }

    private func dragResults(_ available: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 4)
            .updating($draggingSheet) { gesture, value, _ in
                value = gesture.translation.height
            }
            .onEnded { gesture in
                let projected = snapHeight(detent, available: available) -
                    gesture.predictedEndTranslation.height
                withAnimation(.interactiveSpring(response: 0.44, dampingFraction: 0.86)) {
                    detent = snapTarget(projected, available: available)
                }
            }
    }

    private func resultsSheet(availableHeight: CGFloat) -> some View {
        VStack(spacing: 0) {
            VStack(spacing: 10) {
                Capsule()
                    .fill(.white.opacity(0.44))
                    .frame(width: 39, height: 4)
                    .padding(.top, 11)

                HStack(spacing: 9) {
                    Text("Nearby places")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(.white)
                    Spacer(minLength: 0)
                    if model.loading { ProgressView().controlSize(.small) }
                    Text("\(model.places.count) results")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(MXPremiumStyle.muted)
                    Button {
                        withAnimation(.interactiveSpring(response: 0.44, dampingFraction: 0.86)) {
                            detent = detent == .expanded ? .medium : .expanded
                        }
                    } label: {
                        Image(systemName: detent == .expanded ? "chevron.down" : "chevron.up")
                            .font(.system(size: 14, weight: .semibold))
                            .frame(width: 34, height: 34)
                            .foregroundStyle(.white)
                            .background(.white.opacity(0.07), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(detent == .expanded ? "Reduce nearby list" : "Expand nearby list")
                }
                .padding(.horizontal, 17)
                .padding(.bottom, 8)
            }
            .contentShape(Rectangle())
            .gesture(dragResults(availableHeight))
            .accessibilityIdentifier("mxSmoothNearbyDragHandle")

            if detent != .collapsed || draggingSheet < -24 {
                if let error = model.error, model.places.isEmpty && !model.loading {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(MXPremiumStyle.muted)
                        .padding(.horizontal, 17)
                        .padding(.top, 8)
                } else if center == nil {
                    Text("Select a location on Explore first.")
                        .font(.footnote)
                        .foregroundStyle(MXPremiumStyle.muted)
                        .padding(.horizontal, 17)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 9) {
                            if let c = center {
                                ForEach(Array(model.places.enumerated()), id: \.offset) { _, item in
                                    MXPremiumVenueCard(item: item, center: c, category: category, compact: true) {
                                        withAnimation(.easeInOut(duration: 0.25)) {
                                            mapPosition = .region(MKCoordinateRegion(
                                                center: item.placemark.coordinate,
                                                latitudinalMeters: 1700,
                                                longitudinalMeters: 1700
                                            ))
                                        }
                                        selectedVenue = item
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.top, 4)
                        .padding(.bottom, 25)
                    }
                    .scrollIndicators(.hidden)
                    .scrollDisabled(detent == .collapsed)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
        .frame(height: draggedHeight(availableHeight), alignment: .top)
        .background(
            MXPremiumStyle.panel.opacity(0.96),
            in: UnevenRoundedRectangle(topLeadingRadius: 24, topTrailingRadius: 24)
        )
        .overlay(alignment: .top) {
            UnevenRoundedRectangle(topLeadingRadius: 24, topTrailingRadius: 24)
                .stroke(.white.opacity(0.065), lineWidth: 0.7)
        }
        .shadow(color: .black.opacity(0.25), radius: 15, y: -3)
        .animation(.interactiveSpring(response: 0.44, dampingFraction: 0.86),
                   value: detent)
        .accessibilityIdentifier("mxNearbyThreeDetentSheet")
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
