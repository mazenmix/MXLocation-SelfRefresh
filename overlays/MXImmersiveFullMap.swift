import SwiftUI
import MapKit
import MapLibre
import CoreLocation
import UIKit

// A dedicated native full-screen presentation is necessary: hiding controls
// inside TabView cannot remove iOS 26's floating tab bar. This view appears
// ABOVE TabView, hides the status bar and responds to one background map tap.
struct MXImmersiveFullMapView: View {
    @EnvironmentObject private var navigation: MXPremiumNavigation
    @EnvironmentObject private var choice: MXMapChoiceStore
    @EnvironmentObject private var session: SpoofSession
    @State private var appleCamera: MapCameraPosition = .automatic

    private var initialCenter: CLLocationCoordinate2D {
        let defaults = UserDefaults.standard
        let lat = defaults.double(forKey: "mxFullMapLastLatitude")
        let lon = defaults.double(forKey: "mxFullMapLastLongitude")
        let cached = CLLocationCoordinate2D(latitude: lat, longitude: lon)
        if defaults.object(forKey: "mxFullMapLastLatitude") != nil &&
           defaults.object(forKey: "mxFullMapLastLongitude") != nil &&
           CLLocationCoordinate2DIsValid(cached) {
            return cached
        }
        return session.pin ?? session.simulated ?? session.realCoordinate ??
            CLLocationCoordinate2D(latitude: 14.5995, longitude: 120.9842)
    }

    private func restore() {
        withAnimation(.spring(response: 0.38, dampingFraction: 0.88)) {
            navigation.isImmersiveMap = false
        }
    }

    var body: some View {
        GeometryReader { _ in
            Group {
                if choice.selected == .osm {
                    MXImmersiveOSMMap(
                        initialCenter: initialCenter,
                        selectedPin: session.pin,
                        simulated: session.simulated,
                        onSingleTap: restore
                    )
                    .accessibilityIdentifier("mxImmersiveOSMFullBleed")
                } else {
                    Map(position: $appleCamera) {
                        if let point = session.pin {
                            Marker("Selected", coordinate: point).tint(.red)
                        }
                        if let point = session.simulated {
                            Marker("Simulated", coordinate: point).tint(.purple)
                        }
                    }
                    .mapStyle(.standard(elevation: .realistic))
                    .mapControlVisibility(.hidden)
                    .environment(\.colorScheme, .dark)
                    .onTapGesture { _ in restore() }
                    .accessibilityIdentifier("mxImmersiveAppleFullBleed")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black)
        }
        .ignoresSafeArea(.container, edges: .all)
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
        .onAppear {
            let meters = max(500, UserDefaults.standard.double(forKey: "mxFullMapLastDistance"))
            appleCamera = .region(MKCoordinateRegion(
                center: initialCenter,
                latitudinalMeters: meters > 500 ? meters : 5000,
                longitudinalMeters: meters > 500 ? meters : 5000
            ))
        }
        .accessibilityIdentifier("mxTrueFullscreenMapCover")
    }
}

// Gesture lives inside the MapLibre UIView (not a transparent SwiftUI layer).
// Simultaneous recognition retains pan, rotation and pinch-to-zoom.
struct MXImmersiveOSMMap: UIViewRepresentable {
    let initialCenter: CLLocationCoordinate2D
    let selectedPin: CLLocationCoordinate2D?
    let simulated: CLLocationCoordinate2D?
    let onSingleTap: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onSingleTap: onSingleTap)
    }

    func makeUIView(context: Context) -> MLNMapView {
        let map = MLNMapView(frame: .zero,
            styleURL: URL(string: "https://tiles.openfreemap.org/styles/liberty"))
        map.backgroundColor = UIColor(red: 0.91, green: 0.94, blue: 0.92, alpha: 1)
        map.delegate = context.coordinator
        map.logoView.isHidden = false
        map.attributionButton.isHidden = false
        map.isScrollEnabled = true
        map.isZoomEnabled = true
        map.isRotateEnabled = true

        let zoom = UserDefaults.standard.object(forKey: "mxFullMapLastZoom") == nil
            ? 13.0 : UserDefaults.standard.double(forKey: "mxFullMapLastZoom")
        map.setCenter(initialCenter, zoomLevel: max(2, min(19, zoom)), animated: false)

        let tap = UITapGestureRecognizer(target: context.coordinator,
                                        action: #selector(Coordinator.singleTap(_:)))
        tap.numberOfTapsRequired = 1
        tap.numberOfTouchesRequired = 1
        tap.cancelsTouchesInView = false
        tap.delegate = context.coordinator
        map.addGestureRecognizer(tap)
        context.coordinator.refresh(map, selectedPin: selectedPin, simulated: simulated)
        return map
    }

    func updateUIView(_ map: MLNMapView, context: Context) {
        context.coordinator.onSingleTap = onSingleTap
        context.coordinator.refresh(map, selectedPin: selectedPin, simulated: simulated)
    }

    final class Coordinator: NSObject, MLNMapViewDelegate, UIGestureRecognizerDelegate {
        var onSingleTap: () -> Void
        private var savedPin: MLNPointAnnotation?
        private var savedSim: MLNPointAnnotation?
        private var pinSignature: String = ""
        private var simSignature: String = ""

        init(onSingleTap: @escaping () -> Void) {
            self.onSingleTap = onSingleTap
        }

        @objc func singleTap(_ gesture: UITapGestureRecognizer) {
            guard gesture.state == .ended else { return }
            onSingleTap()
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            true
        }

        func mapView(_ mapView: MLNMapView, regionDidChangeAnimated animated: Bool) {
            UserDefaults.standard.set(mapView.centerCoordinate.latitude, forKey: "mxFullMapLastLatitude")
            UserDefaults.standard.set(mapView.centerCoordinate.longitude, forKey: "mxFullMapLastLongitude")
            UserDefaults.standard.set(mapView.zoomLevel, forKey: "mxFullMapLastZoom")
        }

        func refresh(_ map: MLNMapView, selectedPin: CLLocationCoordinate2D?,
                     simulated: CLLocationCoordinate2D?) {
            let newPin = selectedPin.map { String(format: "%.6f:%.6f", $0.latitude, $0.longitude) } ?? ""
            let newSim = simulated.map { String(format: "%.6f:%.6f", $0.latitude, $0.longitude) } ?? ""
            if pinSignature != newPin {
                if let savedPin { map.removeAnnotation(savedPin) }
                savedPin = selectedPin.map {
                    let annotation = MLNPointAnnotation()
                    annotation.coordinate = $0
                    annotation.title = "Selected"
                    map.addAnnotation(annotation)
                    return annotation
                }
                pinSignature = newPin
            }
            if simSignature != newSim {
                if let savedSim { map.removeAnnotation(savedSim) }
                savedSim = simulated.map {
                    let annotation = MLNPointAnnotation()
                    annotation.coordinate = $0
                    annotation.title = "Simulated"
                    map.addAnnotation(annotation)
                    return annotation
                }
                simSignature = newSim
            }
        }
    }
}
