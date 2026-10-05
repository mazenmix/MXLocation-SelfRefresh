from pathlib import Path
import sys

root = Path(sys.argv[1]).resolve()
map_file = root / "Locus/Features/Map/MapHomeView.swift"
text = map_file.read_text(encoding="utf-8")

if "    private func teleportWithUndo(to coordinate: CLLocationCoordinate2D) {" in text:
    print("MX Location v1.3.2 map helpers already present")
    raise SystemExit(0)

anchor = "    private func isFavorite(_ coordinate: CLLocationCoordinate2D) -> Bool {\n"
if anchor not in text:
    raise RuntimeError("isFavorite anchor not found while restoring map helpers")

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
        let previous = session.simulated
        session.teleport(to: coordinate, pairing: pairing)

        guard let previous,
              abs(previous.latitude - coordinate.latitude) > 0.000001 ||
              abs(previous.longitude - coordinate.longitude) > 0.000001 else { return }

        undoTask?.cancel()
        undoCoordinate = previous
        withAnimation(.easeInOut(duration: 0.18)) {
            showUndo = true
        }

        undoTask = Task {
            try? await Task.sleep(nanoseconds: 10_000_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                withAnimation(.easeInOut(duration: 0.18)) {
                    showUndo = false
                }
                undoCoordinate = nil
            }
        }
    }

    private func undoLastLocationChange() {
        guard let previous = undoCoordinate else { return }
        undoTask?.cancel()
        session.teleport(to: previous, pairing: pairing)
        choosePin(previous, name: nil, subtitle: nil, zoom: true)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        withAnimation(.easeInOut(duration: 0.18)) {
            showUndo = false
        }
        undoCoordinate = nil
    }

'''

text = text.replace(anchor, helpers + anchor, 1)
map_file.write_text(text, encoding="utf-8")
print("Restored MX Location Jump Arc + Undo helpers for v1.3.2")
