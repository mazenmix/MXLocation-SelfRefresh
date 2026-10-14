import SwiftUI
import MapKit
import CoreLocation

// Party Animal is deliberately isolated from SpoofSession and all GPS controls.
// It plans real MapKit routes but never changes the simulated or pinned position.
struct MXPartyStop: Codable, Identifiable, Hashable {
    var id = UUID()
    let name: String
    let latitude: Double
    let longitude: Double
    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

@MainActor
final class MXPartyAnimalPlanner: ObservableObject {
    @Published var stops: [MXPartyStop] = []
    @Published var routes: [MKRoute] = []
    @Published var busy = false
    @Published var message: String?
    @Published var duration: TimeInterval = 0
    @Published var distance: CLLocationDistance = 0

    private let key = "mx_party_animal_stops_v1"
    private var generation = UUID()

    init() {
        if let saved = UserDefaults.standard.data(forKey: key),
           let decoded = try? JSONDecoder().decode([MXPartyStop].self, from: saved) {
            stops = decoded
        }
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(stops) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    func discover(around origin: CLLocationCoordinate2D, walking: Bool) async {
        guard CLLocationCoordinate2DIsValid(origin) else {
            message = "Select a starting location first."
            return
        }
        let token = UUID()
        generation = token
        busy = true
        message = nil
        routes = []
        var found: [MXPartyStop] = []
        let searches = ["jazz lounge", "rooftop bar", "nightclub", "late night cafe"]
        let base = CLLocation(latitude: origin.latitude, longitude: origin.longitude)
        for term in searches {
            if generation != token { return }
            let request = MKLocalSearch.Request()
            request.naturalLanguageQuery = term
            request.resultTypes = .pointOfInterest
            request.region = MKCoordinateRegion(center: origin, latitudinalMeters: 12500,
                                                 longitudinalMeters: 12500)
            guard let response = try? await MKLocalSearch(request: request).start() else { continue }
            let item = response.mapItems
                .filter { $0.name != nil && CLLocationCoordinate2DIsValid($0.placemark.coordinate) }
                .sorted {
                    base.distance(from: CLLocation(latitude: $0.placemark.coordinate.latitude,
                                                   longitude: $0.placemark.coordinate.longitude)) <
                    base.distance(from: CLLocation(latitude: $1.placemark.coordinate.latitude,
                                                   longitude: $1.placemark.coordinate.longitude))
                }
                .first(where: { candidate in
                    !found.contains(where: {
                        CLLocation(latitude: $0.latitude, longitude: $0.longitude)
                            .distance(from: CLLocation(latitude: candidate.placemark.coordinate.latitude,
                                                       longitude: candidate.placemark.coordinate.longitude)) < 120
                    })
                })
            if let item, let name = item.name {
                let c = item.placemark.coordinate
                found.append(MXPartyStop(name: name, latitude: c.latitude, longitude: c.longitude))
            }
        }
        guard generation == token else { return }
        stops = found
        persist()
        if found.isEmpty { message = "No matching venues. Try another part of the city." }
        busy = false
        await calculate(from: origin, walking: walking)
    }

    func calculate(from origin: CLLocationCoordinate2D, walking: Bool) async {
        guard CLLocationCoordinate2DIsValid(origin), !stops.isEmpty else {
            routes = []
            distance = 0
            duration = 0
            return
        }
        let token = UUID()
        generation = token
        busy = true
        routes = []
        distance = 0
        duration = 0
        message = nil
        var previous = origin
        var computed: [MKRoute] = []
        for stop in stops {
            guard generation == token else { return }
            let req = MKDirections.Request()
            req.source = MKMapItem(placemark: MKPlacemark(coordinate: previous))
            req.destination = MKMapItem(placemark: MKPlacemark(coordinate: stop.coordinate))
            req.transportType = walking ? .walking : .automobile
            req.requestsAlternateRoutes = false
            if let route = try? await MKDirections(request: req).calculate().routes.first {
                computed.append(route)
            } else {
                message = "Some road segments are unavailable. No straight-line route is invented."
            }
            previous = stop.coordinate
        }
        guard generation == token else { return }
        routes = computed
        distance = computed.reduce(0) { $0 + $1.distance }
        duration = computed.reduce(0) { $0 + $1.expectedTravelTime }
        busy = false
    }

    func move(_ index: Int, by delta: Int, origin: CLLocationCoordinate2D, walking: Bool) async {
        let other = index + delta
        guard stops.indices.contains(index), stops.indices.contains(other) else { return }
        stops.swapAt(index, other)
        persist()
        await calculate(from: origin, walking: walking)
    }

    func clear() {
        generation = UUID()
        stops = []
        routes = []
        distance = 0
        duration = 0
        message = nil
        persist()
        busy = false
    }
}

struct MXPartyAnimalView: View {
    @EnvironmentObject private var session: SpoofSession
    @Environment(\.dismiss) private var dismiss
    @StateObject private var planner = MXPartyAnimalPlanner()
    @State private var walking = false
    @State private var startChoice = 0
    @State private var camera: MapCameraPosition = .automatic

    private var start: CLLocationCoordinate2D? {
        switch startChoice {
        case 1: return session.simulated ?? session.pin ?? session.realCoordinate
        case 2: return session.realCoordinate ?? session.pin ?? session.simulated
        default: return session.pin ?? session.simulated ?? session.realCoordinate
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 5) {
                        Label("PARTY ANIMAL", systemImage: "sparkles")
                            .font(.title2.bold())
                            .foregroundStyle(.white)
                        Text("Find your night. Build a real street route. No voice prompts.")
                            .font(.subheadline)
                            .foregroundStyle(MXPremiumStyle.muted)
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        Text("STARTING POINT").font(.caption.weight(.bold)).foregroundStyle(MXPremiumStyle.muted)
                        Picker("Start", selection: $startChoice) {
                            Text("Selected pin").tag(0)
                            Text("Simulated").tag(1)
                            Text("Real GPS").tag(2)
                        }
                        .pickerStyle(.segmented)
                        Picker("Travel", selection: $walking) {
                            Text("Driving").tag(false)
                            Text("Walking").tag(true)
                        }
                        .pickerStyle(.segmented)
                        Button {
                            if let start { Task { await planner.discover(around: start, walking: walking) } }
                        } label: {
                            Label(planner.busy ? "Finding real places…" : "Plan My Night",
                                  systemImage: "party.popper.fill")
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(MXPremiumStyle.cyan)
                        .disabled(start == nil || planner.busy)
                        .accessibilityIdentifier("mxPartyAnimalPlan")
                    }
                    .padding(15)
                    .background(MXPremiumStyle.panel, in: RoundedRectangle(cornerRadius: 18))

                    if let message = planner.message {
                        Label(message, systemImage: "info.circle")
                            .font(.caption).foregroundStyle(MXPremiumStyle.muted)
                    }
                    if !planner.stops.isEmpty {
                        Map(position: $camera) {
                            if let start {
                                Annotation("Start", coordinate: start) {
                                    Image(systemName: "location.circle.fill").font(.title2)
                                        .foregroundStyle(MXPremiumStyle.cyan)
                                }
                            }
                            ForEach(Array(planner.stops.enumerated()), id: \.element.id) { index, stop in
                                Annotation(stop.name, coordinate: stop.coordinate) {
                                    Text("\(index + 1)").font(.caption.bold()).foregroundStyle(.white)
                                        .frame(width: 31, height: 31)
                                        .background(Color.purple, in: Circle())
                                }
                            }
                            ForEach(Array(planner.routes.enumerated()), id: \.offset) { _, route in
                                MapPolyline(route.polyline)
                                    .stroke(MXPremiumStyle.cyan, lineWidth: 5)
                            }
                        }
                        .mapStyle(.standard(elevation: .realistic))
                        .frame(height: 290)
                        .clipShape(RoundedRectangle(cornerRadius: 20))
                        .accessibilityIdentifier("mxPartyRoadMap")

                        HStack {
                            Label(String(format: "%.1f km", planner.distance / 1000), systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                            Spacer()
                            Label("\(Int(planner.duration / 60)) min travel", systemImage: "clock")
                        }
                        .font(.caption.weight(.semibold)).foregroundStyle(.white)
                        .padding(14)
                        .background(MXPremiumStyle.panel, in: RoundedRectangle(cornerRadius: 16))

                        Text("YOUR STOPS").font(.headline).foregroundStyle(.white)
                        ForEach(Array(planner.stops.enumerated()), id: \.element.id) { index, stop in
                            HStack(spacing: 11) {
                                Text("\(index + 1)").font(.headline).frame(width: 30, height: 30)
                                    .background(Color.purple.opacity(0.6), in: Circle())
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(stop.name).font(.subheadline.bold()).lineLimit(2)
                                    Text("Real map listing").font(.caption2).foregroundStyle(MXPremiumStyle.muted)
                                }
                                Spacer()
                                VStack(spacing: 5) {
                                    Button { if let start { Task { await planner.move(index, by: -1, origin: start, walking: walking) } } } label: {
                                        Image(systemName: "chevron.up")
                                    }.disabled(index == 0 || planner.busy)
                                    Button { if let start { Task { await planner.move(index, by: 1, origin: start, walking: walking) } } } label: {
                                        Image(systemName: "chevron.down")
                                    }.disabled(index == planner.stops.count - 1 || planner.busy)
                                }.buttonStyle(.plain)
                            }
                            .foregroundStyle(.white)
                            .padding(13)
                            .background(MXPremiumStyle.panel, in: RoundedRectangle(cornerRadius: 16))
                        }
                        Button("Clear saved night", role: .destructive) { planner.clear() }
                            .font(.caption.weight(.semibold))
                    }
                }
                .padding(16)
            }
            .scrollIndicators(.hidden)
            .background(MXPremiumStyle.background.ignoresSafeArea())
            .navigationTitle("Party Animal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
            .task {
                if let start { camera = .region(MKCoordinateRegion(center: start, latitudinalMeters: 14500, longitudinalMeters: 14500)) }
                if let start, !planner.stops.isEmpty { await planner.calculate(from: start, walking: walking) }
            }
            .onChange(of: walking) { _, _ in
                if let start { Task { await planner.calculate(from: start, walking: walking) } }
            }
            .onChange(of: startChoice) { _, _ in
                if let start {
                    camera = .region(MKCoordinateRegion(center: start, latitudinalMeters: 14500, longitudinalMeters: 14500))
                    Task { await planner.calculate(from: start, walking: walking) }
                }
            }
        }
        .preferredColorScheme(.dark)
        .accessibilityIdentifier("mxPartyAnimalScreen")
    }
}

struct MXVisualNavigatorView: View {
    let destination: MKMapItem
    let start: CLLocationCoordinate2D?
    @Environment(\.dismiss) private var dismiss
    @State private var routes: [MKRoute] = []
    @State private var selected = 0
    @State private var walking = false
    @State private var loading = false
    @State private var issue: String?
    @State private var camera: MapCameraPosition = .automatic

    private var route: MKRoute? { routes.indices.contains(selected) ? routes[selected] : nil }

    private func reload() async {
        guard let start else { issue = "Choose a pin or enable location before routing."; return }
        loading = true
        issue = nil
        routes = []
        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: start))
        request.destination = destination
        request.transportType = walking ? .walking : .automobile
        request.requestsAlternateRoutes = true
        do {
            let result = try await MKDirections(request: request).calculate()
            routes = result.routes
            selected = 0
            if routes.isEmpty { issue = "No routable road was returned for these locations." }
        } catch {
            issue = "Road directions unavailable. Try another transport mode."
        }
        loading = false
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 15) {
                    Text(destination.name ?? "Destination").font(.headline).foregroundStyle(.white)
                    Picker("Route mode", selection: $walking) {
                        Text("Drive").tag(false)
                        Text("Walk").tag(true)
                    }.pickerStyle(.segmented)
                    Map(position: $camera) {
                        if let start {
                            Marker("Start", coordinate: start).tint(.green)
                        }
                        Marker("Destination", coordinate: destination.placemark.coordinate).tint(.purple)
                        if let route {
                            MapPolyline(route.polyline).stroke(MXPremiumStyle.cyan, lineWidth: 6)
                        }
                    }
                    .mapStyle(.standard)
                    .frame(height: 315)
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                    if loading { ProgressView("Calculating street directions…").tint(MXPremiumStyle.cyan) }
                    if let issue { Text(issue).font(.subheadline).foregroundStyle(MXPremiumStyle.muted) }
                    if routes.count > 1 {
                        HStack(spacing: 8) {
                            ForEach(routes.indices, id: \.self) { index in
                                Button("Route \(index + 1)") { selected = index }
                                    .buttonStyle(.bordered)
                                    .tint(selected == index ? MXPremiumStyle.cyan : .gray)
                            }
                        }
                    }
                    if let route {
                        HStack {
                            Label(String(format: "%.1f km", route.distance / 1000), systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                            Spacer()
                            Label("\(Int(route.expectedTravelTime / 60)) min", systemImage: "clock")
                        }
                        .font(.subheadline.bold()).foregroundStyle(.white)
                        Text("DIRECTIONS · SILENT").font(.caption.bold()).foregroundStyle(MXPremiumStyle.muted)
                        ForEach(Array(route.steps.filter { !$0.instructions.isEmpty }.enumerated()), id: \.offset) { index, step in
                            HStack(alignment: .top, spacing: 10) {
                                Text("\(index + 1)").font(.caption.bold()).frame(width: 28, height: 28)
                                    .background(MXPremiumStyle.cyan.opacity(0.27), in: Circle())
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(step.instructions).font(.subheadline).fixedSize(horizontal: false, vertical: true)
                                    Text(String(format: "%.0f m", step.distance))
                                        .font(.caption2).foregroundStyle(MXPremiumStyle.muted)
                                }
                                Spacer(minLength: 0)
                            }
                            .foregroundStyle(.white)
                            .padding(12)
                            .background(MXPremiumStyle.panel, in: RoundedRectangle(cornerRadius: 14))
                        }
                    }
                }
                .padding(16)
            }
            .background(MXPremiumStyle.background.ignoresSafeArea())
            .navigationTitle("MX Navigator")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
            .task {
                camera = .region(MKCoordinateRegion(center: destination.placemark.coordinate,
                                                    latitudinalMeters: 6500, longitudinalMeters: 6500))
                await reload()
            }
            .onChange(of: walking) { _, _ in Task { await reload() } }
        }
        .preferredColorScheme(.dark)
        .accessibilityIdentifier("mxSilentNavigator")
    }
}
