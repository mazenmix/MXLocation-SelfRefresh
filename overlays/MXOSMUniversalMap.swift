import SwiftUI
import MapKit
import CoreLocation

struct MXUnifiedMarker: Identifiable {
    let id: String
    let name: String
    let coordinate: CLLocationCoordinate2D
    init(id: String, name: String, coordinate: CLLocationCoordinate2D) {
        self.id = id; self.name = name; self.coordinate = coordinate
    }
}

/// One reusable provider-aware map for Places, saved worlds and feature previews.
/// MapKit provides gestures, annotation hit tests, polylines and search-center circles
/// over genuine OSM tiles; Apple Map remains the full native SwiftUI variant.
struct MXOSMUniversalMap: UIViewRepresentable {
    @Binding var camera: MapCameraPosition
    var markers: [MXUnifiedMarker] = []
    var routes: [[CLLocationCoordinate2D]] = []
    var circleCenter: CLLocationCoordinate2D? = nil
    var radiusMeters: Double = 0
    var onRegionChange: ((MKCoordinateRegion) -> Void)? = nil

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView(frame: .zero)
        map.delegate = context.coordinator
        map.overrideUserInterfaceStyle = .light
        map.mapType = .mutedStandard
        map.pointOfInterestFilter = .excludingAll
        map.showsUserLocation = false
        map.showsCompass = false
        map.isPitchEnabled = true
        map.isRotateEnabled = true
        map.isScrollEnabled = true
        map.isZoomEnabled = true
        let tiles = MXOpenStreetMapTiles(urlTemplate: "https://tile.openstreetmap.org/{z}/{x}/{y}.png")
        // Keep cached native map under raster tiles during pinch/zoom, rather
        // than black/blank tiles while a new tile zoom level is loading.
        tiles.canReplaceMapContent = false
        tiles.minimumZ = 1
        tiles.maximumZ = 19
        map.addOverlay(tiles, level: .aboveLabels)
        context.coordinator.updateGraphics(map)
        context.coordinator.applyRequestedCamera(map)
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.updateGraphics(map)
        if !context.coordinator.isUserGesture {
            context.coordinator.applyRequestedCamera(map)
        }
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        var parent: MXOSMUniversalMap
        var isUserGesture = false
        private var isApplying = false
        private var ignoreRegionChange = false
        private var markerFingerprint = ""
        private var routeFingerprint = ""
        private var lastPublished: MapCamera?
        init(_ parent: MXOSMUniversalMap) { self.parent = parent; super.init() }

        func updateGraphics(_ map: MKMapView) {
            let markerID = parent.markers.map { "\($0.id):\($0.coordinate.latitude):\($0.coordinate.longitude)" }.joined(separator: "|")
            if markerID != markerFingerprint {
                markerFingerprint = markerID
                map.removeAnnotations(map.annotations.filter { !($0 is MKUserLocation) })
                let annotations: [MKPointAnnotation] = parent.markers.filter { CLLocationCoordinate2DIsValid($0.coordinate) }.map {
                    let p = MKPointAnnotation()
                    p.title = $0.name; p.coordinate = $0.coordinate
                    return p
                }
                map.addAnnotations(annotations)
            }

            let lineID = parent.routes.map { line in
                line.map { "\($0.latitude),\($0.longitude)" }.joined(separator: ":")
            }.joined(separator: "|")
                + "radius:\(parent.radiusMeters):\(parent.circleCenter?.latitude ?? -999):\(parent.circleCenter?.longitude ?? -999)"
            if lineID != routeFingerprint {
                routeFingerprint = lineID
                map.removeOverlays(map.overlays.filter { !($0 is MKTileOverlay) })
                for line in parent.routes where line.count >= 2 {
                    map.addOverlay(MKPolyline(coordinates: line, count: line.count))
                }
                if let center = parent.circleCenter, CLLocationCoordinate2DIsValid(center),
                   parent.radiusMeters > 0 {
                    map.addOverlay(MKCircle(center: center, radius: parent.radiusMeters))
                }
            }
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            guard !(annotation is MKUserLocation) else { return nil }
            let reuse = "mx-osm-unified-pin"
            let view = (mapView.dequeueReusableAnnotationView(withIdentifier: reuse) as? MKMarkerAnnotationView)
                ?? MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: reuse)
            view.annotation = annotation
            view.markerTintColor = .systemPurple
            view.glyphImage = UIImage(systemName: "mappin")
            view.canShowCallout = true
            return view
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let tiles = overlay as? MKTileOverlay { return MKTileOverlayRenderer(tileOverlay: tiles) }
            if let circle = overlay as? MKCircle {
                let renderer = MKCircleRenderer(circle: circle)
                renderer.strokeColor = UIColor.systemPurple.withAlphaComponent(0.68)
                renderer.fillColor = UIColor.systemPurple.withAlphaComponent(0.08)
                renderer.lineWidth = 1.4
                return renderer
            }
            if let polyline = overlay as? MKPolyline {
                let renderer = MKPolylineRenderer(polyline: polyline)
                renderer.strokeColor = .systemBlue
                renderer.lineWidth = 4
                return renderer
            }
            return MKOverlayRenderer(overlay: overlay)
        }

        func mapView(_ mapView: MKMapView, regionWillChangeAnimated animated: Bool) {
            if !isApplying { isUserGesture = true }
        }
        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
            if isApplying || ignoreRegionChange {
                ignoreRegionChange = false
                isUserGesture = false
                return
            }
            isUserGesture = false
            let mkCamera = mapView.camera
            let observed = MapCamera(centerCoordinate: mkCamera.centerCoordinate,
                                     distance: max(10, mkCamera.centerCoordinateDistance),
                                     heading: mkCamera.heading, pitch: mkCamera.pitch)
            if let prior = lastPublished, approximatelyEqual(prior, observed) { return }
            lastPublished = observed
            parent.camera = .camera(observed)
            parent.onRegionChange?(mapView.region)
        }
        private func approximatelyEqual(_ a: MapCamera, _ b: MapCamera) -> Bool {
            abs(a.centerCoordinate.latitude-b.centerCoordinate.latitude) < 0.00001 &&
            abs(a.centerCoordinate.longitude-b.centerCoordinate.longitude) < 0.00001 &&
            abs(a.distance-b.distance) < max(15, b.distance*0.015) &&
            abs(a.pitch-b.pitch) < 1 &&
            abs(a.heading-b.heading) < 1
        }
        func applyRequestedCamera(_ map: MKMapView) {
            guard let position = parent.camera.camera else {
                if let region = parent.camera.region {
                    let old = map.region
                    if abs(old.center.latitude-region.center.latitude)>0.00005 ||
                        abs(old.center.longitude-region.center.longitude)>0.00005 ||
                        abs(old.span.latitudeDelta-region.span.latitudeDelta)>0.00008 {
                        isApplying = true; ignoreRegionChange = true
                        map.setRegion(region, animated: false)
                        isApplying = false
                    }
                }
                return
            }
            let observed = map.camera
            if abs(observed.centerCoordinate.latitude-position.centerCoordinate.latitude)<0.000015 &&
                abs(observed.centerCoordinate.longitude-position.centerCoordinate.longitude)<0.000015 &&
                abs(observed.centerCoordinateDistance-position.distance)<max(15,position.distance*0.02) &&
                abs(observed.pitch-position.pitch)<1 && abs(observed.heading-position.heading)<1 { return }
            isApplying = true
            ignoreRegionChange = true
            map.setCamera(MKMapCamera(lookingAtCenter: position.centerCoordinate,
                                      fromDistance: max(position.distance, 10),
                                      pitch: position.pitch, heading: position.heading),
                          animated: false)
            isApplying = false
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
                .mapStyle(.standard(elevation: .flat))
            }
        }
        .onAppear { updatePreviewCamera() }
        .onChange(of: center.latitude) { _, _ in updatePreviewCamera() }
        .onChange(of: center.longitude) { _, _ in updatePreviewCamera() }
        .onChange(of: distance) { _, _ in updatePreviewCamera() }
    }
    private func updatePreviewCamera() {
        camera = .region(MKCoordinateRegion(center: center,
                     latitudinalMeters: max(150, distance),
                     longitudinalMeters: max(150, distance)))
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
