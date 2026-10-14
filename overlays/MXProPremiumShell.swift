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
    @Published var isImmersiveMap = false
}

enum MXPremiumCategory: String, CaseIterable, Identifiable, Hashable {
    case dateSpots, adultVenues, afterDark, romanticStays, socialRadar, selfCare, spaWellness, nightclubs, nightlife, convenienceStores, rooftopBars, karaoke, speakeasy, lateNightFood, pharmacies, billiards, cafes, activities, jazz

    var id: String { rawValue }
    var title: String {
        switch self {
        case .dateSpots: "Date Spots"
        case .adultVenues: "Adults 18+"
        case .afterDark: "After Dark"
        case .romanticStays: "Romantic Stays"
        case .socialRadar: "Social Radar"
        case .selfCare: "Grooming & Beauty"
        case .spaWellness: "SPA & Wellness"
        case .nightclubs: "Nightclubs"
        case .convenienceStores: "Convenience Stores"
        case .rooftopBars: "Rooftop Bars"
        case .karaoke: "KTV & Karaoke"
        case .speakeasy: "Speakeasy Bars"
        case .lateNightFood: "Late-Night Food"
        case .pharmacies: "24/7 Pharmacies"
        case .billiards: "Billiards & Games"
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
        case .selfCare: "scissors"
        case .spaWellness: "water.waves"
        case .nightclubs: "music.note.list"
        case .convenienceStores: "basket.fill"
        case .rooftopBars: "building.2.fill"
        case .karaoke: "mic.fill"
        case .speakeasy: "wineglass.fill"
        case .lateNightFood: "fork.knife"
        case .pharmacies: "cross.case.fill"
        case .billiards: "circle.grid.2x2.fill"
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
        case .selfCare: Color(red: 0.40, green: 0.84, blue: 0.82)
        case .spaWellness: Color(red: 0.08, green: 0.59, blue: 1.0)
        case .nightclubs: Color(red: 0.68, green: 0.35, blue: 0.95)
        case .convenienceStores: Color(red: 0.25, green: 0.70, blue: 0.47)
        case .rooftopBars: Color(red: 0.70, green: 0.49, blue: 1.0)
        case .karaoke: Color(red: 0.96, green: 0.46, blue: 0.73)
        case .speakeasy: Color(red: 0.84, green: 0.52, blue: 0.29)
        case .lateNightFood: Color(red: 1.0, green: 0.55, blue: 0.28)
        case .pharmacies: Color(red: 0.20, green: 0.81, blue: 0.54)
        case .billiards: Color(red: 0.28, green: 0.73, blue: 0.69)
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
        case .selfCare: "Grooming, hair, nails and beauty"
        case .spaWellness: "Massage, wellness, saunas and relaxation"
        case .nightclubs: "Dance clubs and DJs"
        case .convenienceStores: "24-hour shops and mini-marts"
        case .rooftopBars: "Sky bars and rooftop lounges"
        case .karaoke: "KTV and private karaoke rooms"
        case .speakeasy: "Hidden and craft cocktail bars"
        case .lateNightFood: "Late-night dining and night markets"
        case .pharmacies: "Pharmacies and drugstores"
        case .billiards: "Billiards, pool and social games"
        case .nightlife: "Lounges, clubs & evening venues"
        case .cafes: "Coffee shops & casual meetups"
        case .activities: "Public activities & attractions"
        case .jazz: "Live jazz & music venues"
        }
    }
    var searchTerms: [String] {
        switch self {
        case .dateSpots: ["romantic restaurant", "rooftop restaurant", "date cafe", "cozy wine bar", "couples activity", "sunset view restaurant"]
        case .adultVenues: ["strip club", "gentlemen's club", "go go bar", "adult dance club"]
        case .afterDark: ["late night lounge", "24 hour cafe", "late night restaurant"]
        case .romanticStays: ["boutique hotel", "romantic hotel", "adults only resort"]
        case .socialRadar: ["social club", "community events venue", "social dance studio", "speed dating event venue", "language exchange cafe", "board game cafe"]
        case .selfCare: ["barbershop", "hair salon", "nail salon", "beauty salon", "brow studio"]
        case .spaWellness: ["day spa", "wellness center", "massage therapy", "Thai massage", "deep tissue massage", "foot reflexology", "head spa", "aromatherapy spa", "facial spa", "sauna steam bath", "hammam spa", "couples spa"]
        case .nightclubs: ["nightclub", "dance club", "DJ nightclub", "disco club"]
        case .convenienceStores: ["convenience store", "7-Eleven", "Uncle John's convenience store", "24 hour mini mart"]
        case .rooftopBars: ["rooftop bar", "sky lounge", "rooftop cocktail lounge"]
        case .karaoke: ["KTV karaoke lounge", "private karaoke room", "karaoke bar"]
        case .speakeasy: ["speakeasy bar", "hidden cocktail bar", "craft cocktail lounge"]
        case .lateNightFood: ["late night restaurant", "24 hour restaurant", "late night food", "night food market"]
        case .pharmacies: ["24 hour pharmacy", "drugstore", "pharmacy"]
        case .billiards: ["billiards hall", "pool hall", "board game cafe"]
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

    private func isRelevant(_ item: MKMapItem, for category: MXPremiumCategory) -> Bool {
        let title = " " + (item.name ?? "").lowercased().replacingOccurrences(of: "-", with: " ") + " "
        let poi = item.pointOfInterestCategory?.rawValue.lowercased() ?? ""
        let wellness = [" spa ", "massage", "wellness", "reflexology", "pamper", "sauna", "salon", "nail", "skin care", "therapy"]
        let adult = ["strip", "pole danc", "go go", "gogo", "gentlemen", "adult entertainment", "exotic dancer"]
        let unrelated = ["gun club", "shooting", "firearm", "rifle", "detective", "private investigator",
                         "police", "hospital", "school", "dental", "clinic", "bank", "security",
                         "allied services", "guard agency", "training academy"]
        if category == .adultVenues {
            return !wellness.contains(where: { title.contains($0) || poi.contains($0.trimmingCharacters(in: .whitespaces)) }) &&
                   !unrelated.contains(where: { title.contains($0) }) &&
                   !["escort", "bridal shower", "adult store", "adult cinema"].contains(where: { title.contains($0) }) &&
                   adult.contains(where: { title.contains($0) })
        }
        if category == .spaWellness {
            return !adult.contains(where: { title.contains($0) }) &&
                   !["escort", "nightclub"].contains(where: { title.contains($0) })
        }
        if category == .nightclubs || category == .nightlife ||
           category == .rooftopBars || category == .speakeasy {
            return !wellness.contains(where: { title.contains($0) }) &&
                   !["escort", "strip"].contains(where: { title.contains($0) })
        }
        return true
    }

    private func normalizedResults(_ items: [MKMapItem], origin: CLLocation,
                                   category: MXPremiumCategory, radiusKm: Double) -> [MKMapItem] {
        var seen = Set<String>()
        return items.filter { item in
            let c = item.placemark.coordinate
            guard CLLocationCoordinate2DIsValid(c) else { return false }
            let distance = origin.distance(from: CLLocation(latitude: c.latitude, longitude: c.longitude))
            let name = (item.name ?? "").folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            let key = name + String(format: ":%.4f:%.4f", c.latitude, c.longitude)
            return distance <= radiusKm * 1000 && isRelevant(item, for: category) && seen.insert(key).inserted
        }.sorted {
            let l = $0.placemark.coordinate
            let r = $1.placemark.coordinate
            return origin.distance(from: CLLocation(latitude: l.latitude, longitude: l.longitude)) <
                   origin.distance(from: CLLocation(latitude: r.latitude, longitude: r.longitude))
        }
    }

    func search(around center: CLLocationCoordinate2D, category: MXPremiumCategory,
                radiusKm: Double, customTerm: String? = nil) async {
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
                guard activeRequest == marker else { return }
                places = normalizedResults(gathered, origin: origin, category: category, radiusKm: radiusKm)
            }
        }
        guard activeRequest == marker else { return }
        if places.isEmpty { error = "No matching venues found here. Try a larger radius." }
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
// Saved coordinates are not necessarily businesses. Do not depict a random
// street map as a venue photograph in the Saved tab.
struct MXPremiumVenueImage: View {
    let coordinate: CLLocationCoordinate2D
    var symbol = "bookmark.fill"
    var color = MXPremiumStyle.cyan

    var body: some View {
        ZStack {
            LinearGradient(colors: [color.opacity(0.27), MXPremiumStyle.panel],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            Image(systemName: symbol)
                .font(.system(size: 23, weight: .semibold))
                .foregroundStyle(.white.opacity(0.88))
        }
        .clipped()
        .accessibilityLabel("Saved coordinate")
    }
}

struct MXPremiumVenueCard: View {
    let item: MKMapItem
    let center: CLLocationCoordinate2D
    let category: MXPremiumCategory
    var compact = false
    let action: () -> Void
    @ObservedObject private var photoLibrary = MXVenuePhotoLibrary.shared

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                if !photoLibrary.didCheck(item) || !photoLibrary.pictures(item).isEmpty {
                    MXVenueRealThumbnail(item: item)
                        .frame(width: compact ? 82 : 100, height: compact ? 82 : 100)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
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
        .task(id: MXVenuePhotoSource.key(item)) {
            photoLibrary.load(item)
        }
    }
    private var distanceKm: Double {
        let origin = CLLocation(latitude: center.latitude, longitude: center.longitude)
        let loc = item.placemark.coordinate
        return origin.distance(from: CLLocation(latitude: loc.latitude, longitude: loc.longitude)) / 1000
    }
}

struct MXPremiumVenueDetails: View {
    let item: MKMapItem
    @State private var showSilentNavigator = false
    @EnvironmentObject private var session: SpoofSession
    @EnvironmentObject private var pairing: PairingStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 15) {
                    MXVenuePhotoGallery(item: item)
                    Text(item.name ?? "Venue").font(.title2.weight(.bold))
                    Text(item.placemark.title ?? "No address supplied")
                        .foregroundStyle(MXPremiumStyle.muted)
                    MXPremiumPanel {
                        MXVenueContactDetails(item: item)
                    }
                    MXPremiumPanel {
                        VStack(alignment: .leading, spacing: 13) {
                            Text("Location actions").font(.headline)
                            Button { showSilentNavigator = true } label: {
                                Label("MX Navigator · Silent route", systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                            }
                            .accessibilityIdentifier("mxSilentRouteAction")
                            Button { item.openInMaps() } label: {
                                Label("Directions in Apple Maps", systemImage: "map.fill")
                            }
                            Button {
                                session.addFavorite(name: item.name ?? "Saved place",
                                                    coordinate: item.placemark.coordinate)
                            } label: {
                                Label("Save to Favorites", systemImage: "bookmark")
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
                }
                .padding(16)
            }
            .background(MXPremiumStyle.background)
            .navigationTitle("Place Details")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showSilentNavigator) {
                MXVisualNavigatorView(destination: item,
                    start: session.pin ?? session.simulated ?? session.realCoordinate)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
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
    @EnvironmentObject private var mapChoice: MXMapChoiceStore
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
        case .adultVenues: return ["All", "Strip Clubs"]
        case .afterDark: return ["All", "Late-Night Food", "24H Cafes", "Lounges"]
        case .romanticStays: return ["All", "Boutique Hotels", "18+ Hotels", "Luxury Hotels", "Resorts"]
        case .socialRadar: return ["All", "Cafés", "Groups", "Activities", "Social Dance", "Language Exchanges", "Board Games"]
        case .selfCare: return ["All", "Nails", "Hair", "Barbers", "Brows"]
        case .spaWellness: return ["All", "Day Spa", "Massage", "Thai Massage", "Deep Tissue", "Foot Massage", "Head Spa", "Aromatherapy", "Facials", "Sauna", "Hammam", "Couples Spa"]
        case .nightclubs: return ["All", "Dance Clubs", "DJ Clubs", "Discos"]
        case .convenienceStores: return ["All", "7-Eleven", "Uncle John's", "Mini Marts", "24H Stores"]
        case .rooftopBars: return ["All", "Sky Bars", "Rooftop Lounges"]
        case .karaoke: return ["All", "KTV", "Private Karaoke"]
        case .speakeasy: return ["All", "Hidden Bars", "Cocktail Bars"]
        case .lateNightFood: return ["All", "24H Restaurants", "Street Food", "Night Markets"]
        case .pharmacies: return ["All", "24H Pharmacy", "Drugstores"]
        case .billiards: return ["All", "Pool Halls", "Board Games"]
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
        case "Strip Clubs": return "strip club"
        case "Brows": return "eyebrow studio"
        case "Day Spa": return "day spa"
        case "Thai Massage": return "Thai massage"
        case "Deep Tissue": return "deep tissue massage"
        case "Foot Massage": return "foot reflexology"
        case "Head Spa": return "head spa"
        case "Aromatherapy": return "aromatherapy spa"
        case "Sauna": return "sauna steam bath"
        case "Hammam": return "hammam spa"
        case "Couples Spa": return "couples spa"
        case "Dance Clubs": return "dance nightclub"
        case "DJ Clubs": return "DJ nightclub"
        case "Discos": return "disco club"
        case "7-Eleven": return "7-Eleven"
        case "Uncle John's": return "Uncle John's convenience store"
        case "Mini Marts": return "mini mart"
        case "24H Stores": return "24 hour convenience store"
        case "Sky Bars": return "sky bar"
        case "Rooftop Lounges": return "rooftop lounge"
        case "KTV": return "KTV lounge"
        case "Private Karaoke": return "private karaoke room"
        case "Hidden Bars": return "speakeasy bar"
        case "Cocktail Bars": return "craft cocktail bar"
        case "Late-Night Food": return "late night food"
        case "24H Restaurants": return "24 hour restaurant"
        case "Street Food": return "late night street food"
        case "Night Markets": return "night food market"
        case "24H Pharmacy": return "24 hour pharmacy"
        case "Drugstores": return "drugstore"
        case "Pool Halls": return "pool hall"
        case "Board Games": return "board game cafe"
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
        case "Social Dance": return "social dance studio"
        case "Language Exchanges": return "language exchange cafe"
        case "Board Games": return "board game cafe"
        case "Massage": return "massage therapy"
        case "Nails": return "nail salon"
        case "Hair": return "hair salon"
        case "Barbers": return "barber shop"
        case "Facials": return "facial spa"
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
                fullScreenMap
                    .ignoresSafeArea(.container, edges: .all)
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
            .ignoresSafeArea(.container, edges: .all)
        }
        .ignoresSafeArea(.container, edges: .all)
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
        Group {
            if mapChoice.selected == .osm {
                MXOpenStreetVenueMapCanvas(
                    center: center,
                    venues: model.places,
                    focusedVenue: selectedVenue?.placemark.coordinate,
                    onSelectVenue: { selectedVenue = $0 }
                )
                .accessibilityIdentifier("mxOpenStreetNearbyFullscreen")
            } else {
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
                .environment(\.colorScheme, .dark)
                .accessibilityIdentifier("mxAppleNearbyFullscreen")
            }
        }
        .ignoresSafeArea(.container, edges: .all)
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
