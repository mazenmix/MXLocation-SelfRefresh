import SwiftUI
import MapKit
import GoogleMaps
import CoreLocation
import Security
import UIKit

enum MXMapProvider: String, CaseIterable {
    case apple = "Apple"
    case google = "Google"
}

// A single map preference store is shared by Explore and the map canvas.
// The preference persists only if the user enables "Remember my choice".
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
    @Published var showSetup = false
    @Published private(set) var googleReady = false
    @Published var feedback = ""

    init() {
        let remember = UserDefaults.standard.bool(forKey: "mxmap.remember")
        rememberChoice = remember
        let previous = remember ? UserDefaults.standard.string(forKey: "mxmap.preferred") : nil
        selected = MXMapProvider(rawValue: previous ?? "") ?? .apple
        googleReady = MXGoogleAPIKey.read() != nil
        if selected == .google && !googleReady {
            selected = .apple
        }
    }

    func select(_ provider: MXMapProvider) {
        guard provider != .google || googleReady else {
            feedback = "Add a Google Maps iOS API key to enable Google Maps."
            showSetup = true
            return
        }
        withAnimation(.easeInOut(duration: 0.22)) { selected = provider }
        if rememberChoice {
            UserDefaults.standard.set(provider.rawValue, forKey: "mxmap.preferred")
        }
    }

    func configureGoogleKey(_ key: String) {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("AIza"), trimmed.count >= 30 else {
            feedback = "Enter your Google Maps SDK for iOS API key."
            return
        }
        guard MXGoogleAPIKey.save(trimmed) else {
            feedback = "Keychain couldn't save this key."
            return
        }
        googleReady = true
        feedback = "Google Maps is enabled on this device."
        showSetup = false
        select(.google)
    }

    func clearGoogleKey() {
        MXGoogleAPIKey.remove()
        googleReady = false
        if selected == .google { select(.apple) }
        feedback = "Google API key removed from this device."
    }
}

enum MXGoogleAPIKey {
    private static let account = "com.mazenmix.mxlocationpro.googlemaps"
    private static let service = "MXLocationPro.Maps"

    static func read() -> String? {
        let q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let key = String(data: data, encoding: .utf8), !key.isEmpty else {
            return nil
        }
        return key
    }

    static func save(_ key: String) -> Bool {
        remove()
        let q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: Data(key.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        return SecItemAdd(q as CFDictionary, nil) == errSecSuccess
    }

    static func remove() {
        let q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(q as CFDictionary)
    }
}

@MainActor
enum MXGoogleMapsBootstrap {
    private static var didConfigure = false
    static func ensureConfigured() -> Bool {
        if didConfigure { return true }
        guard let key = MXGoogleAPIKey.read() else { return false }
        didConfigure = GMSServices.provideAPIKey(key)
        return didConfigure
    }
}

// Only the rendering engine changes. Teleport/Stop/Pairing/Favorites stay in
// SpoofSession, and tapping either native map chooses the same session.pin.
struct MXGoogleMapCanvas: UIViewRepresentable {
    let selectedPin: CLLocationCoordinate2D?
    let simulated: CLLocationCoordinate2D?
    let realLocation: CLLocationCoordinate2D?
    let onTap: (CLLocationCoordinate2D) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onTap: onTap) }

    func makeUIView(context: Context) -> GMSMapView {
        _ = MXGoogleMapsBootstrap.ensureConfigured()
        let target = selectedPin ?? simulated ?? realLocation ??
            CLLocationCoordinate2D(latitude: 14.5995, longitude: 120.9842)
        let options = GMSMapViewOptions()
        options.camera = GMSCameraPosition(
            latitude: target.latitude, longitude: target.longitude, zoom: 14
        )
        let view = GMSMapView(options: options)
        view.delegate = context.coordinator
        view.mapType = .normal
        view.settings.compassButton = false
        view.settings.myLocationButton = false
        view.padding = UIEdgeInsets(top: 125, left: 0, bottom: 140, right: 0)
        context.coordinator.refresh(view: view, selectedPin: selectedPin, simulated: simulated)
        return view
    }

    func updateUIView(_ view: GMSMapView, context: Context) {
        context.coordinator.onTap = onTap
        context.coordinator.refresh(view: view, selectedPin: selectedPin, simulated: simulated)
    }

    final class Coordinator: NSObject, GMSMapViewDelegate {
        var onTap: (CLLocationCoordinate2D) -> Void
        private var selectedMarker: GMSMarker?
        private var simulatedMarker: GMSMarker?
        private var previousSelected: String?
        private var previousSimulated: String?

        init(onTap: @escaping (CLLocationCoordinate2D) -> Void) {
            self.onTap = onTap
        }

        func mapView(_ mapView: GMSMapView, didTapAt coordinate: CLLocationCoordinate2D) {
            onTap(coordinate)
        }

        func refresh(view: GMSMapView, selectedPin: CLLocationCoordinate2D?,
                     simulated: CLLocationCoordinate2D?) {
            let a = selectedPin.map { String(format: "%.7f:%.7f", $0.latitude, $0.longitude) }
            let b = simulated.map { String(format: "%.7f:%.7f", $0.latitude, $0.longitude) }
            if a != previousSelected {
                selectedMarker?.map = nil
                selectedMarker = selectedPin.map { point in
                    let marker = GMSMarker(position: point)
                    marker.title = "Selected location"
                    marker.icon = GMSMarker.markerImage(with: UIColor.systemBlue)
                    marker.map = view
                    return marker
                }
                if let point = selectedPin {
                    view.animate(toLocation: point)
                }
                previousSelected = a
            }
            if b != previousSimulated {
                simulatedMarker?.map = nil
                simulatedMarker = simulated.map { point in
                    let marker = GMSMarker(position: point)
                    marker.title = "GPS Active"
                    marker.icon = GMSMarker.markerImage(with: UIColor.systemRed)
                    marker.map = view
                    return marker
                }
                previousSimulated = b
            }
        }
    }
}

// Compact map-provider switch, paired with a separate opt-in save setting.
struct MXMapProviderPicker: View {
    @EnvironmentObject private var mapChoice: MXMapChoiceStore
    var body: some View {
        HStack(spacing: 0) {
            ForEach(MXMapProvider.allCases, id: \.rawValue) { provider in
                Button {
                    mapChoice.select(provider)
                } label: {
                    Text(provider.rawValue)
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(mapChoice.selected == provider ? .white : .white.opacity(0.7))
                        .padding(.horizontal, 13)
                        .frame(height: 34)
                        .background(mapChoice.selected == provider ?
                                    MXPremiumStyle.cyan.opacity(0.64) : .clear,
                                    in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("mxMapProvider_" + provider.rawValue)
            }
            Button {
                mapChoice.showSetup = true
            } label: {
                Image(systemName: "gearshape")
                    .font(.caption2.weight(.bold))
                    .frame(width: 32, height: 32)
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Map provider preferences")
        }
        .padding(3)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().stroke(.white.opacity(0.12)))
        .accessibilityIdentifier("mxMapProviderSwitch")
    }
}

struct MXGoogleMapSetupSheet: View {
    @EnvironmentObject private var mapChoice: MXMapChoiceStore
    @Environment(\.dismiss) private var dismiss
    @State private var apiKey = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Map provider") {
                    Picker("Default on next launch", selection: Binding(
                        get: { mapChoice.selected },
                        set: { mapChoice.select($0) }
                    )) {
                        Text("Apple Maps").tag(MXMapProvider.apple)
                        Text("Google Maps").tag(MXMapProvider.google)
                    }
                    Toggle("Remember my choice", isOn: $mapChoice.rememberChoice)
                    Text("If off, Apple Maps opens by default next launch.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("Google Maps SDK for iOS") {
                    if mapChoice.googleReady {
                        Label("Google API key stored in device Keychain", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }
                    SecureField("Paste your Google Maps API key", text: $apiKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button("Save Google API key") {
                        mapChoice.configureGoogleKey(apiKey)
                        if mapChoice.googleReady { dismiss() }
                    }
                    .disabled(apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    if mapChoice.googleReady {
                        Button("Remove Google API key", role: .destructive) {
                            mapChoice.clearGoogleKey()
                        }
                    }
                    Text("Enable Maps SDK for iOS and billing in Google Cloud. Restrict this key to iOS bundle com.mazenmix.mxlocationpro and Maps SDK for iOS.")
                        .font(.caption).foregroundStyle(.secondary)
                    Text("Apple Maps remains available without any Google key.")
                        .font(.caption).foregroundStyle(.secondary)
                    if !mapChoice.feedback.isEmpty {
                        Text(mapChoice.feedback).font(.caption)
                    }
                }
            }
            .navigationTitle("Map Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
