#!/usr/bin/env python3
"""MX Pro v4.29: true edge-to-edge map, two-finger OSM pitch, unified provider in Places & mini previews."""
from pathlib import Path
import shutil, sys, re

base=Path(sys.argv[1]).resolve()
mapdir=base/"Locus/Features/Map"
home=mapdir/"MapHomeView.swift"
root=mapdir/"RootView.swift"
osm=mapdir/"MXOpenStreetMapView.swift"
places=mapdir/"MXPlaceExplorer.swift"
worlds=mapdir/"MXWorlds.swift"
toolbox=mapdir/"MXProToolbox.swift"
overlay=Path(__file__).resolve().parents[1]/"overlays/MXOSMUniversalMap.swift"
assert overlay.exists()
shutil.copy2(overlay,mapdir/"MXOSMUniversalMap.swift")

def once(src,old,new):
    assert src.count(old)==1,("Unexpected source structure",old[:160],src.count(old))
    return src.replace(old,new,1)

r=root.read_text(encoding="utf-8")
r=once(r,"""        .safeAreaInset(edge: .bottom, spacing: 2) {
            compactTabBar
        }""",
"""        // Overlay the tab bar over the full-bleed map instead of reserving
        // an opaque black bottom stripe in the parent's safe area.
        .overlay(alignment: .bottom) {
            compactTabBar
                .padding(.bottom, 4)
        }""")
# Non-map tabs still reserve space so their bottom content is not hidden
# behind the custom navigation bar.
partstart=r.index("            switch selectedTab {")
partend=r.index("\n        }\n        // Overlay the tab bar",partstart)
block=r[partstart:partend]
lines=block.splitlines()
for idx,line in enumerate(lines):
    match=re.fullmatch(r"(\s+)([A-Za-z][A-Za-z0-9_]*View\(.*\))",line)
    if match and "MapHomeView" not in line:
        lines[idx]=match.group(1)+match.group(2)+".safeAreaPadding(.bottom, 72)"
r=r[:partstart]+"\n".join(lines)+r[partend:]
assert ".overlay(alignment: .bottom)" in r
assert "compactTabBar" in r and "MapHomeView(position: $retainedMapCamera" in r
root.write_text(r,encoding="utf-8")

h=home.read_text(encoding="utf-8")
# Extend the raw map render surface behind the time/signal at the top and
# under the lower controls/home indicator. Floating search stays safe-area.
h=once(h,"""            .background(Color.black.ignoresSafeArea())""",
"""            .ignoresSafeArea(.container, edges: [.top, .bottom])
            .background(Color.black.ignoresSafeArea())""")
h=once(h,"""            .padding(.horizontal, 14)
            .padding(.top, 10)
            .padding(.bottom, 10)""",
"""            .padding(.horizontal, 14)
            .padding(.top, 10)
            .padding(.bottom, 74)""")
assert ".ignoresSafeArea(.container, edges: [.top, .bottom])" in h
assert 'MXOpenStreetMapView(' in h
home.write_text(h,encoding="utf-8")

o=osm.read_text(encoding="utf-8")
o=once(o,"map.isPitchEnabled = false","map.isPitchEnabled = true")
# The user's two-finger gesture controls pitch, but standard OSM raster
# tiles have no extruded building geometry; Apple 3D stays separate.
o=once(o,"""                pitch: 0
            )
            if wasPublished(snapshot)""",
"""                pitch: camera.pitch
            )
            if wasPublished(snapshot)""")
o=once(o,"""                      pitch: 0)
        }

        func wasPublished""",
"""                      pitch: camera.pitch)
        }

        func wasPublished""")
o=once(o,"""                pitch: 0,
                heading: actual.heading""",
"""                pitch: actual.pitch,
                heading: actual.heading""")
o=once(o,"""                abs(previous.heading - camera.heading) < 0.7""",
"""                abs(previous.heading - camera.heading) < 0.7 &&
                abs(previous.pitch - camera.pitch) < 0.7""")
assert "map.isPitchEnabled = true" in o
osm.write_text(o,encoding="utf-8")

p=places.read_text(encoding="utf-8")
state='    @AppStorage("mx.places.radiusKM") private var radiusKM: Double = 5'
assert p.count(state)==1
p=p.replace(state,state+'\n    @AppStorage("mx.map.provider") private var mapProvider = "apple"',1)

mapstart=p.index("                Map(position: $camera) {")
mapend=p.index("\n                VStack(spacing: 10) {",mapstart)
apple=p[mapstart:mapend]
assert apple.count("MapCircle(center: selectedCenter, radius: radiusKM * 1_000)")==1
assert ".onMapCameraChange(frequency: .onEnd)" in apple

replacement='''                if mapProvider == "osm" {
                    MXOSMUniversalMap(
                        camera: $camera,
                        markers: visiblePlaces.map {
                            MXUnifiedMarker(id: $0.id, name: $0.name, coordinate: $0.coordinate)
                        },
                        circleCenter: selectedCenter,
                        radiusMeters: radiusKM * 1000,
                        onRegionChange: { region in
                            updateVisibleMapRegion(region)
                        }
                    )
                    .ignoresSafeArea(edges: .bottom)
                } else {
'''+apple+'''                }
'''
p=p[:mapstart]+replacement+p[mapend:]
helperAnchor="    private var modePicker: some View {"
assert p.count(helperAnchor)==1
helper='''    private func updateVisibleMapRegion(_ region: MKCoordinateRegion) {
        visibleRegion = region
        guard let selectedCenter else { return }
        let offset = CLLocation(latitude: region.center.latitude, longitude: region.center.longitude)
            .distance(from: CLLocation(latitude: selectedCenter.latitude, longitude: selectedCenter.longitude))
        needsAreaSearch = offset > max(300, radiusKM * 150)
    }

'''
p=p.replace(helperAnchor,helper+helperAnchor,1)
assert "MXOSMUniversalMap(" in p and "Map(position: $camera)" in p
assert "MapCircle(center: selectedCenter, radius: radiusKM * 1_000)" in p
places.write_text(p,encoding="utf-8")

# Saved worlds, Recent/Saved detail mini map views share the selected provider.
w=worlds.read_text(encoding="utf-8")
beg=w.index("struct MXWorldMiniMap: View {")
finish=w.index("\nstruct MXWorldListRow: View {",beg)
worldReplacement='''struct MXWorldMiniMap: View {
    let place: SavedPlace
    var radiusMeters: CLLocationDistance = 5000
    var body: some View {
        MXUnifiedMapPreview(center: place.coordinate,
                            distance: radiusMeters,
                            markers: [
                                MXUnifiedMarker(id: place.id.uuidString,
                                                name: place.name,
                                                coordinate: place.coordinate)
                            ])
            .allowsHitTesting(false)
    }
}
'''
# SavedPlace.id may be String, Int, UUID. Use coordinate-derived stable id instead.
worldReplacement=worldReplacement.replace("place.id.uuidString","String(format: \"%.5f,%.5f\", place.latitude, place.longitude)")
w=w[:beg]+worldReplacement+w[finish:]
assert "MXUnifiedMapPreview(" in w
worlds.write_text(w,encoding="utf-8")

print("PASS v4.29: map full-bleed, 2-finger tilt, provider in Places & Worlds, unchanged GPS")
