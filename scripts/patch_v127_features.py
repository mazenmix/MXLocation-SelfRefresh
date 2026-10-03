from pathlib import Path
import sys

root = Path(sys.argv[1]).resolve()


def replace_required(path: Path, old: str, new: str, count: int = 1) -> None:
    text = path.read_text(encoding="utf-8")
    if old not in text:
        raise RuntimeError(f"Required source fragment not found in {path}: {old[:180]!r}")
    path.write_text(text.replace(old, new, count), encoding="utf-8")


# 1) Favorite drag-reorder persistence in SpoofSession.
spoof = root / "Locus/Engine/SpoofSession.swift"
old_remove = '''    func removeFavorite(_ place: SavedPlace) {\n        favorites.removeAll { $0.id == place.id }\n        SavedPlace.save(favorites, key: favoritesKey)\n    }\n'''
new_remove = '''    func moveFavorite(sourceID: String, toTargetID targetID: String) {\n        guard sourceID != targetID,\n              let fromIndex = favorites.firstIndex(where: { $0.id == sourceID }),\n              let targetIndex = favorites.firstIndex(where: { $0.id == targetID }) else { return }\n\n        let moved = favorites.remove(at: fromIndex)\n        let insertionIndex = min(targetIndex, favorites.count)\n        favorites.insert(moved, at: insertionIndex)\n        SavedPlace.save(favorites, key: favoritesKey)\n    }\n\n    func removeFavorite(_ place: SavedPlace) {\n        favorites.removeAll { $0.id == place.id }\n        SavedPlace.save(favorites, key: favoritesKey)\n    }\n'''
replace_required(spoof, old_remove, new_remove)


# 2) Saved view: drag/drop favorites + Share Location submenu inside the existing ellipsis menu.
root_view = root / "Locus/Features/Map/RootView.swift"
replace_required(root_view, "import SwiftUI\n", "import Foundation\nimport SwiftUI\nimport UIKit\n")

old_foreach = '''                                ForEach(places) { place in\n                                    placeRow(place)\n                                }\n'''
new_foreach = '''                                ForEach(places) { place in\n                                    savedPlaceRow(place)\n                                }\n'''
replace_required(root_view, old_foreach, new_foreach)

insert_before_place_row = '''    @ViewBuilder\n    private func placeRow(_ place: SavedPlace) -> some View {\n'''
reorder_helper = '''    @ViewBuilder\n    private func savedPlaceRow(_ place: SavedPlace) -> some View {\n        if segment == 0 {\n            placeRow(place)\n                .draggable(place.id)\n                .dropDestination(for: String.self) { items, _ in\n                    guard let sourceID = items.first, sourceID != place.id else { return false }\n                    withAnimation(.easeInOut(duration: 0.18)) {\n                        session.moveFavorite(sourceID: sourceID, toTargetID: place.id)\n                    }\n                    UIImpactFeedbackGenerator(style: .light).impactOccurred()\n                    return true\n                }\n        } else {\n            placeRow(place)\n        }\n    }\n\n    @ViewBuilder\n    private func placeRow(_ place: SavedPlace) -> some View {\n'''
replace_required(root_view, insert_before_place_row, reorder_helper)

old_menu_tail = '''                        Button(role: .destructive) {\n                            session.removeRecent(place)\n                        } label: {\n                            Label("Delete", systemImage: "trash")\n                        }\n                    }\n                } label: {\n'''
new_menu_tail = '''                        Button(role: .destructive) {\n                            session.removeRecent(place)\n                        } label: {\n                            Label("Delete", systemImage: "trash")\n                        }\n                    }\n\n                    Menu {\n                        ShareLink(item: appleMapsURL(for: place)) {\n                            Label("Apple Maps", systemImage: "map")\n                        }\n                        ShareLink(item: googleMapsURL(for: place)) {\n                            Label("Google Maps", systemImage: "globe")\n                        }\n                    } label: {\n                        Label("Share Location", systemImage: "square.and.arrow.up")\n                    }\n                } label: {\n'''
replace_required(root_view, old_menu_tail, new_menu_tail)

old_root_end = '''        .buttonStyle(.plain)\n    }\n}\n'''
new_root_end = '''        .buttonStyle(.plain)\n    }\n\n    private func appleMapsURL(for place: SavedPlace) -> URL {\n        var components = URLComponents(string: "https://maps.apple.com/")!\n        components.queryItems = [\n            URLQueryItem(name: "ll", value: "\\(place.latitude),\\(place.longitude)"),\n            URLQueryItem(name: "q", value: place.name)\n        ]\n        return components.url!\n    }\n\n    private func googleMapsURL(for place: SavedPlace) -> URL {\n        var components = URLComponents(string: "https://www.google.com/maps/search/")!\n        components.queryItems = [\n            URLQueryItem(name: "api", value: "1"),\n            URLQueryItem(name: "query", value: "\\(place.latitude),\\(place.longitude)")\n        ]\n        return components.url!\n    }\n}\n'''
# RootView.swift contains one earlier buttonStyle(.plain), so target the final occurrence.
text = root_view.read_text(encoding="utf-8")
if old_root_end not in text:
    raise RuntimeError("Unable to append share URL helpers")
idx = text.rfind(old_root_end)
text = text[:idx] + new_root_end + text[idx + len(old_root_end):]
root_view.write_text(text, encoding="utf-8")


# 3) Map view: 10-second Undo after any actual location change, including long-press teleport.
map_file = root / "Locus/Features/Map/MapHomeView.swift"
old_states = '''    @State private var resolvingPin = false\n    @State private var suppressNextMapTap = false\n'''
new_states = '''    @State private var resolvingPin = false\n    @State private var suppressNextMapTap = false\n    @State private var undoCoordinate: CLLocationCoordinate2D?\n    @State private var showUndo = false\n    @State private var undoTask: Task<Void, Never>?\n'''
replace_required(map_file, old_states, new_states)

# After v1.2.6 there are exactly two direct coordinate teleports: long-press and Set/Change Location button.
text = map_file.read_text(encoding="utf-8")
needle = "session.teleport(to: coordinate, pairing: pairing)"
if text.count(needle) != 2:
    raise RuntimeError(f"Expected exactly 2 direct teleports in MapHomeView, found {text.count(needle)}")
text = text.replace(needle, "teleportWithUndo(to: coordinate)")
map_file.write_text(text, encoding="utf-8")

old_stack = '''                Spacer(minLength: 0)\n\n                HStack {\n                    Spacer()\n                    locateButton\n                }\n\n                if let pin = session.pin {\n'''
new_stack = '''                Spacer(minLength: 0)\n\n                if showUndo, undoCoordinate != nil {\n                    HStack {\n                        Spacer()\n                        Button {\n                            undoLastLocationChange()\n                        } label: {\n                            Label("Undo", systemImage: "arrow.uturn.backward")\n                                .font(.caption.weight(.bold))\n                                .foregroundStyle(.primary)\n                                .padding(.horizontal, 12)\n                                .frame(height: 34)\n                                .background(.ultraThinMaterial, in: Capsule())\n                                .overlay(Capsule().stroke(Color.white.opacity(0.09), lineWidth: 1))\n                        }\n                        .buttonStyle(.plain)\n                    }\n                    .transition(.move(edge: .trailing).combined(with: .opacity))\n                }\n\n                HStack {\n                    Spacer()\n                    locateButton\n                }\n\n                if let pin = session.pin {\n'''
replace_required(map_file, old_stack, new_stack)

old_map_helpers = '''    private func isFavorite(_ coordinate: CLLocationCoordinate2D) -> Bool {\n'''
new_map_helpers = '''    private func teleportWithUndo(to coordinate: CLLocationCoordinate2D) {\n        let previous = session.simulated\n        session.teleport(to: coordinate, pairing: pairing)\n\n        guard let previous,\n              abs(previous.latitude - coordinate.latitude) > 0.000001 ||\n              abs(previous.longitude - coordinate.longitude) > 0.000001 else { return }\n\n        undoTask?.cancel()\n        undoCoordinate = previous\n        withAnimation(.easeInOut(duration: 0.18)) {\n            showUndo = true\n        }\n\n        undoTask = Task {\n            try? await Task.sleep(nanoseconds: 10_000_000_000)\n            guard !Task.isCancelled else { return }\n            await MainActor.run {\n                withAnimation(.easeInOut(duration: 0.18)) {\n                    showUndo = false\n                }\n                undoCoordinate = nil\n            }\n        }\n    }\n\n    private func undoLastLocationChange() {\n        guard let previous = undoCoordinate else { return }\n        undoTask?.cancel()\n        session.teleport(to: previous, pairing: pairing)\n        choosePin(previous, name: nil, subtitle: nil, zoom: true)\n        UIImpactFeedbackGenerator(style: .light).impactOccurred()\n        withAnimation(.easeInOut(duration: 0.18)) {\n            showUndo = false\n        }\n        undoCoordinate = nil\n    }\n\n    private func isFavorite(_ coordinate: CLLocationCoordinate2D) -> Bool {\n'''
replace_required(map_file, old_map_helpers, new_map_helpers)

# 4) Version bump from v1.2.6 / build 19.
project = root / "project.yml"
text = project.read_text(encoding="utf-8")
text = text.replace('MARKETING_VERSION: "1.2.6"', 'MARKETING_VERSION: "1.2.7"')
text = text.replace('CURRENT_PROJECT_VERSION: "19"', 'CURRENT_PROJECT_VERSION: "20"')
project.write_text(text, encoding="utf-8")

print("Applied MX Location v1.2.7: favorite drag reorder, 10-second Undo, Share Location")
