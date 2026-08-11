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

enum MXCertificateRenewal {
    private static let lastAttemptKey = "MXCertificateLastAutomaticAttempt"

    @discardableResult
    static func renewNow() -> Bool {
        invokeHostSelector("refreshHostCertificate")
    }

    @discardableResult
    static func openSigningManager() -> Bool {
        invokeHostSelector("openSigningManager")
    }

    static func refreshAutomaticallyIfDue() {
        let defaults = UserDefaults.standard
        let lastAttempt = defaults.object(forKey: lastAttemptKey) as? Date ?? .distantPast
        guard Date().timeIntervalSince(lastAttempt) >= 24 * 60 * 60 else { return }

        // Delay avoids competing with the map's first render and location setup.
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            if renewNow() {
                defaults.set(Date(), forKey: lastAttemptKey)
            }
        }
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
    + '    @State private var certificateStatus = "Ready"\n'
    + "    @State private var certificateRefreshRunning = false\n",
)

section_needle = '                Section("Privacy") {\n'
certificate_section = '''                Section {
                    Button {
                        certificateRefreshRunning = true
                        certificateStatus = "Starting refresh…"
                        if !MXCertificateRenewal.renewNow() {
                            certificateRefreshRunning = false
                            certificateStatus = "Built-in signing engine unavailable"
                        }
                    } label: {
                        Label(
                            certificateRefreshRunning ? "Renewing Certificate…" : "Renew Certificate Now",
                            systemImage: "checkmark.shield.fill"
                        )
                    }
                    .disabled(certificateRefreshRunning)

                    Button {
                        if !MXCertificateRenewal.openSigningManager() {
                            certificateStatus = "Built-in signing manager unavailable"
                        }
                    } label: {
                        Label("Open Signing Manager", systemImage: "person.badge.key.fill")
                    }

                    LabeledContent("Refresh status", value: certificateStatus)
                } header: {
                    Text("Certificate")
                } footer: {
                    Text("Connect LocalDevVPN before renewing. The signing engine is built into MX Location; a separate SideStore app is not required after setup.")
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
            }
            .onReceive(NotificationCenter.default.publisher(for: .mxCertificateRefreshStarted)) { _ in
                certificateRefreshRunning = true
                certificateStatus = "Renewing…"
            }
            .onReceive(NotificationCenter.default.publisher(for: .mxCertificateRefreshSucceeded)) { _ in
                certificateRefreshRunning = false
                certificateStatus = "Renewed successfully"
            }
            .onReceive(NotificationCenter.default.publisher(for: .mxCertificateRefreshFailed)) { notification in
                certificateRefreshRunning = false
                certificateStatus = notification.userInfo?["error"] as? String ?? "Refresh failed"
            }
'''
if receiver_needle not in settings_text:
    raise RuntimeError("Unable to locate MX Location Settings receiver insertion point")
settings.write_text(settings_text.replace(receiver_needle, receiver_replacement), encoding="utf-8")

root_view = root / "Locus/Features/Map/RootView.swift"
root_text = root_view.read_text(encoding="utf-8")
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
