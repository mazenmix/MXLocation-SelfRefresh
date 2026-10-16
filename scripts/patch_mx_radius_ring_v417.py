#!/usr/bin/env python3
"""Show GPS-first search radius as a subtle MapKit ring without changing camera."""
from pathlib import Path
import sys

root=Path(sys.argv[1]).resolve()
folder=root/"Locus"/"Features"/"Map" if (root/"Locus"/"Features"/"Map").is_dir() else root
path=folder/"MXPlaceExplorer.swift"
source=path.read_text(encoding="utf-8")
old='''                Map(position: $camera) {
                    ForEach(visiblePlaces) { place in'''
new='''                Map(position: $camera) {
                    // Radius ring is part of MapKit, independent of results scrolling.
                    // It follows the selected GPS/search center without moving the camera.
                    if let selectedCenter {
                        MapCircle(center: selectedCenter, radius: radiusKM * 1_000)
                            .foregroundStyle(selectedColor.opacity(0.075))
                            .stroke(selectedColor.opacity(0.60), lineWidth: 1.5)
                    }
                    ForEach(visiblePlaces) { place in'''
assert source.count(old)==1, "Map content layout was unexpectedly changed"
assert r'ForEach([1.0, 5.0, 10.0, 15.0], id: \.self)' in source, "Expected tested v4.16 radius menu"
toolbar = source.split('private var radiusToolbar: some View {', 1)[1].split('private func results(', 1)[0]
assert 'Circle().fill(gpsIndicator.color)' not in toolbar, "Legacy GPS green dot still visible in toolbar"
assert 'session.teleport(to: place.coordinate, pairing: pairing)' in source, "GPS teleport operation changed"
assert '@State private var radiusKM: Double = 5' in source
path.write_text(source.replace(old,new,1),encoding="utf-8")
print("MX radius ring: selected GPS/area center; 1 5 10 15 km; no GPS logic modified")
