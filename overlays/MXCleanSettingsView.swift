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
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let state = activationState(now: context.date)

            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("7-Day Activation")
                            .font(.headline.weight(.bold))
                        Text(state.subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Text(state.remaining)
                        .font(.title3.monospacedDigit().weight(.bold))
                        .foregroundStyle(state.expired ? Color.red : accent)
                }

                ProgressView(value: state.progress)
                    .tint(state.expired ? Color.red : accent)
                    .scaleEffect(x: 1, y: 1.35, anchor: .center)

                HStack {
                    Image(systemName: state.expired ? "exclamationmark.circle.fill" : "checkmark.circle.fill")
                        .foregroundStyle(state.expired ? Color.red : Color.green)
                    Text(state.status)
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.secondary)
                    Spacer()
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

    private func activationState(now: Date) -> ActivationState {
        guard let expiration = certificateExpiration else {
            return ActivationState(
                remaining: "—",
                subtitle: "Waiting for signed profile",
                status: "The 7-day timer appears after SideStore signs the app.",
                progress: 0,
                expired: false
            )
        }

        let remainingSeconds = expiration.timeIntervalSince(now)
        if remainingSeconds <= 0 {
            return ActivationState(
                remaining: "Expired",
                subtitle: "Expired \(formatted(expiration))",
                status: "Open SideStore and refresh MX Location.",
                progress: 0,
                expired: true
            )
        }

        let totalHours = max(0, Int(remainingSeconds / 3600))
        let days = totalHours / 24
        let hours = totalHours % 24
        let sevenDays: TimeInterval = 7 * 24 * 60 * 60
        let progress = min(max(remainingSeconds / sevenDays, 0), 1)

        return ActivationState(
            remaining: "\(days)d \(hours)h",
            subtitle: "Expires \(formatted(expiration))",
            status: "Active — refresh from SideStore before it reaches zero.",
            progress: progress,
            expired: false
        )
    }

    private func formatted(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

private struct ActivationState {
    let remaining: String
    let subtitle: String
    let status: String
    let progress: Double
    let expired: Bool
}
