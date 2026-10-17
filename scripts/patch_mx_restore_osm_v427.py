#!/usr/bin/env python3
"""MX Location Pro v4.27: restore real OSM tiles alongside dark Apple Maps.

Preserve user map camera, GPS operations, location search, pin selection and
all existing Map UI; add only one map layer switch in the lower map controls.
"""
from pathlib import Path
import shutil
import sys

root=Path(sys.argv[1]).resolve()
folder=root/"Locus"/"Features"/"Map"
path=folder/"MapHomeView.swift"
src=path.read_text(encoding="utf-8")
overlay=Path(__file__).resolve().parents[1]/"overlays/MXOpenStreetMapView.swift"
assert overlay.is_file()
shutil.copy2(overlay,folder/"MXOpenStreetMapView.swift")

state="    @ObservedObject var cameraMemory: MXMapCameraMemory"
assert src.count(state)==1,"Camera persistence regression: missing memory"
src=src.replace(state,state+'\n    @AppStorage("mx.map.provider") private var mapProvider = "apple"',1)

start=src.index("            MapReader { proxy in")
end=src.index("            .background(Color.black.ignoresSafeArea())",start)
old=src[start:end]
assert old.count("Map(position: $position)")==1
assert ".onMapCameraChange(frequency: .continuous)" in old
assert ".onMapCameraChange(frequency: .onEnd)" in old
assert "session.simulated" in old and "session.pin" in old
assert ".onTapGesture { point in" in old

replacement='''            Group {
                if mapProvider == "osm" {
                    MXOpenStreetMapView(
                        position: $position,
                        cameraMemory: cameraMemory,
                        pin: session.pin,
                        simulated: session.simulated
                    ) { coordinate in
                        searchFocused = false
                        guard !suppressNextMapTap else { return }
                        choosePin(coordinate, name: nil, subtitle: nil, zoom: false)
                    }
                    .overlay(alignment: .bottomLeading) {
                        Link("© OpenStreetMap contributors",
                             destination: URL(string: "https://www.openstreetmap.org/copyright")!)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.primary)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 5)
                            .background(.regularMaterial, in: Capsule())
                            .padding(.leading, 9)
                            .padding(.bottom, 95)
                    }
                } else {
'''+old+'''                }
            }
'''
src=src[:start]+replacement+src[end:]

oldControls="""                HStack {
                    Spacer()
                    locateButton
                }"""
newControls="""                HStack(spacing: 8) {
                    Spacer()
                    mapLayerMenu
                    locateButton
                }"""
assert src.count(oldControls)==1,"map lower controls unexpectedly changed"
src=src.replace(oldControls,newControls,1)

locate="    private var locateButton: some View {"
menu='''    private var mapLayerMenu: some View {
        Menu {
            Button {
                mapProvider = "apple"
            } label: {
                Label("Apple Maps", systemImage: mapProvider == "apple" ? "checkmark" : "map")
            }
            Button {
                mapProvider = "osm"
            } label: {
                Label("OpenStreetMap", systemImage: mapProvider == "osm" ? "checkmark" : "globe")
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "square.3.layers.3d")
                    .font(.system(size: 16, weight: .semibold))
                Text(mapProvider == "osm" ? "OSM" : "Apple")
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundStyle(.primary)
            .frame(height: 48)
            .padding(.horizontal, 13)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().stroke(Color.white.opacity(0.10), lineWidth: 1))
            .shadow(color: Color.black.opacity(0.25), radius: 10, y: 4)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Choose map provider")
    }

'''
assert src.count(locate)==1
src=src.replace(locate,menu+locate,1)

assert "Map(position: $position)" in src
assert "MXOpenStreetMapView(" in src
assert "cameraMemory.observe(context.camera)" in src
assert 'mapProvider == "osm"' in src
assert "session.teleport(to: coordinate, pairing: pairing)" in src
assert "session.requestedMapPreview" in src
assert "beginFavoriteJumpPreview" in src
assert "centerOnCurrentLocation()" in src
assert "@AppStorage" in src
assert "© OpenStreetMap contributors" in src
assert (folder/"MXOpenStreetMapView.swift").is_file()
path.write_text(src,encoding="utf-8")
print("PASS v4.27: Apple/OSM layer switch, genuine OSM tiles, persistent camera, unchanged Change Location and GPS")
