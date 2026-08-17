from pathlib import Path
import json
import re
import shutil
import sys


root = Path(sys.argv[1]).resolve()
logo_source = Path(sys.argv[2]).resolve() if len(sys.argv) > 2 else None
bs = chr(92)

# 1) Persisted Light / Dark appearance for the whole app.
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

# 2) Make the map and its backing view obey the same appearance.
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
map_environment = f'.environment({bs}.colorScheme, mxAppearance == "light" ? .light : .dark)'
if map_environment not in map_text:
    map_text = map_text.replace(
        map_style_line,
        map_style_line + f'                {map_environment}\n',
        1,
    )
map_text = map_text.replace(
    ".background(Color.black.ignoresSafeArea())",
    ".background(Color(uiColor: UIColor.systemBackground).ignoresSafeArea())",
)
if "import UIKit\n" not in map_text:
    map_text = map_text.replace("import SwiftUI\n", "import SwiftUI\nimport UIKit\n", 1)
map_file.write_text(map_text, encoding="utf-8")

# Pairing sheet should not force black when Light is selected.
pair_view = root / "Locus/Features/Settings/PairOnDeviceView.swift"
pair_view_text = pair_view.read_text(encoding="utf-8")
pair_view_text = pair_view_text.replace(
    ".background(Color.black.ignoresSafeArea())",
    ".background(Color(uiColor: UIColor.systemBackground).ignoresSafeArea())",
)
if "import UIKit\n" not in pair_view_text:
    pair_view_text = pair_view_text.replace("import SwiftUI\n", "import SwiftUI\nimport UIKit\n", 1)
pair_view.write_text(pair_view_text, encoding="utf-8")

# 3) Put the 6-digit pairing code directly in both notification title and body.
pair_service = root / "Locus/Engine/PairOnDeviceService.swift"
service = pair_service.read_text(encoding="utf-8")
notification_pattern = re.compile(
    r'content\.title = "(?:MX Location|Locus) pairing code"\n\s*content\.body = pin'
)
notification_replacement = (
    f'content.title = "MX Location pairing code: {bs}(pin)"\n'
    f'        content.body = "Pairing code: {bs}(pin)"'
)
service, n = notification_pattern.subn(lambda _: notification_replacement, service, count=1)
if n != 1:
    raise RuntimeError("Unable to patch pairing-code notification")
pair_service.write_text(service, encoding="utf-8")

# 4) Replace Settings with exactly the requested minimal UI, preserving PlacesView.
settings_file = root / "Locus/Features/Settings/SettingsView.swift"
settings_text = settings_file.read_text(encoding="utf-8")
marker = "struct PlacesView: View {"
if marker not in settings_text:
    raise RuntimeError("Unable to preserve PlacesView from SettingsView.swift")
places_tail = marker + settings_text.split(marker, 1)[1]

minimal_settings = '''import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(__BS__.dismiss) private var dismiss
    @Environment(__BS__.scenePhase) private var scenePhase
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

'''.replace("__BS__", bs)
settings_file.write_text(minimal_settings + places_tail, encoding="utf-8")

# 5) Add the actual MX icon as a normal image asset for the footer.
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

print("Applied minimal Settings, Light/Dark map appearance, pairing-code notification, and MX branding")
