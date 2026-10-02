from pathlib import Path
import sys

root = Path(sys.argv[1]).resolve()


def replace_required(path: Path, old: str, new: str, count: int = 1) -> None:
    text = path.read_text(encoding="utf-8")
    if old not in text:
        raise RuntimeError(f"Required source fragment not found in {path}: {old[:160]!r}")
    path.write_text(text.replace(old, new, count), encoding="utf-8")


# Replace Quick Places with the full MX travel/dating suite.
root_view = root / "Locus/Features/Map/RootView.swift"
replace_required(
    root_view,
    "        .sheet(isPresented: $showPlaces) {\n            QuickPlacesView()\n        }\n",
    "        .sheet(isPresented: $showPlaces) {\n            MXTravelSuiteView()\n        }\n",
)

# Map upgrades: lock, distance ring, address card, and visible lock control.
map_view = root / "Locus/Features/Map/MapHomeView.swift"
text = map_view.read_text(encoding="utf-8")

state_needle = "    @State private var showUndoToast = false\n"
if state_needle not in text:
    raise RuntimeError("Unable to locate quick-places state")
text = text.replace(
    state_needle,
    state_needle
    + '    @AppStorage("mx.locationLocked") private var locationLocked = false\n'
    + '    @AppStorage("mx.distanceRingKm") private var distanceRingKm = 0.0\n',
    1,
)

user_annotation = "                    UserAnnotation()\n\n"
ring = '''                    UserAnnotation()\n\n                    if distanceRingKm > 0,\n                       let ringCenter = session.simulated ?? session.pin ?? session.realCoordinate {\n                        MapCircle(center: ringCenter, radius: distanceRingKm * 1000)\n                            .foregroundStyle(LocusTheme.accent.opacity(0.10))\n                            .stroke(LocusTheme.accent.opacity(0.75), lineWidth: 2)\n                    }\n\n'''
if user_annotation not in text:
    raise RuntimeError("Unable to locate UserAnnotation")
text = text.replace(user_annotation, ring, 1)

text = text.replace(
    "                    guard !suppressNextMapTap, !isDraggingPin else { return }\n",
    "                    guard !locationLocked, !suppressNextMapTap, !isDraggingPin else { return }\n",
    1,
)
text = text.replace(
    "                            guard !drawMode, !isDraggingPin else { return }\n",
    "                            guard !locationLocked, !drawMode, !isDraggingPin else { return }\n",
    1,
)
text = text.replace(
    '''                                onDragMoved: { globalPoint in\n                                    if let coord = proxy.convert(globalPoint, from: .global) {\n                                        session.pin = coord\n                                    }\n                                },\n''',
    '''                                onDragMoved: { globalPoint in\n                                    guard !locationLocked else { return }\n                                    if let coord = proxy.convert(globalPoint, from: .global) {\n                                        session.pin = coord\n                                    }\n                                },\n''',
    1,
)

chrome_needle = '''            chromeIconButton(drawMode ? "pencil.tip.crop.circle.badge.minus" : "pencil.tip.crop.circle") {\n                drawMode.toggle()\n                if !drawMode { drawnPath.removeAll() }\n            }\n            .foregroundStyle(drawMode ? LocusTheme.accentSecondary : .primary)\n\n'''
if chrome_needle not in text:
    raise RuntimeError("Unable to locate map chrome controls")
text = text.replace(
    chrome_needle,
    chrome_needle
    + '''            chromeIconButton(locationLocked ? "lock.fill" : "lock.open") {\n                locationLocked.toggle()\n            }\n            .foregroundStyle(locationLocked ? LocusTheme.statusWarn : .primary)\n\n''',
    1,
)

on_appear = '''        .onAppear {\n            session.startLocationUpdates()\n        }\n'''
if on_appear not in text:
    raise RuntimeError("Unable to locate map lifecycle insertion point")
text = text.replace(
    on_appear,
    '''        .overlay(alignment: .bottom) {\n            if pinSelected, let pin = session.pin {\n                MXLocationInfoCard(coordinate: pin, onClose: { pinSelected = false })\n                    .padding(.horizontal, 16)\n                    .padding(.bottom, 190)\n            }\n        }\n        .onAppear {\n            session.startLocationUpdates()\n        }\n''',
    1,
)
map_view.write_text(text, encoding="utf-8")

# Longer timeline history for successful direct teleports.
session_file = root / "Locus/Engine/SpoofSession.swift"
session_text = session_file.read_text(encoding="utf-8")
recent_needle = '''            if markRecent {\n                pushRecent(coordinate)\n            }\n'''
if recent_needle not in session_text:
    raise RuntimeError("Unable to locate recent-history insertion point")
session_text = session_text.replace(
    recent_needle,
    '''            if markRecent {\n                pushRecent(coordinate)\n                MXTravelData.recordVisit(coordinate)\n            }\n''',
    1,
)
session_file.write_text(session_text, encoding="utf-8")

print("Patched MX Travel & Dating Suite at", root)
