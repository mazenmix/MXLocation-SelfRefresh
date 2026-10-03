from pathlib import Path
import sys

root = Path(sys.argv[1]).resolve()


def replace_required(path: Path, old: str, new: str, count: int = 1) -> None:
    text = path.read_text(encoding="utf-8")
    if old not in text:
        raise RuntimeError(f"Required source fragment not found in {path}: {old[:200]!r}")
    path.write_text(text.replace(old, new, count), encoding="utf-8")


# -----------------------------------------------------------------------------
# 1) Favorites: show each favorite's local clock without adding visual clutter.
# -----------------------------------------------------------------------------
root_view = root / "Locus/Features/Map/RootView.swift"
replace_required(
    root_view,
    "import Foundation\nimport SwiftUI\nimport UIKit\n",
    "import CoreLocation\nimport Foundation\nimport SwiftUI\nimport UIKit\n",
)

old_before_menu = '''                Spacer(minLength: 8)\n\n                Menu {\n'''
new_before_menu = '''                Spacer(minLength: 8)\n\n                if segment == 0 {\n                    MXFavoriteLocalClock(coordinate: place.coordinate)\n                }\n\n                Menu {\n'''
replace_required(root_view, old_before_menu, new_before_menu)

clock_view = r'''

private struct MXFavoriteLocalClock: View {
    let coordinate: CLLocationCoordinate2D
    @State private var timeZone: TimeZone?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            HStack(spacing: 4) {
                Image(systemName: "clock")
                    .font(.system(size: 10, weight: .semibold))
                Text(timeText(for: context.date))
                    .font(.caption2.monospacedDigit().weight(.semibold))
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .frame(height: 27)
            .background(Color.white.opacity(0.055), in: Capsule())
            .overlay(Capsule().stroke(Color.white.opacity(0.055), lineWidth: 1))
        }
        .task(id: "\(coordinate.latitude),\(coordinate.longitude)") {
            await resolveTimeZone()
        }
        .accessibilityLabel("Local time \(timeText(for: Date()))")
    }

    private func timeText(for date: Date) -> String {
        guard let timeZone else { return "--:--" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    private func resolveTimeZone() async {
        let geocoder = CLGeocoder()
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        let placemarks = try? await geocoder.reverseGeocodeLocation(location)
        guard !Task.isCancelled else { return }
        await MainActor.run {
            timeZone = placemarks?.first?.timeZone
        }
    }
}
'''
root_view.write_text(root_view.read_text(encoding="utf-8") + clock_view, encoding="utf-8")


# -----------------------------------------------------------------------------
# 2) MX Jump Arc: favorite preview animates a soft route line for ~1 second,
#    shows a tiny context capsule, then lands/zooms on the favorite and leaves
#    only the approved glowing dot marker. It NEVER changes simulated location.
# -----------------------------------------------------------------------------
map_file = root / "Locus/Features/Map/MapHomeView.swift"

old_states = '''    @State private var undoCoordinate: CLLocationCoordinate2D?\n    @State private var showUndo = false\n    @State private var undoTask: Task<Void, Never>?\n'''
new_states = '''    @State private var undoCoordinate: CLLocationCoordinate2D?\n    @State private var showUndo = false\n    @State private var undoTask: Task<Void, Never>?\n\n    @State private var jumpArcPoints: [CLLocationCoordinate2D] = []\n    @State private var jumpArcVisibleCount = 0\n    @State private var showJumpArc = false\n    @State private var jumpCapsuleText = ""\n    @State private var jumpArcTask: Task<Void, Never>?\n'''
replace_required(map_file, old_states, new_states)

old_user_annotation = '''                    UserAnnotation()\n\n                    if let pin = session.pin {\n'''
new_user_annotation = '''                    UserAnnotation()\n\n                    if showJumpArc, jumpArcVisibleCount > 1 {\n                        MapPolyline(coordinates: Array(jumpArcPoints.prefix(jumpArcVisibleCount)))\n                            .stroke(accent.opacity(0.82), lineWidth: 2)\n                    }\n\n                    if let pin = session.pin {\n'''
replace_required(map_file, old_user_annotation, new_user_annotation)

old_search_results_area = '''                if searchFocused && !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {\n                    searchResults\n                }\n\n                Spacer(minLength: 0)\n'''
new_search_results_area = '''                if searchFocused && !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {\n                    searchResults\n                }\n\n                if showJumpArc, !jumpCapsuleText.isEmpty {\n                    Text(jumpCapsuleText)\n                        .font(.caption2.weight(.semibold))\n                        .foregroundStyle(.primary)\n                        .lineLimit(1)\n                        .minimumScaleFactor(0.72)\n                        .padding(.horizontal, 11)\n                        .frame(height: 30)\n                        .background(.ultraThinMaterial, in: Capsule())\n                        .overlay(Capsule().stroke(Color.white.opacity(0.08), lineWidth: 1))\n                        .shadow(color: Color.black.opacity(0.22), radius: 10, y: 5)\n                        .transition(.move(edge: .top).combined(with: .opacity))\n                }\n\n                Spacer(minLength: 0)\n'''
replace_required(map_file, old_search_results_area, new_search_results_area)

old_preview_change = '''        .onChange(of: session.requestedMapPreview?.id) { _, _ in\n            guard let place = session.requestedMapPreview else { return }\n            searchFocused = false\n            choosePin(\n                place.coordinate,\n                name: place.name,\n                subtitle: "Favorite",\n                zoom: true\n            )\n            UIImpactFeedbackGenerator(style: .soft).impactOccurred()\n            session.requestedMapPreview = nil\n        }\n'''
new_preview_change = '''        .onChange(of: session.requestedMapPreview?.id) { _, _ in\n            guard let place = session.requestedMapPreview else { return }\n            beginFavoriteJumpPreview(place)\n            session.requestedMapPreview = nil\n        }\n'''
replace_required(map_file, old_preview_change, new_preview_change)

helper_anchor = '''    private func teleportWithUndo(to coordinate: CLLocationCoordinate2D) {\n'''
helpers = r'''    private func beginFavoriteJumpPreview(_ place: SavedPlace) {
        jumpArcTask?.cancel()
        searchFocused = false

        let destination = place.coordinate
        session.pin = destination
        pinName = place.name
        pinSubtitle = "Favorite"

        guard let origin = session.simulated ?? session.realCoordinate else {
            choosePin(destination, name: place.name, subtitle: "Favorite", zoom: true)
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
            return
        }

        let distanceMeters = CLLocation(latitude: origin.latitude, longitude: origin.longitude)
            .distance(from: CLLocation(latitude: destination.latitude, longitude: destination.longitude))

        // Very short jumps do not need a world-scale arc.
        if distanceMeters < 250 {
            choosePin(destination, name: place.name, subtitle: "Favorite", zoom: true)
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
            return
        }

        let points = makeJumpArcPoints(from: origin, to: destination, steps: 48)
        jumpArcPoints = points
        jumpArcVisibleCount = min(2, points.count)
        jumpCapsuleText = "Current → \(place.name) · \(distanceText(distanceMeters))"

        withAnimation(.easeInOut(duration: 0.20)) {
            showJumpArc = true
            position = .rect(jumpMapRect(from: origin, to: destination))
        }
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()

        // Resolve city names + timezone offset concurrently; the base capsule is
        // already visible immediately so the animation never waits on geocoding.
        Task {
            let context = await jumpContextText(
                from: origin,
                to: destination,
                destinationName: place.name,
                distanceMeters: distanceMeters
            )
            guard !Task.isCancelled else { return }
            await MainActor.run {
                if showJumpArc { jumpCapsuleText = context }
            }
        }

        jumpArcTask = Task { @MainActor in
            let total = max(points.count, 2)
            for count in 2...total {
                if Task.isCancelled { return }
                jumpArcVisibleCount = count
                try? await Task.sleep(nanoseconds: 18_000_000)
            }

            try? await Task.sleep(nanoseconds: 130_000_000)
            if Task.isCancelled { return }

            withAnimation(.easeOut(duration: 0.20)) {
                showJumpArc = false
            }

            withAnimation(.easeInOut(duration: 0.42)) {
                position = .region(MKCoordinateRegion(
                    center: destination,
                    latitudinalMeters: 1500,
                    longitudinalMeters: 1500
                ))
            }

            try? await Task.sleep(nanoseconds: 240_000_000)
            if Task.isCancelled { return }
            jumpArcPoints = []
            jumpArcVisibleCount = 0
            jumpCapsuleText = ""
        }
    }

    private func makeJumpArcPoints(
        from start: CLLocationCoordinate2D,
        to end: CLLocationCoordinate2D,
        steps: Int
    ) -> [CLLocationCoordinate2D] {
        let count = max(steps, 2)
        let latSpan = end.latitude - start.latitude
        var lonSpan = end.longitude - start.longitude
        if lonSpan > 180 { lonSpan -= 360 }
        if lonSpan < -180 { lonSpan += 360 }

        // Gentle visual bow. The line remains intentionally subtle rather than
        // looking like an airline-route graphic.
        let visualDistance = min(1.0, hypot(latSpan, lonSpan) / 80.0)
        let lift = min(8.0, 2.0 + (6.0 * visualDistance))

        return (0..<count).map { index in
            let t = Double(index) / Double(count - 1)
            let bow = sin(.pi * t) * lift
            var longitude = start.longitude + lonSpan * t
            if longitude > 180 { longitude -= 360 }
            if longitude < -180 { longitude += 360 }
            return CLLocationCoordinate2D(
                latitude: start.latitude + latSpan * t + bow,
                longitude: longitude
            )
        }
    }

    private func jumpMapRect(
        from start: CLLocationCoordinate2D,
        to end: CLLocationCoordinate2D
    ) -> MKMapRect {
        let a = MKMapPoint(start)
        let b = MKMapPoint(end)
        let minX = min(a.x, b.x)
        let minY = min(a.y, b.y)
        let width = max(abs(a.x - b.x), 120_000)
        let height = max(abs(a.y - b.y), 120_000)
        let rect = MKMapRect(x: minX, y: minY, width: width, height: height)
        return rect.insetBy(dx: -width * 0.22, dy: -height * 0.30)
    }

    private func distanceText(_ meters: CLLocationDistance) -> String {
        let kilometers = meters / 1000
        if kilometers >= 100 {
            return String(format: "%.0f km", kilometers)
        } else if kilometers >= 10 {
            return String(format: "%.1f km", kilometers)
        } else {
            return String(format: "%.2f km", kilometers)
        }
    }

    private func jumpContextText(
        from start: CLLocationCoordinate2D,
        to end: CLLocationCoordinate2D,
        destinationName: String,
        distanceMeters: CLLocationDistance
    ) async -> String {
        async let startMark = reversePlacemark(start)
        async let endMark = reversePlacemark(end)
        let (originPlacemark, destinationPlacemark) = await (startMark, endMark)

        let originName = originPlacemark?.locality
            ?? originPlacemark?.administrativeArea
            ?? "Current"
        let destinationDisplayName = destinationPlacemark?.locality
            ?? destinationPlacemark?.administrativeArea
            ?? destinationName

        var parts = ["\(originName) → \(destinationDisplayName)", distanceText(distanceMeters)]
        if let delta = timezoneDeltaText(
            from: originPlacemark?.timeZone,
            to: destinationPlacemark?.timeZone
        ) {
            parts.append(delta)
        }
        return parts.joined(separator: " · ")
    }

    private func reversePlacemark(_ coordinate: CLLocationCoordinate2D) async -> CLPlacemark? {
        let geocoder = CLGeocoder()
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        return (try? await geocoder.reverseGeocodeLocation(location))?.first
    }

    private func timezoneDeltaText(from: TimeZone?, to: TimeZone?) -> String? {
        guard let from, let to else { return nil }
        let now = Date()
        let seconds = to.secondsFromGMT(for: now) - from.secondsFromGMT(for: now)
        let sign = seconds >= 0 ? "+" : "−"
        let absoluteMinutes = abs(seconds) / 60
        let hours = absoluteMinutes / 60
        let minutes = absoluteMinutes % 60
        if minutes == 0 {
            return "\(sign)\(hours)h"
        }
        return String(format: "%@%d:%02dh", sign, hours, minutes)
    }

    private func teleportWithUndo(to coordinate: CLLocationCoordinate2D) {
'''
replace_required(map_file, helper_anchor, helpers)


# -----------------------------------------------------------------------------
# 3) Version bump from v1.2.8 / build 21.
# -----------------------------------------------------------------------------
project = root / "project.yml"
text = project.read_text(encoding="utf-8")
text = text.replace('MARKETING_VERSION: "1.2.8"', 'MARKETING_VERSION: "1.2.9"')
text = text.replace('CURRENT_PROJECT_VERSION: "21"', 'CURRENT_PROJECT_VERSION: "22"')
project.write_text(text, encoding="utf-8")

print("Applied MX Location v1.2.9: MX Jump Arc + favorite local clocks")
