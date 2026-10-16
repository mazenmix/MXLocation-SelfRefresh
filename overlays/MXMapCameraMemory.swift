import Foundation
import MapKit
import SwiftUI

/// Maintains the *actual rendered MapKit camera*, not the phone's real GPS position.
/// Owned by RootView so tab switches never recreate camera memory.
@MainActor
final class MXMapCameraMemory: ObservableObject {
    private static let storageKey = "mxlocation.map.lastCamera.v1"
    private(set) var lastCamera: MapCamera?

    init() {
        lastCamera = Self.loadCamera()
    }

    static func initialPosition() -> MapCameraPosition {
        // A previously selected Philippines/Indonesia/etc. viewport must win
        // over the physical iPhone GPS when the Map view is recreated.
        if let camera = loadCamera() {
            return .camera(camera)
        }
        return .userLocation(followsHeading: false, fallback: .automatic)
    }

    var hasCamera: Bool { lastCamera != nil }

    func observe(_ camera: MapCamera) {
        guard Self.isValid(camera) else { return }
        lastCamera = camera
    }

    func save() {
        guard let camera = lastCamera, Self.isValid(camera) else { return }
        UserDefaults.standard.set([
            "latitude": camera.centerCoordinate.latitude,
            "longitude": camera.centerCoordinate.longitude,
            "distance": camera.distance,
            "heading": camera.heading,
            "pitch": camera.pitch
        ], forKey: Self.storageKey)
    }

    func lock(_ position: Binding<MapCameraPosition>) {
        guard let camera = lastCamera else { return }
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            position.wrappedValue = .camera(camera)
        }
        save()
    }

    /// Only for explicit user-requested GPS changes; preserve current zoom and orientation.
    func moveToChosenLocation(_ target: CLLocationCoordinate2D,
                              position: Binding<MapCameraPosition>) {
        guard CLLocationCoordinate2DIsValid(target) else { return }
        let before = lastCamera
        let next = MapCamera(
            centerCoordinate: target,
            distance: before?.distance ?? 2500,
            heading: before?.heading ?? 0,
            pitch: before?.pitch ?? 0
        )
        observe(next)
        lock(position)
    }

    private static func isValid(_ camera: MapCamera) -> Bool {
        let center = camera.centerCoordinate
        return CLLocationCoordinate2DIsValid(center)
            && center.latitude.isFinite
            && center.longitude.isFinite
            && camera.distance.isFinite
            && camera.distance > 0
            && camera.heading.isFinite
            && camera.pitch.isFinite
    }

    private static func loadCamera() -> MapCamera? {
        guard let data = UserDefaults.standard.dictionary(forKey: storageKey),
              let latitude = data["latitude"] as? Double,
              let longitude = data["longitude"] as? Double,
              let distance = data["distance"] as? Double,
              let heading = data["heading"] as? Double,
              let pitch = data["pitch"] as? Double else { return nil }
        let coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        guard CLLocationCoordinate2DIsValid(coordinate),
              distance.isFinite, distance > 0,
              heading.isFinite, pitch.isFinite else { return nil }
        return MapCamera(
            centerCoordinate: coordinate,
            distance: distance,
            heading: heading,
            pitch: pitch
        )
    }
}
