from pathlib import Path
import sys


root = Path(sys.argv[1]).resolve()


def replace_required(path: Path, old: str, new: str) -> None:
    text = path.read_text(encoding="utf-8")
    if old not in text:
        raise RuntimeError(f"Required Waze patch fragment not found in {path}: {old[:120]!r}")
    path.write_text(text.replace(old, new), encoding="utf-8")


# Give this compatibility build its own in-app version as well as its IPA name.
project = root / "project.yml"
replace_required(project, '        MARKETING_VERSION: "1.0.2"\n', '        MARKETING_VERSION: "1.0.10"\n')
replace_required(project, '        CURRENT_PROJECT_VERSION: "3"\n', '        CURRENT_PROJECT_VERSION: "10"\n')

# Keep the DVT location session actively fed while MX Location is backgrounded
# and a navigation app owns the foreground. This does not alter the selected
# coordinate; it keeps the simulated fix fresh and the process runnable.
spoof = root / "Locus/Engine/SpoofSession.swift"

replace_required(
    spoof,
    "    private let locationKeeper = BackgroundKeepAlive()\n",
    "    private let locationKeeper = BackgroundKeepAlive()\n"
    "    private let wazeKeepAlive = SilentAudioKeepAlive()\n",
)

replace_required(
    spoof,
    "            endBackground()\n"
    "            // Keep location updates running so the map puck / locate button\n",
    "            endBackground()\n"
    "            wazeKeepAlive.stop()\n"
    "            // Keep location updates running so the map puck / locate button\n",
)

replace_required(
    spoof,
    "            beginBackground()\n"
    "            locationKeeper.start()\n"
    "            startResend(pairing: pairing)\n",
    "            beginBackground()\n"
    "            // Keep MX Location executing while Waze owns the foreground.\n"
    "            // The audio is near-silent and mixes with other audio.\n"
    "            wazeKeepAlive.start()\n"
    "            locationKeeper.start()\n"
    "            startResend(pairing: pairing)\n",
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

        // Navigation compatibility heartbeat: refresh the DVT fix at a sub-second
        // cadence and use the common run-loop mode so UI tracking does not pause it.
        let timer = Timer(timeInterval: 0.75, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let sim = self.simulated, self.isSpoofing else { return }
                let result = LocationEngine.set(
                    latitude: sim.latitude,
                    longitude: sim.longitude,
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

# Build marker so the generated framework can be identified from strings/logs.
marker = root / "Locus/Support/MXWazeCompatibility.swift"
marker.write_text(
    "import Foundation\n\n"
    "enum MXWazeCompatibility {\n"
    "    static let build = \"Waze Fix 1.0.10\"\n"
    "    static let heartbeatSeconds: TimeInterval = 0.75\n"
    "}\n",
    encoding="utf-8",
)

print("Applied MX Location Waze compatibility patch at", root)
