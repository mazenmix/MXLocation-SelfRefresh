import SwiftUI
import UIKit

struct SettingsView: View {
    @EnvironmentObject private var session: SpoofSession
    @EnvironmentObject private var pairing: PairingStore
    @Environment(\.scenePhase) private var scenePhase

    @State private var certificateExpiration = MXCertificateInfo.expirationDate()
    @State private var installedProfileExpiration: Date?
    @State private var checkingInstalledProfile = false

    // A profile-only refresh updates misagent's installed profile, not the
    // embedded profile inside our signed IPA.
    private var displayedExpiration: Date? {
        installedProfileExpiration ?? certificateExpiration
    }
    private var verifiedInstalledProfile: Bool {
        installedProfileExpiration != nil
    }

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
            refreshSigningStatus()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                refreshSigningStatus()
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
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let remaining = displayedExpiration.map { max(0, $0.timeIntervalSince(context.date)) }
            let totalHours = remaining.map { max(0, Int($0 / 3600)) }
            let progress = min(max((remaining ?? 0) / (7 * 24 * 60 * 60), 0), 1)
            let green = Color(red: 0.28, green: 0.84, blue: 0.45)

            VStack(alignment: .leading, spacing: 15) {
                HStack(alignment: .top, spacing: 8) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("7-Day Activation")
                            .font(.headline.weight(.bold))
                            .foregroundStyle(.white)

                        if let expiration = displayedExpiration {
                            Text("\(verifiedInstalledProfile ? "Installed profile expires" : "Embedded profile expires") \(formatted(expiration))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Text("Profile expiration unavailable")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer(minLength: 6)

                    if let totalHours {
                        Text("\(totalHours / 24)d \(totalHours % 24)h")
                            .font(.title3.monospacedDigit().weight(.bold))
                            .foregroundStyle(green)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                    } else {
                        Text("—")
                            .font(.title3.bold())
                            .foregroundStyle(.secondary)
                    }
                }

                ProgressView(value: progress)
                    .tint(green)
                    .scaleEffect(x: 1, y: 1.45, anchor: .center)
                    .accessibilityLabel("Embedded profile time remaining")

                HStack(alignment: .top, spacing: 9) {
                    Image(systemName: "info.circle.fill")
                        .foregroundStyle(green)
                        .font(.system(size: 16))
                    Text(verifiedInstalledProfile
                         ? "Live installed provisioning profile · verified from this device."
                         : (checkingInstalledProfile
                            ? "Checking installed provisioning profile…"
                            : "Embedded profile only. SideStore refresh may have a newer installed expiry."))
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

            }
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
    }

    private var sideStoreButton: some View {
        Button {
            openSideStore()
        } label: {
            Text("Renew Certificate")
                .font(.headline.weight(.bold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 58)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color(red: 0.98, green: 0.48, blue: 0.16))
                )
                .shadow(color: Color.orange.opacity(0.24), radius: 9, y: 3)
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens SideStore to renew the app certificate")
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

    private func refreshSigningStatus() {
        certificateExpiration = MXCertificateInfo.expirationDate()
        guard pairing.hasPairingFile, !checkingInstalledProfile else { return }

        checkingInstalledProfile = true
        let path = pairing.pairingPath
        let ip = TunnelConfig.targetIP
        let bundleID = Bundle.main.bundleIdentifier ?? "com.mazenmix.mxlocationpro"
        Task {
            let observed = await Task.detached(priority: .utility) {
                MXInstalledProvisionReader.installedExpiration(
                    pairingPath: path, deviceIP: ip, bundleID: bundleID
                )
            }.value
            if let observed {
                installedProfileExpiration = observed
            }
            checkingInstalledProfile = false
        }
    }

    private func formatted(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

