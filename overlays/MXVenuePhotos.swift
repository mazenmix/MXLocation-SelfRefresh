import SwiftUI
import MapKit
import UIKit
import CoreLocation
import ImageIO

// Only use photographs explicitly tied to the matching OpenStreetMap entry or
// published by the venue's own website. Never turn a map/street snapshot or a
// generic stock picture into an alleged photograph of the business.
enum MXVenuePhotoSource {
    static func key(_ item: MKMapItem) -> String {
        let p = item.placemark.coordinate
        // Switching or replacing a Google Places key retries venues immediately.
        let keyRevision = (UserDefaults.standard.string(forKey: "mx_places_photo_api_key") ?? "").hashValue
        return String(format: "%@|%.5f|%.5f|%d", item.name ?? "", p.latitude, p.longitude, keyRevision)
    }

    // Independent source pipelines: publish website imagery as soon as it arrives,
    // without waiting for slow OpenStreetMap queries to finish.
    static func websitePictures(for item: MKMapItem) async -> [MXVenueVisual] {
        guard let official = item.url.flatMap({ MXVenueOpenProfile.officialURL($0.absoluteString) }),
              let host = official.host?.lowercased(),
              !host.contains("maps.apple.com"), !host.contains("google.com/maps")
        else { return [] }
        return await imagesFromWebsite(official, label: "Image · venue's official website")
    }

    static func osmPictures(for item: MKMapItem) async -> [MXVenueVisual] {
        let profile = await MXVenueOpenData.lookup(item)
        var pictures: [MXVenueVisual] = []
        for (index, url) in profile.photoURLs.prefix(2).enumerated() {
            if let image = await MXVenueOpenData.photo(url) {
                pictures.append(MXVenueVisual(id: "osm-\(index)-\(url.absoluteString)",
                    image: image, label: "Image · verified OpenStreetMap listing", source: url))
            }
        }
        // Wikidata item is accepted ONLY when inherited from an exact-name,
        // nearby OpenStreetMap venue. Never match an image by broad text search.
        if pictures.isEmpty, let id = profile.wikidataID {
            pictures += await wikidataPictures(id)
        }
        if item.url == nil, let site = profile.site {
            pictures += await imagesFromWebsite(site, label: "Image · venue's official website")
        }
        return pictures
    }

    // Opt-in Google Places Photos (New) provider. Never put API keys into a
    // public build or GitHub source. The owner adds their own key in Settings.
    // Match BOTH normalized business name and location before accepting photos.
    // Google Places API calls can be billable.
    static func googlePlacesPictures(for item: MKMapItem) async -> [MXVenueVisual] {
        let apiKey = (UserDefaults.standard.string(forKey: "mx_places_photo_api_key") ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !apiKey.isEmpty, let name = item.name, !name.isEmpty else { return [] }
        let coordinate = item.placemark.coordinate
        let addr = item.placemark.title ?? ""
        let search = name + ", " + addr
        let payload: [String: Any] = [
            "textQuery": search,
            "locationBias": [
                "circle": [
                    "center": ["latitude": coordinate.latitude,
                               "longitude": coordinate.longitude],
                    "radius": 300.0
                ]
            ],
            "maxResultCount": 5
        ]
        guard let requestData = try? JSONSerialization.data(withJSONObject: payload),
              let url = URL(string: "https://places.googleapis.com/v1/places:searchText")
        else { return [] }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.httpBody = requestData
        req.timeoutInterval = 8
        req.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        req.setValue(apiKey, forHTTPHeaderField: "X-Goog-Api-Key")
        req.setValue("places.id,places.displayName,places.location,places.photos", forHTTPHeaderField: "X-Goog-FieldMask")
        guard let (data, response) = try? await URLSession.shared.data(for: req),
              (response as? HTTPURLResponse)?.statusCode == 200,
              data.count < 750_000,
              let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let matches = root["places"] as? [[String: Any]] else { return [] }

        func normalized(_ text: String) -> String {
            text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
                .lowercased()
                .filter { $0.isLetter || $0.isNumber || $0.isWhitespace }
                .split(whereSeparator: \.isWhitespace)
                .joined(separator: " ")
        }
        let originalName = normalized(name)
        for match in matches {
            guard let displayName = match["displayName"] as? [String: Any],
                  let foundName = displayName["text"] as? String,
                  normalized(foundName) == originalName,
                  let geo = match["location"] as? [String: Any],
                  let lat = geo["latitude"] as? Double,
                  let lng = geo["longitude"] as? Double,
                  CLLocation(latitude: lat, longitude: lng).distance(
                      from: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
                  ) <= 180,
                  let photos = match["photos"] as? [[String: Any]],
                  !photos.isEmpty else { continue }
            let placeID = match["id"] as? String ?? ""
            let googleMapsLink = URLComponents(string: "https://www.google.com/maps/search/").flatMap { base -> URL? in
                var result = base
                result.queryItems = [
                    URLQueryItem(name: "api", value: "1"),
                    URLQueryItem(name: "query", value: name),
                    URLQueryItem(name: "query_place_id", value: placeID)
                ]
                return result.url
            }
            var pictures: [MXVenueVisual] = []
            for (index, entry) in photos.prefix(5).enumerated() {
                guard let resource = entry["name"] as? String,
                      resource.hasPrefix("places/"),
                      let media = URL(string: "https://places.googleapis.com/v1/" + resource + "/media?maxWidthPx=1000") else { continue }
                var imageReq = URLRequest(url: media)
                imageReq.timeoutInterval = 9
                imageReq.setValue(apiKey, forHTTPHeaderField: "X-Goog-Api-Key")
                guard let (bytes, imageResponse) = try? await URLSession.shared.data(for: imageReq),
                      (imageResponse as? HTTPURLResponse)?.statusCode == 200,
                      bytes.count < 7_000_000,
                      let source = CGImageSourceCreateWithData(bytes as CFData, nil) else { continue }
                let options: [CFString: Any] = [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: 1000
                ]
                guard let reduced = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
                else { continue }
                let authors = (entry["authorAttributions"] as? [[String: Any]] ?? [])
                    .compactMap { $0["displayName"] as? String }
                    .filter { !$0.isEmpty }
                    .joined(separator: ", ")
                let label = authors.isEmpty ? "Photo · Google Places" : "Photo · Google Places · " + authors
                pictures.append(MXVenueVisual(id: "google-\(placeID)-\(index)",
                   image: UIImage(cgImage: reduced), label: label, source: googleMapsLink))
            }
            return pictures
        }
        return []
    }

    // The linked Wikidata P18 image is a second, free, identity-verified source.
    // No random nearby photos, street screenshots or unrelated search thumbnails.
    private static func wikidataPictures(_ id: String) async -> [MXVenueVisual] {
        var components = URLComponents(string: "https://www.wikidata.org/w/api.php")
        components?.queryItems = [
            URLQueryItem(name: "action", value: "wbgetclaims"),
            URLQueryItem(name: "entity", value: id),
            URLQueryItem(name: "property", value: "P18"),
            URLQueryItem(name: "format", value: "json")
        ]
        guard let url = components?.url else { return [] }
        var request = URLRequest(url: url)
        request.timeoutInterval = 5
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              data.count < 700_000,
              let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let claims = root["claims"] as? [String: Any],
              let images = claims["P18"] as? [[String: Any]] else { return [] }
        for claim in images.prefix(2) {
            guard let snak = claim["mainsnak"] as? [String: Any],
                  let dataValue = snak["datavalue"] as? [String: Any],
                  let filename = dataValue["value"] as? String, !filename.isEmpty,
                  let escaped = filename.replacingOccurrences(of: " ", with: "_")
                      .addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
                  let file = URL(string: "https://commons.wikimedia.org/wiki/Special:FilePath/" + escaped),
                  let bitmap = await MXVenueOpenData.photo(file) else { continue }
            return [MXVenueVisual(
                id: "wikidata-\(id)-\(filename)",
                image: bitmap,
                label: "Image · verified venue-linked Wikimedia",
                source: URL(string: "https://commons.wikimedia.org/wiki/File:" + escaped)
            )]
        }
        return []
    }

    private static func imagesFromWebsite(_ url: URL, label: String) async -> [MXVenueVisual] {
        guard let host = url.host?.lowercased(),
              !host.contains("facebook.com"), !host.contains("instagram.com"),
              !host.contains("tiktok.com"), !host.contains("google.com") else { return [] }
        var request = URLRequest(url: url)
        request.timeoutInterval = 5
        request.setValue("text/html", forHTTPHeaderField: "Accept")
        guard let (bytes, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              bytes.count < 2_000_000,
              let html = String(data: bytes, encoding: .utf8) else { return [] }

        let candidates = metadataImages(html, pageURL: url)
        var result: [MXVenueVisual] = []
        for candidate in candidates.prefix(2) {
            if let image = await MXVenueOpenData.photo(candidate) {
                result.append(MXVenueVisual(id: candidate.absoluteString, image: image,
                                            label: label, source: url))
            }
            if result.count == 2 { break }
        }
        return result
    }

    private static func metadataImages(_ html: String, pageURL: URL) -> [URL] {
        guard let tags = try? NSRegularExpression(pattern: #"<meta\b[^>]*>"#,
                                                  options: [.caseInsensitive]),
              let attributes = try? NSRegularExpression(
                pattern: #"\b([a-zA-Z][\w:-]*)\s*=\s*["']([^"']+)["']"#,
                options: [.caseInsensitive]) else { return [] }
        let length = (html as NSString).length
        var urls: [URL] = []
        let keys: Set<String> = [
            "og:image", "og:image:url", "og:image:secure_url",
            "twitter:image", "twitter:image:src", "image"
        ]
        for match in tags.matches(in: html, range: NSRange(location: 0, length: length)).prefix(140) {
            let tag = (html as NSString).substring(with: match.range)
            let matches = attributes.matches(in: tag,
                range: NSRange(location: 0, length: (tag as NSString).length))
            var props: [String: String] = [:]
            for a in matches where a.numberOfRanges == 3 {
                props[(tag as NSString).substring(with: a.range(at: 1)).lowercased()] =
                    (tag as NSString).substring(with: a.range(at: 2))
            }
            let kind = (props["property"] ?? props["name"] ?? props["itemprop"] ?? "").lowercased()
            guard keys.contains(kind), let raw = props["content"] else { continue }
            let expanded = raw.replacingOccurrences(of: "&amp;", with: "&")
                              .replacingOccurrences(of: "&#38;", with: "&")
                              .replacingOccurrences(of: "&quot;", with: "\"")
            guard let imageURL = URL(string: expanded, relativeTo: pageURL)?.absoluteURL,
                  imageURL.scheme?.lowercased() == "https",
                  imageURL.host != nil else { continue }
            let path = imageURL.path.lowercased()
            if ["logo", "favicon", "placeholder", "default-avatar", "no-image", "sprite"]
                .contains(where: path.contains) { continue }
            if !urls.contains(imageURL) { urls.append(imageURL) }
        }
        return urls
    }
}

actor MXVenuePhotoLimiter {
    static let shared = MXVenuePhotoLimiter()
    private var active = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []
    func enter() async {
        if active < 3 {
            active += 1
        } else {
            await withCheckedContinuation { waiters.append($0) }
        }
    }
    func leave() {
        if waiters.isEmpty {
            active = max(0, active - 1)
        } else {
            waiters.removeFirst().resume()
        }
    }
}


actor MXVenuePreviewLimiter {
    static let shared = MXVenuePreviewLimiter()
    private var active = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []
    func enter() async {
        if active < 3 { active += 1 }
        else { await withCheckedContinuation { waiters.append($0) } }
    }
    func leave() {
        if waiters.isEmpty { active = max(0, active - 1) }
        else { waiters.removeFirst().resume() }
    }
}

@MainActor
final class MXVenuePhotoLibrary: ObservableObject {
    static let shared = MXVenuePhotoLibrary()
    @Published private(set) var images: [String: [MXVenueVisual]] = [:]
    @Published private(set) var checked: Set<String> = []
    private var inFlight: Set<String> = []
    private var priorityRequests: Set<String> = []
    private var lastAttempted: [String: Date] = [:]
    @Published private(set) var mapPreviews: [String: UIImage] = [:]
    private var previewInFlight: Set<String> = []

    func mapPreview(_ item: MKMapItem) -> UIImage? {
        mapPreviews[MXVenuePhotoSource.key(item)]
    }

    // Real imagery of the exact geographic point, explicitly labelled as a
    // satellite preview. This is not misrepresented as a venue photograph.
    func loadMapPreview(_ item: MKMapItem, priority: Bool = false) {
        let key = MXVenuePhotoSource.key(item)
        guard mapPreviews[key] == nil, !previewInFlight.contains(key) else { return }
        previewInFlight.insert(key)
        Task { @MainActor in
            if !priority { await MXVenuePreviewLimiter.shared.enter() }
            let point = item.placemark.coordinate
            let opts = MKMapSnapshotter.Options()
            opts.size = CGSize(width: 620, height: 390)
            opts.region = MKCoordinateRegion(center: point, latitudinalMeters: 260,
                                             longitudinalMeters: 260)
            opts.mapType = .satellite
            opts.traitCollection = UITraitCollection(userInterfaceStyle: .light)
            let snapshotter = MKMapSnapshotter(options: opts)
            if let snapshot = try? await snapshotter.start() {
                mapPreviews[key] = snapshot.image
            } else {
                opts.mapType = .standard
                if let map = try? await MKMapSnapshotter(options: opts).start() {
                    mapPreviews[key] = map.image
                }
            }
            if !priority { await MXVenuePreviewLimiter.shared.leave() }
            previewInFlight.remove(key)
        }
    }


    // A missing or slow photo source must never block the view indefinitely.
    // The seven-second UI deadline affects the spinner only: source fetching
    // continues independently and real pictures replace the missing state if
    // they subsequently arrive.
    private func armUIWatchdog(for key: String) {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 7_000_000_000)
            if images[key, default: []].isEmpty {
                checked.insert(key)
            }
        }
    }

    private func add(_ photos: [MXVenueVisual], for key: String) {
        guard !photos.isEmpty else { return }
        var existing = images[key, default: []]
        let known = Set(existing.map(\.id))
        existing.append(contentsOf: photos.filter { !known.contains($0.id) })
        images[key] = Array(existing.prefix(6))
        checked.insert(key)
    }

    func load(_ item: MKMapItem, priority: Bool = false) {
        let key = MXVenuePhotoSource.key(item)
        loadMapPreview(item, priority: priority)
        if inFlight.contains(key) {
            // The user opened Place Details while the same card was queued
            // behind many other results. Its own request gets priority.
            if priority && !priorityRequests.contains(key) && images[key, default: []].isEmpty {
                priorityRequests.insert(key)
                Task { @MainActor in
                    await loadSources(item, key: key)
                    priorityRequests.remove(key)
                }
            }
            return
        }
        // A temporary network failure must not permanently block this venue.
        // Retry an empty result after ten minutes, without spamming photo APIs.
        if checked.contains(key) {
            guard images[key, default: []].isEmpty,
                  Date().timeIntervalSince(lastAttempted[key] ?? .distantPast) >= 600
            else { return }
        }
        checked.remove(key)
        lastAttempted[key] = Date()
        inFlight.insert(key)
        armUIWatchdog(for: key)
        Task { @MainActor in
            if !priority { await MXVenuePhotoLimiter.shared.enter() }
            await loadSources(item, key: key)
            if !priority { await MXVenuePhotoLimiter.shared.leave() }
            inFlight.remove(key)
        }
    }

    private func loadSources(_ item: MKMapItem, key: String) async {
        // Publish the first valid source as soon as it finishes. This avoids
        // waiting for another independent website or OSM endpoint.
        await withTaskGroup(of: [MXVenueVisual].self) { group in
            group.addTask { await MXVenuePhotoSource.websitePictures(for: item) }
            group.addTask { await MXVenuePhotoSource.osmPictures(for: item) }
            group.addTask { await MXVenuePhotoSource.googlePlacesPictures(for: item) }
            for await photos in group {
                add(photos, for: key)
            }
        }
        checked.insert(key)
    }

    func pictures(_ item: MKMapItem) -> [MXVenueVisual] {
        images[MXVenuePhotoSource.key(item)] ?? []
    }

    func didCheck(_ item: MKMapItem) -> Bool {
        checked.contains(MXVenuePhotoSource.key(item))
    }
}

// The preview is a *real venue/venue-site* image or a transparent missing state.
// Never show a street map or a moon glyph in a place's picture slot.
struct MXVenueRealThumbnail: View {
    let item: MKMapItem
    @ObservedObject private var library = MXVenuePhotoLibrary.shared

    var body: some View {
        ZStack {
            Color(red: 0.13, green: 0.19, blue: 0.29)
            if let photo = library.pictures(item).first {
                Image(uiImage: photo.image)
                    .resizable()
                    .scaledToFill()
                    .accessibilityLabel(photo.label)
            } else if let preview = library.mapPreview(item) {
                Image(uiImage: preview)
                    .resizable()
                    .scaledToFill()
                    .overlay(alignment: .bottomLeading) {
                        Text("SATELLITE · LOCATION")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(5)
                            .background(.black.opacity(0.65), in: RoundedRectangle(cornerRadius: 4))
                            .padding(5)
                    }
            } else if library.didCheck(item) {
                Image(systemName: "mappin.and.ellipse")
                    .font(.system(size: 28, weight: .medium))
                    .foregroundStyle(.white.opacity(0.7))
            } else {
                ProgressView().tint(.white.opacity(0.8))
            }
        }
        .clipped()
        .task(id: MXVenuePhotoSource.key(item)) {
            library.load(item)
        }
        .accessibilityIdentifier("mxVerifiedVenueThumbnail")
    }
}
