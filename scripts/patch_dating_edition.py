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


# Keyboard-aware professional search results.
# The original full seven-result VStack could force the map search bar above the
# status bar when iOS shrank the safe area for the keyboard. Use an independently
# scrolling, height-bounded result panel and hide controls while editing.
map_text = map_file.read_text(encoding="utf-8")
if "premiumNavigation: MXPremiumNavigation" not in map_text:
    raise RuntimeError("Missing premium navigation shared search state")
body_anchor = "            VStack(spacing: 10) {" + chr(10) + "                searchBar"
if map_text.count(body_anchor) != 1:
    raise RuntimeError("Search layout anchor missing")
map_text = map_text.replace(
    body_anchor,
    "            GeometryReader { searchLayout in" + chr(10) +
    "                VStack(spacing: 10) {" + chr(10) + "                    searchBar",
    1
)
original_results = """                if searchFocused && !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    searchResults
                }
"""
replacement_results = """                    if searchFocused &&
                       !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        searchResults(maxHeight: max(100, min(310, searchLayout.size.height - 115)))
                            .transition(.opacity.combined(with: .move(edge: .top)))
                            .zIndex(30)
                    }
"""
if map_text.count(original_results) != 1:
    raise RuntimeError("Existing results presentation not found")
map_text = map_text.replace(original_results, replacement_results, 1)
old_bottom = """                HStack {
                    Spacer()
                    locateButton
                }

                if let pin = session.pin {
                    selectedLocationCard(pin)
                }
"""
new_bottom = """                    if !searchFocused {
                        HStack {
                            Spacer()
                            locateButton
                        }
                        if let pin = session.pin {
                            selectedLocationCard(pin)
                        }
                    }
"""
if map_text.count(old_bottom) != 1:
    raise RuntimeError("Bottom map controls anchor missing")
map_text = map_text.replace(old_bottom, new_bottom, 1)
# Close the added GeometryReader immediately before the outer ZStack close.
# Other MX patches change bottom padding, so do not rely on that number.
overlay_start = map_text.find("        .overlay(alignment: .top) {")
if overlay_start < 0:
    raise RuntimeError("Top toast overlay missing")
outer_close = map_text.rfind("        }" + chr(10), 0, overlay_start)
if outer_close < 0 or overlay_start - outer_close > 90:
    raise RuntimeError("Cannot locate map ZStack closure safely")
map_text = map_text[:outer_close] + "            }" + chr(10) + map_text[outer_close:]
map_text = map_text.replace(
    '        .onAppear {' + chr(10) + '            session.startLocationUpdates()',
    '''        .onChange(of: searchFocused) { _, focused in
            premiumNavigation.isSearchActive = focused
        }
        .onDisappear {
            premiumNavigation.isSearchActive = false
        }
        .onAppear {
            premiumNavigation.isSearchActive = searchFocused
            session.startLocationUpdates()''',
    1
)
map_text = map_text.replace(
    '''            if !searchText.isEmpty {
                Button {
                    searchText = ""
                    search.query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
''',
    '''            if !searchText.isEmpty {
                Button {
                    searchText = ""
                    search.query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            if searchFocused {
                Button("Done") {
                    searchFocused = false
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(accent)
                .accessibilityIdentifier("mxSearchKeyboardDone")
            }
''',
    1
)
search_start = map_text.index("    @ViewBuilder" + chr(10) + "    private var searchResults: some View {")
search_end = map_text.index("    private var locateButton: some View {", search_start)
new_search = r'''    @ViewBuilder
    private func searchResults(maxHeight: CGFloat) -> some View {
        let results = Array(search.results.prefix(12))
        if results.isEmpty {
            HStack(spacing: 9) {
                ProgressView().controlSize(.small)
                Text("Searching places…")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
            .padding(13)
            .background(.regularMaterial,
                        in: RoundedRectangle(cornerRadius: 17, style: .continuous))
            .accessibilityIdentifier("mxSearchLoading")
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(results.enumerated()), id: \.element) { index, item in
                        Button {
                            select(completion: item)
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "mappin.circle.fill")
                                    .font(.system(size: 18))
                                    .foregroundStyle(accent)
                                    .frame(width: 27)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(item.title)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(.primary)
                                        .lineLimit(1)
                                    if !item.subtitle.isEmpty {
                                        Text(item.subtitle)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                }
                                Spacer(minLength: 4)
                                Image(systemName: "chevron.right")
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(.horizontal, 13)
                            .frame(height: 64)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        if index < results.count - 1 {
                            Divider().opacity(0.15)
                                .padding(.leading, 52)
                        }
                    }
                }
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.never)
            .frame(height: min(maxHeight, CGFloat(results.count) * 64))
            .background(.regularMaterial,
                        in: RoundedRectangle(cornerRadius: 17, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 17, style: .continuous)
                    .stroke(.white.opacity(0.09), lineWidth: 0.8)
            )
            .shadow(color: .black.opacity(0.24), radius: 16, y: 6)
            .accessibilityIdentifier("mxSearchScrollableResults")
        }
    }

'''
map_text = map_text[:search_start] + new_search + map_text[search_end:]
if "searchResults(maxHeight:" not in map_text or "mxSearchScrollableResults" not in map_text:
    raise RuntimeError("Search replacement failed validation")
map_file.write_text(map_text, encoding="utf-8")
print("Dating Edition: bounded scrolling suggestions below search, adaptive keyboard layout and hidden category chips.")
