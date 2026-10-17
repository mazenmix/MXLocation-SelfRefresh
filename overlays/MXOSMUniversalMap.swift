import SwiftUI
import MapKit
import MapLibre
import CoreLocation
import UIKit

struct MXUnifiedMarker: Identifiable {
    let id: String
    let name: String
    let coordinate: CLLocationCoordinate2D
    init(id: String, name: String, coordinate: CLLocationCoordinate2D) {
        self.id = id
        self.name = name
        self.coordinate = coordinate
    }
}

/// All secondary OSM maps use exactly the same vector MapLibre renderer
/// and Liberty 3D building style as the primary Map screen.
/// User camera gestures are authoritative; never fit/rezoom when updating markers.
struct MXOSMUniversalMap: UIViewRepresentable {
    @Binding var camera: MapCameraPosition
    var markers: [MXUnifiedMarker] = []
    var routes: [[CLLocationCoordinate2D]] = []
    var circleCenter: CLLocationCoordinate2D? = nil
    var radiusMeters: Double = 0
    var onRegionChange: ((MKCoordinateRegion) -> Void)? = nil

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
        context.coordinator.updateGraphics(map)
        context.coordinator.applyRequestedCamera(map)
        return map
    }

    func updateUIView(_ map: MLNMapView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.updateGraphics(map)
        if !context.coordinator.isUserGesture {
            context.coordinator.applyRequestedCamera(map)
        }
    }

    final class Coordinator: NSObject, MLNMapViewDelegate {
        var parent: MXOSMUniversalMap
        var isUserGesture = false
        private var isApplying = false
        private var hasLoadedStyle = false
        private var markerFingerprint = ""
        private var overlayFingerprint = ""
        private var graphics: [MLNAnnotation] = []
        private var lastPublished: MapCamera?
        private var pendingProgrammaticCamera: MapCamera?
        private var requestedAtStartup: MapCamera?
        init(_ parent: MXOSMUniversalMap) {
            self.parent = parent
            super.init()
        }

        func mapView(_ mapView: MLNMapView, didFinishLoading style: MLNStyle) {
            MXVectorOSMStyle.ensure3DBuildings(in: style)
            if let initial = requestedAtStartup {
                setCamera(initial, map: mapView)
            }
            hasLoadedStyle = true
        }

        private func mapCamera(_ camera: MLNMapCamera) -> MapCamera {
            MapCamera(centerCoordinate: camera.centerCoordinate,
                      distance: max(camera.altitude, 10),
                      heading: camera.heading,
                      pitch: camera.pitch)
        }

        private func nearlyEqual(_ a: MapCamera, _ b: MapCamera) -> Bool {
            abs(a.centerCoordinate.latitude - b.centerCoordinate.latitude) < 0.000025 &&
            abs(a.centerCoordinate.longitude - b.centerCoordinate.longitude) < 0.000025 &&
            abs(a.distance - b.distance) < max(30, b.distance * 0.03) &&
            abs(a.pitch - b.pitch) < 1.5 &&
            abs(a.heading - b.heading) < 1.5
        }

        private func setCamera(_ camera: MapCamera, map: MLNMapView) {
            isApplying = true
            pendingProgrammaticCamera = camera
            let target = MLNMapCamera(lookingAtCenter: camera.centerCoordinate,
                       altitude: max(camera.distance, 10),
                       pitch: max(0, min(70, camera.pitch)),
                       heading: camera.heading)
            map.setCamera(target, animated: false)
            isApplying = false
        }

        func applyRequestedCamera(_ map: MLNMapView) {
            var intended: MapCamera?
            if let selected = parent.camera.camera {
                intended = selected
            } else if let region = parent.camera.region {
                let middle = region.center
                let northern = CLLocation(latitude: middle.latitude + region.span.latitudeDelta / 2,
                                          longitude: middle.longitude)
                let distance = max(150, 2 * CLLocation(latitude: middle.latitude,
                                                        longitude: middle.longitude)
                                                        .distance(from: northern))
                intended = MapCamera(centerCoordinate: middle, distance: distance,
                                     heading: 0, pitch: 50)
            }
            guard let intended else { return }
            if !hasLoadedStyle {
                requestedAtStartup = intended
            }
            // Own camera updates are already reflected in the binding.
            // A row refresh, tab switch or new pins must not reset zoom.
            if let last = lastPublished, nearlyEqual(last, intended) { return }
            if nearlyEqual(mapCamera(map.camera), intended) { return }
            setCamera(intended, map: map)
        }

        func updateGraphics(_ map: MLNMapView) {
            let newMarkers = parent.markers.map {
                "\($0.id):\($0.coordinate.latitude):\($0.coordinate.longitude)"
            }.joined(separator: "|")
            let overlayKey = parent.routes.map { line in
                line.map { "\($0.latitude),\($0.longitude)" }.joined(separator: ":")
            }.joined(separator: "|") +
            "radius:\(parent.radiusMeters):\(parent.circleCenter?.latitude ?? -999):\(parent.circleCenter?.longitude ?? -999)"
            guard newMarkers != markerFingerprint || overlayKey != overlayFingerprint else { return }
            markerFingerprint = newMarkers
            overlayFingerprint = overlayKey
            if !graphics.isEmpty { map.removeAnnotations(graphics) }
            graphics = []

            for pin in parent.markers where CLLocationCoordinate2DIsValid(pin.coordinate) {
                let annotation = MLNPointAnnotation()
                annotation.title = pin.name
                annotation.coordinate = pin.coordinate
                graphics.append(annotation)
            }
            for line in parent.routes where line.count >= 2 {
                var points = line.filter { CLLocationCoordinate2DIsValid($0) }
                guard points.count >= 2 else { continue }
                let shape = MLNPolyline(coordinates: &points, count: UInt(points.count))
                shape.title = "MX Route"
                graphics.append(shape)
            }
            if let center = parent.circleCenter,
               CLLocationCoordinate2DIsValid(center), parent.radiusMeters > 0 {
                let earthRadius = 6_378_137.0
                let latRadians = center.latitude * .pi / 180
                var points: [CLLocationCoordinate2D] = []
                for step in 0..<72 {
                    let angle = Double(step) * 2 * .pi / 72
                    let lat = center.latitude + (parent.radiusMeters / earthRadius) *
                              cos(angle) * 180 / .pi
                    let lon = center.longitude + (parent.radiusMeters / earthRadius) *
                              sin(angle) * 180 / .pi / max(0.01, cos(latRadians))
                    points.append(CLLocationCoordinate2D(latitude: lat, longitude: lon))
                }
                let boundary = MLNPolygon(coordinates: &points, count: UInt(points.count))
                boundary.title = "MX Search Area"
                graphics.append(boundary)
            }
            if !graphics.isEmpty { map.addAnnotations(graphics) }
        }

        func mapView(_ mapView: MLNMapView, strokeColorForShapeAnnotation annotation: MLNShape) -> UIColor {
            annotation is MLNPolygon ? UIColor.systemPurple.withAlphaComponent(0.75) :
                UIColor.systemBlue
        }
        func mapView(_ mapView: MLNMapView, fillColorForPolygonAnnotation annotation: MLNPolygon) -> UIColor {
            UIColor.systemPurple.withAlphaComponent(0.08)
        }
        func mapView(_ mapView: MLNMapView, lineWidthForPolylineAnnotation annotation: MLNPolyline) -> CGFloat {
            4
        }
        func mapView(_ mapView: MLNMapView, lineWidthForPolygonAnnotation annotation: MLNPolygon) -> CGFloat {
            1.4
        }

        func mapView(_ mapView: MLNMapView, regionWillChangeAnimated animated: Bool) {
            if !isApplying { isUserGesture = true }
        }
        func mapView(_ mapView: MLNMapView, regionDidChangeAnimated animated: Bool) {
            guard hasLoadedStyle, !isApplying else { return }
            isUserGesture = false
            let snapshot = mapCamera(mapView.camera)
            if let pending = pendingProgrammaticCamera {
                if nearlyEqual(snapshot, pending) {
                    pendingProgrammaticCamera = nil
                } else {
                    setCamera(pending, map: mapView)
                }
                return
            }
            if let previous = lastPublished, nearlyEqual(previous, snapshot) { return }
            lastPublished = snapshot
            parent.camera = .camera(snapshot)
            if let onRegionChange = parent.onRegionChange {
                let bounds = mapView.visibleCoordinateBounds
                let region = MKCoordinateRegion(center: snapshot.centerCoordinate,
                   span: MKCoordinateSpan(
                     latitudeDelta: max(0.000001, abs(bounds.ne.latitude - bounds.sw.latitude)),
                     longitudeDelta: max(0.000001, abs(bounds.ne.longitude - bounds.sw.longitude))))
                onRegionChange(region)
            }
        }
    }
}

struct MXUnifiedMapPreview: View {
    let center: CLLocationCoordinate2D
    var distance: Double = 5000
    var markers: [MXUnifiedMarker] = []
    var routes: [[CLLocationCoordinate2D]] = []
    @AppStorage("mx.map.provider") private var mapProvider = "apple"
    @State private var camera: MapCameraPosition = .automatic

    var body: some View {
        Group {
            if mapProvider == "osm" {
                MXOSMUniversalMap(camera: $camera, markers: markers, routes: routes)
            } else {
                Map(position: $camera) {
                    ForEach(markers) { pin in
                        Marker(pin.name, coordinate: pin.coordinate)
                    }
                    ForEach(routes.indices, id: \.self) { index in
                        MapPolyline(coordinates: routes[index]).stroke(.blue, lineWidth: 4)
                    }
                }
                .mapStyle(.standard(elevation: .realistic))
            }
        }
        .onAppear { updatePreviewCamera() }
        .onChange(of: center.latitude) { _, _ in updatePreviewCamera() }
        .onChange(of: center.longitude) { _, _ in updatePreviewCamera() }
        .onChange(of: distance) { _, _ in updatePreviewCamera() }
        .onChange(of: mapProvider) { _, _ in updatePreviewCamera() }
    }
    private func updatePreviewCamera() {
        // Only change preview camera when its *destination* changes.
        // Never change the active main-map viewport.
        camera = .camera(MapCamera(centerCoordinate: center,
            distance: max(150, distance),
            heading: 0, pitch: mapProvider == "osm" ? 50 : 0))
    }
}

enum MXMapRouteGeometry {
    static func coordinates(_ polyline: MKPolyline) -> [CLLocationCoordinate2D] {
        guard polyline.pointCount > 0 else { return [] }
        var points = [CLLocationCoordinate2D](repeating:
                        CLLocationCoordinate2D(latitude: 0, longitude: 0),
                        count: polyline.pointCount)
        polyline.getCoordinates(&points,
            range: NSRange(location: 0, length: polyline.pointCount))
        return points
    }
    static func center(_ coords: [CLLocationCoordinate2D]) -> CLLocationCoordinate2D {
        guard !coords.isEmpty else { return CLLocationCoordinate2D(latitude: 0, longitude: 0) }
        return CLLocationCoordinate2D(
            latitude: (coords.map(\.latitude).min()! + coords.map(\.latitude).max()!) / 2,
            longitude: (coords.map(\.longitude).min()! + coords.map(\.longitude).max()!) / 2)
    }
    static func spanMeters(_ coords: [CLLocationCoordinate2D]) -> Double {
        guard coords.count >= 2 else { return 5000 }
        let latSpan = (coords.map(\.latitude).max()! - coords.map(\.latitude).min()!) * 111_320
        let lonSpan = (coords.map(\.longitude).max()! - coords.map(\.longitude).min()!) * 111_320
        return max(2000, max(latSpan, lonSpan) * 1.65)
    }
}
