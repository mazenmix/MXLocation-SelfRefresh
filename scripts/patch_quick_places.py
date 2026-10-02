from pathlib import Path
import sys


root = Path(sys.argv[1]).resolve()


def replace_required(path: Path, old: str, new: str, count: int = 1) -> None:
    text = path.read_text(encoding="utf-8")
    if old not in text:
        raise RuntimeError(f"Required source fragment not found in {path}: {old[:140]!r}")
    path.write_text(text.replace(old, new, count), encoding="utf-8")


# 1) Reuse the existing Places button, but make it a fast Quick Places sheet.
root_view = root / "Locus/Features/Map/RootView.swift"
replace_required(
    root_view,
    '''        .sheet(isPresented: $showPlaces) {
            PlacesView()
        }
''',
    '''        .sheet(isPresented: $showPlaces) {
            QuickPlacesView()
        }
''',
)


# 2) Expand the map: remove the top spoofing status bar, add long-press teleport,
#    and show a short Undo toast after direct location changes.
map_view = root / "Locus/Features/Map/MapHomeView.swift"
map_text = map_view.read_text(encoding="utf-8")

state_needle = '''    /// Set when the pin comes from search / a named place so starring keeps the title.
    @State private var pinPlaceName: String?
'''
if state_needle not in map_text:
    raise RuntimeError("Unable to locate MapHomeView state insertion point")
map_text = map_text.replace(
    state_needle,
    state_needle + '    @State private var showUndoToast = false\n',
    1,
)

status_needle = '''        VStack(spacing: 10) {
            StatusBarView()

            searchBar
'''
status_replacement = '''        VStack(spacing: 8) {
            searchBar
'''
if status_needle not in map_text:
    raise RuntimeError("Unable to remove Spoofing status bar")
map_text = map_text.replace(status_needle, status_replacement, 1)

tap_needle = '''                .onTapGesture { point in
                    searchFocused = false
                    guard !suppressNextMapTap, !isDraggingPin else { return }
                    pinSelected = false
                    placePin(at: point, proxy: proxy)
                }
'''
tap_replacement = '''                .onTapGesture { point in
                    searchFocused = false
                    guard !suppressNextMapTap, !isDraggingPin else { return }
                    pinSelected = false
                    placePin(at: point, proxy: proxy)
                }
                .simultaneousGesture(
                    LongPressGesture(minimumDuration: 0.55)
                        .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .local))
                        .onEnded { value in
                            guard !drawMode, !isDraggingPin else { return }
                            guard case .second(true, let dragValue) = value,
                                  let dragValue,
                                  let coord = proxy.convert(dragValue.location, from: .local)
                            else { return }

                            searchFocused = false
                            pinSelected = false
                            pinPlaceName = nil
                            suppressNextMapTap = true
                            session.teleport(to: coord, pairing: pairing)
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.30) {
                                suppressNextMapTap = false
                            }
                        }
                )
'''
if tap_needle not in map_text:
    raise RuntimeError("Unable to locate map tap gesture")
map_text = map_text.replace(tap_needle, tap_replacement, 1)

lifecycle_needle = '''        .onAppear {
            session.startLocationUpdates()
        }
        .onChange(of: session.pin?.latitude) { _, newValue in
'''
lifecycle_replacement = '''        .overlay(alignment: .bottom) {
            if showUndoToast, session.undoCoordinate != nil {
                HStack(spacing: 10) {
                    Image(systemName: "location.fill")
                        .foregroundStyle(LocusTheme.accent)
                    Text("Location changed")
                        .font(.subheadline.weight(.semibold))
                    Spacer(minLength: 8)
                    Button("Undo") {
                        session.undoLastTeleport(pairing: pairing)
                        withAnimation(.easeOut(duration: 0.2)) {
                            showUndoToast = false
                        }
                    }
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(LocusTheme.accent)
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
                .locusGlass(.regular, in: Capsule())
                .padding(.horizontal, 16)
                .padding(.bottom, 132)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .onAppear {
            session.startLocationUpdates()
        }
        .onChange(of: session.teleportRevision) { _, revision in
            guard revision > 0, session.undoCoordinate != nil else { return }
            withAnimation(.easeOut(duration: 0.2)) {
                showUndoToast = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) {
                guard session.teleportRevision == revision else { return }
                withAnimation(.easeIn(duration: 0.2)) {
                    showUndoToast = false
                }
            }
        }
        .onChange(of: session.pin?.latitude) { _, newValue in
'''
if lifecycle_needle not in map_text:
    raise RuntimeError("Unable to locate MapHomeView lifecycle block")
map_text = map_text.replace(lifecycle_needle, lifecycle_replacement, 1)
map_view.write_text(map_text, encoding="utf-8")


# 3) Add one-level Undo/Redo memory to the actual teleport engine.
session_file = root / "Locus/Engine/SpoofSession.swift"
session_text = session_file.read_text(encoding="utf-8")

published_needle = '''    @Published var isBusy = false
    @Published var joystickActive = false

    @Published var favorites: [SavedPlace] = []
'''
published_replacement = '''    @Published var isBusy = false
    @Published var joystickActive = false
    @Published private(set) var undoCoordinate: CLLocationCoordinate2D?
    @Published private(set) var teleportRevision = 0

    @Published var favorites: [SavedPlace] = []
'''
if published_needle not in session_text:
    raise RuntimeError("Unable to locate SpoofSession published state")
session_text = session_text.replace(published_needle, published_replacement, 1)

teleport_needle = '''    func teleport(to coordinate: CLLocationCoordinate2D, pairing: PairingStore) {
        guard pairing.hasPairingFile else {
            lastError = "Import an RPPairing file in Settings first."
            return
        }
        pin = coordinate
        apply(coordinate, pairing: pairing, markRecent: true)
    }

'''
teleport_replacement = '''    func teleport(to coordinate: CLLocationCoordinate2D, pairing: PairingStore) {
        guard pairing.hasPairingFile else {
            lastError = "Import an RPPairing file in Settings first."
            return
        }

        let previous = simulated
        pin = coordinate
        apply(coordinate, pairing: pairing, markRecent: true)

        if case .active = status {
            if let previous, Self.coordinatesDiffer(previous, coordinate) {
                undoCoordinate = previous
            }
            teleportRevision += 1
        }
    }

    func undoLastTeleport(pairing: PairingStore) {
        guard pairing.hasPairingFile else {
            lastError = "Import an RPPairing file in Settings first."
            return
        }
        guard let target = undoCoordinate else { return }

        let current = simulated
        pin = target
        apply(target, pairing: pairing, markRecent: true)

        if case .active = status {
            undoCoordinate = current
            teleportRevision += 1
        }
    }

'''
if teleport_needle not in session_text:
    raise RuntimeError("Unable to locate SpoofSession teleport function")
session_text = session_text.replace(teleport_needle, teleport_replacement, 1)

coordinate_needle = '''    private static func coordinateLabel(_ coordinate: CLLocationCoordinate2D) -> String {
        String(format: "%.5f, %.5f", coordinate.latitude, coordinate.longitude)
    }
'''
coordinate_replacement = '''    private static func coordinatesDiffer(
        _ lhs: CLLocationCoordinate2D,
        _ rhs: CLLocationCoordinate2D
    ) -> Bool {
        abs(lhs.latitude - rhs.latitude) > 0.0000001 ||
        abs(lhs.longitude - rhs.longitude) > 0.0000001
    }

    private static func coordinateLabel(_ coordinate: CLLocationCoordinate2D) -> String {
        String(format: "%.5f, %.5f", coordinate.latitude, coordinate.longitude)
    }
'''
if coordinate_needle not in session_text:
    raise RuntimeError("Unable to locate coordinateLabel helper")
session_text = session_text.replace(coordinate_needle, coordinate_replacement, 1)
session_file.write_text(session_text, encoding="utf-8")


# 4) Add the compact Quick Places UI. Favorites/recents already persist in the
#    upstream engine, so this is intentionally a thin UI on top of that data.
quick_places_source = r'''import CoreLocation
import SwiftUI
import UIKit

struct QuickPlacesView: View {
    @EnvironmentObject private var session: SpoofSession
    @EnvironmentObject private var pairing: PairingStore
    @Environment(\.dismiss) private var dismiss

    @State private var showAllPlaces = false
    @State private var copiedCoordinate: String?

    private var currentCoordinate: CLLocationCoordinate2D? {
        session.simulated ?? session.pin
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Current") {
                    if let coordinate = currentCoordinate {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(session.isSpoofing ? "Current spoofed location" : "Selected location")
                                    .font(.subheadline.weight(.semibold))
                                Text(coordinateText(coordinate))
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 8)
                            copyButton(coordinate)
                        }
                    } else {
                        Text("Choose a place or long-press the map.")
                            .foregroundStyle(.secondary)
                    }

                    if session.undoCoordinate != nil {
                        Button {
                            session.undoLastTeleport(pairing: pairing)
                            dismiss()
                        } label: {
                            Label("Back to previous location", systemImage: "arrow.uturn.backward.circle.fill")
                        }
                    }
                }

                Section("Favorites") {
                    if session.favorites.isEmpty {
                        Text("Star a pin to keep it here.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(session.favorites.prefix(6)) { place in
                            placeRow(place)
                        }
                    }
                }

                Section("Last 5 Locations") {
                    if session.recents.isEmpty {
                        Text("Your recent teleports will appear here.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(session.recents.prefix(5)) { place in
                            placeRow(place)
                        }
                    }
                }
            }
            .navigationTitle("Quick Places")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Manage") { showAllPlaces = true }
                }
            }
            .sheet(isPresented: $showAllPlaces) {
                PlacesView()
            }
        }
    }

    private func placeRow(_ place: SavedPlace) -> some View {
        HStack(spacing: 12) {
            Button {
                session.teleport(to: place.coordinate, pairing: pairing)
                dismiss()
            } label: {
                VStack(alignment: .leading, spacing: 3) {
                    Text(place.name)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(coordinateText(place.coordinate))
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            copyButton(place.coordinate)
        }
    }

    private func copyButton(_ coordinate: CLLocationCoordinate2D) -> some View {
        let text = coordinateText(coordinate)
        return Button {
            UIPasteboard.general.string = text
            copiedCoordinate = text
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
                if copiedCoordinate == text {
                    copiedCoordinate = nil
                }
            }
        } label: {
            Image(systemName: copiedCoordinate == text ? "checkmark.circle.fill" : "doc.on.doc")
                .font(.body.weight(.semibold))
                .foregroundStyle(copiedCoordinate == text ? LocusTheme.statusGood : .secondary)
                .frame(width: 36, height: 36)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .accessibilityLabel("Copy coordinates")
    }

    private func coordinateText(_ coordinate: CLLocationCoordinate2D) -> String {
        String(format: "%.6f, %.6f", coordinate.latitude, coordinate.longitude)
    }
}
'''
(root / "Locus/Features/Map/QuickPlacesView.swift").write_text(
    quick_places_source,
    encoding="utf-8",
)

print("Patched MX Location Quick Places features at", root)
