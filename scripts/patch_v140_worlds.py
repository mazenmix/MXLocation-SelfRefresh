from pathlib import Path
import shutil
import sys

root = Path(sys.argv[1]).resolve()
repo_root = Path(__file__).resolve().parent.parent


def replace_required(path: Path, old: str, new: str, count: int = 1) -> None:
    text = path.read_text(encoding="utf-8")
    if old not in text:
        raise RuntimeError(f"Required source fragment not found in {path}: {old[:240]!r}")
    path.write_text(text.replace(old, new, count), encoding="utf-8")


# -----------------------------------------------------------------------------
# 1) Install the self-contained MX Worlds UI/services file.
# -----------------------------------------------------------------------------
worlds_overlay = repo_root / "overlays/MXWorlds.swift"
worlds_target = root / "Locus/Features/Map/MXWorlds.swift"
if not worlds_overlay.exists():
    raise RuntimeError(f"Missing overlay: {worlds_overlay}")
worlds_target.parent.mkdir(parents=True, exist_ok=True)
shutil.copy2(worlds_overlay, worlds_target)


# -----------------------------------------------------------------------------
# 2) Replace Saved with the new Saved Worlds surface while preserving the
#    direct Favorite -> Map preview behavior the user explicitly requested.
#    Tapping the miniature map opens World Details; tapping the main row jumps
#    to the map immediately. The ellipsis contains the rest of the world tools.
# -----------------------------------------------------------------------------
root_view = root / "Locus/Features/Map/RootView.swift"
text = root_view.read_text(encoding="utf-8")
start = text.index("struct MXSavedView: View {")
end = text.index("private struct MXFavoriteLocalClock: View {", start)

new_saved = r'''struct MXSavedView: View {
    @EnvironmentObject private var session: SpoofSession
    @EnvironmentObject private var pairing: PairingStore
    @Binding var selectedTab: Int

    @State private var selectedWorld: SavedPlace?
    @State private var resumeWorld: SavedPlace?
    @State private var editWorld: SavedPlace?

    private var places: [SavedPlace] {
        session.favorites
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                if places.isEmpty {
                    VStack(spacing: 11) {
                        Image(systemName: "globe.americas")
                            .font(.system(size: 38, weight: .medium))
                            .foregroundStyle(.secondary)
                        Text("No saved worlds yet")
                            .font(.headline)
                        Text("Save a location from the map and it becomes a world with local time, weather, notes and session history.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 34)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 10) {
                            ForEach(places) { place in
                                MXWorldListRow(
                                    place: place,
                                    onPreview: {
                                        preview(place)
                                    },
                                    onOpenWorld: {
                                        selectedWorld = place
                                    },
                                    onResume: {
                                        resumeWorld = place
                                    },
                                    onEdit: {
                                        editWorld = place
                                    },
                                    onRemove: {
                                        session.removeFavorite(place)
                                    }
                                )
                                .draggable(place.id)
                                .dropDestination(for: String.self) { items, _ in
                                    guard let sourceID = items.first, sourceID != place.id else { return false }
                                    withAnimation(.easeInOut(duration: 0.18)) {
                                        session.moveFavorite(sourceID: sourceID, toTargetID: place.id)
                                    }
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                    return true
                                }
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.top, 4)
                        .padding(.bottom, 20)
                    }
                }
            }
            .navigationTitle("Saved Worlds")
            .navigationBarTitleDisplayMode(.large)
        }
        .sheet(item: $selectedWorld) { place in
            MXWorldDetailsView(
                place: place,
                onPreview: { previewPlace in
                    preview(previewPlace)
                },
                onEnter: { world in
                    enter(world)
                },
                onRename: { oldPlace, newName in
                    session.renameFavorite(oldPlace, to: newName)
                }
            )
        }
        .sheet(item: $resumeWorld) { place in
            MXWorldResumeView(place: place) { previewPlace in
                preview(previewPlace)
            }
        }
        .sheet(item: $editWorld) { place in
            MXWorldEditView(place: place) { newName, newNote in
                MXWorldStore.setNote(newNote, for: place)
                let clean = newName.trimmingCharacters(in: .whitespacesAndNewlines)
                if !clean.isEmpty, clean != place.name {
                    session.renameFavorite(place, to: clean)
                }
            }
        }
    }

    private func preview(_ place: SavedPlace) {
        session.previewFavoriteOnMap(place)
        withAnimation(.easeInOut(duration: 0.18)) {
            selectedTab = 0
        }
    }

    private func enter(_ place: SavedPlace) {
        MXWorldStore.recordUse(place: place, coordinate: place.coordinate, name: place.name)
        session.pin = place.coordinate
        session.teleport(to: place.coordinate, pairing: pairing)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        withAnimation(.easeInOut(duration: 0.18)) {
            selectedTab = 0
        }
    }
}

'''
root_view.write_text(text[:start] + new_saved + text[end:], encoding="utf-8")


# -----------------------------------------------------------------------------
# 3) Map: add the World Active confirmation banner and record nearby world
#    sessions. Keep the compact bottom bar and all existing jump/undo behavior.
# -----------------------------------------------------------------------------
map_file = root / "Locus/Features/Map/MapHomeView.swift"

replace_required(
    map_file,
    '''    @State private var jumpArcTask: Task<Void, Never>?\n''',
    '''    @State private var jumpArcTask: Task<Void, Never>?\n    @State private var activeWorldBanner: SavedPlace?\n    @State private var showWorldActiveBanner = false\n    @State private var worldBannerTask: Task<Void, Never>?\n'''
)

replace_required(
    map_file,
    '''                searchBar\n\n                if searchFocused && !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {\n''',
    '''                searchBar\n\n                if showWorldActiveBanner, let world = activeWorldBanner {\n                    worldActiveBanner(world)\n                        .transition(.move(edge: .top).combined(with: .opacity))\n                }\n\n                if searchFocused && !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {\n'''
)

old_on_appear = '''        .onAppear {\n            session.startLocationUpdates()\n\n            if let pendingFavorite = session.requestedMapPreview {\n                // Saved -> Map may recreate this view after the request was set.\n                // Consume it here so tapping a Favorite always jumps/zooms to it.\n                DispatchQueue.main.async {\n                    beginFavoriteJumpPreview(pendingFavorite)\n                    session.requestedMapPreview = nil\n                }\n            } else if let pin = session.pin {\n                resolvePin(pin)\n            }\n        }\n'''
new_on_appear = '''        .onAppear {\n            session.startLocationUpdates()\n\n            if session.isSpoofing,\n               let simulated = session.simulated,\n               let world = matchingWorld(for: simulated) {\n                triggerWorldActiveBanner(world)\n            }\n\n            if let pendingFavorite = session.requestedMapPreview {\n                // Saved -> Map may recreate this view after the request was set.\n                // Consume it here so tapping a Favorite always jumps/zooms to it.\n                DispatchQueue.main.async {\n                    beginFavoriteJumpPreview(pendingFavorite)\n                    session.requestedMapPreview = nil\n                }\n            } else if let pin = session.pin {\n                resolvePin(pin)\n            }\n        }\n'''
replace_required(map_file, old_on_appear, new_on_appear)

# Insert the banner view just before the existing search bar view.
replace_required(
    map_file,
    '''    private var searchBar: some View {\n''',
    r'''    private func worldActiveBanner(_ world: SavedPlace) -> some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(Color(red: 0.90, green: 0.24, blue: 0.27).opacity(0.17))
                    .frame(width: 38, height: 38)
                Image(systemName: "mappin.circle.fill")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(Color(red: 0.94, green: 0.28, blue: 0.30))
            }

            VStack(alignment: .leading, spacing: 1) {
                Text("World Active")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(Color.orange)
                Text(world.name.uppercased())
                    .font(.subheadline.weight(.black))
                    .lineLimit(1)
                HStack(spacing: 5) {
                    Text("Local time")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    MXWorldLocalClockBadge(place: world)
                }
            }

            Spacer(minLength: 6)

            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.title3)
        }
        .padding(.horizontal, 12)
        .frame(height: 64)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.25), radius: 14, y: 7)
    }

    private var searchBar: some View {
'''
)

old_teleport_start = '''    private func teleportWithUndo(to coordinate: CLLocationCoordinate2D) {\n        let previous = session.simulated\n        session.teleport(to: coordinate, pairing: pairing)\n'''
new_teleport_start = '''    private func teleportWithUndo(to coordinate: CLLocationCoordinate2D) {\n        let previous = session.simulated\n\n        if let world = matchingWorld(for: coordinate) {\n            MXWorldStore.recordUse(place: world, coordinate: coordinate, name: pinName)\n            triggerWorldActiveBanner(world)\n        }\n\n        session.teleport(to: coordinate, pairing: pairing)\n'''
replace_required(map_file, old_teleport_start, new_teleport_start)

# Add world matching/banner helpers immediately before isFavorite.
replace_required(
    map_file,
    '''    private func isFavorite(_ coordinate: CLLocationCoordinate2D) -> Bool {\n''',
    r'''    private func matchingWorld(for coordinate: CLLocationCoordinate2D) -> SavedPlace? {
        let target = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        let nearest = session.favorites
            .map { place -> (SavedPlace, CLLocationDistance) in
                let point = CLLocation(latitude: place.latitude, longitude: place.longitude)
                return (place, point.distance(from: target))
            }
            .min { $0.1 < $1.1 }

        // A World represents a city/metro context rather than one exact pixel.
        guard let nearest, nearest.1 <= 100_000 else { return nil }
        return nearest.0
    }

    private func triggerWorldActiveBanner(_ world: SavedPlace) {
        worldBannerTask?.cancel()
        activeWorldBanner = world
        withAnimation(.easeInOut(duration: 0.20)) {
            showWorldActiveBanner = true
        }

        worldBannerTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_700_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.22)) {
                showWorldActiveBanner = false
            }
            try? await Task.sleep(nanoseconds: 260_000_000)
            guard !Task.isCancelled else { return }
            activeWorldBanner = nil
        }
    }

    private func isFavorite(_ coordinate: CLLocationCoordinate2D) -> Bool {
'''
)


# -----------------------------------------------------------------------------
# 4) Version bump for the major MX Worlds feature set.
# -----------------------------------------------------------------------------
project = root / "project.yml"
project_text = project.read_text(encoding="utf-8")
project_text = project_text.replace('MARKETING_VERSION: "1.3.3"', 'MARKETING_VERSION: "1.4.0"')
project_text = project_text.replace('CURRENT_PROJECT_VERSION: "26"', 'CURRENT_PROJECT_VERSION: "27"')
project.write_text(project_text, encoding="utf-8")

print("Applied MX Location v1.4.0: MX Worlds experience")
