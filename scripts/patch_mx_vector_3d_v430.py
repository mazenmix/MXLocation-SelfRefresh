#!/usr/bin/env python3
"""MX Pro v4.30: GPU OpenFreeMap Liberty 3D, moderate teleport zoom and visually outlined Short Stay."""
from pathlib import Path
import shutil, sys

root=Path(sys.argv[1]).resolve()
mapdir=root/"Locus/Features/Map"
source=Path(__file__).resolve().parents[1]/"overlays"/"MXVectorOSMMapView.swift"
assert source.is_file(), "Missing MapLibre vector adapter"
shutil.copy2(source,mapdir/"MXVectorOSMMapView.swift")

# The existing hybrid bitmap raster engine remains as a fallback for accessory
# previews and other map miniatures, while main Explore uses vector rendering.
mapfile=mapdir/"MapHomeView.swift"
home=mapfile.read_text(encoding="utf-8")
old="                    MXOpenStreetMapView("
assert home.count(old)==1, "Unexpected primary OpenStreetMap view structure"
home=home.replace(old,"                    MXVectorOSMMapView(",1)
assert "Map(position: $position)" in home, "Preserve native Apple Maps"
assert 'mapProvider == "osm"' in home, "Preserve single map chooser in Settings"
assert 'cameraMemory.lock($position)' in home, "Preserve position/zoom on tab switching"
mapfile.write_text(home,encoding="utf-8")

# No zoom spikes on Change Location: preserve close-enough viewport or gently
# widen to ~5.4km, clamped to 11km for a comfortable city view.
memfile=mapdir/"MXMapCameraMemory.swift"
mem=memfile.read_text(encoding="utf-8")
old="""            distance: 1800,"""
assert mem.count(old)==1
mem=mem.replace(old,"""            distance: max(5400, min(11000, lastCamera?.distance ?? 5400)),""",1)
memfile.write_text(mem,encoding="utf-8")

# Make Short Stay distinctive even when the top-level tab is not selected.
# Retain the existing capsule size: only fill, outline and text emphasis change.
placefile=mapdir/"MXPlaceExplorer.swift"
places=placefile.read_text(encoding="utf-8")
color='private let shortStayTurquoise = Color(red: 0.30, green: 0.78, blue: 0.77)'
assert places.count(color)==1
places=places.replace(color,'private let shortStayTurquoise = Color(red: 0.12, green: 0.67, blue: 0.70)',1)
old_fill='.background(option == .shortStay ? (mode == option ? shortStayTurquoise : shortStayTurquoise.opacity(0.23)) : (mode == option ? selectedColor : Color.black.opacity(0.7)), in: Capsule())'
new_fill='''.background(option == .shortStay
                        ? (mode == option ? Color(red: 0.12, green: 0.67, blue: 0.70)
                                          : Color(red: 0.04, green: 0.25, blue: 0.30))
                        : (mode == option ? selectedColor : Color.black.opacity(0.7)), in: Capsule())
                        .overlay {
                            Capsule()
                                .strokeBorder(option == .shortStay
                                     ? Color(red: 0.60, green: 0.98, blue: 0.94)
                                     : Color.white.opacity(0.07),
                                     lineWidth: option == .shortStay ? 1.7 : 0.7)
                        }'''
assert places.count(old_fill)==1,"Short Stay mode chip changed upstream"
places=places.replace(old_fill,new_fill,1)
assert "session.teleport(to: place.coordinate, pairing: pairing)" in places
assert "MapCircle(center: selectedCenter, radius: radiusKM * 1_000)" in places
placefile.write_text(places,encoding="utf-8")

# Pin the official prebuilt native iOS MapLibre 6.28.0 dependency. Xcodegen links
# the dynamic XCFramework and embeds it in the unsigned app for SideStore signing.
project=root/"project.yml"
text=project.read_text(encoding="utf-8")
assert "targets:\n  Locus:" in text
assert "packages:\n" not in text
text=text.replace("targets:\n  Locus:", """packages:
  MapLibreSDK:
    url: https://github.com/maplibre/maplibre-gl-native-distribution
    exactVersion: 6.28.0
targets:
  Locus:""",1)
needle='''    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER:'''
assert text.count(needle)==1
text=text.replace(needle,'''    dependencies:
      - package: MapLibreSDK
        product: MapLibre
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER:''',1)
project.write_text(text,encoding="utf-8")
assert 'product: MapLibre' in text
assert 'MXVectorOSMMapView(' in home
assert 'distance: max(5400, min(11000' in mem
assert 'option == .shortStay ? 1.7 : 0.7' in places
print("PASS v4.30: true vector building extrusions (MapLibre SDK), smoother hardware map, mild teleport zoom, clear bordered Short Stay")
