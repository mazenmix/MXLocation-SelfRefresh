#!/usr/bin/env python3
"""v4.28: smooth raster OSM zoom without resetting the map camera on every render."""
from pathlib import Path
import sys
p=Path(sys.argv[1]).resolve()/"Locus/Features/Map/MXOpenStreetMapView.swift"
s=p.read_text(encoding="utf-8")
def change(a,b):
    global s
    assert s.count(a)==1, ("Expected once",a[:110],s.count(a))
    s=s.replace(a,b,1)
change("        map.mapType = .standard","        map.mapType = .mutedStandard\n        map.overrideUserInterfaceStyle = .light")
change("        map.isPitchEnabled = true","        // Bitmap raster cannot extrude buildings; flat tiles stop 3D repaint flickering.\n        map.isPitchEnabled = false")
change("        tiles.canReplaceMapContent = true","        // Keep Apple tiles as a bright fallback; no empty black map during zoom.\n        tiles.canReplaceMapContent = false")
change("        private var lastActive: CLLocationCoordinate2D?","        private var lastActive: CLLocationCoordinate2D?\n        private var lastPublishedCamera: MapCamera?\n        private var programmaticTarget: MapCamera?")
change("""        if let camera = cameraMemory.lastCamera ?? position.camera {
            context.coordinator.apply(camera, to: map)""",
"""        if let camera = cameraMemory.lastCamera ?? position.camera {
            context.coordinator.apply(context.coordinator.flat(camera), to: map)""")
change("""        if let requested = position.camera {
            if context.coordinator.needsCameraChange(map, to: requested) {
                context.coordinator.apply(requested, to: map)
            }
        } else if let requested = position.region,
                  context.coordinator.needsRegionChange(map, to: requested) {
            context.coordinator.apply(requested, to: map)
        }""",
"""        if let camera = position.camera {
            let requested = context.coordinator.flat(camera)
            // Prevent re-applying camera snapshots published by this map itself.
            if context.coordinator.wasPublished(requested) { return }
            if context.coordinator.needsCameraChange(map, to: requested) {
                context.coordinator.apply(requested, to: map)
            }
        } else if let requested = position.region,
                  context.coordinator.needsRegionChange(map, to: requested) {
            context.coordinator.apply(requested, to: map)
        }""")
change("""            guard !isApplying else { return }
            isUserMoving = false
            let camera = mapView.camera
            let snapshot = MapCamera(
                centerCoordinate: camera.centerCoordinate,
                distance: max(camera.centerCoordinateDistance, 10),
                heading: camera.heading,
                pitch: camera.pitch
            )
            parent.cameraMemory.observe(snapshot)
            parent.cameraMemory.save()
            parent.position = .camera(snapshot)""",
"""            guard !isApplying else { return }
            isUserMoving = false
            if let target = programmaticTarget {
                programmaticTarget = nil
                if !needsCameraChange(mapView, to: target) { return }
            }
            let camera = mapView.camera
            let snapshot = MapCamera(
                centerCoordinate: camera.centerCoordinate,
                distance: max(camera.centerCoordinateDistance, 10),
                heading: camera.heading,
                pitch: 0
            )
            if wasPublished(snapshot) { return }
            lastPublishedCamera = snapshot
            parent.cameraMemory.observe(snapshot)
            parent.cameraMemory.save()
            parent.position = .camera(snapshot)""")
change("        func needsCameraChange(_ map: MKMapView, to desired: MapCamera) -> Bool {",
"""        func flat(_ camera: MapCamera) -> MapCamera {
            MapCamera(centerCoordinate: camera.centerCoordinate,
                      distance: max(10, camera.distance),
                      heading: camera.heading,
                      pitch: 0)
        }

        func wasPublished(_ camera: MapCamera) -> Bool {
            guard let previous = lastPublishedCamera else { return false }
            return abs(previous.centerCoordinate.latitude - camera.centerCoordinate.latitude) < 0.000015 &&
                abs(previous.centerCoordinate.longitude - camera.centerCoordinate.longitude) < 0.000015 &&
                abs(previous.distance - camera.distance) < max(12, camera.distance * 0.02) &&
                abs(previous.heading - camera.heading) < 0.7
        }

        func needsCameraChange(_ map: MKMapView, to desired: MapCamera) -> Bool {""")
change("""        func apply(_ snapshot: MapCamera, to map: MKMapView) {
            isApplying = true
            let camera = MKMapCamera(
                lookingAtCenter: snapshot.centerCoordinate,
                fromDistance: max(snapshot.distance, 10),
                pitch: snapshot.pitch,
                heading: snapshot.heading
            )
            map.setCamera(camera, animated: false)
            isApplying = false
        }""",
"""        func apply(_ snapshot: MapCamera, to map: MKMapView) {
            isApplying = true
            let actual = flat(snapshot)
            programmaticTarget = actual
            let camera = MKMapCamera(
                lookingAtCenter: actual.centerCoordinate,
                fromDistance: actual.distance,
                pitch: 0,
                heading: actual.heading
            )
            map.setCamera(camera, animated: false)
            isApplying = false
        }""")
change("    private static let tileSession: URLSession = {",
"""    private static let memoryTiles: NSCache<NSString, NSData> = {
        let cache = NSCache<NSString, NSData>()
        cache.totalCostLimit = 20 * 1024 * 1024
        return cache
    }()

    private static let tileSession: URLSession = {""")
change("""        let url = url(forTilePath: path)
        var request = URLRequest(url: url)
        request.cachePolicy = .useProtocolCachePolicy
        Self.tileSession.dataTask(with: request) { data, response, error in
            if let response = response as? HTTPURLResponse, response.statusCode != 200 {
                result(nil, URLError(.badServerResponse))
            } else {
                result(data, error)
            }
        }.resume()""",
"""        let key = "\(path.z)/\(path.x)/\(path.y)/\(path.contentScaleFactor)" as NSString
        if let cached = Self.memoryTiles.object(forKey: key) {
            result(cached as Data, nil)
            return
        }
        let url = url(forTilePath: path)
        var request = URLRequest(url: url)
        request.cachePolicy = .useProtocolCachePolicy
        Self.tileSession.dataTask(with: request) { data, response, error in
            if let response = response as? HTTPURLResponse,
               response.statusCode == 200,
               let data, !data.isEmpty {
                Self.memoryTiles.setObject(data as NSData, forKey: key, cost: data.count)
                result(data, nil)
            } else {
                result(nil, error ?? URLError(.badServerResponse))
            }
        }.resume()""")
assert "map.isPitchEnabled = false" in s
assert "map.canReplaceMapContent" not in s
assert 'tiles.canReplaceMapContent = false' in s
assert "parent.position = .camera(snapshot)" in s
p.write_text(s,encoding="utf-8")
print("PASS 4.28: OSM steady flat tiles, prevent camera feedback loop, cache tiles, maintain map center.")
