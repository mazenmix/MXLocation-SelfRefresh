#!/usr/bin/env python3
"""v4.33 static regression contracts for the MapLibre pinch-zoom spring-back bug."""
from pathlib import Path
import sys

root = Path(sys.argv[1]) / "Locus/Features/Map"
main = (root / "MXVectorOSMMapView.swift").read_text(encoding="utf-8")
places = (root / "MXOSMUniversalMap.swift").read_text(encoding="utf-8")

for name, source in [("Main", main), ("Places/Previews", places)]:
    assert "let map = MLNMapView(" in source, name
    assert "MXVectorOSMStyle.ensure3DBuildings(in: style)" in source, name
    assert "lastAcceptedCamera = snapshot" in source, name
    assert "parent.position = .camera(snapshot)" in source or "parent.camera = .camera(snapshot)" in source, name
    assert "pendingProgrammaticCamera" not in source, name
    assert "programmaticTarget" not in source, name
    assert "apply(requested, to: mapView)" not in source, name
    assert "map.setCenter(region.center, zoomLevel: 14" not in source, name

assert "applyExternalCameraOnlyIfChanged(on: map, position: position)" in main
assert "if let accepted = lastAcceptedCamera" in main
assert "restoreNativeZoom: Bool = false" in main
assert "if restoreNativeZoom," in main
assert "if !hasLoadedStyle, let original = startCamera" in main

assert "if let accepted = lastAcceptedCamera, nearlyEqual(accepted, intended)" in places
assert "if !hasLoadedStyle, let initial = requestedAtStartup" in places
assert "if let prior = lastPublished, nearlyEqual(prior, snapshot)" in places

print("PASS v4.33: Map and Places 3D gesture zoom never chase a stale camera target")
