import SwiftUI
import MapKit
import UIKit

// Only use photographs explicitly tied to the matching OpenStreetMap entry or
// published by the venue's own website. Never turn a map/street snapshot or a
// generic stock picture into an alleged photograph of the business.
enum MXVenuePhotoSource {
    static func key(_ item: MKMapItem) -> String {
        let p = item.placemark.coordinate
        return String(format: "%@|%.5f|%.5f", item.name ?? "", p.latitude, p.longitude)
    }

    // Independent source pipelines: publish website imagery as soon as it arrives,
    // without waiting for slow OpenStreetMap queries to finish.
    static func websitePictures(for item: MKMapItem) async -> [MXVenueVisual] {
        guard let official = item.url.flatMap({ MXVenueOpenProfile.officialURL($0.absoluteString) })
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
        if item.url == nil, let site = profile.site {
            pictures += await imagesFromWebsite(site, label: "Image · venue's official website")
        }
        return pictures
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

@MainActor
final class MXVenuePhotoLibrary: ObservableObject {
    static let shared = MXVenuePhotoLibrary()
    @Published private(set) var images: [String: [MXVenueVisual]] = [:]
    @Published private(set) var checked: Set<String> = []
    private var inFlight: Set<String> = []
    private var priorityRequests: Set<String> = []

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
        guard !checked.contains(key) else { return }
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
            } else if library.didCheck(item) {
                VStack(spacing: 5) {
                    Image(systemName: "photo.badge.exclamationmark")
                        .font(.system(size: 24, weight: .light))
                    Text("No photo")
                        .font(.system(size: 10, weight: .semibold))
                }
                .foregroundStyle(.white.opacity(0.65))
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
