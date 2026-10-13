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

struct MXMapSettingsScreen: View {
    @EnvironmentObject private var choice: MXMapChoiceStore
    @State private var showProviderInfo = false

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
