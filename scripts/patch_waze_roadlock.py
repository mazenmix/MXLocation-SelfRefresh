from pathlib import Path
import sys


root = Path(sys.argv[1]).resolve()


def replace_required(path: Path, old: str, new: str) -> None:
    text = path.read_text(encoding="utf-8")
    if old not in text:
        raise RuntimeError(f"Required Waze RoadLock patch fragment not found in {path}: {old[:140]!r}")
    path.write_text(text.replace(old, new), encoding="utf-8")


# This patch is applied AFTER patch_waze.py (v1.0.12). It adds an on-road
# anchor, road-aligned stationary freshness pulses, and a short heading warm-up.
project = root / "project.yml"
replace_required(project, '        MARKETING_VERSION: "1.0.12"\n', '        MARKETING_VERSION: "1.0.13"\n')
replace_required(project, '        CURRENT_PROJECT_VERSION: "12"\n', '        CURRENT_PROJECT_VERSION: "13"\n')

spoof = root / "Locus/Engine/SpoofSession.swift"

replace_required(
    spoof,
    "    private var heartbeatPhase = false\n",
    "    private var heartbeatPhase = false\n"
    "    private var roadLockAnchor: CLLocationCoordinate2D?\n"
    "    private var roadLockHeading: CLLocationDirection?\n"
    "    private var roadLockTask: Task<Void, Never>?\n",
)

old_teleport = '''    func teleport(to coordinate: CLLocationCoordinate2D, pairing: PairingStore) {
        guard pairing.hasPairingFile else {
            lastError = "Import an RPPairing file in Settings first."
            return
        }
        pin = coordinate
        apply(coordinate, pairing: pairing, markRecent: true)
    }
'''

new_teleport = '''    func teleport(to coordinate: CLLocationCoordinate2D, pairing: PairingStore) {
        guard pairing.hasPairingFile else {
            lastError = "Import an RPPairing file in Settings first."
            return
        }

        // Waze is happiest when the injected coordinate is physically on a
        // routable road, not merely near one. Probe Apple Maps routes that cross
        // the selected point and project to the nearest road segment before the
        // DVT location session is started.
        roadLockTask?.cancel()
        pin = coordinate
        isBusy = true
        roadLockTask = Task { [weak self] in
            guard let self else { return }
            let fix = await RoadLockEngine.snap(coordinate)
            if Task.isCancelled { return }

            self.isBusy = false
            let target = fix?.coordinate ?? coordinate
            self.roadLockAnchor = target
            self.roadLockHeading = fix?.bearing
            self.routeStreaming = fix != nil
            self.apply(target, pairing: pairing, markRecent: true)

            if fix != nil {
                self.startRoadWarmup(pairing: pairing)
            } else {
                self.routeStreaming = false
            }
            self.roadLockTask = nil
        }
    }
'''
replace_required(spoof, old_teleport, new_teleport)

replace_required(
    spoof,
    "        routeTask?.cancel()\n"
    "        routeTask = nil\n"
    "        routeStreaming = false\n"
    "        stopJoystick()\n",
    "        routeTask?.cancel()\n"
    "        routeTask = nil\n"
    "        roadLockTask?.cancel()\n"
    "        roadLockTask = nil\n"
    "        routeStreaming = false\n"
    "        roadLockAnchor = nil\n"
    "        roadLockHeading = nil\n"
    "        stopJoystick()\n",
)

# Insert a brief monotonic on-road warm-up before settling into the stationary
# heartbeat. This gives navigation apps a few fresh, heading-consistent samples
# immediately after teleport without jumping off the road centerline.
helper_anchor = '''    private func applyMotionSample(_ coordinate: CLLocationCoordinate2D, pairing: PairingStore) -> Bool {
'''
helper = '''    private func startRoadWarmup(pairing: PairingStore) {
        guard let anchor = roadLockAnchor, let heading = roadLockHeading else {
            routeStreaming = false
            return
        }

        routeTask?.cancel()
        routeStreaming = true
        routeTask = Task { [weak self] in
            guard let self else { return }
            let forwardMeters: [Double] = [0.55, 1.10, 1.65, 2.20, 2.75, 3.30]
            var finalCoordinate = anchor

            for meters in forwardMeters {
                if Task.isCancelled { break }
                try? await Task.sleep(nanoseconds: 250_000_000)
                let coordinate = RoadLockEngine.offset(anchor, bearing: heading, meters: meters)
                let accepted = await MainActor.run {
                    self.applyMotionSample(coordinate, pairing: pairing)
                }
                if !accepted { break }
                finalCoordinate = coordinate
            }

            await MainActor.run {
                if !Task.isCancelled {
                    self.roadLockAnchor = finalCoordinate
                    self.simulated = finalCoordinate
                    self.pin = finalCoordinate
                }
                self.routeStreaming = false
                self.routeTask = nil
            }
        }
    }

    private func applyMotionSample(_ coordinate: CLLocationCoordinate2D, pairing: PairingStore) -> Bool {
'''
replace_required(spoof, helper_anchor, helper)

# Teach every continuous-motion sample to preserve the road axis. When a route
# finishes, the stationary heartbeat continues along the last valid heading.
old_motion_prefix = '''    private func applyMotionSample(_ coordinate: CLLocationCoordinate2D, pairing: PairingStore) -> Bool {
        let result = LocationEngine.set(
'''
new_motion_prefix = '''    private func applyMotionSample(_ coordinate: CLLocationCoordinate2D, pairing: PairingStore) -> Bool {
        if let previous = simulated {
            let distance = CLLocation(latitude: previous.latitude, longitude: previous.longitude)
                .distance(from: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude))
            if distance > 0.12 {
                roadLockHeading = RoadLockEngine.bearing(from: previous, to: coordinate)
            }
        }
        roadLockAnchor = coordinate

        let result = LocationEngine.set(
'''
replace_required(spoof, old_motion_prefix, new_motion_prefix)

# Replace v1.0.12's east/west pulse with a road-aligned freshness pulse. This
# keeps the sample changing enough to avoid stale-location coalescing while the
# injected point remains on the same road segment.
old_resend = '''    private func startResend(pairing: PairingStore) {
        resendTimer?.invalidate()
        heartbeatPhase = false

        // Sending the exact same coordinate repeatedly can be coalesced by
        // locationd, leaving navigation clients with an old sample timestamp.
        // Alternate a sub-meter east/west pulse around the selected coordinate.
        // The anchor remains unchanged in UI/state, but Core Location receives a
        // genuinely fresh location event every second while stationary.
        let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let sim = self.simulated, self.isSpoofing else { return }
                guard !self.routeStreaming else { return }

                self.heartbeatPhase.toggle()
                let pulseMeters = self.heartbeatPhase ? 0.65 : -0.65
                let latitudeRadians = sim.latitude * .pi / 180.0
                let metersPerLongitudeDegree = max(1.0, 111_320.0 * cos(latitudeRadians))
                let pulseLongitude = sim.longitude + pulseMeters / metersPerLongitudeDegree

                let result = LocationEngine.set(
                    latitude: sim.latitude,
                    longitude: pulseLongitude,
                    pairingPath: pairing.pairingPath,
                    deviceIP: TunnelConfig.targetIP
                )
                if case .failure(let error) = result {
                    self.lastError = error.localizedDescription
                    self.status = .dropped(error.localizedDescription)
                }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        resendTimer = timer
    }
'''

new_resend = '''    private func startResend(pairing: PairingStore) {
        resendTimer?.invalidate()
        heartbeatPhase = false

        // Navigation-grade stationary freshness: update faster than the old
        // keepalive and move only along the detected road axis. The visible
        // anchor does not wander; only the injected fix gets the tiny GPS-like
        // variation needed to stay fresh for foreground navigation clients.
        let timer = Timer(timeInterval: 0.75, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let sim = self.simulated, self.isSpoofing else { return }
                guard !self.routeStreaming else { return }

                let anchor = self.roadLockAnchor ?? sim
                self.heartbeatPhase.toggle()
                let pulseMeters = self.heartbeatPhase ? 0.90 : -0.90
                let heading = self.roadLockHeading ?? 90.0
                let pulse = RoadLockEngine.offset(anchor, bearing: heading, meters: pulseMeters)

                let result = LocationEngine.set(
                    latitude: pulse.latitude,
                    longitude: pulse.longitude,
                    pairingPath: pairing.pairingPath,
                    deviceIP: TunnelConfig.targetIP
                )
                switch result {
                case .success:
                    self.status = .active
                    self.lastError = nil
                case .failure(let error):
                    self.lastError = error.localizedDescription
                    self.status = .dropped(error.localizedDescription)
                }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        resendTimer = timer
    }
'''
replace_required(spoof, old_resend, new_resend)

# Keep route geometry dense so the stream follows corners rather than cutting
# across them between sparse polyline vertices.
route_builder = root / "Locus/Engine/RouteBuilder.swift"
replace_required(
    route_builder,
    "        return sample(polyline: route.polyline, every: 12)\n",
    "        let spacing: CLLocationDistance = mode == .drive ? 3.0 : 5.0\n"
    "        return sample(polyline: route.polyline, every: spacing)\n",
)

# A road-lock helper based only on MapKit. It does not need a third-party token:
# it asks for several short automobile routes crossing the selected location,
# then projects the point onto the nearest route segment and captures its bearing.
roadlock = root / "Locus/Engine/RoadLockEngine.swift"
roadlock.write_text(r'''import CoreLocation
import Foundation
import MapKit

struct RoadLockFix {
    let coordinate: CLLocationCoordinate2D
    let bearing: CLLocationDirection
    let distance: CLLocationDistance
}

enum RoadLockEngine {
    static func snap(
        _ coordinate: CLLocationCoordinate2D,
        maxDistance: CLLocationDistance = 95
    ) async -> RoadLockFix? {
        var best: RoadLockFix?

        // Opposite probe pairs make the target an interior point of the routing
        // search instead of a source/destination, avoiding entrance connector
        // lines that are not the actual road centerline.
        let axes: [CLLocationDirection] = [0, 30, 60, 90, 120, 150]
        let radii: [CLLocationDistance] = [180, 320]

        for radius in radii {
            for axis in axes {
                if Task.isCancelled { return nil }

                let start = offset(coordinate, bearing: axis, meters: radius)
                let end = offset(coordinate, bearing: axis + 180, meters: radius)

                let request = MKDirections.Request()
                request.source = MKMapItem(placemark: MKPlacemark(coordinate: start))
                request.destination = MKMapItem(placemark: MKPlacemark(coordinate: end))
                request.transportType = .automobile
                request.requestsAlternateRoutes = true

                do {
                    let response = try await MKDirections(request: request).calculate()
                    for route in response.routes.prefix(3) {
                        if let fix = closestFix(to: coordinate, on: route.polyline),
                           fix.distance <= maxDistance,
                           (best == nil || fix.distance < best!.distance) {
                            best = fix
                        }
                    }
                } catch {
                    continue
                }

                // A sub-12 m projection is already strong road-lock quality; no
                // reason to wait for the larger-radius fallback sweep.
                if let best, best.distance < 12 {
                    return best
                }
            }

            if let best, best.distance < 35 {
                return best
            }
        }

        return best
    }

    static func offset(
        _ coordinate: CLLocationCoordinate2D,
        bearing: CLLocationDirection,
        meters: CLLocationDistance
    ) -> CLLocationCoordinate2D {
        let earth = 6_378_137.0
        let brng = bearing * .pi / 180
        let lat1 = coordinate.latitude * .pi / 180
        let lon1 = coordinate.longitude * .pi / 180
        let angular = meters / earth

        let lat2 = asin(
            sin(lat1) * cos(angular) +
            cos(lat1) * sin(angular) * cos(brng)
        )
        let lon2 = lon1 + atan2(
            sin(brng) * sin(angular) * cos(lat1),
            cos(angular) - sin(lat1) * sin(lat2)
        )

        return CLLocationCoordinate2D(
            latitude: lat2 * 180 / .pi,
            longitude: lon2 * 180 / .pi
        )
    }

    static func bearing(
        from a: CLLocationCoordinate2D,
        to b: CLLocationCoordinate2D
    ) -> CLLocationDirection {
        let lat1 = a.latitude * .pi / 180
        let lat2 = b.latitude * .pi / 180
        let deltaLon = (b.longitude - a.longitude) * .pi / 180
        let y = sin(deltaLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(deltaLon)
        let degrees = atan2(y, x) * 180 / .pi
        return (degrees + 360).truncatingRemainder(dividingBy: 360)
    }

    private static func closestFix(
        to target: CLLocationCoordinate2D,
        on polyline: MKPolyline
    ) -> RoadLockFix? {
        guard polyline.pointCount >= 2 else { return nil }

        var coordinates = [CLLocationCoordinate2D](
            repeating: CLLocationCoordinate2D(),
            count: polyline.pointCount
        )
        polyline.getCoordinates(
            &coordinates,
            range: NSRange(location: 0, length: polyline.pointCount)
        )

        let latitudeScale = 111_132.0
        let longitudeScale = max(1.0, 111_320.0 * cos(target.latitude * .pi / 180))
        var best: RoadLockFix?

        for (a, b) in zip(coordinates, coordinates.dropFirst()) {
            let ax = (a.longitude - target.longitude) * longitudeScale
            let ay = (a.latitude - target.latitude) * latitudeScale
            let bx = (b.longitude - target.longitude) * longitudeScale
            let by = (b.latitude - target.latitude) * latitudeScale
            let dx = bx - ax
            let dy = by - ay
            let lengthSquared = dx * dx + dy * dy
            guard lengthSquared > 0.25 else { continue }

            let unclamped = -(ax * dx + ay * dy) / lengthSquared
            let t = min(1.0, max(0.0, unclamped))
            let px = ax + t * dx
            let py = ay + t * dy
            let distance = hypot(px, py)
            let projected = CLLocationCoordinate2D(
                latitude: target.latitude + py / latitudeScale,
                longitude: target.longitude + px / longitudeScale
            )
            let fix = RoadLockFix(
                coordinate: projected,
                bearing: bearing(from: a, to: b),
                distance: distance
            )

            if best == nil || distance < best!.distance {
                best = fix
            }
        }

        return best
    }
}
''', encoding="utf-8")

# Update the diagnostic marker created by patch_waze.py.
marker = root / "Locus/Support/MXWazeCompatibility.swift"
replace_required(marker, '    static let build = "Navigation Mode 1.0.12"\n', '    static let build = "Waze RoadLock 1.0.13"\n')
replace_required(marker, '    static let stationaryHeartbeatSeconds: TimeInterval = 1.0\n', '    static let stationaryHeartbeatSeconds: TimeInterval = 0.75\n')
replace_required(marker, '    static let stationaryPulseMeters: Double = 0.65\n', '    static let stationaryPulseMeters: Double = 0.90\n')

print("Applied MX Location Waze RoadLock v1.0.13 patch at", root)
