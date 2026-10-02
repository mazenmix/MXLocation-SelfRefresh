from pathlib import Path
import shutil
import sys

root = Path(sys.argv[1]).resolve()
repo_root = Path(__file__).resolve().parent.parent


def replace_required(path: Path, old: str, new: str, count: int = 1) -> None:
    text = path.read_text(encoding="utf-8")
    if old not in text:
        raise RuntimeError(f"Required source fragment not found in {path}: {old[:160]!r}")
    path.write_text(text.replace(old, new, count), encoding="utf-8")


# Copy the self-contained Travel/Dating suite into the generated Locus source.
overlay = repo_root / "overlays/MXTravelSuite.swift"
destination = root / "Locus/Features/Map/MXTravelSuite.swift"
shutil.copy2(overlay, destination)

# Make the existing star button open the full MX Travel Hub.
root_view = root / "Locus/Features/Map/RootView.swift"
replace_required(
    root_view,
    '''        .sheet(isPresented: $showPlaces) {
            QuickPlacesView()
        }
''',
    '''        .sheet(isPresented: $showPlaces) {
            MXTravelSuiteView()
        }
''',
)

# Map upgrades: lock, distance ring, richer pin card and address/share helpers.
map_view = root / "Locus/Features/Map/MapHomeView.swift"
map_text = map_view.read_text(encoding="utf-8")

if "import UIKit\n" not in map_text:
    map_text = map_text.replace("import SwiftUI\n", "import SwiftUI\nimport UIKit\n", 1)

state_needle = '''    @State private var showUndoToast = false
'''
state_replacement = '''    @State private var showUndoToast = false
    @AppStorage("mx.locationLocked") private var mxLocationLocked = false
    @AppStorage("mx.distanceRingKm") private var mxDistanceRingKm = 0.0
    @State private var pinAddress: String?
'''
if state_needle not in map_text:
    raise RuntimeError("Unable to locate Travel Suite map state insertion point")
map_text = map_text.replace(state_needle, state_replacement, 1)

user_annotation = '''                    UserAnnotation()

                    if let pin = session.pin {
'''
user_annotation_replacement = '''                    UserAnnotation()

                    if mxDistanceRingKm > 0,
                       let ringCenter = session.simulated ?? session.pin {
                        MapCircle(center: ringCenter, radius: mxDistanceRingKm * 1000)
                            .foregroundStyle(LocusTheme.accent.opacity(0.12))
                    }

                    if let pin = session.pin {
'''
if user_annotation not in map_text:
    raise RuntimeError("Unable to locate UserAnnotation for distance ring")
map_text = map_text.replace(user_annotation, user_annotation_replacement, 1)

select_needle = '''                                    withAnimation(.spring(response: 0.28, dampingFraction: 0.78)) {
                                        pinSelected.toggle()
                                    }
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
'''
select_replacement = '''                                    withAnimation(.spring(response: 0.28, dampingFraction: 0.78)) {
                                        pinSelected.toggle()
                                    }
                                    if pinSelected { resolvePinAddress() }
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
'''
if select_needle not in map_text:
    raise RuntimeError("Unable to locate pin select handler")
map_text = map_text.replace(select_needle, select_replacement, 1)

map_text = map_text.replace(
    '''                    guard !suppressNextMapTap, !isDraggingPin else { return }
''',
    '''                    guard !mxLocationLocked, !suppressNextMapTap, !isDraggingPin else { return }
''',
    1,
)

long_press_guard = '''                            guard !drawMode, !isDraggingPin else { return }
'''
if long_press_guard not in map_text:
    raise RuntimeError("Unable to locate long-press guard")
map_text = map_text.replace(
    long_press_guard,
    '''                            guard !mxLocationLocked, !drawMode, !isDraggingPin else { return }
''',
    1,
)

chrome_needle = '''            if session.pin != nil {
                chromeIconButton("star.circle") {
'''
chrome_replacement = '''            chromeIconButton(mxLocationLocked ? "lock.fill" : "lock.open") {
                mxLocationLocked.toggle()
            }
            .foregroundStyle(mxLocationLocked ? LocusTheme.accentSecondary : .primary)

            if session.pin != nil {
                chromeIconButton("star.circle") {
'''
if chrome_needle not in map_text:
    raise RuntimeError("Unable to add map lock button")
map_text = map_text.replace(chrome_needle, chrome_replacement, 1)

top_chrome_needle = '''            HStack(alignment: .center, spacing: 10) {
                mapChromeButtons
                Spacer(minLength: 0)
                locateButton
            }
        }
        .padding(.horizontal, 16)
'''
top_chrome_replacement = '''            HStack(alignment: .center, spacing: 10) {
                mapChromeButtons
                Spacer(minLength: 0)
                locateButton
            }

            if pinSelected, let pin = session.pin {
                pinInfoCard(pin)
            }
        }
        .padding(.horizontal, 16)
'''
if top_chrome_needle not in map_text:
    raise RuntimeError("Unable to insert pin info card")
map_text = map_text.replace(top_chrome_needle, top_chrome_replacement, 1)

change_needle = '''        .onChange(of: session.pin?.latitude) { _, newValue in
            if newValue == nil { pinSelected = false }
        }
'''
change_replacement = '''        .onChange(of: session.pin?.latitude) { _, newValue in
            if newValue == nil {
                pinSelected = false
                pinAddress = nil
            } else if pinSelected {
                resolvePinAddress()
            }
        }
'''
if change_needle not in map_text:
    raise RuntimeError("Unable to extend pin lifecycle")
map_text = map_text.replace(change_needle, change_replacement, 1)

helper_needle = '''    private func select(completion: MKLocalSearchCompletion) {
'''
helper_block = '''    private func pinInfoCard(_ coordinate: CLLocationCoordinate2D) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(pinAddress ?? "Selected location")
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
                Text(String(format: "%.6f, %.6f", coordinate.latitude, coordinate.longitude))
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Button {
                UIPasteboard.general.string = String(format: "%.6f, %.6f", coordinate.latitude, coordinate.longitude)
            } label: {
                Image(systemName: "doc.on.doc")
                    .frame(width: 34, height: 34)
            }
            .buttonStyle(.plain)
            Button {
                sharePin(coordinate)
            } label: {
                Image(systemName: "square.and.arrow.up")
                    .frame(width: 34, height: 34)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .locusGlass(.regular, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func resolvePinAddress() {
        guard let pin = session.pin else {
            pinAddress = nil
            return
        }
        pinAddress = nil
        Task {
            let geocoder = CLGeocoder()
            let marks = try? await geocoder.reverseGeocodeLocation(CLLocation(latitude: pin.latitude, longitude: pin.longitude))
            let mark = marks?.first
            let parts = [mark?.name, mark?.locality, mark?.administrativeArea, mark?.country]
                .compactMap { $0 }
                .filter { !$0.isEmpty }
            await MainActor.run {
                pinAddress = parts.isEmpty ? "Selected location" : parts.joined(separator: ", ")
            }
        }
    }

    private func sharePin(_ coordinate: CLLocationCoordinate2D) {
        var text = String(format: "%.6f, %.6f", coordinate.latitude, coordinate.longitude)
        if let pinAddress, !pinAddress.isEmpty {
            text = "\\(pinAddress)\\n\\(text)"
        }
        let controller = UIActivityViewController(activityItems: [text], applicationActivities: nil)
        if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let root = scene.keyWindow?.rootViewController {
            root.present(controller, animated: true)
        }
    }

    private func select(completion: MKLocalSearchCompletion) {
'''
if helper_needle not in map_text:
    raise RuntimeError("Unable to insert address card helpers")
map_text = map_text.replace(helper_needle, helper_block, 1)
map_view.write_text(map_text, encoding="utf-8")

# Record a persistent travel timeline each time a real direct teleport succeeds.
session_file = root / "Locus/Engine/SpoofSession.swift"
session_text = session_file.read_text(encoding="utf-8")
history_needle = '''            if markRecent {
                pushRecent(coordinate)
            }
'''
history_replacement = '''            if markRecent {
                pushRecent(coordinate)
                MXTravelData.recordHistory(coordinate)
            }
'''
if history_needle not in session_text:
    raise RuntimeError("Unable to wire trip history")
session_text = session_text.replace(history_needle, history_replacement, 1)
session_file.write_text(session_text, encoding="utf-8")

print("Patched MX Travel/Dating Suite at", root)
