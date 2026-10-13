"""Unify all map surfaces behind Apple/MapLibre preference and true dark full bleed."""
from pathlib import Path
import sys

root = Path(sys.argv[1]).resolve() / "Locus/Features/Map"
home = root / "MapHomeView.swift"
shell = root / "MXProPremiumShell.swift"
provider = root / "MXOpenStreetMapProvider.swift"
assert all(p.is_file() for p in (home, shell, provider))

provider_code = provider.read_text(encoding="utf-8")
if "https://tiles.openfreemap.org/styles/dark" not in provider_code:
    raise RuntimeError("MapLibre dark basemap was not installed")
if "struct MXOpenStreetVenueMapCanvas" not in provider_code:
    raise RuntimeError("OpenStreetMap category venue canvas not found")

home_text = home.read_text(encoding="utf-8")
# Preserve the existing responsive search and keyboard layout. Only change
# the native MapLibre canvas' safe area so the dark map extends behind status
# bar and tab bar. Do NOT extend the search/controls beyond the safe area.
old = '''                .accessibilityIdentifier("mxOpenStreetMapCanvas")
                .transition(.opacity)'''
new = '''                .background(Color(red: 0.055, green: 0.075, blue: 0.11).ignoresSafeArea())
                .ignoresSafeArea(.container, edges: [.top, .bottom])
                .accessibilityIdentifier("mxOpenStreetMapCanvas")
                .transition(.opacity)'''
if home_text.count(old) != 1:
    raise RuntimeError("Unique Explore MapLibre safe area anchor missing")
home_text = home_text.replace(old, new, 1)
home.write_text(home_text, encoding="utf-8")

premium = shell.read_text(encoding="utf-8")
start = premium.index("struct MXPremiumCategoryScreen: View {")
end = premium.index("struct MXPremiumSavedScreen: View {", start)
section = premium[start:end]

env = '    @EnvironmentObject private var session: SpoofSession'
if section.count(env) != 1:
    raise RuntimeError("Category environment anchor missing")
section = section.replace(env, env + '\n    @EnvironmentObject private var mapChoice: MXMapChoiceStore', 1)

state = '    @State private var mapPosition: MapCameraPosition = .automatic'
if section.count(state) != 1:
    raise RuntimeError("Category MapCameraPosition state anchor missing")
section = section.replace(state, state +
    '\n    @State private var focusedVenue: CLLocationCoordinate2D?', 1)

map_start = section.index("    private var fullScreenMap: some View {")
map_end = section.index("    // Floating chips keep the map visible", map_start)
unified = '''    @ViewBuilder
    private var fullScreenMap: some View {
        if mapChoice.selected == .osm {
            MXOpenStreetVenueMapCanvas(
                center: center,
                venues: model.places,
                focusedVenue: focusedVenue,
                onSelectVenue: { item in
                    selectedVenue = item
                }
            )
            .background(MXPremiumStyle.background.ignoresSafeArea())
            .ignoresSafeArea(.container, edges: .all)
            .accessibilityIdentifier("mxOpenStreetMapCategory")
        } else {
            Map(position: $mapPosition) {
                if let c = center {
                    Annotation("Selected", coordinate: c) {
                        Image(systemName: "location.circle.fill")
                            .font(.system(size: 29))
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, MXPremiumStyle.cyan)
                    }
                }
                ForEach(Array(model.places.enumerated()), id: \\.offset) { _, item in
                    Annotation(item.name ?? "Venue", coordinate: item.placemark.coordinate) {
                        Button {
                            selectedVenue = item
                        } label: {
                            Image(systemName: category.symbol)
                                .font(.system(size: 15, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(width: 36, height: 36)
                                .background(category.tint, in: Circle())
                                .overlay(Circle().stroke(.white.opacity(0.8), lineWidth: 2))
                                .shadow(color: .black.opacity(0.4), radius: 5)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .mapStyle(.standard(elevation: .realistic))
            .environment(\\.colorScheme, .dark)
            .mapControlVisibility(.hidden)
            .ignoresSafeArea()
        }
    }

'''
if "\\\\." in unified:
    raise RuntimeError("Bad generated Swift escaping")
section = section[:map_start] + unified + section[map_end:]
# A tap on any nearby venue row also re-centers the native MapLibre canvas,
# instead of updating MapKit's inactive map position only.
focus_anchor = '''                                            mapPosition = .region(MKCoordinateRegion(
                                                center: item.placemark.coordinate,
                                                latitudinalMeters: 1700,
                                                longitudinalMeters: 1700
                                            ))'''
if section.count(focus_anchor) != 1:
    raise RuntimeError("Nearby venue recenter action missing")
section = section.replace(focus_anchor,
    '''                                            focusedVenue = item.placemark.coordinate
''' + focus_anchor, 1)

premium = premium[:start] + section + premium[end:]
shell.write_text(premium, encoding="utf-8")
print("MX Location Pro: native MapLibre dark full-bleed Explore + universal category surfaces and markers.")
