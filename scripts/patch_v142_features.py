from pathlib import Path
import sys

root = Path(sys.argv[1]).resolve()


def replace_required(path: Path, old: str, new: str, count: int = 1) -> None:
    text = path.read_text(encoding="utf-8")
    if old not in text:
        raise RuntimeError(f"Required source fragment not found in {path}: {old[:260]!r}")
    path.write_text(text.replace(old, new, count), encoding="utf-8")


worlds = root / "Locus/Features/Map/MXWorlds.swift"
root_view = root / "Locus/Features/Map/RootView.swift"

# -----------------------------------------------------------------------------
# 1) Weather model: richer current conditions + hourly rain outlook + sunrise /
#    sunset. Keep this compact enough for an elegant one-card presentation.
# -----------------------------------------------------------------------------
text = worlds.read_text(encoding="utf-8")
weather_start = text.index("struct MXWorldWeather: Equatable {")
response_start = text.index("private struct MXOpenMeteoResponse: Decodable {", weather_start)

new_weather = r'''struct MXWorldWeather: Equatable {
    let temperature: Int
    let apparentTemperature: Int?
    let humidity: Int?
    let windSpeed: Int?
    let precipitation: Double?
    let rain: Double?
    let description: String
    let isDay: Bool
    let rainProbability: Int?
    let peakRainProbability: Int?
    let nextRainText: String
    let sunriseText: String
    let sunsetText: String
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
            URLQueryItem(name: "current", value: "temperature_2m,apparent_temperature,relative_humidity_2m,precipitation,rain,weather_code,is_day,wind_speed_10m"),
            URLQueryItem(name: "hourly", value: "precipitation_probability,precipitation,rain"),
            URLQueryItem(name: "daily", value: "sunrise,sunset,precipitation_probability_max"),
            URLQueryItem(name: "forecast_days", value: "2"),
            URLQueryItem(name: "timezone", value: "auto")
        ]

        guard let url = components.url,
              let (data, _) = try? await URLSession.shared.data(from: url),
              let response = try? JSONDecoder().decode(MXOpenMeteoResponse.self, from: data) else {
            return nil
        }

        let hourIndex = response.hourly?.time.firstIndex(of: response.current.time)
        let hourlyProbability = hourIndex.flatMap { index in
            response.hourly?.precipitation_probability?[safe: index]
        }
        let peakProbability = response.daily?.precipitation_probability_max?.first

        return MXWorldWeather(
            temperature: Int(response.current.temperature_2m.rounded()),
            apparentTemperature: response.current.apparent_temperature.map { Int($0.rounded()) },
            humidity: response.current.relative_humidity_2m,
            windSpeed: response.current.wind_speed_10m.map { Int($0.rounded()) },
            precipitation: response.current.precipitation,
            rain: response.current.rain,
            description: Self.weatherDescription(response.current.weather_code),
            isDay: response.current.is_day == 1,
            rainProbability: hourlyProbability ?? peakProbability,
            peakRainProbability: peakProbability,
            nextRainText: Self.nextRainText(response: response, currentIndex: hourIndex),
            sunriseText: Self.clockPart(response.daily?.sunrise.first),
            sunsetText: Self.clockPart(response.daily?.sunset.first)
        )
    }

    private static func nextRainText(response: MXOpenMeteoResponse, currentIndex: Int?) -> String {
        guard let hourly = response.hourly, !hourly.time.isEmpty else {
            return "Rain outlook unavailable"
        }

        let start = currentIndex ?? 0
        for index in start..<hourly.time.count {
            let probability = hourly.precipitation_probability?[safe: index] ?? 0
            let precipitation = hourly.precipitation?[safe: index] ?? 0
            let rain = hourly.rain?[safe: index] ?? 0
            if probability >= 35 || precipitation >= 0.1 || rain >= 0.1 {
                if index == start {
                    return "Rain possible now · \(probability)%"
                }
                let time = clockPart(hourly.time[index])
                return "Rain possible around \(time) · \(probability)%"
            }
        }

        if let peak = response.daily?.precipitation_probability_max?.first, peak > 0 {
            return "No near-term rain · peak chance \(peak)%"
        }
        return "No rain expected soon"
    }

    private static func clockPart(_ value: String?) -> String {
        guard let value, value.count >= 5 else { return "—" }
        return String(value.suffix(5))
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

private extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

'''
text = text[:weather_start] + new_weather + text[response_start:]
worlds.write_text(text, encoding="utf-8")

text = worlds.read_text(encoding="utf-8")
response_start = text.index("private struct MXOpenMeteoResponse: Decodable {")
wiki_start = text.index("private struct MXWikipediaResponse: Decodable {", response_start)
new_response = r'''private struct MXOpenMeteoResponse: Decodable {
    let timezone: String?
    let current: Current
    let hourly: Hourly?
    let daily: Daily?

    struct Current: Decodable {
        let time: String
        let temperature_2m: Double
        let apparent_temperature: Double?
        let relative_humidity_2m: Int?
        let precipitation: Double?
        let rain: Double?
        let weather_code: Int
        let is_day: Int
        let wind_speed_10m: Double?
    }

    struct Hourly: Decodable {
        let time: [String]
        let precipitation_probability: [Int]?
        let precipitation: [Double]?
        let rain: [Double]?
    }

    struct Daily: Decodable {
        let sunrise: [String]
        let sunset: [String]
        let precipitation_probability_max: [Int]?
    }
}

'''
text = text[:response_start] + new_response + text[wiki_start:]
worlds.write_text(text, encoding="utf-8")


# -----------------------------------------------------------------------------
# 2) Saved list: only name + user's note on the left. On the right, local time
#    separated cleanly from current temperature/condition. No period labels.
# -----------------------------------------------------------------------------
text = worlds.read_text(encoding="utf-8")
row_start = text.index("struct MXWorldListRow: View {")
row_end = text.index("struct MXWorldDetailsView: View {", row_start)
new_row = r'''struct MXWorldListRow: View {
    let place: SavedPlace
    let onPreview: () -> Void
    let onOpenWorld: () -> Void
    let onResume: () -> Void
    let onEdit: () -> Void
    let onRemove: () -> Void

    @StateObject private var context = MXWorldContextModel()

    var body: some View {
        let note = MXWorldStore.note(for: place)

        HStack(spacing: 10) {
            Button(action: onPreview) {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(place.name)
                            .font(.headline.weight(.bold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)

                        if !note.isEmpty {
                            Text(note)
                                .font(.caption.weight(.medium))
                                .foregroundStyle(Color.orange.opacity(0.92))
                                .lineLimit(2)
                        }
                    }

                    Spacer(minLength: 6)

                    HStack(spacing: 9) {
                        TimelineView(.periodic(from: .now, by: 30)) { timeline in
                            Text(context.timeText(for: timeline.date))
                                .font(.subheadline.monospacedDigit().weight(.bold))
                                .foregroundStyle(.white)
                        }

                        Rectangle()
                            .fill(Color.white.opacity(0.15))
                            .frame(width: 1, height: 25)

                        VStack(alignment: .trailing, spacing: 1) {
                            Text(context.weather.map { "\($0.temperature)°" } ?? "—°")
                                .font(.subheadline.monospacedDigit().weight(.bold))
                                .foregroundStyle(Color.cyan.opacity(0.92))
                            Text(context.weather?.description ?? "Weather")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(Color.cyan.opacity(0.62))
                                .lineLimit(1)
                        }
                        .frame(minWidth: 54, alignment: .trailing)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Menu {
                Button(action: onOpenWorld) {
                    Label("World Details", systemImage: "globe.americas.fill")
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
                    .foregroundStyle(Color(red: 0.18, green: 0.55, blue: 1.0).opacity(0.82))
                    .frame(width: 30, height: 44)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 13)
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

'''
worlds.write_text(text[:row_start] + new_row + text[row_end:], encoding="utf-8")


# -----------------------------------------------------------------------------
# 3) World Details: no images, no Recent, no Last Used, no From Current card.
#    Center the place/time/date/distance and use two wide information cards:
#    Daylight (period + sunrise/sunset) and advanced Weather Details.
# -----------------------------------------------------------------------------
text = worlds.read_text(encoding="utf-8")
details_start = text.index("struct MXWorldDetailsView: View {")
details_end = text.index("private struct MXWorldStatCard: View {", details_start)
new_details = r'''struct MXWorldDetailsView: View {
    let place: SavedPlace
    let onPreview: (SavedPlace) -> Void
    let onEnter: (SavedPlace) -> Void
    let onRename: (SavedPlace, String) -> Void

    @EnvironmentObject private var session: SpoofSession
    @Environment(\.dismiss) private var dismiss
    @StateObject private var context = MXWorldContextModel()
    @State private var note = ""
    @State private var showEdit = false

    private let accent = Color(red: 0.18, green: 0.55, blue: 1.0)

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    centeredHeader
                    daylightCard
                    noteCard
                    weatherDetailsCard
                }
                .padding(.horizontal, 14)
                .padding(.top, 6)
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
    }

    private var centeredHeader: some View {
        VStack(spacing: 5) {
            Text(place.name.uppercased())
                .font(.title2.weight(.black))
                .multilineTextAlignment(.center)
                .lineLimit(2)

            TimelineView(.periodic(from: .now, by: 30)) { timeline in
                VStack(spacing: 3) {
                    Text(context.timeText(for: timeline.date))
                        .font(.system(size: 40, weight: .bold, design: .rounded).monospacedDigit())
                    Text(context.dateText(for: timeline.date))
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Color.white.opacity(0.62))
                    Text(distanceText == "—" ? "Distance unavailable" : "\(distanceText) away")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.white.opacity(0.42))
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
        .padding(.horizontal, 14)
        .background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.white.opacity(0.06), lineWidth: 1)
        )
    }

    private var daylightCard: some View {
        TimelineView(.periodic(from: .now, by: 60)) { timeline in
            VStack(spacing: 12) {
                Text(context.periodText(for: timeline.date))
                    .font(.title3.weight(.bold))
                    .foregroundStyle(periodColor(context.periodText(for: timeline.date)))

                HStack(spacing: 0) {
                    VStack(spacing: 3) {
                        Text("Sunrise")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(context.weather?.sunriseText ?? "—")
                            .font(.subheadline.monospacedDigit().weight(.bold))
                    }
                    .frame(maxWidth: .infinity)

                    Rectangle()
                        .fill(Color.white.opacity(0.10))
                        .frame(width: 1, height: 34)

                    VStack(spacing: 3) {
                        Text("Sunset")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(context.weather?.sunsetText ?? "—")
                            .font(.subheadline.monospacedDigit().weight(.bold))
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(15)
            .frame(maxWidth: .infinity)
            .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
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

    private var weatherDetailsCard: some View {
        let weather = context.weather

        return VStack(spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Weather")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Color.cyan.opacity(0.72))
                    Text(weather?.description ?? "Checking conditions…")
                        .font(.title3.weight(.bold))
                }

                Spacer()

                Text(weather.map { "\($0.temperature)°C" } ?? "—°")
                    .font(.system(size: 31, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(Color.cyan.opacity(0.94))
            }

            Rectangle()
                .fill(Color.white.opacity(0.08))
                .frame(height: 1)

            HStack(spacing: 0) {
                weatherMetric("Rain", value: weather?.rainProbability.map { "\($0)%" } ?? "—")
                metricDivider
                weatherMetric("Feels", value: weather?.apparentTemperature.map { "\($0)°" } ?? "—")
                metricDivider
                weatherMetric("Humidity", value: weather?.humidity.map { "\($0)%" } ?? "—")
                metricDivider
                weatherMetric("Wind", value: weather?.windSpeed.map { "\($0) km/h" } ?? "—")
            }

            Rectangle()
                .fill(Color.white.opacity(0.08))
                .frame(height: 1)

            VStack(alignment: .leading, spacing: 5) {
                Text(weather?.nextRainText ?? "Checking rain outlook…")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(rainAccent(weather))
                    .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 8) {
                    if let precipitation = weather?.precipitation {
                        Text(String(format: "Precipitation %.1f mm", precipitation))
                    }
                    if let peak = weather?.peakRainProbability {
                        Text("•")
                        Text("Peak rain chance \(peak)%")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(15)
        .background(Color.white.opacity(0.065), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.cyan.opacity(0.07), lineWidth: 1)
        )
    }

    private func weatherMetric(_ title: String, value: String) -> some View {
        VStack(spacing: 3) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption.monospacedDigit().weight(.bold))
                .foregroundStyle(.white.opacity(0.90))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity)
    }

    private var metricDivider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.08))
            .frame(width: 1, height: 30)
    }

    private func rainAccent(_ weather: MXWorldWeather?) -> Color {
        guard let probability = weather?.rainProbability else { return Color.white.opacity(0.72) }
        if probability >= 70 { return Color.blue.opacity(0.95) }
        if probability >= 35 { return Color.cyan.opacity(0.90) }
        return Color.mint.opacity(0.86)
    }

    private func periodColor(_ period: String) -> Color {
        switch period {
        case "Morning": return Color.orange.opacity(0.92)
        case "Afternoon": return Color.yellow.opacity(0.92)
        case "Evening": return Color(red: 1.0, green: 0.58, blue: 0.22)
        default: return Color(red: 0.42, green: 0.61, blue: 1.0)
        }
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
}

'''
worlds.write_text(text[:details_start] + new_details + text[details_end:], encoding="utf-8")


# -----------------------------------------------------------------------------
# 4) Saved screen: remove the large navigation title so the list owns the
#    screen and gains vertical space.
# -----------------------------------------------------------------------------
replace_required(
    root_view,
    '''            .navigationTitle("Saved Worlds")\n            .navigationBarTitleDisplayMode(.large)\n''',
    '''            .toolbar(.hidden, for: .navigationBar)\n'''
)


# -----------------------------------------------------------------------------
# 5) Version bump.
# -----------------------------------------------------------------------------
project = root / "project.yml"
project_text = project.read_text(encoding="utf-8")
project_text = project_text.replace('MARKETING_VERSION: "1.4.1"', 'MARKETING_VERSION: "1.4.2"')
project_text = project_text.replace('CURRENT_PROJECT_VERSION: "28"', 'CURRENT_PROJECT_VERSION: "29"')
project.write_text(project_text, encoding="utf-8")

print("Applied MX Location v1.4.2: minimal Saved list, centered details, advanced weather, no visible photos/recent/last-used")
