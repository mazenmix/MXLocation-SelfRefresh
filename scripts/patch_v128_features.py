from pathlib import Path
import sys

root = Path(sys.argv[1]).resolve()


def replace_required(path: Path, old: str, new: str, count: int = 1) -> None:
    text = path.read_text(encoding="utf-8")
    if old not in text:
        raise RuntimeError(f"Required source fragment not found in {path}: {old[:180]!r}")
    path.write_text(text.replace(old, new, count), encoding="utf-8")


# 1) Add a one-shot map preview request for Saved/Favorites.
spoof = root / "Locus/Engine/SpoofSession.swift"
old_published = '''    @Published var favorites: [SavedPlace] = []\n    @Published var recents: [SavedPlace] = []\n'''
new_published = '''    @Published var favorites: [SavedPlace] = []\n    @Published var recents: [SavedPlace] = []\n    @Published var requestedMapPreview: SavedPlace?\n'''
replace_required(spoof, old_published, new_published)

old_add_favorite = '''    func addFavorite(name: String, coordinate: CLLocationCoordinate2D) {\n'''
new_add_favorite = '''    func previewFavoriteOnMap(_ place: SavedPlace) {\n        pin = place.coordinate\n        requestedMapPreview = place\n    }\n\n    func addFavorite(name: String, coordinate: CLLocationCoordinate2D) {\n'''
replace_required(spoof, old_add_favorite, new_add_favorite)


# 2) Favorite tap becomes preview-only: jump/zoom the map first, without teleporting.
root_view = root / "Locus/Features/Map/RootView.swift"
old_tap = '''        Button {\n            session.pin = place.coordinate\n            selectedTab = 0\n        } label: {\n'''
new_tap = '''        Button {\n            session.previewFavoriteOnMap(place)\n            selectedTab = 0\n        } label: {\n'''
replace_required(root_view, old_tap, new_tap)


# 3) Replace the selected-location pin with the small soft glowing dot approved by the user.
map_file = root / "Locus/Features/Map/MapHomeView.swift"
old_marker = '''                    if let pin = session.pin {\n                        Annotation("", coordinate: pin, anchor: .bottom) {\n                            VStack(spacing: 3) {\n                                ZStack {\n                                    Circle()\n                                        .fill(accent.opacity(0.24))\n                                        .frame(width: 46, height: 46)\n                                    Image(systemName: "mappin.circle.fill")\n                                        .font(.system(size: 34, weight: .semibold))\n                                        .symbolRenderingMode(.palette)\n                                        .foregroundStyle(.white, accent)\n                                }\n                                Circle()\n                                    .fill(Color.black.opacity(0.35))\n                                    .frame(width: 7, height: 4)\n                            }\n                        }\n                    }\n'''
new_marker = '''                    if let pin = session.pin {\n                        Annotation("", coordinate: pin, anchor: .center) {\n                            ZStack {\n                                Circle()\n                                    .fill(accent.opacity(0.08))\n                                    .frame(width: 34, height: 34)\n                                Circle()\n                                    .fill(accent.opacity(0.16))\n                                    .frame(width: 23, height: 23)\n                                Circle()\n                                    .fill(accent.opacity(0.35))\n                                    .frame(width: 15, height: 15)\n                                    .blur(radius: 3)\n                                Circle()\n                                    .fill(Color.white.opacity(0.98))\n                                    .frame(width: 8, height: 8)\n                                    .overlay(\n                                        Circle()\n                                            .stroke(accent.opacity(0.95), lineWidth: 2)\n                                    )\n                                    .shadow(color: accent.opacity(0.95), radius: 7)\n                                    .shadow(color: accent.opacity(0.55), radius: 14)\n                            }\n                            .accessibilityLabel("Selected location")\n                        }\n                    }\n'''
replace_required(map_file, old_marker, new_marker)

# When a Favorite is tapped, smoothly center and zoom to it. Do not change simulated location.
old_pin_change = '''        .onChange(of: session.pin?.latitude) { _, newValue in\n            if newValue == nil {\n                pinName = "Selected Location"\n                pinSubtitle = ""\n            }\n        }\n'''
new_pin_change = '''        .onChange(of: session.pin?.latitude) { _, newValue in\n            if newValue == nil {\n                pinName = "Selected Location"\n                pinSubtitle = ""\n            }\n        }\n        .onChange(of: session.requestedMapPreview?.id) { _, _ in\n            guard let place = session.requestedMapPreview else { return }\n            searchFocused = false\n            choosePin(\n                place.coordinate,\n                name: place.name,\n                subtitle: "Favorite",\n                zoom: true\n            )\n            UIImpactFeedbackGenerator(style: .soft).impactOccurred()\n            session.requestedMapPreview = nil\n        }\n'''
replace_required(map_file, old_pin_change, new_pin_change)


# 4) Version bump from v1.2.7 / build 20.
project = root / "project.yml"
text = project.read_text(encoding="utf-8")
text = text.replace('MARKETING_VERSION: "1.2.7"', 'MARKETING_VERSION: "1.2.8"')
text = text.replace('CURRENT_PROJECT_VERSION: "20"', 'CURRENT_PROJECT_VERSION: "21"')
project.write_text(text, encoding="utf-8")

print("Applied MX Location v1.2.8: favorite map preview + soft glowing dot marker")
