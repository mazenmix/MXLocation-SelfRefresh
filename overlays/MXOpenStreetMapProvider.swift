import SwiftUI
import MapLibre
import MapKit
import CoreLocation
import UIKit

// Two actual map providers, not three:
// Apple uses MapKit; OpenStreetMap data is drawn by the MapLibre renderer.
// OpenFreeMap supplies vector tiles/styles without a Google key or billing.
enum MXMapProvider: String, CaseIterable, Identifiable {
    case apple = "Apple Maps"
    case osm = "OpenStreetMap"

    var id: String { rawValue }
}

@MainActor
final class MXMapChoiceStore: ObservableObject {
    @Published private(set) var selected: MXMapProvider
    @Published var rememberChoice: Bool {
        didSet {
            UserDefaults.standard.set(rememberChoice, forKey: "mxmap.remember")
            if rememberChoice {
                UserDefaults.standard.set(selected.rawValue, forKey: "mxmap.preferred")
            } else {
                UserDefaults.standard.removeObject(forKey: "mxmap.preferred")
            }
        }
    }

    init() {
        let remembered = UserDefaults.standard.bool(forKey: "mxmap.remember")
        rememberChoice = remembered
        let rawValue = remembered ? UserDefaults.standard.string(forKey: "mxmap.preferred") : nil
        selected = MXMapProvider(rawValue: rawValue ?? "") ?? .apple
    }

    func choose(_ provider: MXMapProvider) {
        withAnimation(.easeInOut(duration: 0.22)) {
            selected = provider
        }
        if rememberChoice {
            UserDefaults.standard.set(provider.rawValue, forKey: "mxmap.preferred")
        }
    }
}

// Native OpenStreetMap rendering. Its position is driven by SpoofSession, so
// selecting either map doesn't reset pairing, favorites or simulated GPS.
struct MXOpenStreetMapCanvas: UIViewRepresentable {
    let selectedPin: CLLocationCoordinate2D?
    let simulated: CLLocationCoordinate2D?
    let realLocation: CLLocationCoordinate2D?
    let onTap: (CLLocationCoordinate2D) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onTap: onTap) }

    func makeUIView(context: Context) -> MLNMapView {
        // OpenFreeMap Liberty is a colorful daytime-style map, independent of the app's dark UI.
        let style = URL(string: "https://tiles.openfreemap.org/styles/liberty")
        let map = MLNMapView(frame: .zero, styleURL: style)
        map.delegate = context.coordinator
        map.logoView.isHidden = false
        map.attributionButton.isHidden = false
        let target = selectedPin ?? simulated ?? realLocation ??
            CLLocationCoordinate2D(latitude: 14.5995, longitude: 120.9842)
        map.setCenter(target, zoomLevel: 14, animated: false)
        context.coordinator.refresh(map, pin: selectedPin, active: simulated)
        return map
    }

    func updateUIView(_ map: MLNMapView, context: Context) {
        context.coordinator.onTap = onTap
        context.coordinator.refresh(map, pin: selectedPin, active: simulated)
    }

    final class Coordinator: NSObject, MLNMapViewDelegate {
        var onTap: (CLLocationCoordinate2D) -> Void
        private var selectedAnnotation: MLNPointAnnotation?
        private var activeAnnotation: MLNPointAnnotation?
        private var previousPin: String?
        private var previousActive: String?

        init(onTap: @escaping (CLLocationCoordinate2D) -> Void) {
            self.onTap = onTap
        }

        func mapView(_ mapView: MLNMapView, didTapAt coordinate: CLLocationCoordinate2D) {
            onTap(coordinate)
        }

        func refresh(_ map: MLNMapView, pin: CLLocationCoordinate2D?,
                     active: CLLocationCoordinate2D?) {
            let pinKey = pin.map { String(format: "%.7f:%.7f", $0.latitude, $0.longitude) }
            let activeKey = active.map { String(format: "%.7f:%.7f", $0.latitude, $0.longitude) }
            if pinKey != previousPin {
                if let old = selectedAnnotation { map.removeAnnotation(old) }
                selectedAnnotation = pin.map {
                    let marker = MLNPointAnnotation()
                    marker.coordinate = $0
                    marker.title = "Selected place"
                    map.addAnnotation(marker)
                    return marker
                }
                if let pin { map.setCenter(pin, animated: true) }
                previousPin = pinKey
            }
            if activeKey != previousActive {
                if let old = activeAnnotation { map.removeAnnotation(old) }
                activeAnnotation = active.map {
                    let marker = MLNPointAnnotation()
                    marker.coordinate = $0
                    marker.title = "GPS Active"
                    map.addAnnotation(marker)
                    return marker
                }
                previousActive = activeKey
            }
        }
    }
}

// One rendering engine for *every* venue category: 18+, Date Spots,
// After Dark, Social Radar, cafés, stays and more. Venue discovery remains
// Apple MKLocalSearch, while selected map tiles follow the user's preference.
struct MXOpenStreetVenueMapCanvas: UIViewRepresentable {
    let center: CLLocationCoordinate2D?
    let venues: [MKMapItem]
    let focusedVenue: CLLocationCoordinate2D?
    let onSelectVenue: (MKMapItem) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onSelectVenue: onSelectVenue)
    }

    func makeUIView(context: Context) -> MLNMapView {
        let map = MLNMapView(
            frame: .zero,
            styleURL: URL(string: "https://tiles.openfreemap.org/styles/liberty")
        )
        map.backgroundColor = UIColor(red: 0.91, green: 0.94, blue: 0.92, alpha: 1)
        map.delegate = context.coordinator
        map.logoView.isHidden = false
        map.attributionButton.isHidden = false
        map.isRotateEnabled = true
        let initial = center ?? CLLocationCoordinate2D(latitude: 14.5995, longitude: 120.9842)
        map.setCenter(initial, zoomLevel: 12.8, animated: false)
        context.coordinator.refresh(map, center: center, venues: venues, focused: focusedVenue)
        return map
    }

    func updateUIView(_ map: MLNMapView, context: Context) {
        context.coordinator.onSelectVenue = onSelectVenue
        context.coordinator.refresh(map, center: center, venues: venues, focused: focusedVenue)
    }

    final class Coordinator: NSObject, MLNMapViewDelegate {
        var onSelectVenue: (MKMapItem) -> Void
        private var markers: [MLNPointAnnotation] = []
        private var mappedItems: [MKMapItem] = []
        private var markerSignature = ""
        private var centerSignature = ""
        private var focusSignature = ""

        init(onSelectVenue: @escaping (MKMapItem) -> Void) {
            self.onSelectVenue = onSelectVenue
        }

        func mapView(_ mapView: MLNMapView, didSelect annotation: MLNAnnotation) {
            guard let selected = annotation as? MLNPointAnnotation,
                  let index = markers.firstIndex(where: { $0 === selected }),
                  mappedItems.indices.contains(index) else { return }
            onSelectVenue(mappedItems[index])
        }

        func refresh(_ map: MLNMapView,
                     center: CLLocationCoordinate2D?,
                     venues: [MKMapItem],
                     focused: CLLocationCoordinate2D?) {
            let signature = venues.map { item in
                let c = item.placemark.coordinate
                return "\(item.name ?? "Venue"):\(c.latitude):\(c.longitude)"
            }.joined(separator: ";")
            if signature != markerSignature {
                if !markers.isEmpty {
                    map.removeAnnotations(markers)
                }
                mappedItems = venues
                markers = venues.map { item in
                    let pin = MLNPointAnnotation()
                    pin.coordinate = item.placemark.coordinate
                    pin.title = item.name ?? "Place"
                    pin.subtitle = item.placemark.title
                    return pin
                }
                if !markers.isEmpty { map.addAnnotations(markers) }
                markerSignature = signature
            }

            let newCenter = center.map {
                String(format: "%.6f:%.6f", $0.latitude, $0.longitude)
            } ?? ""
            if !newCenter.isEmpty && newCenter != centerSignature {
                if let center {
                    map.setCenter(center, zoomLevel: 12.8, animated: false)
                }
                centerSignature = newCenter
            }

            let newFocus = focused.map {
                String(format: "%.6f:%.6f", $0.latitude, $0.longitude)
            } ?? ""
            if !newFocus.isEmpty && newFocus != focusSignature {
                if let focused {
                    map.setCenter(focused, zoomLevel: 15.2, animated: true)
                }
                focusSignature = newFocus
            }
        }
    }
}

struct MXMapSettingsScreen: View {
    @EnvironmentObject private var choice: MXMapChoiceStore
    @State private var showProviderInfo = false
    @AppStorage("mx_places_photo_api_key") private var placesPhotoAPIKey = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 12) {
                        Image(systemName: "map.fill")
                            .font(.title2)
                            .foregroundStyle(MXPremiumStyle.cyan)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Map Engine").font(.headline)
                            Text("Choose your default map appearance")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Picker("Map", selection: Binding(
                        get: { choice.selected },
                        set: { choice.choose($0) }
                    )) {
                        Text("Apple Maps").tag(MXMapProvider.apple)
                        Text("OpenStreetMap").tag(MXMapProvider.osm)
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("mxMapProviderSettingsPicker")

                    Toggle("Remember my choice", isOn: $choice.rememberChoice)
                        .accessibilityIdentifier("mxRememberMapChoice")

                    Text("Changes take effect on Explore when you return. If remembering is off, Apple Maps opens on the next launch.")
                        .font(.caption).foregroundStyle(.secondary)
                } header: {
                    Text("Maps")
                }

                Section("Free OpenStreetMap") {
                    Label("Rendered by MapLibre", systemImage: "map")
                    Label("Tiles provided by OpenFreeMap", systemImage: "network")
                    Label("No Google Cloud, card or API key", systemImage: "checkmark.shield")
                    Text("OpenFreeMap is an external online tile provider. An internet connection is needed for uncached areas.")
                        .font(.caption).foregroundStyle(.secondary)
                    Link(destination: URL(string: "https://openfreemap.org")!) {
                        Label("Map data and attribution information", systemImage: "info.circle")
                    }
                }

                Section("Real business photos (optional)") {
                    SecureField("Google Places API key", text: $placesPhotoAPIKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("mxGooglePlacesPhotosKey")
                    Label(placesPhotoAPIKey.isEmpty ? "Google venue photos not enabled" : "Google venue photos enabled",
                          systemImage: placesPhotoAPIKey.isEmpty ? "photo" : "photo.fill")
                    Text("Uses Places API (New) to display photos of matched businesses. Google Cloud billing is required. Searches and photo requests may incur charges. No key is included in the IPA. When unavailable, you can still open the venue in Google Maps.")
                        .font(.caption).foregroundStyle(.secondary)
                    Link("Set up Google Places API ↗", destination: URL(string: "https://console.cloud.google.com/apis/library/places-backend.googleapis.com")!)
                }

                Section("Original Location Controls") {
                    NavigationLink {
                        SettingsView()
                    } label: {
                        Label("GPS, Pairing & Advanced Settings", systemImage: "gearshape.2")
                    }
                    Text("Favorites, GPS simulation, saved coordinates and pairing stay unchanged whichever map you select.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .scrollContentBackground(.hidden)
            .background(MXPremiumStyle.background)
            .navigationTitle("Settings")
        }
    }
}
