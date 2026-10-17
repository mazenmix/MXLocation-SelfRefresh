import CoreLocation
import MapKit
import SwiftUI
import UIKit

/// Native MapKit gestures plus genuine, standard OpenStreetMap raster tiles.
/// The App's camera binding is shared with Apple Maps and is never reset by
/// creating the tile renderer, changing tabs or rendering new annotations.
struct MXOpenStreetMapView: UIViewRepresentable {
    @Binding var position: MapCameraPosition
    @ObservedObject var cameraMemory: MXMapCameraMemory
    var pin: CLLocationCoordinate2D?
    var simulated: CLLocationCoordinate2D?
    var onTap: (CLLocationCoordinate2D) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView(frame: .zero)
        map.delegate = context.coordinator
        map.mapType = .standard
        map.showsCompass = false
        map.showsScale = false
        map.showsUserLocation = false
        map.pointOfInterestFilter = .excludingAll
        map.isRotateEnabled = true
        map.isPitchEnabled = true
        let tiles = MXOpenStreetMapTiles(urlTemplate: "https://tile.openstreetmap.org/{z}/{x}/{y}.png")
        tiles.canReplaceMapContent = true
        tiles.minimumZ = 1
        tiles.maximumZ = 19
        map.addOverlay(tiles, level: .aboveLabels)

        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        tap.cancelsTouchesInView = false
        tap.delegate = context.coordinator
        map.addGestureRecognizer(tap)

        if let camera = cameraMemory.lastCamera ?? position.camera {
            context.coordinator.apply(camera, to: map)
        } else if let region = position.region {
            context.coordinator.apply(region, to: map)
        } else if let coordinate = simulated ?? pin {
            context.coordinator.apply(
                MKCoordinateRegion(center: coordinate, latitudinalMeters: 4500, longitudinalMeters: 4500),
                to: map
            )
        }
        context.coordinator.updateAnnotations(on: map, pin: pin, simulated: simulated)
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.updateAnnotations(on: map, pin: pin, simulated: simulated)
        // While the user is dragging/pinching, do not overwrite their camera
        // because another SwiftUI state (pin/search/status) re-rendered the view.
        guard !context.coordinator.isUserMoving else { return }

        if let requested = position.camera {
            if context.coordinator.needsCameraChange(map, to: requested) {
                context.coordinator.apply(requested, to: map)
            }
        } else if let requested = position.region,
                  context.coordinator.needsRegionChange(map, to: requested) {
            context.coordinator.apply(requested, to: map)
        }
    }

    final class Coordinator: NSObject, MKMapViewDelegate, UIGestureRecognizerDelegate {
        var parent: MXOpenStreetMapView
        var isApplying = false
        var isUserMoving = false
        private let selectedAnnotation = MKPointAnnotation()
        private let activeAnnotation = MKPointAnnotation()
        private var lastPin: CLLocationCoordinate2D?
        private var lastActive: CLLocationCoordinate2D?

        init(_ parent: MXOpenStreetMapView) {
            self.parent = parent
            super.init()
            selectedAnnotation.title = "Selected Location"
            activeAnnotation.title = "Active"
        }

        private func same(_ a: CLLocationCoordinate2D?, _ b: CLLocationCoordinate2D?) -> Bool {
            if a == nil && b == nil { return true }
            guard let a, let b else { return false }
            return abs(a.latitude - b.latitude) < 0.0000001 &&
                abs(a.longitude - b.longitude) < 0.0000001
        }

        func updateAnnotations(on map: MKMapView, pin: CLLocationCoordinate2D?, simulated: CLLocationCoordinate2D?) {
            if !same(lastPin, pin) {
                map.removeAnnotation(selectedAnnotation)
                lastPin = pin
                if let pin, CLLocationCoordinate2DIsValid(pin) {
                    selectedAnnotation.coordinate = pin
                    map.addAnnotation(selectedAnnotation)
                }
            }
            if !same(lastActive, simulated) {
                map.removeAnnotation(activeAnnotation)
                lastActive = simulated
                if let simulated, CLLocationCoordinate2DIsValid(simulated) {
                    activeAnnotation.coordinate = simulated
                    map.addAnnotation(activeAnnotation)
                }
            }
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            if annotation === selectedAnnotation {
                let v = MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: "mx-selected")
                v.markerTintColor = .systemPurple
                v.glyphImage = UIImage(systemName: "mappin")
                v.canShowCallout = false
                return v
            }
            if annotation === activeAnnotation {
                let v = MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: "mx-active")
                v.markerTintColor = .systemRed
                v.glyphImage = UIImage(systemName: "location.fill")
                v.canShowCallout = false
                return v
            }
            return nil
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let tiles = overlay as? MKTileOverlay {
                return MKTileOverlayRenderer(tileOverlay: tiles)
            }
            return MKOverlayRenderer(overlay: overlay)
        }

        func mapView(_ mapView: MKMapView, regionWillChangeAnimated animated: Bool) {
            if !isApplying { isUserMoving = true }
        }

        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
            guard !isApplying else { return }
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
            parent.position = .camera(snapshot)
        }

        func needsCameraChange(_ map: MKMapView, to desired: MapCamera) -> Bool {
            let current = map.camera
            let desiredCenter = desired.centerCoordinate
            let delta = abs(current.centerCoordinate.latitude - desiredCenter.latitude) +
                abs(current.centerCoordinate.longitude - desiredCenter.longitude)
            return delta > 0.00001 ||
                abs(current.centerCoordinateDistance - desired.distance) > max(15, desired.distance * 0.015) ||
                abs(current.heading - desired.heading) > 0.8 ||
                abs(current.pitch - desired.pitch) > 0.8
        }

        func needsRegionChange(_ map: MKMapView, to desired: MKCoordinateRegion) -> Bool {
            let current = map.region
            return abs(current.center.latitude - desired.center.latitude) > 0.00001 ||
                abs(current.center.longitude - desired.center.longitude) > 0.00001 ||
                abs(current.span.latitudeDelta - desired.span.latitudeDelta) > max(0.0001, desired.span.latitudeDelta * 0.02)
        }

        func apply(_ snapshot: MapCamera, to map: MKMapView) {
            isApplying = true
            let camera = MKMapCamera(
                lookingAtCenter: snapshot.centerCoordinate,
                fromDistance: max(snapshot.distance, 10),
                pitch: snapshot.pitch,
                heading: snapshot.heading
            )
            map.setCamera(camera, animated: false)
            isApplying = false
        }

        func apply(_ region: MKCoordinateRegion, to map: MKMapView) {
            isApplying = true
            map.setRegion(region, animated: false)
            isApplying = false
        }

        @objc func handleTap(_ recognizer: UITapGestureRecognizer) {
            guard recognizer.state == .ended,
                  let map = recognizer.view as? MKMapView else { return }
            let point = recognizer.location(in: map)
            let coordinate = map.convert(point, toCoordinateFrom: map)
            guard CLLocationCoordinate2DIsValid(coordinate) else { return }
            parent.onTap(coordinate)
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            true
        }
    }
}

/// The tile.openstreetmap.org policy requires an identifiable user-agent,
/// standard HTTP caching, and visible © OpenStreetMap contributors attribution.
/// No bulk downloads or prefetch of surrounding tiles.
final class MXOpenStreetMapTiles: MKTileOverlay {
    private static let tileSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.urlCache = URLCache(memoryCapacity: 12 * 1024 * 1024, diskCapacity: 80 * 1024 * 1024)
        config.requestCachePolicy = .useProtocolCachePolicy
        config.httpAdditionalHeaders = [
            "User-Agent": "MXLocationPro/4.27 (+https://github.com/mazenmix/MXLocation-SelfRefresh)"
        ]
        return URLSession(configuration: config)
    }()

    override func loadTile(at path: MKTileOverlayPath,
                           result: @escaping (Data?, (any Error)?) -> Void) {
        let url = url(forTilePath: path)
        var request = URLRequest(url: url)
        request.cachePolicy = .useProtocolCachePolicy
        Self.tileSession.dataTask(with: request) { data, response, error in
            if let response = response as? HTTPURLResponse, response.statusCode != 200 {
                result(nil, URLError(.badServerResponse))
            } else {
                result(data, error)
            }
        }.resume()
    }
}
