import CoreLocation
import Foundation
import MapKit
import SwiftUI
import UIKit

struct MXWorldPoint: Codable, Hashable, Identifiable {
    let name: String
    let latitude: Double
    let longitude: Double
    let date: Date

    var id: String {
        "\(date.timeIntervalSince1970)-\(latitude)-\(longitude)"
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

struct MXWorldMetadata: Codable {
    var lastUsed: Date?
    var useCount: Int
    var lastLatitude: Double?
    var lastLongitude: Double?
    var history: [MXWorldPoint]
}

enum MXWorldStore {
    private static let metadataKey = "mx.worldMetadata.v1"
    private static let notesKey = "mx.favoriteNotes.v1"

    static func metadata(for place: SavedPlace) -> MXWorldMetadata {
        loadAll()[place.id] ?? MXWorldMetadata(
            lastUsed: nil,
            useCount: 0,
            lastLatitude: nil,
            lastLongitude: nil,
            history: []
        )
    }

    static func recordUse(
        place: SavedPlace,
        coordinate: CLLocationCoordinate2D,
        name: String? = nil
    ) {
        var all = loadAll()
        var value = all[place.id] ?? MXWorldMetadata(
            lastUsed: nil,
            useCount: 0,
            lastLatitude: nil,
            lastLongitude: nil,
            history: []
        )

        let now = Date()
        value.lastUsed = now
        value.useCount += 1
        value.lastLatitude = coordinate.latitude
        value.lastLongitude = coordinate.longitude

        let cleanName = name?.trimmingCharacters(in: .whitespacesAndNewlines)
        let point = MXWorldPoint(
            name: (cleanName?.isEmpty == false ? cleanName! : place.name),
            latitude: coordinate.latitude,
            longitude: coordinate.longitude,
            date: now
        )

        if let first = value.history.first {
            let previous = CLLocation(latitude: first.latitude, longitude: first.longitude)
            let current = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
            if previous.distance(from: current) < 40 {
                value.history[0] = point
            } else {
                value.history.insert(point, at: 0)
            }
        } else {
            value.history = [point]
        }

        value.history = Array(value.history.prefix(12))
        all[place.id] = value
        saveAll(all)
    }

    static func note(for place: SavedPlace) -> String {
        let notes = (UserDefaults.standard.dictionary(forKey: notesKey) as? [String: String]) ?? [:]
        return notes[place.id] ?? ""
    }

    static func setNote(_ note: String, for place: SavedPlace) {
        var notes = (UserDefaults.standard.dictionary(forKey: notesKey) as? [String: String]) ?? [:]
        let clean = note.trimmingCharacters(in: .whitespacesAndNewlines)
        if clean.isEmpty {
            notes.removeValue(forKey: place.id)
        } else {
            notes[place.id] = clean
        }
        UserDefaults.standard.set(notes, forKey: notesKey)
    }

    static func lastCoordinate(for place: SavedPlace) -> CLLocationCoordinate2D? {
        let value = metadata(for: place)
        guard let latitude = value.lastLatitude, let longitude = value.lastLongitude else { return nil }
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    static func relativeText(_ date: Date?) -> String {
        guard let date else { return "Never used" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    private static func loadAll() -> [String: MXWorldMetadata] {
        guard let data = UserDefaults.standard.data(forKey: metadataKey),
              let value = try? JSONDecoder().decode([String: MXWorldMetadata].self, from: data) else {
            return [:]
        }
        return value
    }

    private static func saveAll(_ value: [String: MXWorldMetadata]) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        UserDefaults.standard.set(data, forKey: metadataKey)
    }
}

struct MXWorldWeather: Equatable {
    let temperature: Int
    let description: String
    let isDay: Bool
}

@MainActor
final class MXWorldContextModel: ObservableObject {
    @Published var timeZone: TimeZone?
    @Published var countryCode: String?
    @Published var weather: MXWorldWeather?

    func load(_ place: SavedPlace) async {
        let coordinate = place.coordinate
        async let context = reverseContext(coordinate)
        async let currentWeather = fetchWeather(coordinate)

        let (resolvedContext, resolvedWeather) = await (context, currentWeather)
        timeZone = resolvedContext.timeZone
        countryCode = resolvedContext.countryCode
        weather = resolvedWeather
    }

    func timeText(for date: Date) -> String {
        guard let timeZone else { return "--:--" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    func dateText(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone ?? .current
        formatter.dateFormat = "EEEE, MMM d, yyyy"
        return formatter.string(from: date)
    }

    func periodText(for date: Date) -> String {
        let calendar = Calendar(identifier: .gregorian)
        var zoned = calendar
        zoned.timeZone = timeZone ?? .current
        let hour = zoned.component(.hour, from: date)
        switch hour {
        case 5..<11: return "Morning"
        case 11..<17: return "Afternoon"
        case 17..<21: return "Evening"
        default: return "Night"
        }
    }

    var flag: String {
        guard let code = countryCode, code.count == 2 else { return "🌐" }
        return code.uppercased().unicodeScalars.compactMap {
            UnicodeScalar(127397 + $0.value)
        }.map(String.init).joined()
    }

    private func reverseContext(_ coordinate: CLLocationCoordinate2D) async -> (timeZone: TimeZone?, countryCode: String?) {
        let geocoder = CLGeocoder()
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        let marks = try? await geocoder.reverseGeocodeLocation(location)
        return (marks?.first?.timeZone, marks?.first?.isoCountryCode)
    }

    private func fetchWeather(_ coordinate: CLLocationCoordinate2D) async -> MXWorldWeather? {
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        components.queryItems = [
            URLQueryItem(name: "latitude", value: String(format: "%.6f", coordinate.latitude)),
            URLQueryItem(name: "longitude", value: String(format: "%.6f", coordinate.longitude)),
            URLQueryItem(name: "current", value: "temperature_2m,weather_code,is_day"),
            URLQueryItem(name: "timezone", value: "auto")
        ]
        guard let url = components.url,
              let (data, _) = try? await URLSession.shared.data(from: url),
              let response = try? JSONDecoder().decode(MXOpenMeteoResponse.self, from: data) else {
            return nil
        }

        return MXWorldWeather(
            temperature: Int(response.current.temperature_2m.rounded()),
            description: Self.weatherDescription(response.current.weather_code),
            isDay: response.current.is_day == 1
        )
    }

    private static func weatherDescription(_ code: Int) -> String {
        switch code {
        case 0: return "Clear"
        case 1, 2: return "Partly Cloudy"
        case 3: return "Cloudy"
        case 45, 48: return "Fog"
        case 51, 53, 55, 56, 57: return "Drizzle"
        case 61, 63, 65, 66, 67, 80, 81, 82: return "Rain"
        case 71, 73, 75, 77, 85, 86: return "Snow"
        case 95, 96, 99: return "Thunderstorm"
        default: return "Weather"
        }
    }
}

private struct MXOpenMeteoResponse: Decodable {
    let current: Current

    struct Current: Decodable {
        let temperature_2m: Double
        let weather_code: Int
        let is_day: Int
    }
}

struct MXWorldLocalClockBadge: View {
    let place: SavedPlace
    @StateObject private var context = MXWorldContextModel()

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { timeline in
            Text(context.timeText(for: timeline.date))
                .font(.caption.monospacedDigit().weight(.semibold))
                .foregroundStyle(Color.white.opacity(0.92))
        }
        .task(id: place.id) {
            await context.load(place)
        }
    }
}

struct MXWorldMiniMap: View {
    let place: SavedPlace
    var radiusMeters: CLLocationDistance = 5000

    var body: some View {
        Map(initialPosition: .region(MKCoordinateRegion(
            center: place.coordinate,
            latitudinalMeters: radiusMeters,
            longitudinalMeters: radiusMeters
        ))) {
            Annotation("", coordinate: place.coordinate, anchor: .center) {
                ZStack {
                    Circle()
                        .fill(Color(red: 0.18, green: 0.55, blue: 1.0).opacity(0.22))
                        .frame(width: 22, height: 22)
                    Circle()
                        .fill(Color.white)
                        .frame(width: 7, height: 7)
                        .overlay(Circle().stroke(Color(red: 0.18, green: 0.55, blue: 1.0), lineWidth: 2))
                }
            }
        }
        .mapStyle(.standard(elevation: .flat))
        .allowsHitTesting(false)
    }
}

struct MXWorldListRow: View {
    let place: SavedPlace
    let onPreview: () -> Void
    let onOpenWorld: () -> Void
    let onResume: () -> Void
    let onEdit: () -> Void
    let onRemove: () -> Void

    @StateObject private var context = MXWorldContextModel()

    var body: some View {
        let metadata = MXWorldStore.metadata(for: place)

        HStack(spacing: 11) {
            Button(action: onOpenWorld) {
                MXWorldMiniMap(place: place, radiusMeters: 8500)
                    .frame(width: 62, height: 62)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Color.white.opacity(0.08), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)

            Button(action: onPreview) {
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 5) {
                        HStack(spacing: 5) {
                            Text(place.name)
                                .font(.headline.weight(.bold))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                            Text(context.flag)
                                .font(.caption)
                        }

                        TimelineView(.periodic(from: .now, by: 60)) { timeline in
                            HStack(spacing: 4) {
                                Text(context.periodText(for: timeline.date))
                                    .foregroundStyle(periodColor(context.periodText(for: timeline.date)))
                                if let weather = context.weather {
                                    Text("•")
                                        .foregroundStyle(.secondary)
                                    Text("\(weather.temperature)°C")
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .font(.caption.weight(.semibold))
                        }

                        Text("Last used \(MXWorldStore.relativeText(metadata.lastUsed))")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 4)

                    TimelineView(.periodic(from: .now, by: 30)) { timeline in
                        Text(context.timeText(for: timeline.date))
                            .font(.subheadline.monospacedDigit().weight(.bold))
                            .foregroundStyle(.white)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Menu {
                Button(action: onOpenWorld) {
                    Label("World Details", systemImage: "globe.americas.fill")
                }

                if metadata.lastUsed != nil {
                    Button(action: onResume) {
                        Label("Resume Last Session", systemImage: "arrow.counterclockwise.circle")
                    }
                }

                Button(action: onEdit) {
                    Label("Edit World", systemImage: "slider.horizontal.3")
                }

                Menu {
                    ShareLink(item: appleMapsURL) {
                        Label("Apple Maps", systemImage: "map")
                    }
                    ShareLink(item: googleMapsURL) {
                        Label("Google Maps", systemImage: "globe")
                    }
                } label: {
                    Label("Share Location", systemImage: "square.and.arrow.up")
                }

                Button(role: .destructive, action: onRemove) {
                    Label("Remove Favorite", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.body.weight(.bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 34, height: 44)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.white.opacity(0.065))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.white.opacity(0.06), lineWidth: 1)
        )
        .task(id: place.id) {
            await context.load(place)
        }
    }

    private func periodColor(_ period: String) -> Color {
        switch period {
        case "Morning": return .orange
        case "Afternoon": return .yellow
        case "Evening": return Color(red: 1.0, green: 0.58, blue: 0.22)
        default: return Color(red: 0.34, green: 0.64, blue: 1.0)
        }
    }

    private var appleMapsURL: URL {
        var components = URLComponents(string: "https://maps.apple.com/")!
        components.queryItems = [
            URLQueryItem(name: "ll", value: "\(place.latitude),\(place.longitude)"),
            URLQueryItem(name: "q", value: place.name)
        ]
        return components.url!
    }

    private var googleMapsURL: URL {
        var components = URLComponents(string: "https://www.google.com/maps/search/")!
        components.queryItems = [
            URLQueryItem(name: "api", value: "1"),
            URLQueryItem(name: "query", value: "\(place.latitude),\(place.longitude)")
        ]
        return components.url!
    }
}

struct MXWorldDetailsView: View {
    let place: SavedPlace
    let onPreview: (SavedPlace) -> Void
    let onEnter: (SavedPlace) -> Void
    let onRename: (SavedPlace, String) -> Void

    @EnvironmentObject private var session: SpoofSession
    @Environment(\.dismiss) private var dismiss
    @StateObject private var context = MXWorldContextModel()
    @State private var note = ""
    @State private var showEdit = false
    @State private var showResume = false
    @State private var showRecent = false

    private let accent = Color(red: 0.18, green: 0.55, blue: 1.0)

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    hero
                    stats
                    noteCard
                    lastUsedCard
                    recentSection
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 18)
            }
            .background(Color.black.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(.white)
                            .frame(width: 34, height: 34)
                            .background(Color.white.opacity(0.10), in: Circle())
                    }
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                VStack(spacing: 8) {
                    Button {
                        onEnter(place)
                        dismiss()
                    } label: {
                        Label("Enter World", systemImage: "location.fill")
                            .font(.headline.weight(.bold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                            .background(accent, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)

                    Button {
                        onPreview(place)
                        dismiss()
                    } label: {
                        Label("Preview on Map", systemImage: "magnifyingglass")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.94))
                            .frame(maxWidth: .infinity)
                            .frame(height: 42)
                            .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 14)
                .padding(.top, 10)
                .padding(.bottom, 6)
                .background(.ultraThinMaterial)
            }
        }
        .preferredColorScheme(.dark)
        .task(id: place.id) {
            note = MXWorldStore.note(for: place)
            await context.load(place)
        }
        .sheet(isPresented: $showEdit) {
            MXWorldEditView(place: place) { newName, newNote in
                note = newNote
                MXWorldStore.setNote(newNote, for: place)
                let clean = newName.trimmingCharacters(in: .whitespacesAndNewlines)
                if !clean.isEmpty, clean != place.name {
                    onRename(place, clean)
                }
            }
        }
        .sheet(isPresented: $showResume) {
            MXWorldResumeView(place: place) { previewPlace in
                onPreview(previewPlace)
                dismiss()
            }
        }
        .sheet(isPresented: $showRecent) {
            MXWorldRecentLocationsView(place: place) { previewPlace in
                onPreview(previewPlace)
                dismiss()
            }
        }
    }

    private var hero: some View {
        ZStack(alignment: .bottomLeading) {
            MXWorldMiniMap(place: place, radiusMeters: 16000)
                .frame(height: 235)

            LinearGradient(
                colors: [.clear, Color.black.opacity(0.88)],
                startPoint: .center,
                endPoint: .bottom
            )

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 7) {
                    Text(place.name.uppercased())
                        .font(.title2.weight(.black))
                        .lineLimit(1)
                    Text(context.flag)
                }

                TimelineView(.periodic(from: .now, by: 30)) { timeline in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(context.timeText(for: timeline.date))
                            .font(.system(size: 32, weight: .bold, design: .rounded).monospacedDigit())
                        Text(context.dateText(for: timeline.date))
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(16)
        }
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    private var stats: some View {
        HStack(spacing: 8) {
            TimelineView(.periodic(from: .now, by: 60)) { timeline in
                MXWorldStatCard(
                    icon: periodIcon(context.periodText(for: timeline.date)),
                    title: context.periodText(for: timeline.date),
                    value: "Local time"
                )
            }

            MXWorldStatCard(
                icon: context.weather?.isDay == false ? "cloud.moon.fill" : "cloud.sun.fill",
                title: context.weather.map { "\($0.temperature)°C" } ?? "—",
                value: context.weather?.description ?? "Weather"
            )

            MXWorldStatCard(
                icon: "airplane",
                title: distanceText,
                value: "from current"
            )
        }
    }

    private var noteCard: some View {
        HStack(alignment: .top, spacing: 11) {
            Image(systemName: "sparkles")
                .foregroundStyle(.yellow)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 4) {
                Text("Your Note")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.yellow)
                Text(note.isEmpty ? "Add a note so this world is easy to remember." : note)
                    .font(.subheadline)
                    .foregroundStyle(note.isEmpty ? .secondary : Color.orange.opacity(0.94))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            Button("Edit") {
                showEdit = true
            }
            .font(.caption.weight(.bold))
            .foregroundStyle(accent)
        }
        .padding(14)
        .background(Color.white.opacity(0.065), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var lastUsedCard: some View {
        let metadata = MXWorldStore.metadata(for: place)

        return Button {
            if metadata.lastUsed != nil {
                showResume = true
            }
        } label: {
            HStack(spacing: 11) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.title3)
                    .foregroundStyle(.white.opacity(0.82))
                    .frame(width: 32)

                VStack(alignment: .leading, spacing: 3) {
                    Text("Last Used")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.primary)
                    Text(MXWorldStore.relativeText(metadata.lastUsed))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.mint)
                }

                Spacer()

                Text("\(metadata.useCount) times")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.tertiary)
            }
            .padding(14)
            .background(Color.white.opacity(0.065), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(metadata.lastUsed == nil)
    }

    private var recentSection: some View {
        let history = Array(MXWorldStore.metadata(for: place).history.prefix(3))

        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Recent Locations in \(place.name)")
                    .font(.subheadline.weight(.bold))
                Spacer()
                if !history.isEmpty {
                    Button("See All") {
                        showRecent = true
                    }
                    .font(.caption.weight(.bold))
                    .foregroundStyle(accent)
                }
            }

            if history.isEmpty {
                Text("Locations you use around this world will appear here automatically.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            } else {
                HStack(spacing: 8) {
                    ForEach(history) { point in
                        Button {
                            onPreview(SavedPlace(
                                name: point.name,
                                latitude: point.latitude,
                                longitude: point.longitude
                            ))
                            dismiss()
                        } label: {
                            VStack(alignment: .leading, spacing: 5) {
                                MXWorldMiniMap(
                                    place: SavedPlace(name: point.name, latitude: point.latitude, longitude: point.longitude),
                                    radiusMeters: 5000
                                )
                                .frame(height: 72)
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                                Text(point.name)
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                            }
                            .padding(7)
                            .frame(maxWidth: .infinity)
                            .background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(14)
        .background(Color.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 19, style: .continuous))
    }

    private var distanceText: String {
        guard let origin = session.simulated ?? session.realCoordinate else { return "—" }
        let meters = CLLocation(latitude: origin.latitude, longitude: origin.longitude)
            .distance(from: CLLocation(latitude: place.latitude, longitude: place.longitude))
        let km = meters / 1000
        if km >= 100 { return String(format: "%.0f km", km) }
        if km >= 10 { return String(format: "%.1f km", km) }
        return String(format: "%.2f km", km)
    }

    private func periodIcon(_ period: String) -> String {
        switch period {
        case "Morning": return "sunrise.fill"
        case "Afternoon": return "sun.max.fill"
        case "Evening": return "sunset.fill"
        default: return "moon.stars.fill"
        }
    }
}

private struct MXWorldStatCard: View {
    let icon: String
    let title: String
    let value: String

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white.opacity(0.88))
            Text(title)
                .font(.caption.weight(.bold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text(value)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 74)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

struct MXWorldResumeView: View {
    let place: SavedPlace
    let onPreview: (SavedPlace) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let metadata = MXWorldStore.metadata(for: place)
        let coordinate = MXWorldStore.lastCoordinate(for: place) ?? place.coordinate
        let preview = SavedPlace(
            name: "\(place.name) · Last Session",
            latitude: coordinate.latitude,
            longitude: coordinate.longitude
        )

        NavigationStack {
            VStack(spacing: 16) {
                Text("Resume last \(place.name) session?")
                    .font(.title3.weight(.bold))
                    .frame(maxWidth: .infinity, alignment: .leading)

                MXWorldMiniMap(place: preview, radiusMeters: 6500)
                    .frame(height: 190)
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))

                VStack(spacing: 10) {
                    infoRow(icon: "mappin.and.ellipse", text: String(format: "%.5f, %.5f", coordinate.latitude, coordinate.longitude))
                    infoRow(icon: "clock", text: MXWorldStore.relativeText(metadata.lastUsed))
                    infoRow(icon: "arrow.triangle.2.circlepath", text: "Used \(metadata.useCount) times")
                }
                .padding(14)
                .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 18, style: .continuous))

                Button {
                    onPreview(preview)
                    dismiss()
                } label: {
                    Label("Resume", systemImage: "arrow.counterclockwise")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(Color(red: 0.18, green: 0.55, blue: 1.0), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)

                Text("Resume previews the last spot on the map. Change Location is still required to activate it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                Spacer()
            }
            .padding(16)
            .background(Color.black.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func infoRow(icon: String, text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(.secondary)
                .frame(width: 22)
            Text(text)
                .font(.subheadline)
            Spacer()
        }
    }
}

struct MXWorldRecentLocationsView: View {
    let place: SavedPlace
    let onPreview: (SavedPlace) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let history = MXWorldStore.metadata(for: place).history

        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                if history.isEmpty {
                    ContentUnavailableView(
                        "No Recent Locations",
                        systemImage: "clock.arrow.circlepath",
                        description: Text("Use locations around this world and they will appear here.")
                    )
                } else {
                    ScrollView {
                        LazyVStack(spacing: 10) {
                            ForEach(history) { point in
                                Button {
                                    onPreview(SavedPlace(
                                        name: point.name,
                                        latitude: point.latitude,
                                        longitude: point.longitude
                                    ))
                                    dismiss()
                                } label: {
                                    HStack(spacing: 11) {
                                        MXWorldMiniMap(
                                            place: SavedPlace(name: point.name, latitude: point.latitude, longitude: point.longitude),
                                            radiusMeters: 5500
                                        )
                                        .frame(width: 58, height: 58)
                                        .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))

                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(point.name)
                                                .font(.headline)
                                                .foregroundStyle(.primary)
                                                .lineLimit(1)
                                            Text(String(format: "%.5f, %.5f", point.latitude, point.longitude))
                                                .font(.caption.monospaced())
                                                .foregroundStyle(.secondary)
                                            Text(MXWorldStore.relativeText(point.date))
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                        }

                                        Spacer()

                                        Image(systemName: "chevron.right")
                                            .foregroundStyle(.tertiary)
                                    }
                                    .padding(10)
                                    .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(14)
                    }
                }
            }
            .navigationTitle("Recent Locations in \(place.name)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}

struct MXWorldEditView: View {
    let place: SavedPlace
    let onSave: (String, String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var note: String

    init(place: SavedPlace, onSave: @escaping (String, String) -> Void) {
        self.place = place
        self.onSave = onSave
        _name = State(initialValue: place.name)
        _note = State(initialValue: MXWorldStore.note(for: place))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    MXWorldMiniMap(place: place, radiusMeters: 8500)
                        .frame(height: 175)
                        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))

                    VStack(alignment: .leading, spacing: 7) {
                        Text("Name")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.secondary)
                        TextField("World name", text: $name)
                            .textFieldStyle(.plain)
                            .padding(.horizontal, 12)
                            .frame(height: 46)
                            .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                    }

                    VStack(alignment: .leading, spacing: 7) {
                        Text("Note")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.secondary)
                        TextEditor(text: $note)
                            .scrollContentBackground(.hidden)
                            .frame(minHeight: 110)
                            .padding(8)
                            .foregroundStyle(Color.orange.opacity(0.95))
                            .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                    }

                    VStack(alignment: .leading, spacing: 7) {
                        Text("Location")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.secondary)
                        Text(String(format: "%.5f, %.5f", place.latitude, place.longitude))
                            .font(.subheadline.monospaced())
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .frame(height: 46)
                            .background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                    }
                }
                .padding(16)
            }
            .background(Color.black.ignoresSafeArea())
            .navigationTitle("Edit World")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        onSave(name, note)
                        dismiss()
                    } label: {
                        Image(systemName: "checkmark")
                            .font(.body.weight(.bold))
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}
