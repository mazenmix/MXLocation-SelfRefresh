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

    static func pictures(for item: MKMapItem) async -> [MXVenueVisual] {
        var result: [MXVenueVisual] = []
        let official = item.url.flatMap { MXVenueOpenProfile.officialURL($0.absoluteString) }
        if let official {
            result += await imagesFromWebsite(official, label: "Photo · venue website")
        }

        // Public OSM tags are used only when the name and coordinates match.
        let profile = await MXVenueOpenData.lookup(item)
        for (index, url) in profile.photoURLs.prefix(4).enumerated() {
            if result.contains(where: { $0.source?.absoluteString == url.absoluteString }) { continue }
            if let img = await MXVenueOpenData.photo(url) {
                result.append(
                    MXVenueVisual(id: "osm-\(index)-\(url.absoluteString)",
                                  image: img, label: "Venue photo · OSM source", source: url)
                )
            }
        }

        if official == nil, let site = profile.site {
            result += await imagesFromWebsite(site, label: "Photo · venue website")
        }
        return Array(result.prefix(6))
    }

    private static func imagesFromWebsite(_ url: URL, label: String) async -> [MXVenueVisual] {
        guard let host = url.host?.lowercased(),
              !host.contains("facebook.com"), !host.contains("instagram.com"),
              !host.contains("tiktok.com"), !host.contains("google.com") else { return [] }
        var request = URLRequest(url: url)
        request.timeoutInterval = 7
        request.setValue("text/html", forHTTPHeaderField: "Accept")
        guard let (bytes, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              bytes.count < 2_000_000,
              let html = String(data: bytes, encoding: .utf8) else { return [] }

        let candidates = metadataImages(html, pageURL: url)
        var result: [MXVenueVisual] = []
        for candidate in candidates.prefix(5) {
            if let image = await MXVenueOpenData.photo(candidate) {
                result.append(MXVenueVisual(id: candidate.absoluteString, image: image,
                                            label: label, source: url))
            }
            if result.count == 3 { break }
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

    func load(_ item: MKMapItem) {
        let key = MXVenuePhotoSource.key(item)
        guard !checked.contains(key), !inFlight.contains(key) else { return }
        inFlight.insert(key)
        Task {
            await MXVenuePhotoLimiter.shared.enter()
            let photos = await MXVenuePhotoSource.pictures(for: item)
            await MXVenuePhotoLimiter.shared.leave()
            images[key] = photos
            checked.insert(key)
            inFlight.remove(key)
        }
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
