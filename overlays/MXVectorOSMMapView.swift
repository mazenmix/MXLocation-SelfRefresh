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
        map.showsCompass = false
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

        if let prior = cameraMemory.lastCamera ?? position.camera {
            var target = prior
            // Single migration for the former raster provider:
            // reveal 3D when OSM first loads, without forcing pitch on
            // each tab return or discarding the saved map center/zoom.
            if !UserDefaults.standard.bool(forKey: "mx.osm.vector.introduced3D") {
                target = MapCamera(centerCoordinate: prior.centerCoordinate,
                                   distance: prior.distance,
                                   heading: prior.heading,
                                   pitch: 54)
                UserDefaults.standard.set(true, forKey: "mx.osm.vector.introduced3D")
                cameraMemory.observe(target)
                cameraMemory.save()
                DispatchQueue.main.async {
                    self.position = .camera(target)
                }
            }
            context.coordinator.apply(target, to: map)
        } else if let chosen = simulated ?? pin {
            let snapshot = MapCamera(centerCoordinate: chosen, distance: 5500,
                                      heading: 0, pitch: 54)
            context.coordinator.apply(snapshot, to: map)
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
                map.setCenter(region.center, zoomLevel: 14, animated: false)
            }
        }
    }

    final class Coordinator: NSObject, MLNMapViewDelegate, UIGestureRecognizerDelegate {
        var parent: MXVectorOSMMapView
        var isGesturing = false
        private var isApplying = false
        private var lastPublished: MapCamera?
        private var selectedAnnotation: MLNPointAnnotation?
        private var activeAnnotation: MLNPointAnnotation?
        private var lastPin: CLLocationCoordinate2D?
        private var lastActive: CLLocationCoordinate2D?
        init(_ parent: MXVectorOSMMapView) { self.parent = parent }

        func mapView(_ mapView: MLNMapView, didFinishLoading style: MLNStyle) {
            // The Liberty style normally ships native fill-extruded buildings.
            // Only inject our fallback when the public style lacks that layer.
            if style.layer(withIdentifier: "building-3d") == nil,
               let source = style.source(withIdentifier: "openmaptiles") {
                let extrusions = MLNFillExtrusionStyleLayer(identifier: "mx-3d-buildings",
                                                          source: source)
                extrusions.sourceLayerIdentifier = "building"
                extrusions.minimumZoomLevel = 14
                extrusions.fillExtrusionHeight = NSExpression(forKeyPath: "render_height")
                extrusions.fillExtrusionBase = NSExpression(forKeyPath: "render_min_height")
                extrusions.fillExtrusionColor = NSExpression(forConstantValue:
                    UIColor(red: 0.80, green: 0.84, blue: 0.83, alpha: 1))
                extrusions.fillExtrusionOpacity = NSExpression(forConstantValue: 0.87)
                if let label = style.layer(withIdentifier: "poi") {
                    style.insertLayer(extrusions, below: label)
                } else {
                    style.addLayer(extrusions)
                }
            }
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
            guard !isApplying else { return }
            isGesturing = false
            let camera = mapView.camera
            let snapshot = MapCamera(centerCoordinate: camera.centerCoordinate,
                distance: max(camera.altitude, 10),
                heading: camera.heading,
                pitch: camera.pitch)
            if wasPublished(snapshot) { return }
            lastPublished = snapshot
            parent.cameraMemory.observe(snapshot)
            parent.cameraMemory.save()
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
            let target = MLNMapCamera(lookingAtCenter: snapshot.centerCoordinate,
                                      altitude: max(10, snapshot.distance),
                                      pitch: max(0, min(70, snapshot.pitch)),
                                      heading: snapshot.heading)
            map.setCamera(target, animated: false)
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
