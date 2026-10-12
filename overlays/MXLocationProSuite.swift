import SwiftUI
import MapKit
import CoreLocation
import LocalAuthentication
import Security
import UserNotifications

// Separate MX Location Pro destination discovery. Everything is driven by the
// currently selected pin, never by a fixed Manila/Jakarta city list.
// The host app's SpoofSession owns the actual Locus teleport/pairing engine.

struct MXProFeature: Identifiable {
    let id: Int
    let name: String
    let symbol: String
    let description: String
    let query: String?
    let availability: String
    init(_ id: Int, _ name: String, _ symbol: String, _ description: String,
         query: String? = nil, availability: String = "Available") {
        self.id = id
        self.name = name
        self.symbol = symbol
        self.description = description
        self.query = query
        self.availability = availability
    }
}

enum MXProCatalog {
    static let all: [MXProFeature] = [
        .init(1,"MX Teleport","location.fill","Teleport to a selected coordinate through the existing pairing engine."),
        .init(2,"MX Dating Explorer","heart.fill","Real venues near the selected point, refreshed when the pin moves.",query:"date night"),
        .init(3,"MX Social Radar","dot.radiowaves.left.and.right","Public social venues near the pin, not a live people-tracking radar.",query:"social club"),
        .init(4,"MX Singles Nearby","person.2.fill","Profiles only from consenting adult members of a future authorized directory.",availability:"Needs opt-in directory"),
        .init(5,"Date Spot Finder","wineglass.fill","Nearby cafes, restaurants and date-friendly venues.",query:"romantic restaurant"),
        .init(6,"Dating City Compare","square.split.2x1","Compare visible venue results by moving the pin between neighborhoods."),
        .init(7,"MX Icebreaker","text.bubble.fill","Offline conversation starters in English, Tagalog and Indonesian."),
        .init(8,"MX Date Planner","calendar","Save a date plan, note and optional local reminder."),
        .init(9,"Dating App Shortcuts","app.badge","Open official dating app websites. No private profile scraping."),
        .init(10,"MX Virtual Journey","car.fill","Preview a walking or driving route. Does not force system-wide GPS movement."),
        .init(11,"MX Live Control","antenna.radiowaves.left.and.right","Inspect selected and simulated coordinates and launch the host map."),
        .init(12,"MX World Passport","globe.asia.australia.fill","Use locally saved locations as reusable worlds."),
        .init(13,"Smart Favorites","star.fill","Save the currently selected location into the existing Favorites."),
        .init(14,"Dynamic Location Cards","square.grid.2x2.fill","Live nearby cards recomputed from the selected coordinate.",query:"cafe"),
        .init(15,"Smart Radius Filter","circle.dotted.circle","Adjust nearby search from one to 25 kilometers."),
        .init(16,"Smart Location Search","magnifyingglass","Worldwide search is available on the Map tab."),
        .init(17,"MX Dark Glass UI","moon.stars.fill","Dark glass treatment across the discovery suite."),
        .init(18,"Quick Teleport","bolt.fill","Return to Map to teleport to your selected or saved location."),
        .init(19,"Location Restore","location.slash.fill","Restore your actual location using the original engine's map controls."),
        .init(20,"Background Status","battery.100percent","Shows app-visible spoof status; iOS may suspend or terminate the app."),
        .init(21,"MX Nightlife Pulse","moon.fill","Nightlife and live music venues in the chosen area.",query:"nightlife"),
        .init(22,"MX Singles Events","person.3.fill","Find likely event venues; verified event schedules require an events feed.",query:"speed dating",availability:"Venue discovery; events feed needed"),
        .init(23,"MX Social Hotspots","flame.fill","Nearby public gathering places, not inferred crowd or gender counts.",query:"popular bar"),
        .init(24,"MX City DNA","chart.bar.fill","Inspect categories of venues to understand a neighborhood.",query:"restaurants"),
        .init(25,"MX Best Time","clock.fill","See local time and open venue details for posted opening hours."),
        .init(26,"MX Vibe Finder","music.note","Discover jazz, lounges and live music near the pin.",query:"jazz lounge"),
        .init(27,"MX Street Preview","binoculars.fill","Open the selected point in Apple Maps for available street imagery."),
        .init(28,"MX Smart Itinerary","point.topleft.down.curvedto.point.bottomright.up","Choose several venues and open a route in Maps."),
        .init(29,"MX Instant Translator","character.bubble.fill","Offline practical multilingual phrases; not a universal translator."),
        .init(30,"MX Conversation Coach","bubble.left.and.bubble.right.fill","Respectful conversation starters matched to travel contexts."),
        .init(31,"MX Dating Safety","checkmark.shield.fill","First-date safety checklist and scam awareness."),
        .init(32,"MX Time Zone Sync","clock.badge.checkmark","Local time for the selected region when geocoding resolves a time zone."),
        .init(33,"MX Weather Match","cloud.sun.fill","Current local forecast from Open-Meteo; activity suggestions.",query:"indoor activities"),
        .init(34,"MX Date Budget","banknote.fill","Personal manually entered date spending budget."),
        .init(35,"MX Event Alerts","bell.fill","Optional reminder for a date you choose; no fabricated event alerts."),
        .init(36,"MX Dual City Compare","rectangle.split.2x1","Save a comparison anchor and check venues in a second place."),
        .init(37,"MX Privacy Vault","lock.shield.fill","Face ID or device passcode guarded notes stored in iOS Keychain."),
        .init(38,"MX Location History","clock.arrow.circlepath","Recent chosen locations from the original application's history."),
        .init(39,"MX Offline Travel Pack","square.and.arrow.up.fill","Export saved location, notes and itinerary as text; not offline map tiles."),
        .init(40,"MX Smart Discovery","sparkles.rectangle.stack.fill","Fast venue lookup adapted to your selected coordinate.",query:"things to do"),
        .init(41,"MX Discovery Engine","sparkles","Coordinates nearby venue discovery and region-aware cards.",query:"places to visit")
    ]
}

@MainActor
final class MXProDiscovery: ObservableObject {
    @Published var venues: [MKMapItem] = []
    @Published var regionName = "Select a destination"
    @Published var timeZone: TimeZone?
    @Published var temperature: Double?
    @Published var isLoading = false
    @Published var errorText: String?
    private var token = UUID()

    func refresh(center: CLLocationCoordinate2D, query: String, radiusKm: Double) async {
        guard CLLocationCoordinate2DIsValid(center) else { return }
        let requestToken = UUID()
        token = requestToken
        isLoading = true
        errorText = nil
        venues = []

        let region = MKCoordinateRegion(
            center: center,
            latitudinalMeters: max(900, radiusKm * 2400),
            longitudinalMeters: max(900, radiusKm * 2400)
        )
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        request.region = region
        request.resultTypes = .pointOfInterest
        let target = CLLocation(latitude: center.latitude, longitude: center.longitude)
        do {
            let response = try await MKLocalSearch(request: request).start()
            guard requestToken == token else { return }
            venues = response.mapItems
                .filter { $0.location.distance(from: target) <= radiusKm * 1000 }
                .sorted { $0.location.distance(from: target) < $1.location.distance(from: target) }
            if venues.isEmpty { errorText = "No matching verified map venues in this radius. Widen the radius or try another category." }
        } catch {
            guard requestToken == token else { return }
            errorText = "Map search unavailable: \(error.localizedDescription)"
        }
        if requestToken == token { isLoading = false }
        await resolveContext(center: center, token: requestToken)
    }

    private func resolveContext(center: CLLocationCoordinate2D, token requested: UUID) async {
        let geocoder = CLGeocoder()
        do {
            let marks = try await geocoder.reverseGeocodeLocation(CLLocation(latitude: center.latitude, longitude: center.longitude))
            guard requested == token else { return }
            if let p = marks.first {
                regionName = [p.subLocality, p.locality, p.administrativeArea, p.country]
                    .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", ")
                timeZone = p.timeZone
            }
        } catch {
            if requested == token { regionName = String(format: "%.4f, %.4f", center.latitude, center.longitude) }
        }
        await fetchWeather(center, requested)
    }

    private struct Forecast: Decodable {
        struct Current: Decodable { let temperature_2m: Double }
        let current: Current
    }

    private func fetchWeather(_ center: CLLocationCoordinate2D, _ requested: UUID) async {
        var parts = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        parts.queryItems = [
            URLQueryItem(name:"latitude", value:String(center.latitude)),
            URLQueryItem(name:"longitude", value:String(center.longitude)),
            URLQueryItem(name:"current", value:"temperature_2m")
        ]
        guard let url = parts.url,
              let (bytes, _) = try? await URLSession.shared.data(from: url),
              let forecast = try? JSONDecoder().decode(Forecast.self, from: bytes),
              requested == token else { return }
        temperature = forecast.current.temperature_2m
    }

    func clockText() -> String {
        guard let zone = timeZone else { return "Local time unavailable" }
        let formatter = DateFormatter()
        formatter.timeZone = zone
        formatter.dateFormat = "EEE HH:mm"
        return formatter.string(from: Date())
    }
}

struct MXProSuiteView: View {
    @EnvironmentObject private var session: SpoofSession
    @EnvironmentObject private var pairing: PairingStore
    @StateObject private var discovery = MXProDiscovery()
    @State private var segment = 0
    @State private var radiusKm: Double = 5
    @State private var selectedQuery = "date night"
    @State private var selectedTitle = "Dating Explorer"
    @State private var openedFeature: MXProFeature?
    @State private var selectedVenue: MKMapItem?
    @State private var itinerary: [String] = []
    @State private var comparison: CLLocationCoordinate2D?
    @State private var selectedPlaceName = "Chosen location"
    @State private var routeMode: MKDirectionsTransportType = .automobile
    @State private var routeDetails = "Choose a destination and calculate a route."
    @State private var routeLoading = false
    @State private var preferredLanguage = "Tagalog"
    @State private var budget: Double = 1500
    @State private var dateTime = Date().addingTimeInterval(3600)
    @AppStorage("mxpro.date.note.v1") private var dateNote = ""
    @State private var vaultNote = ""
    @State private var vaultUnlocked = false
    @State private var vaultMessage = "Private note is locked."
    @State private var notificationStatus = ""

    private let cyan = Color(red:0.23,green:0.73,blue:0.99)
    private var center: CLLocationCoordinate2D? {
        session.pin ?? session.simulated ?? session.realCoordinate
    }
    private var scanKey: String {
        guard let c = center else { return "no-location" }
        return "\(c.latitude):\(c.longitude):\(radiusKm):\(selectedQuery)"
    }
    private var phrases: [String] {
        switch preferredLanguage {
        case "Indonesian": return [
            "Halo, apa kabar? — Hi, how are you?",
            "Apa tempat favoritmu di kota ini? — What's your favorite place here?",
            "Mau ngobrol sambil minum kopi? — Would you like to chat over coffee?"
        ]
        case "English": return [
            "What's your favorite place in this city?",
            "Do you know a good spot for live jazz?",
            "Would you like to meet for coffee somewhere public?"
        ]
        default: return [
            "Kumusta ka? — How are you?",
            "Ano ang paborito mong lugar dito? — What's your favorite spot here?",
            "Gusto mo bang magkape? — Would you like to have coffee?"
        ]
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing:0) {
                Picker("MX Pro", selection:$segment) {
                    Text("Discover").tag(0)
                    Text("Toolkit 41").tag(1)
                    Text("Planner").tag(2)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal,14).padding(.vertical,9)
                if segment == 0 { discoverScreen }
                else if segment == 1 { toolkitScreen }
                else { plannerScreen }
            }
            .background(Color.black)
            .navigationTitle("MX Location Pro")
            .navigationBarTitleDisplayMode(.inline)
            .preferredColorScheme(.dark)
            .sheet(item:$openedFeature) { feature in featureDetails(feature) }
            .sheet(isPresented:Binding(get:{ selectedVenue != nil },set:{ if !$0 { selectedVenue=nil } })) { if let item=selectedVenue { venueDetails(item) } }
            .task(id:scanKey) {
                if let center {
                    await discovery.refresh(center:center,query:selectedQuery,radiusKm:radiusKm)
                }
            }
        }
    }

    private var discoverScreen: some View {
        ScrollView {
            VStack(alignment:.leading,spacing:14) {
                VStack(alignment:.leading,spacing:6) {
                    HStack {
                        Label("DISCOVERY ENGINE",systemImage:"scope").foregroundStyle(cyan)
                        Spacer()
                        Text(discovery.isLoading ? "SEARCHING" : "REGION AWARE")
                            .font(.caption2.weight(.bold)).foregroundStyle(.secondary)
                    }
                    Text(discovery.regionName)
                        .font(.headline).lineLimit(2)
                    HStack {
                        Text(discovery.clockText())
                        Spacer()
                        if let t = discovery.temperature {
                            Text(String(format:"%.0f°C", t))
                        }
                    }.font(.caption).foregroundStyle(.secondary)
                    if let c = center {
                        Text(String(format:"%.5f, %.5f",c.latitude,c.longitude))
                            .font(.caption.monospaced()).foregroundStyle(.secondary)
                    } else {
                        Text("Choose a pin in the Map tab to start.").foregroundStyle(.orange)
                    }
                }.padding(15).background(.ultraThinMaterial,in:RoundedRectangle(cornerRadius:18))

                ScrollView(.horizontal,showsIndicators:false) {
                    HStack {
                        category("Dating","heart.fill","date night")
                        category("Social Radar","dot.radiowaves.left.and.right","social club")
                        category("Cafes","cup.and.saucer.fill","cafe")
                        category("Nightlife","moon.stars.fill","nightlife")
                        category("Jazz","music.note","jazz lounge")
                        category("Events","calendar","social events venue")
                        category("Food","fork.knife","restaurant")
                        category("Activities","sparkles","things to do")
                    }
                }
                HStack {
                    Text(selectedTitle).font(.headline)
                    Spacer()
                    Text("\(Int(radiusKm)) km").font(.caption.monospacedDigit()).foregroundStyle(cyan)
                }
                Slider(value:$radiusKm,in:1...25,step:1)
                    .tint(cyan)
                if discovery.isLoading { ProgressView("Scanning this selected area…") }
                if let error = discovery.errorText {
                    Text(error).font(.footnote).foregroundStyle(.secondary)
                }

                if let c = center {
                    Map(initialPosition:.region(MKCoordinateRegion(center:c,latitudinalMeters:9000,longitudinalMeters:9000))) {
                        Marker("Selected",systemImage:"scope",coordinate:c).tint(cyan)
                        ForEach(Array(discovery.venues.enumerated()),id:\.offset) { _, item in
                            Marker(item.name ?? "Place", coordinate:item.location.coordinate).tint(.pink)
                        }
                    }
                    .frame(height:205).clipShape(RoundedRectangle(cornerRadius:17))
                    .allowsHitTesting(false)
                }

                ForEach(Array(discovery.venues.enumerated()),id:\.offset) { _, item in
                    Button { selectedVenue = item } label: {
                        HStack(spacing:12) {
                            Image(systemName:"mappin.and.ellipse")
                                .foregroundStyle(cyan)
                                .frame(width:28)
                            VStack(alignment:.leading,spacing:3) {
                                Text(item.name ?? "Unnamed venue")
                                    .foregroundStyle(.primary).font(.subheadline.weight(.semibold))
                                Text(item.placemark.title ?? discovery.regionName)
                                    .font(.caption2).foregroundStyle(.secondary).lineLimit(2)
                            }
                            Spacer()
                            Image(systemName:"chevron.right").foregroundStyle(.tertiary)
                        }
                        .padding(13)
                        .background(.white.opacity(0.065),in:RoundedRectangle(cornerRadius:15))
                    }.buttonStyle(.plain)
                }
                Text("Map venue data ≠ live attendance, gender counts or verified single profiles.")
                    .font(.caption2).foregroundStyle(.secondary)
            }.padding(15)
        }
    }

    private func category(_ label:String,_ symbol:String,_ query:String) -> some View {
        Button {
            selectedTitle=label
            selectedQuery=query
        } label: {
            Label(label,systemImage:symbol)
                .font(.caption.weight(.semibold))
                .padding(.horizontal,13).padding(.vertical,10)
                .background(selectedQuery == query ? cyan.opacity(0.25) : .white.opacity(0.09),
                            in:Capsule())
        }.buttonStyle(.plain)
    }

    private var toolkitScreen: some View {
        List {
            Section {
                Text("41 modules in the suite. Each indicates whether it is usable locally, a preview, or requires an authorized live-data provider.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            ForEach(MXProCatalog.all) { feature in
                Button {
                    if let query = feature.query {
                        selectedTitle=feature.name
                        selectedQuery=query
                        segment=0
                    } else { openedFeature=feature }
                } label: {
                    HStack(spacing:12) {
                        Image(systemName:feature.symbol).foregroundStyle(cyan).frame(width:25)
                        VStack(alignment:.leading,spacing:4) {
                            Text("\(feature.id). \(feature.name)").foregroundStyle(.primary)
                            Text(feature.availability).font(.caption2)
                                .foregroundStyle(feature.availability == "Available" ? .green : .orange)
                        }
                        Spacer()
                        Image(systemName:"chevron.right").foregroundStyle(.tertiary)
                    }
                }
            }
        }.listStyle(.insetGrouped)
    }

    private var plannerScreen: some View {
        Form {
            Section("Date Planner / Event Alerts") {
                DatePicker("Date and time",selection:$dateTime)
                TextField("Plan, venue, or notes",text:$dateNote,axis:.vertical)
                    .lineLimit(2...5)
                Button("Schedule a local reminder") { scheduleReminder() }
                if !notificationStatus.isEmpty {
                    Text(notificationStatus).font(.caption).foregroundStyle(.secondary)
                }
            }
            Section("Date Budget") {
                TextField("Budget", value:$budget, format:.number)
                    .keyboardType(.decimalPad)
                Text("Your own estimate: \(budget,format:.number) in the currency you enter. Venue prices are not guessed.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("Conversation / Translation") {
                Picker("Language",selection:$preferredLanguage) {
                    ForEach(["Tagalog","Indonesian","English"],id:\.self) { Text($0) }
                }
                ForEach(phrases,id:\.self) { phrase in
                    ShareLink(item:phrase) { Text(phrase).font(.subheadline) }
                }
            }
            Section("Itinerary") {
                if itinerary.isEmpty { Text("Add locations from Discover cards.").foregroundStyle(.secondary) }
                ForEach(itinerary,id:\.self) { Text($0) }
                Button("Clear itinerary") { itinerary=[] }.disabled(itinerary.isEmpty)
            }
            Section("Privacy Vault") {
                if vaultUnlocked {
                    SecureField("Private note",text:$vaultNote)
                    Button("Save to Keychain") { saveVault() }
                    Button("Lock now") { vaultUnlocked=false;vaultNote="" }
                } else {
                    Button("Unlock with Face ID / passcode") { unlockVault() }
                }
                Text(vaultMessage).font(.caption).foregroundStyle(.secondary)
            }
        }.scrollContentBackground(.hidden)
    }

    @ViewBuilder
    private func venueDetails(_ item: MKMapItem) -> some View {
        NavigationStack {
            Form {
                Section("Venue") {
                    Text(item.name ?? "Unnamed venue").font(.headline)
                    Text(item.placemark.title ?? "Location details unavailable")
                    if let url = item.url { Link("Official venue link",destination:url) }
                    Button("Open Apple Maps / photos / hours") { item.openInMaps() }
                }
                Section("Location") {
                    Button("Use this as selected pin") {
                        session.pin=item.location.coordinate
                        selectedVenue=nil
                    }
                    Button("Teleport here using MX pairing") {
                        session.pin=item.location.coordinate
                        session.teleport(to:item.location.coordinate,pairing:pairing)
                        selectedVenue=nil
                    }
                    Button("Add to favorites") {
                        session.addFavorite(name:item.name ?? "Saved place",coordinate:item.location.coordinate)
                    }
                    Button("Add to itinerary") {
                        itinerary.append(item.name ?? "Unnamed venue")
                    }
                    Button("Show route from real device position") {
                        Task { await calculateRoute(to:item) }
                    }
                    Text(routeDetails).font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Place details")
            .toolbar { ToolbarItem(placement:.topBarTrailing) {
                Button("Done") { selectedVenue=nil }
            }}
        }
    }

    @ViewBuilder
    private func featureDetails(_ feature:MXProFeature) -> some View {
        NavigationStack {
            Form {
                Section {
                    Label(feature.name,systemImage:feature.symbol).font(.headline)
                    Text(feature.description)
                    Text("Availability: \(feature.availability)")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("Actions") {
                    switch feature.id {
                    case 1,18:
                        if let c=center {
                            Button("Teleport to selected pin") {
                                session.teleport(to:c,pairing:pairing)
                                openedFeature=nil
                            }
                        } else { Text("Choose a map pin first.") }
                    case 7,29,30:
                        Picker("Language",selection:$preferredLanguage) {
                            ForEach(["English","Tagalog","Indonesian"],id:\.self) { Text($0) }
                        }
                        ForEach(phrases,id:\.self) { phrase in
                            ShareLink(item:phrase) { Text(phrase) }
                        }
                    case 8,34,35,37:
                        Button("Open Planner / Vault") {
                            openedFeature=nil
                            segment=2
                        }
                    case 9:
                        Link("Tinder",destination:URL(string:"https://tinder.com")!)
                        Link("Bumble",destination:URL(string:"https://bumble.com")!)
                        Link("Badoo",destination:URL(string:"https://badoo.com")!)
                    case 10:
                        if let c = center, let real = session.realCoordinate {
                            Text(String(format:"From %.4f, %.4f to %.4f, %.4f",
                                        real.latitude,real.longitude,c.latitude,c.longitude))
                            Picker("Route",selection:$routeMode) {
                                Text("Drive").tag(MKDirectionsTransportType.automobile)
                                Text("Walk").tag(MKDirectionsTransportType.walking)
                            }.pickerStyle(.segmented)
                            Button("Calculate route preview") {
                                Task { await calculateRoute(from:real,to:c) }
                            }
                            Text(routeDetails)
                        } else { Text("Select a destination and allow real location.") }
                    case 11,20:
                        if let c=center {
                            Text(String(format:"Selected: %.5f, %.5f",c.latitude,c.longitude))
                        }
                        Text(session.simulated == nil ? "No simulated location reported by the app." : "A simulated coordinate is reported by the app.")
                        Text("An iOS force-quit can stop this session; this does not imply guaranteed persistence.")
                    case 12,13,38:
                        ForEach(session.favorites) { favorite in
                            Button(favorite.name) {
                                session.pin=favorite.coordinate
                                openedFeature=nil
                            }
                        }
                        if let c=center {
                            Button("Save selected pin") {
                                session.addFavorite(name:discovery.regionName,coordinate:c)
                            }
                        }
                    case 6,36:
                        if let c=center {
                            Button("Save this location as comparison anchor") { comparison=c }
                        }
                        if let anchor=comparison {
                            Text(String(format:"Anchor: %.4f, %.4f",anchor.latitude,anchor.longitude))
                            Text("Move the pin and discover venues at the second location to compare.")
                        }
                    case 15:
                        Slider(value:$radiusKm,in:1...25,step:1)
                        Text("Search radius: \(Int(radiusKm)) km")
                    case 16,19:
                        Text("Use the original Map tab for search and the original engine's restore controls.")
                    case 25,32,33:
                        Text(discovery.regionName)
                        Text(discovery.clockText())
                        if let t=discovery.temperature {
                            Text(String(format:"Current temperature: %.0f°C",t))
                        }
                    case 27:
                        if let c=center {
                            Link("Open area in Apple Maps",
                                 destination:URL(string:"https://maps.apple.com/?ll=\(c.latitude),\(c.longitude)")!)
                        }
                    case 28:
                        Button("Open planner itinerary") { openedFeature=nil; segment=2 }
                    case 31:
                        Text("Meet in a public place. Confirm identity through the service itself. Avoid money transfers and share your plans with a trusted contact.")
                    case 39:
                        ShareLink(item:offlinePack) { Label("Export trip summary",systemImage:"square.and.arrow.up") }
                    case 4:
                        Text("No women or profiles are inferred from location. A consenting adults-only service with published APIs and active members must be integrated before this can show real accounts.")
                    default:
                        Button("Explore venues for this location") {
                            openedFeature=nil
                            segment=0
                        }
                    }
                }
            }
            .navigationTitle("MX Pro Tool")
            .toolbar { ToolbarItem(placement:.topBarTrailing) {
                Button("Done") { openedFeature=nil }
            }}
        }
    }

    private var offlinePack: String {
        let coordinateText: String
        if let c=center { coordinateText=String(format:"%.5f, %.5f",c.latitude,c.longitude) }
        else { coordinateText="No selected point" }
        return "MX Location Pro Travel Pack\n\(discovery.regionName)\n\(coordinateText)\n\nDate plan:\n\(dateNote)\n\nStops:\n\(itinerary.joined(separator:"\n"))"
    }

    private func calculateRoute(to item:MKMapItem) async {
        guard let origin=session.realCoordinate else {
            routeDetails="Real device location unavailable."
            return
        }
        await calculateRoute(from:origin,to:item.location.coordinate)
    }

    private func calculateRoute(from origin:CLLocationCoordinate2D,to destination:CLLocationCoordinate2D) async {
        routeLoading=true
        defer { routeLoading=false }
        let request=MKDirections.Request()
        request.source=MKMapItem(placemark:MKPlacemark(coordinate:origin))
        request.destination=MKMapItem(placemark:MKPlacemark(coordinate:destination))
        request.transportType=routeMode
        do {
            let result=try await MKDirections(request:request).calculate()
            if let route=result.routes.first {
                routeDetails="Preview: \(Int(route.distance/1000)) km · about \(Int(route.expectedTravelTime/60)) minutes."
            } else { routeDetails="No route found." }
        } catch { routeDetails="Directions unavailable: \(error.localizedDescription)" }
    }

    private func scheduleReminder() {
        guard dateTime>Date() else { notificationStatus="Choose a future time.";return }
        UNUserNotificationCenter.current().requestAuthorization(options:[.alert,.badge,.sound]) { granted,_ in
            guard granted else {
                Task { @MainActor in notificationStatus="Notifications are not permitted." }
                return
            }
            let content=UNMutableNotificationContent()
            content.title="MX Date Planner"
            content.body=dateNote.isEmpty ? "Your saved date reminder" : dateNote
            content.sound=.default
            let components=Calendar.current.dateComponents([.year,.month,.day,.hour,.minute],from:dateTime)
            let trigger=UNCalendarNotificationTrigger(dateMatching:components,repeats:false)
            UNUserNotificationCenter.current().add(UNNotificationRequest(identifier:"mxpro-date-" + UUID().uuidString,content:content,trigger:trigger)) { error in
                Task { @MainActor in notificationStatus = error == nil ? "Reminder scheduled." : "Reminder failed: \(error!.localizedDescription)" }
            }
        }
    }

    private func unlockVault() {
        let context=LAContext()
        var problem:NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication,error:&problem) else {
            vaultMessage="Enable device passcode / Face ID to unlock private notes."
            return
        }
        context.evaluatePolicy(.deviceOwnerAuthentication,localizedReason:"Unlock private MX Location Pro notes") { success,error in
            Task { @MainActor in
                if success {
                    vaultUnlocked=true
                    vaultNote=loadSecret()
                    vaultMessage="Keychain note unlocked."
                } else { vaultMessage=error?.localizedDescription ?? "Unlock cancelled." }
            }
        }
    }

    private func saveVault() {
        let key="com.mazenmix.mxlocationpro.vault"
        let query:[String:Any]=[kSecClass as String:kSecClassGenericPassword,
                                kSecAttrAccount as String:key]
        SecItemDelete(query as CFDictionary)
        var add=query
        add[kSecValueData as String]=Data(vaultNote.utf8)
        add[kSecAttrAccessible as String]=kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let code=SecItemAdd(add as CFDictionary,nil)
        vaultMessage = code == errSecSuccess ? "Encrypted note saved to device Keychain." : "Keychain save failed (\(code))."
    }

    private func loadSecret() -> String {
        let query:[String:Any]=[
            kSecClass as String:kSecClassGenericPassword,
            kSecAttrAccount as String:"com.mazenmix.mxlocationpro.vault",
            kSecReturnData as String:true,
            kSecMatchLimit as String:kSecMatchLimitOne
        ]
        var item:CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary,&item)==errSecSuccess,
              let data=item as? Data else { return "" }
        return String(data:data,encoding:.utf8) ?? ""
    }
}
