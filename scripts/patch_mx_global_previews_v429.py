#!/usr/bin/env python3
"""v4.29: honor Apple/OSM map selection throughout feature previews and planned routes."""
from pathlib import Path
import sys

path=Path(sys.argv[1]).resolve()/"Locus/Features/Map/MXProToolbox.swift"
s=path.read_text(encoding="utf-8")

def map_replace(source, starting, replacement):
    assert source.count(starting)==1, ("Expected unique map",starting,source.count(starting))
    start=source.index(starting)
    op=source.index("{",start)
    depth=0
    closing=None
    for i in range(op,len(source)):
        if source[i]=="{": depth+=1
        elif source[i]=="}":
            depth-=1
            if depth==0:
                closing=i
                break
    assert closing is not None
    return source[:start]+replacement+source[closing+1:]

s=map_replace(s,
    "Map(initialPosition: .region(MKCoordinateRegion(center: pin, latitudinalMeters: radius * 2000, longitudinalMeters: radius * 2000))) {",
    '''MXUnifiedMapPreview(center: pin, distance: radius * 2000,
                                markers: [MXUnifiedMarker(id: "A", name: "Area A", coordinate: pin)])''')
s=map_replace(s,
    "Map(initialPosition: .region(MKCoordinateRegion(center: otherPin, latitudinalMeters: radius * 2000, longitudinalMeters: radius * 2000))) {",
    '''MXUnifiedMapPreview(center: otherPin, distance: radius * 2000,
                                markers: [MXUnifiedMarker(id: "B", name: "Area B", coordinate: otherPin)])''')
s=map_replace(s,
    "Map(initialPosition: .region(MKCoordinateRegion(center: pin, latitudinalMeters: max(1200, path.distance * 1.7), longitudinalMeters: max(1200, path.distance * 1.7)))) {",
    '''MXUnifiedMapPreview(
                        center: pin, distance: max(1200, path.distance * 1.7),
                        markers: [MXUnifiedMarker(id: "start", name: "Start", coordinate: pin)] +
                            (destination.map { [MXUnifiedMarker(id: "finish", name: "Finish", coordinate: $0)] } ?? []),
                        routes: [MXMapRouteGeometry.coordinates(path.polyline)])''')
s=map_replace(s,
    "Map(initialPosition: .region(MKCoordinateRegion(center: pin, latitudinalMeters: 12000, longitudinalMeters: 12000))) {",
    '''MXUnifiedMapPreview(
                    center: pin, distance: 12000,
                    markers: groups.map {
                        MXUnifiedMarker(id: String(format: "%.5f,%.5f", $0.latitude, $0.longitude),
                                        name: "\($0.count) venues", coordinate: $0.coordinate)
                    })''')
s=map_replace(s,
    "Map(initialPosition: .automatic) {",
    '''MXUnifiedMapPreview(
                        center: MXMapRouteGeometry.center(library.itinerary.map(\.coordinate)),
                        distance: MXMapRouteGeometry.spanMeters(library.itinerary.map(\.coordinate)),
                        markers: library.itinerary.map {
                            MXUnifiedMarker(id: String(format: "%.5f,%.5f", $0.coordinate.latitude, $0.coordinate.longitude),
                                             name: $0.name, coordinate: $0.coordinate)
                        },
                        routes: routeLegs.map { MXMapRouteGeometry.coordinates($0.polyline) })''')
assert "Map(initialPosition:" not in s, "Some Toolbox feature maps still ignore the map provider"
assert s.count("MXUnifiedMapPreview(")>=5
path.write_text(s,encoding="utf-8")
print("PASS v4.29: Compare, Route, Hotspots and Itinerary map previews use the selected global provider")
