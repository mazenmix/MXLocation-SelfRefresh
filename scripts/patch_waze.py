from pathlib import Path
import sys


root = Path(sys.argv[1]).resolve()


def replace_required(path: Path, old: str, new: str) -> None:
    text = path.read_text(encoding="utf-8")
    if old not in text:
        raise RuntimeError(f"Required navigation patch fragment not found in {path}: {old[:120]!r}")
    path.write_text(text.replace(old, new), encoding="utf-8")


# Navigation compatibility build identity.
project = root / "project.yml"
replace_required(project, '        MARKETING_VERSION: "1.0.2"\n', '        MARKETING_VERSION: "1.0.12"\n')
replace_required(project, '        CURRENT_PROJECT_VERSION: "3"\n', '        CURRENT_PROJECT_VERSION: "12"\n')

spoof = root / "Locus/Engine/SpoofSession.swift"

# Keep the DVT simulation process alive while a navigation app owns foreground.
replace_required(
    spoof,
    "    private let locationKeeper = BackgroundKeepAlive()\n",
    "    private let locationKeeper = BackgroundKeepAlive()\n"
    "    private let navigationKeepAlive = SilentAudioKeepAlive()\n"
    "    private var routeStreaming = false\n"
    "    private var heartbeatPhase = false\n",
)

replace_required(
    spoof,
    "        routeTask?.cancel()\n"
    "        routeTask = nil\n"
    "        stopJoystick()\n",
    "        routeTask?.cancel()\n"
    "        routeTask = nil\n"
    "        routeStreaming = false\n"
    "        stopJoystick()\n",
)

replace_required(
    spoof,
    "            endBackground()\n"
    "            // Keep location updates running so the map puck / locate button\n",
    "            endBackground()\n"
    "            navigationKeepAlive.stop()\n"
    "            // Keep location updates running so the map puck / locate button\n",
)

replace_required(
    spoof,
    "            beginBackground()\n"
    "            locationKeeper.start()\n"
    "            startResend(pairing: pairing)\n",
    "            beginBackground()\n"
    "            navigationKeepAlive.start()\n"
    "            locationKeeper.start()\n"
    "            startResend(pairing: pairing)\n",
)

# Route playback: feed coordinates at a stable navigation-like cadence so apps
# can infer course and speed from successive samples rather than sparse jumps.
old_route = '''    func followRoute(_ coordinates: [CLLocationCoordinate2D], pairing: PairingStore) {
        guard pairing.hasPairingFile, coordinates.count >= 2 else { return }
        routeTask?.cancel()
        stopJoystick()
        let mode = travelMode
        routeTask = Task { [weak self] in
            guard let self else { return }
            var previous = coordinates[0]
            await MainActor.run {
                self.apply(previous, pairing: pairing, markRecent: true)
            }
            for next in coordinates.dropFirst() {
                if Task.isCancelled { break }
                let distance = CLLocation(latitude: previous.latitude, longitude: previous.longitude)
                    .distance(from: CLLocation(latitude: next.latitude, longitude: next.longitude))
                var speed = mode.baseSpeed * Double.random(in: 0.88...1.12)
                speed = max(0.8, speed)
                let stepMeters: CLLocationDistance = min(12, max(4, speed * 0.5))
                let steps = max(1, Int(ceil(distance / stepMeters)))
                for i in 1...steps {
                    if Task.isCancelled { break }
                    let t = Double(i) / Double(steps)
                    let coord = CLLocationCoordinate2D(
                        latitude: previous.latitude + (next.latitude - previous.latitude) * t,
                        longitude: previous.longitude + (next.longitude - previous.longitude) * t
                    )
                    let delay = stepMeters / speed
                    try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                    await MainActor.run {
                        self.apply(coord, pairing: pairing, markRecent: false)
                    }
                }
                previous = next
            }
        }
    }
'''

new_route = '''    func followRoute(_ coordinates: [CLLocationCoordinate2D], pairing: PairingStore) {
        guard pairing.hasPairingFile, coordinates.count >= 2 else { return }
        routeTask?.cancel()
        stopJoystick()
        let mode = travelMode
        routeStreaming = true

        routeTask = Task { [weak self] in
            guard let self else { return }
            var previous = coordinates[0]
            await MainActor.run {
                self.apply(previous, pairing: pairing, markRecent: true)
            }

            let sampleInterval: TimeInterval
            switch mode {
            case .walk: sampleInterval = 0.50
            case .run: sampleInterval = 0.40
            case .cycle: sampleInterval = 0.35
            case .drive: sampleInterval = 0.25
            }

            for next in coordinates.dropFirst() {
                if Task.isCancelled { break }
                let startLocation = CLLocation(latitude: previous.latitude, longitude: previous.longitude)
                let endLocation = CLLocation(latitude: next.latitude, longitude: next.longitude)
                let distance = startLocation.distance(from: endLocation)

                var speed = mode.baseSpeed * Double.random(in: 0.94...1.06)
                speed = max(0.8, speed)
                let metersPerSample = max(0.35, speed * sampleInterval)
                let steps = max(1, Int(ceil(distance / metersPerSample)))

                for i in 1...steps {
                    if Task.isCancelled { break }
                    let t = Double(i) / Double(steps)
                    let coord = CLLocationCoordinate2D(
                        latitude: previous.latitude + (next.latitude - previous.latitude) * t,
                        longitude: previous.longitude + (next.longitude - previous.longitude) * t
                    )
                    try? await Task.sleep(nanoseconds: UInt64(sampleInterval * 1_000_000_000))
                    let accepted = await MainActor.run {
                        self.applyMotionSample(coord, pairing: pairing)
                    }
                    if !accepted { break }
                }
                previous = next
            }

            await MainActor.run {
                self.routeStreaming = false
                self.routeTask = nil
            }
        }
    }
'''
replace_required(spoof, old_route, new_route)

# Motion samples advance the already-established DVT session without restarting
# timers/background sessions on every tick.
helper_anchor = '''    private func tickJoystick(pairing: PairingStore) {
'''
helper = '''    private func applyMotionSample(_ coordinate: CLLocationCoordinate2D, pairing: PairingStore) -> Bool {
        let result = LocationEngine.set(
            latitude: coordinate.latitude,
            longitude: coordinate.longitude,
            pairingPath: pairing.pairingPath,
            deviceIP: TunnelConfig.targetIP
        )
        switch result {
        case .success:
            simulated = coordinate
            pin = coordinate
            status = .active
            lastError = nil
            return true
        case .failure(let error):
            lastError = error.localizedDescription
            status = .dropped(error.localizedDescription)
            postDropNotification(error.localizedDescription)
            return false
        }
    }

    private func tickJoystick(pairing: PairingStore) {
'''
replace_required(spoof, helper_anchor, helper)

replace_required(
    spoof,
    "        apply(next, pairing: pairing, markRecent: false)\n"
    "    }\n\n"
    "    private func startResend(pairing: PairingStore) {\n",
    "        _ = applyMotionSample(next, pairing: pairing)\n"
    "    }\n\n"
    "    private func startResend(pairing: PairingStore) {\n",
)

old_resend = '''    private func startResend(pairing: PairingStore) {
        resendTimer?.invalidate()
        resendTimer = Timer.scheduledTimer(withTimeInterval: 8, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let sim = self.simulated else { return }
                _ = LocationEngine.set(
                    latitude: sim.latitude,
                    longitude: sim.longitude,
                    pairingPath: pairing.pairingPath,
                    deviceIP: TunnelConfig.targetIP
                )
            }
        }
    }
'''

new_resend = '''    private func startResend(pairing: PairingStore) {
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
replace_required(spoof, old_resend, new_resend)

replace_required(
    spoof,
    "        healthTimer = Timer.scheduledTimer(withTimeInterval: 12, repeats: true) { [weak self] _ in\n",
    "        healthTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in\n",
)

# Keep Core Location active in a navigation-grade configuration while spoofing.
keeper = root / "Locus/Engine/BackgroundKeepAlive.swift"
replace_required(
    keeper,
    "        manager.desiredAccuracy = kCLLocationAccuracyThreeKilometers\n"
    "        manager.pausesLocationUpdatesAutomatically = false\n",
    "        manager.desiredAccuracy = kCLLocationAccuracyBestForNavigation\n"
    "        manager.distanceFilter = kCLDistanceFilterNone\n"
    "        manager.activityType = .automotiveNavigation\n"
    "        manager.pausesLocationUpdatesAutomatically = false\n",
)

marker = root / "Locus/Support/MXWazeCompatibility.swift"
marker.write_text(
    "import Foundation\n\n"
    "enum MXWazeCompatibility {\n"
    "    static let build = \"Navigation Mode 1.0.12\"\n"
    "    static let stationaryHeartbeatSeconds: TimeInterval = 1.0\n"
    "    static let stationaryPulseMeters: Double = 0.65\n"
    "    static let drivingSampleSeconds: TimeInterval = 0.25\n"
    "}\n",
    encoding="utf-8",
)

print("Applied MX Location navigation compatibility patch at", root)
