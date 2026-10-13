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
            MXSavedView(selectedTab: $navigation.tab)
                .tabItem { Label("Saved", systemImage: "star.fill") }
                .tag(1)
            MXDatingWingmanScreen()
                .tabItem { Label("Wingman", systemImage: "heart.text.square.fill") }
                .tag(2)
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

# Remove the old six-category map strip and its redundant blue Radar button.
# The new Explore overlay owns the glass navigation chips.
list_start = map_text.find("                ScrollView(.horizontal, showsIndicators: false) {\n                    HStack(spacing: 8) {\n                        ForEach([MXPremiumCategory")
if list_start >= 0:
    list_end_marker = '                .accessibilityIdentifier("mxPremiumMapCategories")\n                Spacer(minLength: 0)\n'
    list_end = map_text.find(list_end_marker, list_start)
    assert list_end > list_start, "Expected old category bar"
    list_end += len(list_end_marker)
    map_text = map_text[:list_start] + "                Spacer(minLength: 0)\n" + map_text[list_end:]
# No separate Map / Dating Radar / GPS Control segmented picker.
# The map's Change Location and Stop buttons remain unmodified.
map_file.write_text(map_text, encoding="utf-8")
assert 'MXDatingWingmanScreen()' in shell.read_text(encoding='utf-8')
assert 'MXDatingExploreHome()' in shell.read_text(encoding='utf-8')
print("Dating Edition 4.4: Explore/Wingman tabs; full-screen venue maps, GPS actions on Map.")

# Saved Worlds restoration and transient toast.
# Move the legacy banner out of the vertical map stack; it must not push
# the map/search down or remain in the middle of the map.
map_text = map_file.read_text(encoding="utf-8")
embedded = """                if showWorldActiveBanner, let world = activeWorldBanner {
                    worldActiveBanner(world)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }

"""
if map_text.count(embedded) != 1:
    raise RuntimeError("World Active banner must occur exactly once in map stack")
map_text = map_text.replace(embedded, "", 1)
map_overlay = """        .overlay(alignment: .top) {
            if showWorldActiveBanner, let world = activeWorldBanner {
                worldActiveBanner(world)
                    .padding(.horizontal, 20)
                    .padding(.top, 1)
                    .transition(.asymmetric(
                        insertion: .move(edge: .top).combined(with: .opacity),
                        removal: .move(edge: .top).combined(with: .opacity)
                    ))
                    .zIndex(50)
                    .allowsHitTesting(false)
            }
        }
"""
appear = "        .onAppear {" + chr(10)
if map_text.count(appear) < 1:
    raise RuntimeError("Map onAppear anchor missing")
map_text = map_text.replace(appear, map_overlay + appear, 1)
# A compact toast does not need the local clock: date/time remains in Saved.
map_text = map_text.replace('''                HStack(spacing: 5) {
                    Text("Local time")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    MXWorldLocalClockBadge(place: world)
                }
''', "", 1)
map_text = map_text.replace('''        .frame(height: 64)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
''', '''        .frame(height: 54)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
''', 1)
map_text = map_text.replace('''try? await Task.sleep(nanoseconds: 2_700_000_000)''',
                            '''try? await Task.sleep(nanoseconds: 1_900_000_000)''', 1)
# Do not present confirmation every time the user enters Explore after app launches.
map_text = map_text.replace('''            if session.isSpoofing,
               let simulated = session.simulated,
               let world = matchingWorld(for: simulated) {
                triggerWorldActiveBanner(world)
            }

''', "", 1)
map_file.write_text(map_text, encoding="utf-8")

# Show an Add Favorite button directly in Saved Worlds. This saves into
# SpoofSession's established favorites collection (no duplicate database).
root_file = target / "RootView.swift"
saved_code = root_file.read_text(encoding="utf-8")
saved_start = saved_code.index("struct MXSavedView: View {")
saved_end = saved_code.index("private struct MXFavoriteLocalClock: View {", saved_start)
saved_section = saved_code[saved_start:saved_end]
title_anchor = '            .toolbar(.hidden, for: .navigationBar)'
if saved_section.count(title_anchor) != 1:
    raise RuntimeError("Saved Worlds title anchor missing")
new_title = '''            .navigationTitle("Favorites")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        if let coordinate = session.pin ?? session.simulated {
                            let name = String(format: "Saved %.4f, %.4f",
                                              coordinate.latitude, coordinate.longitude)
                            session.addFavorite(name: name, coordinate: coordinate)
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        }
                    } label: {
                        Label("Add Favorite", systemImage: "star.circle.fill")
                            .font(.headline)
                    }
                    .disabled(session.pin == nil && session.simulated == nil)
                    .accessibilityIdentifier("mxAddFavoriteToSaved")
                }
            }'''
saved_section = saved_section.replace(title_anchor, new_title, 1)
root_file.write_text(saved_code[:saved_start] + saved_section +
                     saved_code[saved_end:], encoding="utf-8")
print("Saved Worlds: add favorite button, drag reorder, rename and local weather retained.")
print("Dating Edition: Saved favorites/tab and 1.9-second top transient World Active toast.")
