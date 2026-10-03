import CoreLocation
import MapKit
import SwiftUI
import UIKit

struct MapHomeView: View {
    @EnvironmentObject private var session: SpoofSession
    @EnvironmentObject private var pairing: PairingStore

    @StateObject private var search = MXGlobalPlaceSearch()
    @State private var position: MapCameraPosition = .userLocation(fallback: .automatic)
    @State private var searchText = ""
    @FocusState private var searchFocused: Bool
    @State private var pinName = "Selected Location"
    @State private var pinSubtitle = ""
    @State private var resolvingPin = false
    @State private var suppressNextMapTap = false

    private let accent = Color(red: 0.18, green: 0.55, blue: 1.0)

    var body: some View {
        ZStack {
            MapReader { proxy in
                Map(position: $position) {
                    UserAnnotation()

                    if let pin = session.pin {
                        Annotation("", coordinate: pin, anchor: .bottom) {
                            VStack(spacing: 3) {
                                ZStack {
                                    Circle()
                                        .fill(accent.opacity(0.24))
                                        .frame(width: 46, height: 46)
                                    Image(systemName: "mappin.circle.fill")
                                        .font(.system(size: 34, weight: .semibold))
                                        .symbolRenderingMode(.palette)
                                        .foregroundStyle(.white, accent)
                                }
                                Circle()
                                    .fill(Color.black.opacity(0.35))
                                    .frame(width: 7, height: 4)
                            }
                        }
                    }

                    if let simulated = session.simulated {
                        Annotation("Active", coordinate: simulated) {
                            ZStack {
                                Circle()
                                    .fill(accent.opacity(0.22))
                                    .frame(width: 42, height: 42)
                                Circle()
                                    .fill(accent)
                                    .frame(width: 14, height: 14)
                                    .overlay(Circle().stroke(Color.white, lineWidth: 2))
                            }
                        }
                    }
                }
                .mapStyle(.standard(elevation: .realistic))
                .mapControlVisibility(.hidden)
                .onTapGesture { point in
                    searchFocused = false
                    guard !suppressNextMapTap,
                          let coordinate = proxy.convert(point, from: .local) else { return }
                    choosePin(coordinate, name: nil, subtitle: nil, zoom: false)
                }
            }
            .background(Color.black.ignoresSafeArea())

            VStack(spacing: 10) {
                searchBar

                if searchFocused && !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    searchResults
                }

                Spacer(minLength: 0)

                HStack {
                    Spacer()
                    locateButton
                }

                if let pin = session.pin {
                    selectedLocationCard(pin)
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 10)
            .padding(.bottom, 10)
        }
        .onAppear {
            session.startLocationUpdates()
            if let pin = session.pin {
                resolvePin(pin)
            }
        }
        .onChange(of: session.pin?.latitude) { _, newValue in
            if newValue == nil {
                pinName = "Selected Location"
                pinSubtitle = ""
            }
        }
    }

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.body.weight(.medium))
                .foregroundStyle(.secondary)

            TextField("Search any city or place worldwide", text: $searchText)
                .focused($searchFocused)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled(false)
                .submitLabel(.search)
                .onChange(of: searchText) { _, value in
                    search.query = value
                }
                .onSubmit {
                    runNaturalLanguageSearch()
                }

            if !searchText.isEmpty {
                Button {
                    searchText = ""
                    search.query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 50)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 17, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.28), radius: 16, y: 8)
    }

    @ViewBuilder
    private var searchResults: some View {
        let results = Array(search.results.prefix(7))

        if results.isEmpty {
            HStack(spacing: 10) {
                ProgressView()
                    .controlSize(.small)
                Text("Searching worldwide…")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(14)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
        } else {
            VStack(spacing: 0) {
                ForEach(Array(results.enumerated()), id: \.element) { index, item in
                    Button {
                        select(completion: item)
                    } label: {
                        HStack(spacing: 11) {
                            Image(systemName: "mappin.and.ellipse")
                                .foregroundStyle(accent)
                                .frame(width: 26)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.title)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                                if !item.subtitle.isEmpty {
                                    Text(item.subtitle)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                            }

                            Spacer(minLength: 4)
                        }
                        .padding(.horizontal, 13)
                        .padding(.vertical, 10)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    if index != results.count - 1 {
                        Divider().opacity(0.18)
                    }
                }
            }
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 17, style: .continuous)
                    .stroke(Color.white.opacity(0.07), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.3), radius: 18, y: 8)
        }
    }

    private var locateButton: some View {
        Button {
            searchFocused = false
            centerOnCurrentLocation()
        } label: {
            Image(systemName: "location.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: 48, height: 48)
                .background(.ultraThinMaterial, in: Circle())
                .overlay(Circle().stroke(Color.white.opacity(0.08), lineWidth: 1))
                .shadow(color: Color.black.opacity(0.28), radius: 12, y: 6)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Current location")
    }

    private func selectedLocationCard(_ coordinate: CLLocationCoordinate2D) -> some View {
        VStack(spacing: 12) {
            HStack(alignment: .center, spacing: 11) {
                ZStack {
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .fill(accent.opacity(0.16))
                    Image(systemName: "mappin.circle.fill")
                        .font(.system(size: 25, weight: .semibold))
                        .foregroundStyle(accent)
                }
                .frame(width: 46, height: 46)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(pinName)
                            .font(.headline)
                            .lineLimit(1)
                        if resolvingPin {
                            ProgressView().controlSize(.mini)
                        }
                    }

                    if !pinSubtitle.isEmpty {
                        Text(pinSubtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Text(String(format: "%.5f, %.5f", coordinate.latitude, coordinate.longitude))
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 6)

                Button {
                    let name = pinName == "Selected Location" ? session.suggestedFavoriteName(for: coordinate) : pinName
                    session.addFavorite(name: name, coordinate: coordinate)
                } label: {
                    Image(systemName: isFavorite(coordinate) ? "star.fill" : "star")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(isFavorite(coordinate) ? Color.yellow : Color.secondary)
                        .frame(width: 38, height: 38)
                        .background(Color.white.opacity(0.06), in: Circle())
                }
                .buttonStyle(.plain)

                Button {
                    UIPasteboard.general.string = String(format: "%.6f, %.6f", coordinate.latitude, coordinate.longitude)
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 38, height: 38)
                        .background(Color.white.opacity(0.06), in: Circle())
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 10) {
                if session.isSpoofing {
                    Button {
                        session.stop(pairing: pairing)
                    } label: {
                        Image(systemName: "stop.fill")
                            .font(.body.weight(.bold))
                            .foregroundStyle(.white)
                            .frame(width: 48, height: 48)
                            .background(Color.red.opacity(0.88), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }

                Button {
                    session.teleport(to: coordinate, pairing: pairing)
                } label: {
                    HStack(spacing: 8) {
                        if session.isBusy {
                            ProgressView().tint(.white)
                        } else {
                            Image(systemName: "location.fill")
                        }
                        Text(session.isSpoofing ? "Change Location" : "Set Location")
                    }
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(accent, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(session.isBusy)
            }
        }
        .padding(13)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.34), radius: 22, y: 10)
    }

    private func isFavorite(_ coordinate: CLLocationCoordinate2D) -> Bool {
        session.favorites.contains {
            abs($0.latitude - coordinate.latitude) < 0.00015 &&
            abs($0.longitude - coordinate.longitude) < 0.00015
        }
    }

    private func choosePin(
        _ coordinate: CLLocationCoordinate2D,
        name: String?,
        subtitle: String?,
        zoom: Bool
    ) {
        session.pin = coordinate
        pinName = name?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? name! : "Selected Location"
        pinSubtitle = subtitle ?? ""

        if zoom {
            withAnimation(.easeInOut(duration: 0.3)) {
                position = .region(MKCoordinateRegion(
                    center: coordinate,
                    latitudinalMeters: 1500,
                    longitudinalMeters: 1500
                ))
            }
        }

        if name == nil {
            resolvePin(coordinate)
        }
    }

    private func resolvePin(_ coordinate: CLLocationCoordinate2D) {
        resolvingPin = true
        Task {
            let geocoder = CLGeocoder()
            let marks = try? await geocoder.reverseGeocodeLocation(
                CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
            )
            let mark = marks?.first
            let bestName = mark?.name ?? mark?.locality ?? mark?.administrativeArea ?? "Selected Location"
            let subtitleParts = [mark?.locality, mark?.administrativeArea, mark?.country]
                .compactMap { $0 }
                .filter { !$0.isEmpty && $0 != bestName }
            await MainActor.run {
                pinName = bestName
                pinSubtitle = subtitleParts.joined(separator: ", ")
                resolvingPin = false
            }
        }
    }

    private func select(completion: MKLocalSearchCompletion) {
        searchFocused = false
        Task {
            let request = MKLocalSearch.Request(completion: completion)
            guard let response = try? await MKLocalSearch(request: request).start(),
                  let item = response.mapItems.first else { return }

            let coordinate = item.placemark.coordinate
            let name = item.name ?? completion.title
            let subtitleParts = [
                item.placemark.locality,
                item.placemark.administrativeArea,
                item.placemark.country
            ]
            .compactMap { $0 }
            .filter { !$0.isEmpty && $0 != name }

            await MainActor.run {
                searchText = ""
                search.query = ""
                choosePin(coordinate, name: name, subtitle: subtitleParts.joined(separator: ", "), zoom: true)
                session.pushNamedRecent(name: name, coordinate: coordinate)
            }
        }
    }

    private func runNaturalLanguageSearch() {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }
        searchFocused = false

        Task {
            let request = MKLocalSearch.Request()
            request.naturalLanguageQuery = query
            guard let response = try? await MKLocalSearch(request: request).start(),
                  let item = response.mapItems.first else {
                await MainActor.run {
                    session.lastError = "No place found for \"\(query)\"."
                }
                return
            }

            let coordinate = item.placemark.coordinate
            let name = item.name ?? query
            let subtitleParts = [
                item.placemark.locality,
                item.placemark.administrativeArea,
                item.placemark.country
            ]
            .compactMap { $0 }
            .filter { !$0.isEmpty && $0 != name }

            await MainActor.run {
                searchText = ""
                search.query = ""
                choosePin(coordinate, name: name, subtitle: subtitleParts.joined(separator: ", "), zoom: true)
                session.pushNamedRecent(name: name, coordinate: coordinate)
            }
        }
    }

    private func centerOnCurrentLocation() {
        let meters: CLLocationDistance = 1100
        withAnimation(.easeInOut(duration: 0.35)) {
            if session.isSpoofing, let simulated = session.simulated {
                position = .region(MKCoordinateRegion(
                    center: simulated,
                    latitudinalMeters: meters,
                    longitudinalMeters: meters
                ))
            } else if let real = session.realCoordinate {
                position = .region(MKCoordinateRegion(
                    center: real,
                    latitudinalMeters: meters,
                    longitudinalMeters: meters
                ))
            } else {
                position = .userLocation(followsHeading: false, fallback: .automatic)
            }
        }
    }
}

@MainActor
final class MXGlobalPlaceSearch: NSObject, ObservableObject, MKLocalSearchCompleterDelegate {
    @Published var results: [MKLocalSearchCompletion] = []
    private let completer = MKLocalSearchCompleter()

    var query: String = "" {
        didSet {
            let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
            completer.queryFragment = trimmed
            if trimmed.isEmpty {
                results = []
            }
        }
    }

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = [.address, .pointOfInterest, .query]
    }

    nonisolated func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        let items = completer.results
        Task { @MainActor in
            self.results = items
        }
    }

    nonisolated func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        Task { @MainActor in
            self.results = []
        }
    }
}
