from pathlib import Path
import re
import sys


root = Path(sys.argv[1]).resolve()


def replace_required(path: Path, old: str, new: str) -> None:
    text = path.read_text(encoding="utf-8")
    if old not in text:
        raise RuntimeError(f"Required source fragment not found in {path}: {old[:120]!r}")
    path.write_text(text.replace(old, new, 1), encoding="utf-8")


# Product identity. Keep the internal target/scheme named Locus for build stability.
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
text = text.replace(
    "Locus keeps a light location session alive",
    "MX Location keeps a light location session alive",
)
text = text.replace("Locus uses the local network", "MX Location uses the local network")
text = text.replace("com.chrismack.locus.rppairing", "com.mazenmix.mxlocation.rppairing")
text = text.replace("<string>com.chrismack.locus</string>", "<string>com.mazenmix.mxlocation</string>")
text = text.replace("<string>locus</string>", "<string>mxlocation</string>")
plist.write_text(text, encoding="utf-8")

# Rebrand visible Swift literals while preserving machine identifiers/symbols.
string_re = re.compile(r'"(?:\\.|[^"\\])*"')


def replace_literal(match: re.Match[str]) -> str:
    value = match.group(0)
    if any(token in value for token in ("com.chrismack.locus", "locus://", "LocusApp", "Locus.")):
        return value
    value = value.replace("LocusLocation", "MXLocation")
    return value.replace("Locus", "MX Location")


for swift_file in (root / "Locus").rglob("*.swift"):
    source = swift_file.read_text(encoding="utf-8")
    swift_file.write_text(string_re.sub(replace_literal, source), encoding="utf-8")


# Lightweight certificate display only. There is deliberately no renewal/signing engine.
certificate_source = r'''import Foundation

enum MXCertificateInfo {
    static func expirationDate() -> Date? {
        var directory = Bundle.main.bundleURL.standardizedFileURL

        for _ in 0..<5 {
            let profileURL = directory.appendingPathComponent("embedded.mobileprovision")
            if let data = try? Data(contentsOf: profileURL),
               let expiration = expirationDate(fromProvisioningProfile: data) {
                return expiration
            }
            directory.deleteLastPathComponent()
        }

        return nil
    }

    static func remainingText(until expiration: Date?, now: Date = Date()) -> String {
        guard let expiration else { return "Unavailable" }
        let remaining = expiration.timeIntervalSince(now)
        guard remaining > 0 else { return "Expired" }

        let totalHours = Int(remaining / 3600)
        let days = totalHours / 24
        let hours = totalHours % 24
        return "\(days) days, \(hours) hours"
    }

    private static func expirationDate(fromProvisioningProfile data: Data) -> Date? {
        let xmlStart = Data("<?xml".utf8)
        let plistEnd = Data("</plist>".utf8)

        guard let startRange = data.range(of: xmlStart),
              let endRange = data.range(
                of: plistEnd,
                options: [],
                in: startRange.lowerBound..<data.endIndex
              )
        else {
            return nil
        }

        let plistData = data.subdata(in: startRange.lowerBound..<endRange.upperBound)
        guard let plist = try? PropertyListSerialization.propertyList(
            from: plistData,
            options: [],
            format: nil
        ),
        let dictionary = plist as? [String: Any]
        else {
            return nil
        }

        return dictionary["ExpirationDate"] as? Date
    }
}
'''
(root / "Locus/Support/MXCertificateInfo.swift").write_text(certificate_source, encoding="utf-8")


# Keep Settings compact: pairing, certificate time remaining, and About.
settings = root / "Locus/Features/Settings/SettingsView.swift"
settings_text = settings.read_text(encoding="utf-8")

settings_text = settings_text.replace("    @State private var showNameEasterEgg = false\n", "", 1)
settings_text = settings_text.replace(
    "    @State private var localDevVPNInstalled = LocalDevVPN.isInstalled\n",
    "    @State private var certificateExpiration = MXCertificateInfo.expirationDate()\n",
    1,
)

app_version = '''    private var appVersion: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? ""
        return build.isEmpty ? short : "\\(short) (\\(build))"
    }

'''
if app_version not in settings_text:
    raise RuntimeError("Unable to remove Settings appVersion helper")
settings_text = settings_text.replace(app_version, "", 1)

pairing_footer = re.compile(
    r'''(                \} header: \{\n                    Text\("Developer pairing"\)\n                \}) footer: \{\n                    Text\(supportsOnDevicePairing\n.*?                \}\n''',
    re.DOTALL,
)
settings_text, count = pairing_footer.subn(r"\1\n", settings_text, count=1)
if count != 1:
    raise RuntimeError("Unable to remove Developer pairing footer")

tunnel_section = '''                Section {
                    TextField("Device tunnel IP", text: $tunnelIP)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .onSubmit {
                            TunnelConfig.setTargetIP(tunnelIP)
                        }
                    LabeledContent("Status") {
                        Text(LocalDevVPN.isConnected ? "Connected" : "Not connected")
                            .foregroundStyle(LocalDevVPN.isConnected ? LocusTheme.statusGood : LocusTheme.statusWarn)
                    }
                    Button("Save tunnel IP") {
                        TunnelConfig.setTargetIP(tunnelIP)
                    }
                    Button {
                        if localDevVPNInstalled {
                            LocalDevVPN.openInstalled()
                        } else {
                            LocalDevVPN.openAppStore()
                        }
                    } label: {
                        Label(
                            localDevVPNInstalled ? "Open LocalDevVPN" : "Get LocalDevVPN (App Store)",
                            systemImage: localDevVPNInstalled ? "lock.shield.fill" : "arrow.down.app.fill"
                        )
                    }
                } header: {
                    Text("Tunnel")
                } footer: {
                    Text("Connect LocalDevVPN before teleporting. Default tunnel IP is 10.7.0.1. Start a spoof on Wi‑Fi first; it can keep working on cellular afterward.")
                }

'''
if tunnel_section not in settings_text:
    raise RuntimeError("Unable to remove Tunnel section")
settings_text = settings_text.replace(tunnel_section, "", 1)

privacy_section = '''                Section("Privacy") {
                    Text("Fully on-device. Favorites and recents stay in UserDefaults. No analytics, no accounts, nothing uploaded.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

'''
if privacy_section not in settings_text:
    raise RuntimeError("Unable to remove Privacy section")
settings_text = settings_text.replace(privacy_section, "", 1)

about_and_easter = '''                Section("About") {
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
replacement = '''                Section {
                    TimelineView(.periodic(from: .now, by: 60)) { context in
                        LabeledContent(
                            "Time remaining",
                            value: MXCertificateInfo.remainingText(
                                until: certificateExpiration,
                                now: context.date
                            )
                        )
                    }
                }

                Section("About") {
                    Text("MazenmiX (Mazen Mozh) Products")
                        .font(.headline)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
'''
if about_and_easter not in settings_text:
    raise RuntimeError("Unable to replace About/easter-egg sections")
settings_text = settings_text.replace(about_and_easter, replacement, 1)

full_screen_cover = '''            .fullScreenCover(isPresented: $showNameEasterEgg) {
                LocusEasterEggView()
            }
'''
if full_screen_cover not in settings_text:
    raise RuntimeError("Unable to remove easter-egg cover")
settings_text = settings_text.replace(full_screen_cover, "", 1)

appearance_block = '''            .onAppear {
                localDevVPNInstalled = LocalDevVPN.isInstalled
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    localDevVPNInstalled = LocalDevVPN.isInstalled
                }
            }
'''
appearance_replacement = '''            .onAppear {
                certificateExpiration = MXCertificateInfo.expirationDate()
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    certificateExpiration = MXCertificateInfo.expirationDate()
                }
            }
'''
if appearance_block not in settings_text:
    raise RuntimeError("Unable to replace Settings lifecycle block")
settings_text = settings_text.replace(appearance_block, appearance_replacement, 1)
settings.write_text(settings_text, encoding="utf-8")


root_view = root / "Locus/Features/Map/RootView.swift"
root_text = root_view.read_text(encoding="utf-8")
if 'Text("Teleport")' not in root_text:
    raise RuntimeError("Unable to locate Teleport button label")
root_view.write_text(root_text.replace('Text("Teleport")', 'Text("Change")', 1), encoding="utf-8")


(root / "MX_LOCATION_NOTICE.md").write_text(
    "# MX Location Navigation Build\n\n"
    "This is a direct MX Location sideload build with no embedded SideStore, "
    "no LiveContainer host, and no renewal engine. Certificate time remaining "
    "is read locally from the installed provisioning profile.\n",
    encoding="utf-8",
)

print("Patched direct MX Location source at", root)
