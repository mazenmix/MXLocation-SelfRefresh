"""Apply the focused MX Dating Edition UI after patch_mx_pro.py."""
from pathlib import Path
import sys

root = Path(sys.argv[1]).resolve()
repo = Path(__file__).resolve().parent.parent
target = root / "Locus/Features/Map"
shell = target / "MXProPremiumShell.swift"
assert shell.exists(), "Apply patch_mx_pro.py first."
text = shell.read_text(encoding="utf-8")
start = text.index("struct MXProPremiumRoot: View {")
end = text.index("// Look Around imagery", start)
replacement = '''struct MXProPremiumRoot: View {
    @EnvironmentObject private var session: SpoofSession
    @StateObject private var navigation = MXPremiumNavigation()

    var body: some View {
        TabView(selection: $navigation.tab) {
            MXDatingExploreHome()
                .tabItem { Label("Explore", systemImage: "map.fill") }
                .tag(0)
            MXDatingWingmanScreen()
                .tabItem { Label("Wingman", systemImage: "heart.text.square.fill") }
                .tag(1)
        }
        .environmentObject(navigation)
        .tint(MXPremiumStyle.cyan)
        .preferredColorScheme(.dark)
        .alert("MX Location Pro", isPresented: Binding(
            get: { session.lastError != nil },
            set: { if !$0 { session.lastError = nil } }
        )) {
            Button("OK", role: .cancel) { session.lastError = nil }
        } message: {
            Text(session.lastError ?? "")
        }
    }
}

'''
shell.write_text(text[:start] + replacement + text[end:], encoding="utf-8")

source = repo / "overlays/MXDatingEdition.swift"
assert source.exists()
(target / source.name).write_bytes(source.read_bytes())

# Existing shortcuts now open Dating Radar inside Explore instead of a removed tab.
map_file = target / "MapHomeView.swift"
map_text = map_file.read_text(encoding="utf-8")
map_text = map_text.replace("premiumNavigation.tab = 1", "premiumNavigation.tab = 0")

# Remove the redundant "MX Pro" launch button: advanced tools remain available
# through the existing GPS controls and Explore map workflow.
button_start = map_text.find("                HStack(spacing: 8) {\n                    searchBar\n                    Button {\n                        searchFocused = false\n                        showMXProHub = true")
if button_start >= 0:
    button_end = map_text.find('                }\n', map_text.find('.accessibilityIdentifier("mxProHubMapButton")', button_start))
    if button_end >= 0:
        map_text = map_text[:button_start] + "                searchBar\n" + map_text[button_end + len("                }\n"):]

# Replace the six quick links with a single Dating Radar entry point.
list_start = map_text.find("                ScrollView(.horizontal, showsIndicators: false) {\n                    HStack(spacing: 8) {\n                        ForEach([MXPremiumCategory")
if list_start >= 0:
    list_end_marker = '                .accessibilityIdentifier("mxPremiumMapCategories")\n                Spacer(minLength: 0)\n'
    list_end = map_text.find(list_end_marker, list_start)
    assert list_end > list_start, "Expected category bar end marker"
    list_end += len(list_end_marker)
    simpler = '''                Button {
                    searchFocused = false
                    premiumNavigation.category = .dateSpots
                    premiumNavigation.openCategory = true
                    premiumNavigation.tab = 0
                } label: {
                    Label("Dating Radar", systemImage: "heart.fill")
                        .font(.subheadline.weight(.semibold))
                        .padding(10)
                        .foregroundStyle(.white)
                        .background(Color(red: 0.12, green: 0.34, blue: 0.62),
                                    in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("mxDatingRadarMapButton")
                Spacer(minLength: 0)
'''
    map_text = map_text[:list_start] + simpler + map_text[list_end:]
map_file.write_text(map_text, encoding="utf-8")
assert 'MXDatingWingmanScreen()' in shell.read_text(encoding='utf-8')
assert 'MXDatingExploreHome()' in shell.read_text(encoding='utf-8')
print("Dating Edition: 2 tabs; Map / Radar / GPS; on-device Wingman and translator.")
