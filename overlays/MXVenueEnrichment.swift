import SwiftUI
import MapKit
import CoreLocation
import UIKit
import ImageIO

// Unverified search-engine pictures can easily depict the wrong business.
// Only images explicitly tagged against a matching OpenStreetMap business are
// treated as "venue photos". Look Around is clearly marked "Nearby street view"
// and a map snapshot is marked "Map preview".
struct MXVenueVisual: Identifiable {
    let id: String
    let image: UIImage
    let label: String
    let source: URL?
}

struct MXVenueOpenProfile {
    var photoURLs: [URL] = []
    var site: URL?
    var facebook: URL?
    var instagram: URL?
    var whatsapp: URL?
    var phone: String?
    var email: String?
    var verifiedOSMMatch = false

    static func officialURL(_ value: String?) -> URL? {
        guard let text = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty else { return nil }
        let prefixed = text.lowercased().hasPrefix("https://") ? text :
                       text.lowercased().hasPrefix("www.") ? "https://" + text : text
        guard let url = URL(string: prefixed), url.scheme == "https",
              url.host != nil else { return nil }
        return url
    }

    static func contactPage(_ value: String?, domain: String) -> URL? {
        guard let raw = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty else { return nil }
        if let url = officialURL(raw) { return url }
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_./-")
        guard raw.unicodeScalars.allSatisfy({ allowed.contains($0) }) else { return nil }
        return URL(string: "https://www." + domain + "/" + raw)
    }

    static func whatsappURL(_ value: String?) -> URL? {
        if let link = officialURL(value), link.host?.contains("wa.me") == true ||
           link.host?.contains("whatsapp.com") == true { return link }
        let digits = (value ?? "").filter(\.isNumber)
        guard digits.count >= 9, digits.count <= 15 else { return nil }
        return URL(string: "https://wa.me/" + digits)
    }
}

enum MXVenueOpenData {
    private static func normalized(_ s: String) -> String {
        s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
            .filter { $0.isLetter || $0.isNumber || $0.isWhitespace }
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    // Network requests are optional and brief. We never invent contact details.
    static func lookup(_ item: MKMapItem) async -> MXVenueOpenProfile {
        var profile = MXVenueOpenProfile()
        profile.site = item.url.flatMap { MXVenueOpenProfile.officialURL($0.absoluteString) }
        profile.phone = item.phoneNumber
        guard let name = item.name, !name.isEmpty else { return profile }
        let p = item.placemark.coordinate
        let q = String(format:
            "[out:json][timeout:7];nwr(around:130,%.6f,%.6f)[\"name\"];out center 50;",
            p.latitude, p.longitude)
        var comps = URLComponents(string: "https://overpass.kumi.systems/api/interpreter")
        comps?.queryItems = [URLQueryItem(name: "data", value: q)]
        guard let url = comps?.url else { return profile }
        var req = URLRequest(url: url)
        req.timeoutInterval = 10
        req.setValue("MX Location Pro Venue Info/4.8 (OpenStreetMap verified listing)", forHTTPHeaderField: "User-Agent")
        guard let (data, response) = try? await URLSession.shared.data(for: req),
              (response as? HTTPURLResponse)?.statusCode == 200,
              data.count < 1_500_000,
              let dict = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let entries = dict["elements"] as? [[String: Any]] else { return profile }

        for entry in entries {
            guard let tags = entry["tags"] as? [String: String],
                  let found = tags["name"],
                  normalized(found) == normalized(name) else { continue }
            let center = entry["center"] as? [String: Double]
            let lat = (entry["lat"] as? Double) ?? center?["lat"]
            let lon = (entry["lon"] as? Double) ?? center?["lon"]
            guard let lat, let lon, CLLocation(latitude: lat, longitude: lon)
                .distance(from: CLLocation(latitude: p.latitude, longitude: p.longitude)) <= 130 else { continue }

            profile.verifiedOSMMatch = true
            profile.site = profile.site ?? MXVenueOpenProfile.officialURL(tags["contact:website"] ?? tags["website"])
            profile.phone = profile.phone ?? tags["contact:phone"] ?? tags["phone"]
            profile.email = tags["contact:email"] ?? tags["email"]
            profile.facebook = MXVenueOpenProfile.contactPage(tags["contact:facebook"] ?? tags["facebook"], domain: "facebook.com")
            profile.instagram = MXVenueOpenProfile.contactPage(tags["contact:instagram"] ?? tags["instagram"], domain: "instagram.com")
            profile.whatsapp = MXVenueOpenProfile.whatsappURL(tags["contact:whatsapp"] ?? tags["whatsapp"])

            for raw in (tags["image"] ?? "").split(separator: ";").prefix(3) {
                let string = String(raw).trimmingCharacters(in: .whitespaces)
                if let url = MXVenueOpenProfile.officialURL(string) {
                    profile.photoURLs.append(url)
                } else if string.hasPrefix("File:") {
                    let path = String(string.dropFirst(5))
                    if let escaped = path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
                       let url = URL(string: "https://commons.wikimedia.org/wiki/Special:FilePath/" + escaped) {
                        profile.photoURLs.append(url)
                    }
                }
            }
            if let commons = tags["wikimedia_commons"], commons.hasPrefix("File:"),
               let escaped = String(commons.dropFirst(5)).addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
               let url = URL(string: "https://commons.wikimedia.org/wiki/Special:FilePath/" + escaped) {
                profile.photoURLs.append(url)
            }
            break
        }
        return profile
    }

    static func photo(_ url: URL) async -> UIImage? {
        guard url.scheme == "https" else { return nil }
        var req = URLRequest(url: url)
        req.timeoutInterval = 9
        req.setValue("MXLocationPro/4.8", forHTTPHeaderField: "User-Agent")
        guard let (data, response) = try? await URLSession.shared.data(for: req),
              (response as? HTTPURLResponse)?.statusCode == 200,
              data.count < 7_000_000 else { return nil }
        // Decode a capped-size bitmap for smooth scrolling and bounded memory;
        // original multi-megapixel site images could otherwise exhaust RAM.
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 1200
        ]
        guard let reduced = CGImageSourceCreateThumbnailAtIndex(
            source, 0, options as CFDictionary
        ) else { return nil }
        return UIImage(cgImage: reduced)
    }

    static func streetView(_ coordinate: CLLocationCoordinate2D) async -> UIImage? {
        guard let scene = try? await MKLookAroundSceneRequest(coordinate: coordinate).scene else { return nil }
        let options = MKLookAroundSnapshotter.Options()
        options.size = CGSize(width: 850, height: 540)
        let snapshotter = MKLookAroundSnapshotter(scene: scene, options: options)
        let snapshot = try? await snapshotter.snapshot
        return snapshot?.image
    }

    static func mapPreview(_ coordinate: CLLocationCoordinate2D) async -> UIImage? {
        let opts = MKMapSnapshotter.Options()
        opts.size = CGSize(width: 850, height: 540)
        opts.region = MKCoordinateRegion(
            center: coordinate, latitudinalMeters: 550, longitudinalMeters: 550
        )
        opts.mapType = .standard
        // Explicit light appearance makes this real geographic preview legible
        // even though the app's chrome uses a dark color scheme.
        opts.traitCollection = UITraitCollection(userInterfaceStyle: .light)
        return try? await MKMapSnapshotter(options: opts).start().image
    }
}

// A venue-photo gallery: only pictures from the venue's own site or an
// exact-name / coordinate OpenStreetMap record. Never show map screenshots.
struct MXVenuePhotoGallery: View {
    let item: MKMapItem
    @ObservedObject private var library = MXVenuePhotoLibrary.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color(red: 0.12, green: 0.19, blue: 0.30))
                if !library.pictures(item).isEmpty {
                    TabView {
                        ForEach(library.pictures(item)) { photo in
                            ZStack(alignment: .bottomLeading) {
                                Image(uiImage: photo.image)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                                    .clipped()
                                HStack(spacing: 7) {
                                    Image(systemName: "checkmark.seal")
                                    Text(photo.label)
                                    Spacer(minLength: 0)
                                    if let source = photo.source {
                                        Link("Source ↗", destination: source)
                                    }
                                }
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 12)
                                .frame(height: 42)
                                .background(.black.opacity(0.75))
                            }
                            .clipShape(RoundedRectangle(cornerRadius: 20))
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: .automatic))
                    .accessibilityIdentifier("mxRealVenueSwipeGallery")
                } else if library.didCheck(item) {
                    VStack(spacing: 10) {
                        Image(systemName: "photo.on.rectangle.angled")
                            .font(.system(size: 29, weight: .light))
                            .foregroundStyle(.white.opacity(0.7))
                        Text("No confirmed photos for this venue")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                        Text("We won't substitute a street map or another business's pictures.")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.64))
                            .multilineTextAlignment(.center)
                        if let website = item.url, website.scheme == "https" {
                            Link("Check the venue's website ↗", destination: website)
                                .font(.caption.weight(.semibold))
                        }
                    }
                    .padding(.horizontal, 25)
                } else {
                    VStack(spacing: 10) {
                        ProgressView().tint(.white)
                        Text("Finding actual venue photos…")
                            .font(.caption).foregroundStyle(.white.opacity(0.7))
                    }
                }
            }
            .frame(height: 230)
            .clipShape(RoundedRectangle(cornerRadius: 20))

            if !library.pictures(item).isEmpty {
                Text("Swipe for more • Photos supplied by the venue website or matching public venue records.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
        .task(id: MXVenuePhotoSource.key(item)) { library.load(item) }
    }
}

struct MXVenueContactDetails: View {
    let item: MKMapItem
    @State private var profile = MXVenueOpenProfile()
    @State private var wasCopied = false

    private var coordinates: String {
        let p = item.placemark.coordinate
        return String(format: "%.6f, %.6f", p.latitude, p.longitude)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            Label("Contact & official links", systemImage: "link.circle.fill")
                .font(.headline).foregroundStyle(.white)
            if let website = profile.site {
                Link(destination: website) {
                    Label("Official website", systemImage: "globe")
                }
            }
            if let facebook = profile.facebook {
                Link(destination: facebook) {
                    Label("Facebook page", systemImage: "person.2")
                }
            }
            if let instagram = profile.instagram {
                Link(destination: instagram) {
                    Label("Instagram", systemImage: "camera")
                }
            }
            if let whatsapp = profile.whatsapp {
                Link(destination: whatsapp) {
                    Label("WhatsApp", systemImage: "message")
                }
            }
            if let phone = profile.phone {
                let cleaned = phone.filter { $0.isNumber || $0 == "+" }
                if let url = URL(string: "tel:" + cleaned), !cleaned.isEmpty {
                    Link(destination: url) {
                        Label(phone, systemImage: "phone.arrow.up.right")
                    }
                }
            }
            if let email = profile.email,
               let mailto = URL(string: "mailto:" + email.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!) {
                Link(destination: mailto) {
                    Label(email, systemImage: "envelope")
                }
            }
            if profile.site == nil && profile.phone == nil && profile.facebook == nil &&
               profile.instagram == nil && profile.whatsapp == nil && profile.email == nil {
                Text("No verified website or contact details were supplied for this business.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }

            Divider().overlay(.white.opacity(0.1))
            Text("GPS coordinates")
                .font(.headline).foregroundStyle(.white)
            HStack(spacing: 12) {
                Text(coordinates)
                    .font(.system(.subheadline, design: .monospaced))
                    .textSelection(.enabled)
                    .foregroundStyle(.white)
                Spacer(minLength: 0)
                Button {
                    UIPasteboard.general.string = coordinates
                    wasCopied = true
                } label: {
                    Label(wasCopied ? "Copied" : "Copy", systemImage: wasCopied ? "checkmark" : "doc.on.doc")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("mxCopyLatLong")
            }
            Link(destination: URL(string: "https://www.google.com/maps/search/?api=1&query=\(item.placemark.coordinate.latitude),\(item.placemark.coordinate.longitude)")!) {
                Label("Open coordinates in Google Maps", systemImage: "arrow.up.right.square")
            }
            Text("Contact fields come from Apple Maps and matching public OpenStreetMap tags. Missing fields aren't guessed.")
                .font(.caption2).foregroundStyle(.secondary)
        }
        .tint(MXPremiumStyle.cyan)
        .task {
            profile = await MXVenueOpenData.lookup(item)
        }
    }
}
