import SwiftUI
import UIKit

struct SettingsView: View {
    @EnvironmentObject private var session: SpoofSession
    @Environment(\.scenePhase) private var scenePhase

    @State private var certificateExpiration = MXCertificateInfo.expirationDate()

    private let accent = Color(red: 0.18, green: 0.55, blue: 1.0)

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 22) {
                        brandHeader
                        activationCard
                        sideStoreButton

                        Text("MazenmiX")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.top, 18)
                            .padding(.bottom, 26)
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 14)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.large)
        }
        .onAppear {
            certificateExpiration = MXCertificateInfo.expirationDate()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                certificateExpiration = MXCertificateInfo.expirationDate()
            }
        }
    }

    private var brandHeader: some View {
        VStack(spacing: 10) {
            Image("MXIcon")
                .resizable()
                .scaledToFill()
                .frame(width: 88, height: 88)
                .clipShape(RoundedRectangle(cornerRadius: 21, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 21, style: .continuous)
                        .stroke(Color.white.opacity(0.10), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.45), radius: 16, y: 8)

            Text("MX Location")
                .font(.title2.weight(.bold))

            Text("by MazenmiX")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    private var activationCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 9) {
                Image(systemName: "checkmark.shield.fill")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(accent)

                Text("SideStore Signing")
                    .font(.headline.weight(.bold))

                Spacer(minLength: 5)

                Text("Managed by SideStore")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(accent)
            }

            Text("Signing and renewal are controlled by SideStore. MX Location cannot confirm that a refresh succeeded.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let expiration = certificateExpiration {
                Divider().opacity(0.22)
                VStack(alignment: .leading, spacing: 5) {
                    Text("Embedded profile expiration")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(formatted(expiration))
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.white.opacity(0.88))
                    Text("Reference only. This date may remain unchanged after a successful SideStore refresh.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                Text("No readable embedded provisioning profile was found.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text("Verify the active signing status in SideStore → My Apps.")
                .font(.footnote.weight(.medium))
                .foregroundStyle(.white.opacity(0.82))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.white.opacity(0.07))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.white.opacity(0.07), lineWidth: 1)
        )
    }

    private var sideStoreButton: some View {
        Button {
            openSideStore()
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(accent.opacity(0.16))
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 19, weight: .bold))
                        .foregroundStyle(accent)
                }
                .frame(width: 44, height: 44)

                VStack(alignment: .leading, spacing: 3) {
                    Text("Open SideStore")
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text("Open SideStore and refresh MX Location manually.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                }

                Spacer(minLength: 6)

                Image(systemName: "chevron.right")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.tertiary)
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color.white.opacity(0.07))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(Color.white.opacity(0.07), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func openSideStore() {
        guard let url = URL(string: "sidestore://") else { return }
        UIApplication.shared.open(url, options: [:]) { opened in
            if !opened {
                Task { @MainActor in
                    session.lastError = "SideStore could not be opened. Make sure SideStore is installed."
                }
            }
        }
    }

    private func formatted(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

