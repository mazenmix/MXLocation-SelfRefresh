from pathlib import Path
import sys

root = Path(sys.argv[1]).resolve()


def replace_required(path: Path, old: str, new: str, count: int = 1) -> None:
    text = path.read_text(encoding="utf-8")
    if old not in text:
        raise RuntimeError(f"Required source fragment not found in {path}: {old[:240]!r}")
    path.write_text(text.replace(old, new, count), encoding="utf-8")


worlds = root / "Locus/Features/Map/MXWorlds.swift"

# -----------------------------------------------------------------------------
# 1) Actual place photography for World details.
#    Use Wikipedia's public page-image API: name search first, nearby geo search
#    as fallback. Never use the map snapshot as the photo fallback.
# -----------------------------------------------------------------------------
photo_anchor = '''struct MXWorldLocalClockBadge: View {\n'''
photo_code = r'''private struct MXWikipediaResponse: Decodable {
    let query: Query?

    struct Query: Decodable {
        let pages: [Page]?
    }

    struct Page: Decodable {
        let title: String?
        let thumbnail: Thumbnail?
    }

    struct Thumbnail: Decodable {
        let source: String
    }
}

@MainActor
final class MXWorldPhotoModel: ObservableObject {
    @Published var imageURL: URL?
    @Published var isLoading = false

    func load(_ place: SavedPlace) async {
        isLoading = true
        defer { isLoading = false }

        if let byName = await fetchByName(place.name) {
            imageURL = byName
            return
        }
        imageURL = await fetchNearby(place.coordinate)
    }

    private func fetchByName(_ name: String) async -> URL? {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return nil }

        var components = URLComponents(string: "https://en.wikipedia.org/w/api.php")!
        components.queryItems = [
            URLQueryItem(name: "action", value: "query"),
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "formatversion", value: "2"),
            URLQueryItem(name: "generator", value: "search"),
            URLQueryItem(name: "gsrsearch", value: clean),
            URLQueryItem(name: "gsrnamespace", value: "0"),
            URLQueryItem(name: "gsrlimit", value: "8"),
            URLQueryItem(name: "prop", value: "pageimages"),
            URLQueryItem(name: "piprop", value: "thumbnail"),
            URLQueryItem(name: "pithumbsize", value: "1400")
        ]
        return await fetchFirstImage(components.url)
    }

    private func fetchNearby(_ coordinate: CLLocationCoordinate2D) async -> URL? {
        var components = URLComponents(string: "https://en.wikipedia.org/w/api.php")!
        components.queryItems = [
            URLQueryItem(name: "action", value: "query"),
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "formatversion", value: "2"),
            URLQueryItem(name: "generator", value: "geosearch"),
            URLQueryItem(name: "ggscoord", value: "\(coordinate.latitude)|\(coordinate.longitude)"),
            URLQueryItem(name: "ggsradius", value: "10000"),
            URLQueryItem(name: "ggslimit", value: "15"),
            URLQueryItem(name: "ggsnamespace", value: "0"),
            URLQueryItem(name: "prop", value: "pageimages"),
            URLQueryItem(name: "piprop", value: "thumbnail"),
            URLQueryItem(name: "pithumbsize", value: "1400")
        ]
        return await fetchFirstImage(components.url)
    }

    private func fetchFirstImage(_ url: URL?) async -> URL? {
        guard let url else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 8
        request.setValue("MXLocation/1.4.1", forHTTPHeaderField: "User-Agent")

        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let response = try? JSONDecoder().decode(MXWikipediaResponse.self, from: data),
              let pages = response.query?.pages else {
            return nil
        }

        return pages
            .compactMap { $0.thumbnail?.source }
            .compactMap(URL.init(string:))
            .first
    }
}

struct MXWorldPlacePhoto: View {
    let place: SavedPlace
    @StateObject private var model = MXWorldPhotoModel()

    var body: some View {
        ZStack {
            if let url = model.imageURL {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    case .failure:
                        placeholder
                    default:
                        ZStack {
                            placeholder
                            ProgressView()
                                .tint(.white.opacity(0.85))
                        }
                    }
                }
            } else if model.isLoading {
                ZStack {
                    placeholder
                    ProgressView()
                        .tint(.white.opacity(0.85))
                }
            } else {
                placeholder
            }
        }
        .clipped()
        .task(id: place.id) {
            await model.load(place)
        }
    }

    private var placeholder: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.12, green: 0.20, blue: 0.34),
                    Color(red: 0.18, green: 0.11, blue: 0.28)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            VStack(spacing: 7) {
                Image(systemName: "photo.fill")
                    .font(.system(size: 27, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.72))
                Text(place.name)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.70))
                    .lineLimit(1)
            }
        }
    }
}

struct MXWorldLocalClockBadge: View {
'''
replace_required(worlds, photo_anchor, photo_code)


# -----------------------------------------------------------------------------
# 2) Saved Worlds list: no thumbnails, no automatic flags, and show the user's
#    note instead of Last Used. World Details stays available in the ellipsis.
# -----------------------------------------------------------------------------
text = worlds.read_text(encoding="utf-8")
start = text.index("struct MXWorldListRow: View {")
end = text.index("struct MXWorldDetailsView: View {", start)
new_row = r'''struct MXWorldListRow: View {
    let place: SavedPlace
    let onPreview: () -> Void
    let onOpenWorld: () -> Void
    let onResume: () -> Void
    let onEdit: () -> Void
    let onRemove: () -> Void

    @StateObject private var context = MXWorldContextModel()

    var body: some View {
        let metadata = MXWorldStore.metadata(for: place)
        let note = MXWorldStore.note(for: place)

        HStack(spacing: 9) {
            Button(action: onPreview) {
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(place.name)
                            .font(.headline.weight(.bold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)

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

                        Text(note.isEmpty ? "No note" : note)
                            .font(.caption2.weight(note.isEmpty ? .regular : .medium))
                            .foregroundStyle(note.isEmpty ? Color.secondary : Color.orange.opacity(0.94))
                            .lineLimit(2)
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
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
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

'''
worlds.write_text(text[:start] + new_row + text[end:], encoding="utf-8")


# -----------------------------------------------------------------------------
# 3) World Details: replace map thumbnails with actual place photography and
#    remove all automatically generated country flags.
# -----------------------------------------------------------------------------
replace_required(
    worlds,
    '''            MXWorldMiniMap(place: place, radiusMeters: 16000)\n                .frame(height: 235)\n''',
    '''            MXWorldPlacePhoto(place: place)\n                .frame(height: 235)\n'''
)

replace_required(
    worlds,
    '''                HStack(spacing: 7) {\n                    Text(place.name.uppercased())\n                        .font(.title2.weight(.black))\n                        .lineLimit(1)\n                    Text(context.flag)\n                }\n''',
    '''                Text(place.name.uppercased())\n                    .font(.title2.weight(.black))\n                    .lineLimit(1)\n'''
)

old_recent_photo = '''                                MXWorldMiniMap(\n                                    place: SavedPlace(name: point.name, latitude: point.latitude, longitude: point.longitude),\n                                    radiusMeters: 5000\n                                )\n                                .frame(height: 72)\n                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))\n'''
new_recent_photo = '''                                MXWorldPlacePhoto(\n                                    place: SavedPlace(name: point.name, latitude: point.latitude, longitude: point.longitude)\n                                )\n                                .frame(height: 72)\n                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))\n'''
replace_required(worlds, old_recent_photo, new_recent_photo)

replace_required(
    worlds,
    '''                MXWorldMiniMap(place: preview, radiusMeters: 6500)\n                    .frame(height: 190)\n                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))\n''',
    '''                MXWorldPlacePhoto(place: preview)\n                    .frame(height: 190)\n                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))\n'''
)

# Remove the automatic flag helper entirely so future UI additions cannot
# accidentally reintroduce country flags without an explicit user note.
text = worlds.read_text(encoding="utf-8")
flag_block = '''    var flag: String {\n        guard let code = countryCode, code.count == 2 else { return "🌐" }\n        return code.uppercased().unicodeScalars.compactMap {\n            UnicodeScalar(127397 + $0.value)\n        }.map(String.init).joined()\n    }\n\n'''
if flag_block in text:
    text = text.replace(flag_block, "", 1)
worlds.write_text(text, encoding="utf-8")


# -----------------------------------------------------------------------------
# 4) Version bump.
# -----------------------------------------------------------------------------
project = root / "project.yml"
project_text = project.read_text(encoding="utf-8")
project_text = project_text.replace('MARKETING_VERSION: "1.4.0"', 'MARKETING_VERSION: "1.4.1"')
project_text = project_text.replace('CURRENT_PROJECT_VERSION: "27"', 'CURRENT_PROJECT_VERSION: "28"')
project.write_text(project_text, encoding="utf-8")

print("Applied MX Location v1.4.1: clean Saved Worlds, note rows, real place photos, no auto flags")
