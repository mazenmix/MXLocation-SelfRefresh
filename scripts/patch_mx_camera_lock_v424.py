#!/usr/bin/env python3
"""v4.24: lock the main MapKit *rendered viewport* across tabs.

v4.23 stored MapCameraPosition with a .userLocation target, which can resolve
again to the phone's real GPS (e.g. Iraq) on return. Freeze the exact camera
center/distance/heading/pitch when the user pans, pinches or leaves Map, persist
it in UserDefaults, and restore it before Map reappears.
"""
from pathlib import Path
import shutil
import sys

base=Path(sys.argv[1]).resolve()
folder=base/"Locus"/"Features"/"Map"
root_file=folder/"RootView.swift"
map_file=folder/"MapHomeView.swift"
root=root_file.read_text(encoding="utf-8")
view=map_file.read_text(encoding="utf-8")

source=Path(__file__).resolve().parents[1]/"overlays"/"MXMapCameraMemory.swift"
assert source.is_file(), "Missing Map camera memory source"
shutil.copy2(source, folder/"MXMapCameraMemory.swift")

old_state="    @State private var retainedMapCamera: MapCameraPosition = .userLocation(fallback: .automatic)"
new_state="""    @State private var retainedMapCamera: MapCameraPosition = MXMapCameraMemory.initialPosition()
    @StateObject private var mapCameraMemory = MXMapCameraMemory()"""
assert root.count(old_state)==1, "Expected v4.23 retained camera state"
root=root.replace(old_state,new_state,1)

old_home="                MapHomeView(position: $retainedMapCamera)"
new_home="                MapHomeView(position: $retainedMapCamera, cameraMemory: mapCameraMemory)"
assert root.count(old_home)==1, "Root MapHomeView constructor changed"
root=root.replace(old_home,new_home,1)

old_bottom="""        .safeAreaInset(edge: .bottom, spacing: 2) {
            compactTabBar
        }"""
new_bottom="""        .safeAreaInset(edge: .bottom, spacing: 2) {
            compactTabBar
        }
        // Real phone GPS updates must never re-center this map by themselves.
        // An explicit simulated-location change may switch countries without changing zoom.
        .onChange(of: session.simulated?.latitude) { previousLatitude, newLatitude in
            guard previousLatitude != newLatitude,
                  let target = session.simulated else { return }
            mapCameraMemory.moveToChosenLocation(target, position: $retainedMapCamera)
        }"""
assert root.count(old_bottom)==1, "Could not locate root shell safe area"
root=root.replace(old_bottom,new_bottom,1)
# One-time migration: users upgrading from v4.23 have no persisted camera yet.
# Prefer their actual *selected/simulated* location to the phone's physical GPS.
insert='''        .onAppear {
            if !didSeedInitialMapCamera {
                didSeedInitialMapCamera = true
                if !mapCameraMemory.restoredFromDisk,
                   let chosen = session.simulated ?? session.pin {
                    mapCameraMemory.moveToChosenLocation(chosen, position: $retainedMapCamera)
                }
            }
        }
'''
anchor='''        .safeAreaInset(edge: .bottom, spacing: 2) {
            compactTabBar
        }
'''
assert root.count(anchor)==1
root=root.replace(anchor,anchor+insert,1)
state_anchor="    @StateObject private var mapCameraMemory = MXMapCameraMemory()"
assert root.count(state_anchor)==1
root=root.replace(state_anchor,state_anchor+"\n    @State private var didSeedInitialMapCamera = false",1)

old_binding="    @Binding var position: MapCameraPosition"
new_binding="""    @Binding var position: MapCameraPosition
    @ObservedObject var cameraMemory: MXMapCameraMemory"""
assert view.count(old_binding)==1
view=view.replace(old_binding,new_binding,1)

old_map="""                .mapStyle(.standard(elevation: .realistic))
                .mapControlVisibility(.hidden)"""
new_map="""                .mapStyle(.standard(elevation: .realistic))
                .mapControlVisibility(.hidden)
                // Capture the actual MapKit camera after user drag/pinch/rotate.
                // Do not infer the viewport from physical GPS or selected pin.
                .onMapCameraChange(frequency: .continuous) { context in
                    cameraMemory.observe(context.camera)
                }
                .onMapCameraChange(frequency: .onEnd) { context in
                    cameraMemory.observe(context.camera)
                    cameraMemory.save()
                }"""
assert view.count(old_map)==1, "MapKit map style/controls changed"
view=view.replace(old_map,new_map,1)

start_appear="""        .onAppear {
            session.startLocationUpdates()
"""
repl_appear="""        .onAppear {
            session.startLocationUpdates()
            // Restore the camera exactly as it was left. Do not follow
            // the iPhone's unspoofed GPS on tab activation.
            if session.requestedMapPreview == nil {
                cameraMemory.lock($position)
            }
"""
assert view.count(start_appear)==1
view=view.replace(start_appear,repl_appear,1)

needle="        .onChange(of: session.pin?.latitude) { _, newValue in"
assert view.count(needle)==1
view=view.replace(needle, """        .onDisappear {
            // Convert any MapCameraPosition.userLocation tracking into an exact
            // camera snapshot before SwiftUI destroys this tab's Map view.
            cameraMemory.lock($position)
        }
"""+needle,1)

# Explicit search/favorite/locate buttons must retain their intentional camera actions.
assert "beginFavoriteJumpPreview" in view
assert "position = .region(MKCoordinateRegion(" in view
assert "private func centerOnCurrentLocation()" in view
assert "session.teleport(to: coordinate, pairing: pairing)" in view
assert "Map(position: $position)" in view
assert view.count("cameraMemory.observe(context.camera)")==2
assert "MapHomeView(position: $retainedMapCamera, cameraMemory: mapCameraMemory)" in root
assert "private var compactTabBar: some View" in root
assert "private var placesRadiusMenu: some View" in root
assert (folder/"MXMapCameraMemory.swift").is_file()

root_file.write_text(root, encoding="utf-8")
map_file.write_text(view, encoding="utf-8")
print("PASS v4.24: exact MapKit camera retained & persisted, physical phone location cannot reset it on tab change")
