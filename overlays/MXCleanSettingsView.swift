import SwiftUI
import UIKit

struct SettingsView: View {
    @EnvironmentObject private var session: SpoofSession
    @Environment(\.scenePhase) private var scenePhase

    @State private var certificateExpiration = MXCertificateInfo.expirationDate()
    @AppStorage("mx.signing.userConfirmedRefreshAt") private var userConfirmedRefreshAt: Double = 0
    @AppStorage("mx.signing.pendingReturnAt") private var pendingReturnAt: Double = 0
    @State private var showRefreshConfirmation = false

    // A profile-only SideStore refresh normally does not replace the IPA's
    // embedded.mobileprovision. Never present a locally estimated date as
    // verified proof of signing. SideStore remains the authority.
    private var estimatedExpiration: Date? {
        guard userConfirmedRefreshAt > 0 else { return nil }
        return Date(timeIntervalSince1970: userConfirmedRefreshAt + 7 * 24 * 60 * 60)
    }

    private var displayedExpiration: Date? {
        guard let estimate = estimatedExpiration else { return certificateExpiration }
        guard let embedded = certificateExpiration else { return estimate }
        return max(estimate, embedded)
    }

    private var showingEstimate: Bool {
        guard let estimate = estimatedExpiration else { return false }
        return estimate > (certificateExpiration ?? .distantPast)
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
            updateSigningStatusOnReturn()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                updateSigningStatusOnReturn()
            }
        }
        .confirmationDialog(
            "Did MX Location refresh successfully in SideStore?",
            isPresented: $showRefreshConfirmation,
            titleVisibility: .visible
        ) {
            Button("Yes, refresh succeeded") {
                // An estimate only, because iOS sandbox isolation prevents
                // reading SideStore's refreshed installed provisioning profile.
                userConfirmedRefreshAt = Date().timeIntervalSince1970
                pendingReturnAt = 0
                certificateExpiration = MXCertificateInfo.expirationDate()
            }
            Button("No / Not sure", role: .cancel) {
                pendingReturnAt = 0
            }
        } message: {
            Text("Confirm only after SideStore shows success. This updates an estimated 7-day timer, not the verified signing expiry.")
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
            let totalHours = remaining.map { max(0, min(168, Int(ceil($0 / 3600)))) }
            let progress = min(max((remaining ?? 0) / (7 * 24 * 60 * 60), 0), 1)
            let green = Color(red: 0.28, green: 0.84, blue: 0.45)

            VStack(alignment: .leading, spacing: 15) {
                HStack(alignment: .top, spacing: 8) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("7-Day Activation")
                            .font(.headline.weight(.bold))
                            .foregroundStyle(.white)

                        if let expiration = displayedExpiration {
                            Text("\(showingEstimate ? "Estimated until" : "Profile expires") \(formatted(expiration))")
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
                    Text(showingEstimate
                         ? "Estimated from your confirmed refresh. Verify the actual expiry in SideStore."
                         : "Profile countdown only. Renewal status is verified in SideStore.")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Button {
                    showRefreshConfirmation = true
                } label: {
                    Text("I refreshed in SideStore · Sync timer")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(green)
                }
                .buttonStyle(.plain)
                .accessibilityHint("Confirm a successful SideStore renewal to estimate seven new days")
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
        pendingReturnAt = Date().timeIntervalSince1970
        UIApplication.shared.open(url, options: [:]) { opened in
            if !opened {
                Task { @MainActor in
                    pendingReturnAt = 0
                    session.lastError = "SideStore could not be opened. Make sure SideStore is installed."
                }
            }
        }
    }

    private func updateSigningStatusOnReturn() {
        let previous = certificateExpiration
        let current = MXCertificateInfo.expirationDate()
        certificateExpiration = current

        // If a new signed embedded profile really was installed, trust it.
        if let previous, let current, current.timeIntervalSince(previous) > 60 {
            userConfirmedRefreshAt = 0
            pendingReturnAt = 0
            return
        }

        guard pendingReturnAt > 0 else { return }
        let elapsed = Date().timeIntervalSince1970 - pendingReturnAt
        if elapsed > 3 && elapsed < 2 * 60 * 60 {
            showRefreshConfirmation = true
        } else if elapsed >= 2 * 60 * 60 {
            pendingReturnAt = 0
        }
    }

    private func formatted(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

