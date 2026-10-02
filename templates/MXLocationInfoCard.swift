import CoreLocation
import SwiftUI
import UIKit

struct MXLocationInfoCard: View {
    @EnvironmentObject private var session: SpoofSession
    @AppStorage("mx.selectedCity") private var selectedCity = "Manila"

    let coordinate: CLLocationCoordinate2D
    let onClose: () -> Void

    @State private var address = "Finding address…"
    @State private var copied = false

    private var coordinateText: String {
        String(format: "%.6f, %.6f", coordinate.latitude, coordinate.longitude)
    }

    private var shareText: String {
        "\(address)\n\(coordinateText)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(address)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(2)
                    Text(coordinateText)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }

            HStack(spacing: 16) {
                Button {
                    UIPasteboard.general.string = coordinateText
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                        copied = false
                    }
                } label: {
                    Label(
                        copied ? "Copied" : "Copy",
                        systemImage: copied ? "checkmark" : "doc.on.doc"
                    )
                }

                ShareLink(item: shareText) {
                    Label("Share", systemImage: "square.and.arrow.up")
                }

                Button {
                    let name = address == "Finding address…" ? coordinateText : address
                    session.addFavorite(name: name, coordinate: coordinate)
                    let id = SavedPlace(
                        name: name,
                        latitude: coordinate.latitude,
                        longitude: coordinate.longitude
                    ).id
                    MXTravelData.setFavoriteMeta(
                        id: id,
                        category: .other,
                        city: selectedCity
                    )
                } label: {
                    Label("Save", systemImage: "star.fill")
                }
            }
            .font(.caption.weight(.semibold))
        }
        .padding(14)
        .locusGlass(
            .regular,
            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
        )
        .task(id: coordinateText) {
            await resolveAddress()
        }
    }

    private func resolveAddress() async {
        let location = CLLocation(
            latitude: coordinate.latitude,
            longitude: coordinate.longitude
        )

        if let place = try? await CLGeocoder().reverseGeocodeLocation(location).first {
            let pieces = [
                place.name,
                place.locality,
                place.administrativeArea,
                place.country
            ]
            .compactMap { $0 }
            .filter { !$0.isEmpty }

            await MainActor.run {
                address = pieces.isEmpty
                    ? coordinateText
                    : pieces.joined(separator: ", ")
            }
        } else {
            await MainActor.run {
                address = coordinateText
            }
        }
    }
}
