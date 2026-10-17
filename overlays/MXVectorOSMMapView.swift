import CoreLocation
import MapKit
import MapLibre
import SwiftUI
import UIKit

/// A genuine GPU vector-tile OSM map. OpenFreeMap Liberty has
/// OpenStreetMap building-height extrusions (where source data exists).
/// Camera state is bridged to the same MapCameraPosition as Apple Maps.
struct MXVectorOSMMapView: UIViewRepresentable {
    @Binding var position: MapCameraPosition
    @ObservedObject var cameraMemory: MXMapCameraMemory
    var pin: CLLocationCoordinate2D?
    var simulated: CLLocationCoordinate2D?
    var onTap: (CLLocationCoordinate2D) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> MLNMapView {
        let map = MLNMapView(frame: .zero,
                             styleURL: URL(string: "https://tiles.openfreemap.org/styles/liberty"))
        map.delegate = context.coordinator
        map.showsUserLocation = false
        map.compassView.isHidden = true
        map.showsScale = false
        map.isPitchEnabled = true
        map.isRotateEnabled = true
        map.isScrollEnabled = true
        map.isZoomEnabled = true
        map.minimumZoomLevel = 2
        map.maximumZoomLevel = 19

        let tap = UITapGestureRecognizer(target: context.coordinator,
                                         action: #selector(Coordinator.mapTapped(_:)))
        tap.cancelsTouchesInView = false
        tap.delegate = context.coordinator
        map.addGestureRecognizer(tap)

        // Never auto-pitch, zoom or re-center when returning from another tab.
        // The exact saved camera belongs to the user, not the map renderer.
        if let prior = cameraMemory.lastCamera ?? position.camera {
            context.coordinator.startCamera = prior
            context.coordinator.apply(prior, to: map)
        } else if let chosen = simulated ?? pin {
            let initial = MapCamera(centerCoordinate: chosen, distance: 5500,
                                    heading: 0, pitch: 0)
            context.coordinator.startCamera = initial
            context.coordinator.apply(initial, to: map)
        }
        context.coordinator.updateMarkers(on: map, pin: pin, active: simulated)
        return map
    }

    func updateUIView(_ map: MLNMapView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.updateMarkers(on: map, pin: pin, active: simulated)
        guard !context.coordinator.isGesturing else { return }
        // Re-apply camera only when the *user/app* requested a different
        // position (Change Location, Favorite). Ignore our own camera echo.
        if let camera = position.camera {
            if !context.coordinator.wasPublished(camera),
               context.coordinator.cameraDiffers(map.camera, from: camera) {
                context.coordinator.apply(camera, to: map)
            }
        } else if let region = position.region {
            let current = map.centerCoordinate
            if abs(current.latitude - region.center.latitude) > 0.00002 ||
                abs(current.longitude - region.center.longitude) > 0.00002 {
                // A provider/region change may move the center, never the zoom.
                map.setCenter(region.center, animated: false)
            }
        }
    }

    final class Coordinator: NSObject, MLNMapViewDelegate, UIGestureRecognizerDelegate {
        var parent: MXVectorOSMMapView
        var isGesturing = false
        private var isApplying = false
        private var hasLoadedStyle = false
        private var programmaticTarget: MapCamera?
        var startCamera: MapCamera?
        private var lastPublished: MapCamera?
        private static let nativeViewportKey = "mx.osm.main.nativeViewport.v432"
        private var selectedAnnotation: MLNPointAnnotation?
        private var activeAnnotation: MLNPointAnnotation?
        private var lastPin: CLLocationCoordinate2D?
        private var lastActive: CLLocationCoordinate2D?
        init(_ parent: MXVectorOSMMapView) { self.parent = parent }

        func mapView(_ mapView: MLNMapView, didFinishLoading style: MLNStyle) {
            MXVectorOSMStyle.ensure3DBuildings(in: style)
            // MapLibre may asynchronously reset the camera while it loads
            // the vector style. Ignore those initial camera events completely.
            if let original = startCamera {
                apply(original, to: mapView)
            }
            hasLoadedStyle = true
        }

        private func same(_ a: CLLocationCoordinate2D?, _ b: CLLocationCoordinate2D?) -> Bool {
            if a == nil && b == nil { return true }
            guard let a, let b else { return false }
            return abs(a.latitude - b.latitude) < 0.0000001 &&
                abs(a.longitude - b.longitude) < 0.0000001
        }
        func updateMarkers(on map: MLNMapView, pin: CLLocationCoordinate2D?,
                           active: CLLocationCoordinate2D?) {
            if !same(lastPin, pin) {
                if let old = selectedAnnotation { map.removeAnnotation(old) }
                lastPin = pin
                if let pin, CLLocationCoordinate2DIsValid(pin) {
                    let annotation = MLNPointAnnotation()
                    annotation.coordinate = pin
                    annotation.title = "Selected Location"
                    selectedAnnotation = annotation
                    map.addAnnotation(annotation)
                } else {
                    selectedAnnotation = nil
                }
            }
            if !same(lastActive, active) {
                if let old = activeAnnotation { map.removeAnnotation(old) }
                lastActive = active
                if let active, CLLocationCoordinate2DIsValid(active) {
                    let annotation = MLNPointAnnotation()
                    annotation.coordinate = active
                    annotation.title = "Active"
                    activeAnnotation = annotation
                    map.addAnnotation(annotation)
                } else {
                    activeAnnotation = nil
                }
            }
        }

        func mapView(_ mapView: MLNMapView, regionWillChangeAnimated animated: Bool) {
            if !isApplying { isGesturing = true }
        }
        func mapView(_ mapView: MLNMapView, regionDidChangeAnimated animated: Bool) {
            guard hasLoadedStyle, !isApplying else { return }
            isGesturing = false
            if let requested = programmaticTarget {
                // Do not publish synthetic viewport events triggered by app
                // initialization, map-style refresh, or explicit camera sets.
                // Never chase a spontaneously changing camera during style load.
                if !cameraDiffers(mapView.camera, from: requested) {
                    programmaticTarget = nil
                } else {
                    apply(requested, to: mapView)
                }
                return
            }
            let camera = mapView.camera
            let snapshot = MapCamera(centerCoordinate: camera.centerCoordinate,
                distance: max(camera.altitude, 10),
                heading: camera.heading,
                pitch: camera.pitch)
            if wasPublished(snapshot) { return }
            lastPublished = snapshot
            startCamera = snapshot
            parent.cameraMemory.observe(snapshot)
            parent.cameraMemory.save()
            UserDefaults.standard.set([
                "latitude": camera.centerCoordinate.latitude,
                "longitude": camera.centerCoordinate.longitude,
                "altitude": camera.altitude,
                "zoom": mapView.zoomLevel,
                "pitch": camera.pitch,
                "heading": camera.heading
            ], forKey: Self.nativeViewportKey)
            parent.position = .camera(snapshot)
        }

        func cameraDiffers(_ actual: MLNMapCamera, from target: MapCamera) -> Bool {
            abs(actual.centerCoordinate.latitude - target.centerCoordinate.latitude) > 0.000025 ||
            abs(actual.centerCoordinate.longitude - target.centerCoordinate.longitude) > 0.000025 ||
            abs(actual.altitude - target.distance) > max(30, target.distance * 0.03) ||
            abs(actual.pitch - target.pitch) > 1.5 ||
            abs(actual.heading - target.heading) > 1.5
        }
        func wasPublished(_ target: MapCamera) -> Bool {
            guard let previous = lastPublished else { return false }
            return abs(previous.centerCoordinate.latitude-target.centerCoordinate.latitude) < 0.000025 &&
                abs(previous.centerCoordinate.longitude-target.centerCoordinate.longitude) < 0.000025 &&
                abs(previous.distance-target.distance) < max(30, target.distance * 0.03) &&
                abs(previous.pitch-target.pitch) < 1.5 &&
                abs(previous.heading-target.heading) < 1.5
        }
        func apply(_ snapshot: MapCamera, to map: MLNMapView) {
            isApplying = true
            programmaticTarget = snapshot
            let target = MLNMapCamera(lookingAtCenter: snapshot.centerCoordinate,
                                      altitude: max(10, snapshot.distance),
                                      pitch: max(0, min(70, snapshot.pitch)),
                                      heading: snapshot.heading)
            map.setCamera(target, animated: false)
            if let native = UserDefaults.standard.dictionary(forKey: Self.nativeViewportKey),
               let lat = native["latitude"] as? Double,
               let lon = native["longitude"] as? Double,
               let altitude = native["altitude"] as? Double,
               let zoom = native["zoom"] as? Double,
               abs(lat - snapshot.centerCoordinate.latitude) < 0.00003,
               abs(lon - snapshot.centerCoordinate.longitude) < 0.00003,
               abs(altitude - snapshot.distance) < max(30, snapshot.distance * 0.03),
               zoom.isFinite, (2...19).contains(zoom) {
                // Native MapLibre zoom is restored rather than approximated
                // with MapKit distance, preventing cumulative zoom drift.
                map.setZoomLevel(zoom, animated: false)
            }
            // Compare against the actual rendered camera after restoring
            // native vector zoom; MapCamera.distance may round differently.
            let rendered = map.camera
            programmaticTarget = MapCamera(centerCoordinate: rendered.centerCoordinate,
                    distance: max(10, rendered.altitude),
                    heading: rendered.heading,
                    pitch: rendered.pitch)
            isApplying = false
        }

        @objc func mapTapped(_ recognizer: UITapGestureRecognizer) {
            guard recognizer.state == .ended, let map = recognizer.view as? MLNMapView else { return }
            let location = recognizer.location(in: map)
            let target = map.convert(location, toCoordinateFrom: map)
            guard CLLocationCoordinate2DIsValid(target) else { return }
            parent.onTap(target)
        }
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            true
        }
    }
}


/// Shared 3D vector building style used by Map, Places, and previews.
enum MXVectorOSMStyle {
    static func ensure3DBuildings(in style: MLNStyle) {
        guard style.layer(withIdentifier: "building-3d") == nil,
              style.layer(withIdentifier: "mx-3d-buildings") == nil,
              let source = style.source(withIdentifier: "openmaptiles") else { return }
        let buildings = MLNFillExtrusionStyleLayer(identifier: "mx-3d-buildings", source: source)
        buildings.sourceLayerIdentifier = "building"
        buildings.minimumZoomLevel = 14
        buildings.fillExtrusionHeight = NSExpression(forKeyPath: "render_height")
        buildings.fillExtrusionBase = NSExpression(forKeyPath: "render_min_height")
        buildings.fillExtrusionColor = NSExpression(forConstantValue:
            UIColor(red: 0.80, green: 0.84, blue: 0.83, alpha: 1))
        buildings.fillExtrusionOpacity = NSExpression(forConstantValue: 0.87)
        if let poi = style.layer(withIdentifier: "poi") {
            style.insertLayer(buildings, below: poi)
        } else {
            style.addLayer(buildings)
        }
    }
}
