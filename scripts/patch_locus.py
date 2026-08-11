from pathlib import Path
import re
import sys


root = Path(sys.argv[1]).resolve()


def replace_required(path: Path, old: str, new: str) -> None:
    text = path.read_text(encoding="utf-8")
    if old not in text:
        raise RuntimeError(f"Required source fragment not found in {path}: {old[:100]!r}")
    path.write_text(text.replace(old, new), encoding="utf-8")


# Product identity. Keep the internal target/scheme named Locus for stability.
project = root / "project.yml"
replace_required(
    project,
    "PRODUCT_BUNDLE_IDENTIFIER: com.chrismack.locus",
    "PRODUCT_BUNDLE_IDENTIFIER: com.mazenmix.mxlocation",
)
replace_required(project, "PRODUCT_NAME: Locus", "PRODUCT_NAME: MXLocation")

plist = root / "Locus/Resources/Info.plist"
text = plist.read_text(encoding="utf-8")
text = text.replace("<string>Locus</string>", "<string>MX Location</string>")
text = text.replace("Locus uses your real location", "MX Location uses your real location")
text = text.replace("Locus keeps a light location session alive", "MX Location keeps a light location session alive")
text = text.replace("Locus uses the local network", "MX Location uses the local network")
text = text.replace("com.chrismack.locus.rppairing", "com.mazenmix.mxlocation.rppairing")
text = text.replace("<string>com.chrismack.locus</string>", "<string>com.mazenmix.mxlocation</string>")
text = text.replace("<string>locus</string>", "<string>mxlocation</string>")
if "<string>sidestore</string>" not in text:
    text = text.replace(
        "<string>localdevvpn</string>",
        "<string>localdevvpn</string>\n\t\t<string>sidestore</string>",
    )
plist.write_text(text, encoding="utf-8")

# Rebrand visible Swift literals while preserving machine identifiers/symbols.
string_re = re.compile(r'"(?:\\.|[^"\\])*"')


def replace_literal(match: re.Match[str]) -> str:
    value = match.group(0)
    if any(token in value for token in ("com.chrismack.locus", "locus://", "LocusApp", "Locus.")):
        return value
    # Preserve this machine-facing tunnel label as a compact identifier.
    value = value.replace("LocusLocation", "MXLocation")
    return value.replace("Locus", "MX Location")


for swift_file in (root / "Locus").rglob("*.swift"):
    source = swift_file.read_text(encoding="utf-8")
    swift_file.write_text(string_re.sub(replace_literal, source), encoding="utf-8")

# Runtime-only bridge: the host provides MXCertificateBridge. MX Location remains
# independently buildable because there is no link-time dependency on the host.
bridge_source = r'''import Foundation
import ObjectiveC.runtime

extension Notification.Name {
    static let mxCertificateRefreshStarted = Notification.Name("MXCertificateRefreshStarted")
    static let mxCertificateRefreshSucceeded = Notification.Name("MXCertificateRefreshSucceeded")
    static let mxCertificateRefreshFailed = Notification.Name("MXCertificateRefreshFailed")
}

struct MXCertificateSnapshot {
    let expirationDate: Date?
    let lastSuccessfulRefresh: Date?
    let status: String
    let engineReady: Bool
    let engineStatus: String
}

enum MXCertificateRenewal {
    private static let lastAttemptKey = "MXCertificateLastAutomaticAttempt"
    private static let pendingAttemptKey = "MXCertificatePendingAttempt"
    private static let pendingProcessKey = "MXCertificatePendingProcess"
    private static let expirationBeforeAttemptKey = "MXCertificateExpirationBeforeAttempt"
    private static let lastSuccessfulRefreshKey = "MXCertificateLastSuccessfulRefresh"
    private static let lastResultKey = "MXCertificateLastResult"
    private static let managedExpirationKey = "MXRenewalManagedExpiration"
    private static let engineReadyKey = "MXRenewalEngineReady"
    private static let engineStatusKey = "MXRenewalEngineStatus"
    private static let v106StatusMigrationKey = "MXCertificateV106StatusMigration"
    private static let processIdentifier = UUID().uuidString
    private static let relaunchedFailureGracePeriod: TimeInterval = 5 * 60

    @discardableResult
    static func renewNow() -> Bool {
        let defaults = UserDefaults.standard
        let now = Date()

        refreshHostMetadata()
        guard defaults.bool(forKey: engineReadyKey) else {
            markFailed(defaults.string(forKey: engineStatusKey) ?? "Renewal Engine Setup required")
            return false
        }

        // Persist the attempt before the host replaces itself. iOS terminates
        // the running process during a successful self-refresh, so the result
        // is reconciled against the new provisioning profile on next launch.
        defaults.set(now, forKey: pendingAttemptKey)
        defaults.set(processIdentifier, forKey: pendingProcessKey)
        defaults.set(now, forKey: lastAttemptKey)
        defaults.set("Renewing…", forKey: lastResultKey)
        if let expiration = certificateExpirationDate() {
            defaults.set(expiration, forKey: expirationBeforeAttemptKey)
        } else {
            defaults.removeObject(forKey: expirationBeforeAttemptKey)
        }

        guard invokeHostSelector("refreshHostCertificate") else {
            markFailed("Signing engine unavailable")
            return false
        }
        return true
    }

    static func refreshAutomaticallyIfDue() {
        let defaults = UserDefaults.standard
        refreshHostMetadata()
        guard defaults.bool(forKey: engineReadyKey) else { return }
        guard defaults.object(forKey: lastSuccessfulRefreshKey) as? Date != nil else { return }
        guard defaults.object(forKey: pendingAttemptKey) as? Date == nil else { return }
        guard LocalDevVPN.isConnected else { return }
        let lastAttempt = defaults.object(forKey: lastAttemptKey) as? Date ?? .distantPast
        guard Date().timeIntervalSince(lastAttempt) >= 24 * 60 * 60 else { return }

        // Delay avoids competing with the map's first render and location setup.
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            if renewNow() {
                defaults.set(Date(), forKey: lastAttemptKey)
            }
        }
    }

    static func snapshot() -> MXCertificateSnapshot {
        migrateIncorrectInitialSuccessIfNeeded()
        refreshHostMetadata()
        reconcilePendingRefresh()
        let defaults = UserDefaults.standard
        return MXCertificateSnapshot(
            expirationDate: certificateExpirationDate(),
            lastSuccessfulRefresh: defaults.object(forKey: lastSuccessfulRefreshKey) as? Date,
            status: defaults.string(forKey: lastResultKey) ?? "Not refreshed yet",
            engineReady: defaults.bool(forKey: engineReadyKey),
            engineStatus: defaults.string(forKey: engineStatusKey) ?? "Checking…"
        )
    }

    @discardableResult
    static func openRenewalSetup() -> Bool {
        guard invokeHostSelector("openSigningManager") else {
            markFailed("Bundled signing engine unavailable")
            return false
        }
        return true
    }

    static func remainingText(until expiration: Date?, now: Date = Date()) -> String {
        guard let expiration else { return "Unavailable" }
        let remaining = expiration.timeIntervalSince(now)
        guard remaining > 0 else { return "Expired" }
        let totalHours = Int(remaining / 3600)
        return "\(totalHours / 24) days, \(totalHours % 24) hours"
    }

    static func dateText(_ date: Date?) -> String {
        guard let date else { return "Unavailable" }
        return certificateDateFormatter.string(from: date)
    }

    static func markSucceeded() {
        let defaults = UserDefaults.standard
        let successfulAttempt = defaults.object(forKey: pendingAttemptKey) as? Date ?? Date()
        defaults.set(successfulAttempt, forKey: lastSuccessfulRefreshKey)
        defaults.set("Succeeded", forKey: lastResultKey)
        clearPendingAttempt(defaults)
    }

    static func markFailed(_ message: String) {
        let defaults = UserDefaults.standard
        defaults.set("Failed: \(message)", forKey: lastResultKey)
        clearPendingAttempt(defaults)
    }

    private static var certificateDateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }

    private static func reconcilePendingRefresh() {
        let defaults = UserDefaults.standard
        guard let attempt = defaults.object(forKey: pendingAttemptKey) as? Date else { return }

        // RefreshAllApps may legitimately take several minutes. Scene changes
        // while its embedded SideStore process is working must not be treated as
        // a failure. In the process that started the operation, the host's
        // success/failure notification is authoritative.
        let initiatingProcess = defaults.string(forKey: pendingProcessKey)
        guard initiatingProcess != processIdentifier else { return }

        let previousExpiration = defaults.object(forKey: expirationBeforeAttemptKey) as? Date
        let currentExpiration = certificateExpirationDate()
        if let currentExpiration {
            if let previousExpiration {
                if currentExpiration.timeIntervalSince(previousExpiration) > 1 {
                    markSucceeded()
                    return
                }
            } else {
                markSucceeded()
                return
            }
        }

        // A successful self-replacement terminates MX Location. On the next
        // launch the changed profile above proves success. If iOS relaunched us
        // while the helper is still finishing, retain the pending state for the
        // same six-minute window used by the host-side refresh timeout.
        if Date().timeIntervalSince(attempt) > relaunchedFailureGracePeriod {
            markFailed("Certificate expiry did not change")
        }
    }

    private static func clearPendingAttempt(_ defaults: UserDefaults) {
        defaults.removeObject(forKey: pendingAttemptKey)
        defaults.removeObject(forKey: pendingProcessKey)
        defaults.removeObject(forKey: expirationBeforeAttemptKey)
    }

    private static func migrateIncorrectInitialSuccessIfNeeded() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: v106StatusMigrationKey) else { return }

        // Older builds treated the initial SideStore database timestamp as a
        // completed renewal. Reset that inherited state; only an expiry change
        // after Renew Certificate Now is considered a successful renewal.
        defaults.removeObject(forKey: lastSuccessfulRefreshKey)
        clearPendingAttempt(defaults)
        defaults.set("Not refreshed yet", forKey: lastResultKey)
        defaults.set(true, forKey: v106StatusMigrationKey)
    }

    private static func certificateExpirationDate() -> Date? {
        let managedExpiration = UserDefaults.standard.object(forKey: managedExpirationKey) as? Date
        var embeddedExpiration: Date?
        var directory = Bundle.main.bundleURL.standardizedFileURL
        for _ in 0..<5 {
            let profileURL = directory.appendingPathComponent("embedded.mobileprovision")
            if let data = try? Data(contentsOf: profileURL),
               let expiration = expirationDate(fromProvisioningProfile: data) {
                embeddedExpiration = expiration
                break
            }
            directory.deleteLastPathComponent()
        }

        return [managedExpiration, embeddedExpiration]
            .compactMap { $0 }
            .max()
    }

    private static func expirationDate(fromProvisioningProfile data: Data) -> Date? {
        let xmlStart = Data("<?xml".utf8)
        let plistEnd = Data("</plist>".utf8)
        guard let startRange = data.range(of: xmlStart),
              let endRange = data.range(of: plistEnd, options: [], in: startRange.lowerBound..<data.endIndex)
        else { return nil }

        let plistData = data.subdata(in: startRange.lowerBound..<endRange.upperBound)
        guard let plist = try? PropertyListSerialization.propertyList(from: plistData, options: [], format: nil),
              let dictionary = plist as? [String: Any]
        else { return nil }
        return dictionary["ExpirationDate"] as? Date
    }

    private static func invokeHostSelector(_ selectorName: String) -> Bool {
        guard let bridgeClass = NSClassFromString("MXCertificateBridge") else {
            return false
        }

        let selector = NSSelectorFromString(selectorName)
        guard let method = class_getClassMethod(bridgeClass, selector) else {
            return false
        }

        typealias ClassMethod = @convention(c) (AnyClass, Selector) -> Void
        let implementation = method_getImplementation(method)
        unsafeBitCast(implementation, to: ClassMethod.self)(bridgeClass, selector)
        return true
    }

    private static func refreshHostMetadata() {
        _ = invokeHostSelector("refreshRenewalMetadata")
    }
}
'''
(root / "Locus/Support/MXCertificateRenewal.swift").write_text(bridge_source, encoding="utf-8")

settings = root / "Locus/Features/Settings/SettingsView.swift"
settings_text = settings.read_text(encoding="utf-8")
state_needle = "    @State private var localDevVPNInstalled = LocalDevVPN.isInstalled\n"
if state_needle not in settings_text:
    raise RuntimeError("Unable to locate MX Location Settings state insertion point")
settings_text = settings_text.replace(
    state_needle,
    state_needle
    + '    @State private var certificateExpiration: Date?\n'
    + '    @State private var certificateLastSuccess: Date?\n'
    + '    @State private var certificateStatus = "Not refreshed yet"\n'
    + '    @State private var certificateEngineReady = false\n'
    + '    @State private var certificateEngineStatus = "Checking…"\n'
    + "    @State private var certificateRefreshRunning = false\n",
)

section_needle = '                Section("Privacy") {\n'
certificate_section = '''                Section {
                    TimelineView(.periodic(from: .now, by: 60)) { context in
                        LabeledContent(
                            "Time remaining",
                            value: MXCertificateRenewal.remainingText(
                                until: certificateExpiration,
                                now: context.date
                            )
                        )
                    }

                    LabeledContent(
                        "Expires",
                        value: MXCertificateRenewal.dateText(certificateExpiration)
                    )

                    LabeledContent(
                        "Last successful renewal",
                        value: MXCertificateRenewal.dateText(certificateLastSuccess)
                    )

                    LabeledContent("Refresh status") {
                        Text(certificateStatus)
                            .foregroundStyle(
                                certificateStatus.hasPrefix("Succeeded")
                                    ? LocusTheme.statusGood
                                    : certificateStatus.hasPrefix("Failed")
                                        ? LocusTheme.statusBad
                                        : LocusTheme.statusWarn
                            )
                    }

                    LabeledContent("Renewal engine") {
                        Text(certificateEngineStatus)
                            .foregroundStyle(
                                certificateEngineReady
                                    ? LocusTheme.statusGood
                                    : LocusTheme.statusWarn
                            )
                    }

                    Button {
                        _ = MXCertificateRenewal.openRenewalSetup()
                    } label: {
                        Label(
                            certificateEngineReady ? "MX Signing Settings" : "Open MX Signing Setup",
                            systemImage: "key.fill"
                        )
                    }

                    Button {
                        guard LocalDevVPN.isConnected else {
                            MXCertificateRenewal.markFailed("Connect LocalDevVPN first")
                            reloadCertificateInfo()
                            return
                        }
                        if MXCertificateRenewal.renewNow() {
                            certificateRefreshRunning = true
                            certificateStatus = "Renewing…"
                        } else {
                            certificateRefreshRunning = false
                        }
                        reloadCertificateInfo()
                    } label: {
                        Label(
                            certificateRefreshRunning ? "Renewing Certificate…" : "Renew Certificate Now",
                            systemImage: "checkmark.shield.fill"
                        )
                    }
                    .disabled(certificateRefreshRunning)
                } header: {
                    Text("Certificate")
                } footer: {
                    Text("One-time setup: open the signing engine built into MX Location, sign in, choose the pairing file, then use + to install this same IPA from Files once. A separate SideStore app is not required. After setup, connect LocalDevVPN before renewing. Renewal stops with an error after 4 minutes instead of hanging.")
                }

'''
if section_needle not in settings_text:
    raise RuntimeError("Unable to locate MX Location Settings section insertion point")
settings_text = settings_text.replace(section_needle, certificate_section + section_needle)

receiver_needle = '''            .onAppear {
                localDevVPNInstalled = LocalDevVPN.isInstalled
            }
'''
receiver_replacement = '''            .onAppear {
                localDevVPNInstalled = LocalDevVPN.isInstalled
                reloadCertificateInfo()
            }
            .onReceive(NotificationCenter.default.publisher(for: .mxCertificateRefreshStarted)) { _ in
                certificateRefreshRunning = true
                certificateStatus = "Renewing…"
            }
            .onReceive(NotificationCenter.default.publisher(for: .mxCertificateRefreshSucceeded)) { _ in
                certificateRefreshRunning = false
                reloadCertificateInfo()
            }
            .onReceive(NotificationCenter.default.publisher(for: .mxCertificateRefreshFailed)) { notification in
                certificateRefreshRunning = false
                reloadCertificateInfo()
            }
'''
if receiver_needle not in settings_text:
    raise RuntimeError("Unable to locate MX Location Settings receiver insertion point")
settings.write_text(settings_text.replace(receiver_needle, receiver_replacement), encoding="utf-8")

# Remove the upstream About/easter-egg copy and keep only the requested product identity.
settings_text = settings.read_text(encoding="utf-8")
settings_text = settings_text.replace("    @State private var showNameEasterEgg = false\n", "")
settings_text = settings_text.replace(
    '''    private var appVersion: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? ""
        return build.isEmpty ? short : "\\(short) (\\(build))"
    }

''',
    "",
)
about_needle = '''                Section("About") {
                    LabeledContent("Version", value: appVersion)
                    LabeledContent("Engine", value: "idevice DVT location simulation")
                    Text("MX Location is free and open source (MIT). Location injection uses the MIT-licensed idevice FFI.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section {
                    Button {
                        showNameEasterEgg = true
                    } label: {
                        Text("locus, n. — a place. From the Latin for where you are.")
                            .font(.footnote.italic())
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 4)
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }
'''
about_replacement = '''                Section("About") {
                    Text("MazenmiX (Mazen Mozh) Products")
                        .font(.headline)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
'''
if about_needle not in settings_text:
    raise RuntimeError("Unable to replace MX Location About section")
settings_text = settings_text.replace(about_needle, about_replacement)
settings_text = settings_text.replace(
    '''            .fullScreenCover(isPresented: $showNameEasterEgg) {
                LocusEasterEggView()
            }
''',
    "",
)

# Keep certificate fields synchronized when returning from the system or VPN.
settings_end_needle = '''            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    localDevVPNInstalled = LocalDevVPN.isInstalled
                }
            }
        }
    }
}
'''
settings_end_replacement = '''            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    localDevVPNInstalled = LocalDevVPN.isInstalled
                    reloadCertificateInfo()
                }
            }
        }
    }

    private func reloadCertificateInfo() {
        let snapshot = MXCertificateRenewal.snapshot()
        certificateExpiration = snapshot.expirationDate
        certificateLastSuccess = snapshot.lastSuccessfulRefresh
        certificateStatus = snapshot.status
        certificateEngineReady = snapshot.engineReady
        certificateEngineStatus = snapshot.engineStatus
        certificateRefreshRunning = snapshot.status == "Renewing…"
    }
}
'''
if settings_end_needle not in settings_text:
    raise RuntimeError("Unable to add certificate snapshot reload helper")
settings.write_text(settings_text.replace(settings_end_needle, settings_end_replacement), encoding="utf-8")

root_view = root / "Locus/Features/Map/RootView.swift"
root_text = root_view.read_text(encoding="utf-8")
if 'Text("Teleport")' not in root_text:
    raise RuntimeError("Unable to locate Teleport button label")
root_text = root_text.replace('Text("Teleport")', 'Text("Change")', 1)
root_needle = '''        .alert("MX Location", isPresented: Binding(
'''
if root_needle not in root_text:
    # Upstream source is patched after branding, so provide a diagnostic if it changes.
    raise RuntimeError("Unable to locate MX Location RootView insertion point")
root_text = root_text.replace(
    root_needle,
    '''        .onAppear {
            MXCertificateRenewal.refreshAutomaticallyIfDue()
        }
''' + root_needle,
)
root_view.write_text(root_text, encoding="utf-8")

(root / "MX_LOCATION_NOTICE.md").write_text(
    "# MX Location Self-Refresh Build\n\n"
    "MX Location is derived from the MIT-licensed Locus project. This build is "
    "designed to run as the bundled guest inside the AGPL-3.0 LiveContainer + "
    "SideStore host. Upstream licenses are retained.\n",
    encoding="utf-8",
)

print("Patched MX Location source at", root)
