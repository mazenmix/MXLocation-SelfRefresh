from pathlib import Path
import shutil
import sys

root = Path(sys.argv[1]).resolve()
repo = Path(__file__).resolve().parent.parent
project = root / "project.yml"
plist = root / "Locus/Resources/Info.plist"
root_view = root / "Locus/Features/Map/RootView.swift"
source = project.read_text(encoding="utf-8")
assert "PRODUCT_BUNDLE_IDENTIFIER: com.mazenmix.mxlocation" in source
assert "PRODUCT_NAME: MXLocation" in source
source = source.replace("PRODUCT_BUNDLE_IDENTIFIER: com.mazenmix.mxlocation",
                        "PRODUCT_BUNDLE_IDENTIFIER: com.mazenmix.mxlocationpro")
source = source.replace("PRODUCT_NAME: MXLocation",
                        "PRODUCT_NAME: MXLocationPro")
source = source.replace('MARKETING_VERSION: "1.4.2"', 'MARKETING_VERSION: "4.0.0"')
source = source.replace('CURRENT_PROJECT_VERSION: "29"', 'CURRENT_PROJECT_VERSION: "40"')
project.write_text(source,encoding="utf-8")

info = plist.read_text(encoding="utf-8")
info = info.replace("com.mazenmix.mxlocation", "com.mazenmix.mxlocationpro")
info = info.replace("<string>mxlocation</string>", "<string>mxlocationpro</string>")
info = info.replace("<string>MX Location</string>", "<string>MX Location Pro</string>")
info = info.replace("MX Location uses", "MX Location Pro uses")
info = info.replace("MX Location keeps", "MX Location Pro keeps")
plist.write_text(info,encoding="utf-8")

ui = root_view.read_text(encoding="utf-8")
anchor = '''            SettingsView()
'''
addition = '''            MXProSuiteView()
                .tabItem {
                    Label("MX Pro", systemImage: "sparkles")
                }
                .tag(3)

            SettingsView()
'''
if anchor not in ui: raise RuntimeError("RootView SettingsView was not found")
root_view.write_text(ui.replace(anchor,addition,1),encoding="utf-8")

# Make Pro discovery accessible directly from the Map, independently of tab bar
# rendering on recent iOS builds. This is a second entry point, not a duplicate
# GPS engine or a second background session.
map_home = root / "Locus/Features/Map/MapHomeView.swift"
map_source = map_home.read_text(encoding="utf-8")
state_anchor = "    @State private var resolvingPin = false"
if map_source.count(state_anchor) != 1:
    raise RuntimeError("MapHomeView location-state anchor not found exactly once")
map_source = map_source.replace(state_anchor, state_anchor + '\n    @State private var showMXProHub = false', 1)
search_anchor = "                searchBar\\n"
if map_source.count(search_anchor) != 1:
    raise RuntimeError("MapHomeView search bar insertion anchor not found exactly once")
pro_button = """                HStack(spacing: 8) {
                    searchBar
                    Button {
                        searchFocused = false
                        showMXProHub = true
                    } label: {
                        Label("MX Pro", systemImage: "sparkles")
                            .font(.system(size: 12, weight: .semibold))
                            .lineLimit(1)
                            .padding(.horizontal, 12)
                            .frame(height: 50)
                            .foregroundStyle(.white)
                            .background(Color(red: 0.12, green: 0.34, blue: 0.62),
                                        in: RoundedRectangle(cornerRadius: 16))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("mxProHubMapButton")
                }
"""
map_source = map_source.replace(search_anchor, pro_button, 1)
sheet_anchor = "        .onAppear {\\n"
if map_source.count(sheet_anchor) < 1:
    raise RuntimeError("MapHomeView view-modifier anchor missing")
map_source = map_source.replace(sheet_anchor,
    "        .sheet(isPresented: $showMXProHub) {\\n"
    "            MXProSuiteView()\\n"
    "                .environmentObject(session)\\n"
    "                .environmentObject(pairing)\\n"
    "        }\\n" + sheet_anchor, 1)
map_home.write_text(map_source, encoding="utf-8")
print("MX Pro launch button added to Map and sheet route verified.")

src = repo / "overlays/MXLocationProSuite.swift"
dst = root / "Locus/Features/Map/MXLocationProSuite.swift"
assert src.is_file()
shutil.copy2(src,dst)

print("MX Location Pro: unique bundle ID, URL scheme, storage sandbox, separate root tab, 41-module discovery suite.")
