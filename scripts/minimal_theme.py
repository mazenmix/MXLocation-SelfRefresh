from pathlib import Path
import json
import re
import shutil
import sys


root = Path(sys.argv[1]).resolve()
logo_source = Path(sys.argv[2]).resolve() if len(sys.argv) > 2 else None

# -----------------------------------------------------------------------------
# 1) Persisted Light / Dark appearance for the whole app.
# -----------------------------------------------------------------------------
app_file = root / "Locus/App/LocusApp.swift"
app = app_file.read_text(encoding="utf-8")

setup_state = "    @AppStorage(SetupGate.defaultsKey) private var setupComplete = false\n"
if setup_state not in app:
    raise RuntimeError("Unable to find setupComplete AppStorage in LocusApp.swift")
if 'mxAppearance' not in app:
    app = app.replace(
        setup_state,
        setup_state + '    @AppStorage("mxAppearance") private var mxAppearance = "dark"\n',
        1,
    )

if ".preferredColorScheme(.dark)" not in app:
    raise RuntimeError("Unable to find hard-coded dark appearance in LocusApp.swift")
app = app.replace(
    ".preferredColorScheme(.dark)",
    '.preferredColorScheme(mxAppearance == "light" ? .light : .dark)',
    1,
)
app_file.write_text(app, encoding="utf-8")

# -----------------------------------------------------------------------------
# 2) Make the Map obey the same appearance and remove hard-coded black backing.
#    Standard Apple Maps tiles follow the SwiftUI color scheme; the chrome and
#    map background now switch with the selected appearance as well.
# -----------------------------------------------------------------------------
map_file = root / "Locus/Features/Map/MapHomeView.swift"
map_text = map_file.read_text(encoding="utf-8")

pairing_state = "    @EnvironmentObject private var pairing: PairingStore\n"
if pairing_state not in map_text:
    raise RuntimeError("Unable to find MapHomeView pairing environment object")
if 'mxAppearance' not in map_text:
    map_text = map_text.replace(
        pairing_state,
        pairing_state + '    @AppStorage("mxAppearance") private var mxAppearance = "dark"\n',
        1,
    )

map_style_line = "                .mapStyle(mapStyle)\n"
if map_style_line not in map_text:
    raise RuntimeError("Unable to find Map mapStyle modifier")
if '.environment(\\.colorScheme, mxAppearance == "light" ? .light : .dark)' not in map_text:
    map_text = map_text.replace(
        map_style_line,
        map_style_line + '                .environment(\\.colorScheme, mxAppearance == "light" ? .light : .dark)\n',
        1,
    )

map_text = map_text.replace(
    ".background(Color.black.ignoresSafeArea())",
    ".background(Color(uiColor: .systemBackground).ignoresSafeArea())",
)
map_file.write_text(map_text, encoding="utf-8")

# Pairing sheet should also honor Light / Dark instead of forcing black.
pair_view = root / "Locus/Features/Settings/PairOnDeviceView.swift"
pair_view_text = pair_view.read_text(encoding="utf-8")
pair_view_text = pair_view_text.replace(
    ".background(Color.black.ignoresSafeArea())",
    ".background(Color(uiColor: .systemBackground).ignoresSafeArea())",
)
pair_view.write_text(pair_view_text, encoding="utf-8")

# -----------------------------------------------------------------------------
# 3) Make the 6-digit pairing code impossible to miss in the local notification.
#    The code is placed in both title and body. Existing time-sensitive delivery
#    and permission request remain untouched.
# -----------------------------------------------------------------------------
pair_service = root / "Locus/Engine/PairOnDeviceService.swift"
service = pair_service.read_text(encoding="utf-8")
notification_pattern = re.compile(
    r'content\.title = "(?:MX Location|Locus) pairing code"\n\s*content\.body = pin'
)
service, n = notification_pattern.subn(
    'content.title = "MX Location pairing code: \\(pin)"\n        content.body = "Pairing code: \\(pin)"',
    service,
    count=1,
)
if n != 1:
    raise RuntimeError("Unable to patch pairing-code notification")
pair_service.write_text(service, encoding="utf-8")

# -----------------------------------------------------------------------------
# 4) Replace Settings with the requested minimal UI only:
#       - Light / Dark
#       - certificate time remaining
#       - MX logo + Mazen Mozh
#    No pairing-file import/export/paste/remove, renewal controls/status, tunnel,
#    privacy, version, engine, or explanatory text is shown.
#    PlacesView is preserved verbatim because it lives in the same Swift file.
# -----------------------------------------------------------------------------
settings_file = root / "Locus/Features/Settings/SettingsView.swift"
settings_text = settings_file.read_text(encoding="utf-8")
marker = "struct PlacesView: View {"
if marker not in settings_text:
    raise RuntimeError("Unable to preserve PlacesView from SettingsView.swift")
places_tail = marker + settings_text.split(marker, 1)[1]

minimal_settings = r'''import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("mxAppearance") private var mxAppearance = "dark"
    @State private var certificateExpiration: Date?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("Appearance", selection: $mxAppearance) {
                        Label("Light", systemImage: "sun.max.fill").tag("light")
                        Label("Dark", systemImage: "moon.fill").tag("dark")
                    }
                    .pickerStyle(.segmented)
                }

                Section {
                    TimelineView(.periodic(from: .now, by: 60)) { context in
                        LabeledContent(
                            "Time remaining",
                            value: MXCertificateRenewal.remainingText(
                                until: certificateExpiration,
                                now: context.date
                            )
                        )
                    }
                }

                Section {
                    VStack(spacing: 10) {
                        Image("MXLogo")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 72, height: 72)
                            .clipShape(RoundedRectangle(cornerRadius: 17, style: .continuous))

                        Text("Mazen Mozh")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear(perform: reloadCertificateInfo)
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    reloadCertificateInfo()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .mxCertificateRefreshSucceeded)) { _ in
                reloadCertificateInfo()
            }
            .onReceive(NotificationCenter.default.publisher(for: .mxCertificateRefreshFailed)) { _ in
                reloadCertificateInfo()
            }
        }
    }

    private func reloadCertificateInfo() {
        certificateExpiration = MXCertificateRenewal.snapshot().expirationDate
    }
}

'''
settings_file.write_text(minimal_settings + places_tail, encoding="utf-8")

# -----------------------------------------------------------------------------
# 5) Add the actual MX icon as a normal image asset so it can be shown in Settings.
# -----------------------------------------------------------------------------
logo_dir = root / "Locus/Resources/Assets.xcassets/MXLogo.imageset"
logo_dir.mkdir(parents=True, exist_ok=True)
contents = {
    "images": [
        {"filename": "MXLogo.png", "idiom": "universal", "scale": "1x"},
        {"idiom": "universal", "scale": "2x"},
        {"idiom": "universal", "scale": "3x"},
    ],
    "info": {"author": "xcode", "version": 1},
}
(logo_dir / "Contents.json").write_text(json.dumps(contents, indent=2) + "\n", encoding="utf-8")

if logo_source is None or not logo_source.is_file():
    raise RuntimeError("MX logo source image is missing")
shutil.copy2(logo_source, logo_dir / "MXLogo.png")

print("Applied MX minimal Settings, Light/Dark map appearance, pairing-code notification, and logo branding")
