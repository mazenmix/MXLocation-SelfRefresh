#!/usr/bin/env python3
"""MX Location Pro v4.23: retain Map camera zoom/center/heading across bottom-tab changes.

The old RootView switch destroys MapHomeView when opening any other tab.
Keeping MapCameraPosition in RootView and passing a binding stops reinitialization
from snapping back to userLocation. Intentional Favorite jumps and locate/search
buttons still update that same camera binding.
"""
from pathlib import Path
import sys

root=Path(sys.argv[1]).resolve()
maps=root/"Locus"/"Features"/"Map"
root_path=maps/"RootView.swift"
map_path=maps/"MapHomeView.swift"
root_code=root_path.read_text(encoding="utf-8")
map_code=map_path.read_text(encoding="utf-8")

assert "import SwiftUI" in root_code, "Root must import SwiftUI"
assert root_code.count("struct RootView: View {")==1
assert root_code.count("    @State private var selectedTab = 0")==1
assert root_code.count("            default:\n                MapHomeView()")==1
assert "    @State private var retainedMapCamera" not in root_code
assert map_code.count("struct MapHomeView: View {")==1
old_state="    @State private var position: MapCameraPosition = .userLocation(fallback: .automatic)"
assert map_code.count(old_state)==1
assert "Map(position: $position)" in map_code
assert ".onAppear {" in map_code
assert "requestedMapPreview" in map_code
assert "centerOnCurrentLocation()" in map_code

# Persist in the long-lived RootView across Map/Saved/Discover/Places/Settings.
root_code=root_code.replace("import SwiftUI","import SwiftUI\nimport MapKit",1)
root_code=root_code.replace(
"    @State private var selectedTab = 0",
"    @State private var selectedTab = 0\n    @State private var retainedMapCamera: MapCameraPosition = .userLocation(fallback: .automatic)",1)
root_code=root_code.replace(
"            default:\n                MapHomeView()",
"            default:\n                MapHomeView(position: $retainedMapCamera)",1)

# Map continues writing all camera changes (user gestures and explicit zoom) through
# the binding. When re-created, its position comes from RootView, not the initial GPS.
map_code=map_code.replace(old_state,"    @Binding var position: MapCameraPosition",1)

assert root_code.count("MapHomeView(position: $retainedMapCamera)")==1
assert "MapHomeView()" not in root_code.split("struct RootView: View {",1)[1].split("struct MXSavedView: View {",1)[0]
assert "@Binding var position: MapCameraPosition" in map_code
assert old_state not in map_code
assert "Map(position: $position)" in map_code
assert "beginFavoriteJumpPreview" in map_code
assert "centerOnCurrentLocation()" in map_code
assert "session.teleport(to:" in map_code
assert "private var compactTabBar: some View" in root_code
assert "private var placesRadiusMenu: some View" in root_code

root_path.write_text(root_code,encoding="utf-8")
map_path.write_text(map_code,encoding="utf-8")
print("PASS v4.23: MapKit camera state is owned by RootView and survives all tab transitions without default GPS zoom")
