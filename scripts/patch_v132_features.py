from pathlib import Path
import sys

root = Path(sys.argv[1]).resolve()


def replace_required(path: Path, old: str, new: str, count: int = 1) -> None:
    text = path.read_text(encoding="utf-8")
    if old not in text:
        raise RuntimeError(f"Required source fragment not found in {path}: {old[:240]!r}")
    path.write_text(text.replace(old, new, count), encoding="utf-8")


# -----------------------------------------------------------------------------
# 1) Root shell: replace the wide system TabView with a smaller custom tab bar.
#    Keep the 48-hour reminder resync and global error alert behavior.
# -----------------------------------------------------------------------------
root_view = root / "Locus/Features/Map/RootView.swift"
text = root_view.read_text(encoding="utf-8")
start = text.index("struct RootView: View {")
end = text.index("struct MXSavedView: View {")
new_root = r'''struct RootView: View {
    @EnvironmentObject private var session: SpoofSession
    @Environment(\.scenePhase) private var scenePhase
    @State private var selectedTab = 0

    init() {
        MXNotificationRouter.configure()
    }

    var body: some View {
        ZStack {
            switch selectedTab {
            case 1:
                MXSavedView(selectedTab: $selectedTab)
            case 2:
                SettingsView()
            default:
                MapHomeView()
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 2) {
            compactTabBar
        }
        .preferredColorScheme(.dark)
        .task {
            await MXExpiryReminder.sync()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task {
                    await MXExpiryReminder.sync()
                }
            }
        }
        .alert("MX Location", isPresented: Binding(
            get: { session.lastError != nil },
            set: { if !$0 { session.lastError = nil } }
        )) {
            Button("OK", role: .cancel) {
                session.lastError = nil
            }
        } message: {
            Text(session.lastError ?? "")
        }
    }

    private var compactTabBar: some View {
        HStack(spacing: 0) {
            compactTabButton(title: "Map", systemImage: "map.fill", tag: 0)
            compactTabButton(title: "Saved", systemImage: "star.fill", tag: 1)
            compactTabButton(title: "Settings", systemImage: "gearshape.fill", tag: 2)
        }
        .padding(5)
        .frame(width: 282, height: 54)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().stroke(Color.white.opacity(0.10), lineWidth: 1))
        .shadow(color: Color.black.opacity(0.34), radius: 16, y: 8)
        .padding(.bottom, 2)
    }

    private func compactTabButton(title: String, systemImage: String, tag: Int) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.18)) {
                selectedTab = tag
            }
        } label: {
            VStack(spacing: 2) {
                Image(systemName: systemImage)
                    .font(.system(size: 17, weight: .semibold))
                Text(title)
                    .font(.caption2.weight(.semibold))
            }
            .foregroundStyle(selectedTab == tag ? Color(red: 0.18, green: 0.55, blue: 1.0) : Color.white.opacity(0.88))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                Group {
                    if selectedTab == tag {
                        Capsule().fill(Color.white.opacity(0.08))
                    }
                }
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

'''
root_view.write_text(text[:start] + new_root + text[end:], encoding="utf-8")


# -----------------------------------------------------------------------------
# 2) Saved: Favorites only. Remove Recent selector and make clock quiet white.
# -----------------------------------------------------------------------------
replace_required(
    root_view,
    '''    private var places: [SavedPlace] {\n        segment == 0 ? session.favorites : session.recents\n    }\n''',
    '''    private var places: [SavedPlace] {\n        session.favorites\n    }\n'''
)

replace_required(
    root_view,
    '''                    Picker("Saved places", selection: $segment) {\n                        Text("Favorites").tag(0)\n                        Text("Recent").tag(1)\n                    }\n                    .pickerStyle(.segmented)\n                    .padding(.horizontal, 16)\n\n''',
    ''''''
)

old_clock = '''            HStack(spacing: 4) {\n                Image(systemName: "clock")\n                    .font(.system(size: 10, weight: .semibold))\n                    .foregroundStyle(Color.yellow.opacity(0.78))\n                Text(timeText(for: context.date))\n                    .font(.caption2.monospacedDigit().weight(.bold))\n                    .foregroundStyle(Color.yellow.opacity(0.98))\n                    .shadow(color: Color.yellow.opacity(0.72), radius: 4)\n            }\n            .padding(.horizontal, 8)\n            .frame(height: 27)\n            .background(Color.yellow.opacity(0.045), in: Capsule())\n            .overlay(Capsule().stroke(Color.yellow.opacity(0.13), lineWidth: 1))\n            .shadow(color: Color.yellow.opacity(0.08), radius: 7)\n'''
new_clock = '''            HStack(spacing: 4) {\n                Image(systemName: "clock")\n                    .font(.system(size: 10, weight: .semibold))\n                    .foregroundStyle(Color.white.opacity(0.62))\n                Text(timeText(for: context.date))\n                    .font(.caption2.monospacedDigit().weight(.semibold))\n                    .foregroundStyle(Color.white.opacity(0.96))\n            }\n            .padding(.horizontal, 8)\n            .frame(height: 27)\n            .background(Color.white.opacity(0.045), in: Capsule())\n            .overlay(Capsule().stroke(Color.white.opacity(0.07), lineWidth: 1))\n'''
replace_required(root_view, old_clock, new_clock)


# -----------------------------------------------------------------------------
# 3) Map: compact single-row action bar and softer stateful location indicator.
#    Purple before spoofing, red after location change. Selected glow dot remains.
# -----------------------------------------------------------------------------
map_file = root / "Locus/Features/Map/MapHomeView.swift"
map_text = map_file.read_text(encoding="utf-8")

# Replace the v1.3.1 real-location red marker with a calmer purple marker shown
# only before a spoofed location becomes active.
old_real_marker = '''                    if let realCoordinate = session.realCoordinate {\n                        Annotation("", coordinate: realCoordinate, anchor: .center) {\n                            ZStack {\n                                Circle()\n                                    .fill(Color.red.opacity(0.055))\n                                    .frame(width: 32, height: 32)\n                                Circle()\n                                    .fill(Color.red.opacity(0.12))\n                                    .frame(width: 22, height: 22)\n                                Circle()\n                                    .fill(Color(red: 0.93, green: 0.25, blue: 0.28).opacity(0.28))\n                                    .frame(width: 15, height: 15)\n                                    .blur(radius: 2.2)\n                                Circle()\n                                    .fill(Color(red: 0.93, green: 0.25, blue: 0.28))\n                                    .frame(width: 9, height: 9)\n                                    .overlay(\n                                        Circle()\n                                            .stroke(Color.white.opacity(0.92), lineWidth: 1.4)\n                                    )\n                                    .shadow(\n                                        color: Color(red: 0.93, green: 0.25, blue: 0.28).opacity(0.55),\n                                        radius: 5\n                                    )\n                            }\n                            .accessibilityLabel("My location")\n                        }\n                    }\n'''
new_real_marker = '''                    if !session.isSpoofing, let realCoordinate = session.realCoordinate {\n                        Annotation("", coordinate: realCoordinate, anchor: .center) {\n                            ZStack {\n                                Circle()\n                                    .fill(Color(red: 0.56, green: 0.39, blue: 0.94).opacity(0.08))\n                                    .frame(width: 36, height: 36)\n                                Circle()\n                                    .fill(Color(red: 0.56, green: 0.39, blue: 0.94).opacity(0.18))\n                                    .frame(width: 24, height: 24)\n                                Circle()\n                                    .fill(Color(red: 0.56, green: 0.39, blue: 0.94).opacity(0.32))\n                                    .frame(width: 16, height: 16)\n                                    .blur(radius: 2.2)\n                                Circle()\n                                    .fill(Color(red: 0.56, green: 0.39, blue: 0.94))\n                                    .frame(width: 11, height: 11)\n                                    .overlay(Circle().stroke(Color.white.opacity(0.92), lineWidth: 1.6))\n                                    .shadow(color: Color(red: 0.56, green: 0.39, blue: 0.94).opacity(0.38), radius: 5)\n                            }\n                            .accessibilityLabel("My location")\n                        }\n                    }\n'''
if old_real_marker not in map_text:
    raise RuntimeError("v1.3.1 real-location marker not found")
map_text = map_text.replace(old_real_marker, new_real_marker, 1)

old_active_marker = '''                    if let simulated = session.simulated {\n                        Annotation("Active", coordinate: simulated) {\n                            ZStack {\n                                Circle()\n                                    .fill(accent.opacity(0.22))\n                                    .frame(width: 42, height: 42)\n                                Circle()\n                                    .fill(accent)\n                                    .frame(width: 14, height: 14)\n                                    .overlay(Circle().stroke(Color.white, lineWidth: 2))\n                            }\n                        }\n                    }\n'''
new_active_marker = '''                    if session.isSpoofing, let simulated = session.simulated {\n                        Annotation("Active", coordinate: simulated) {\n                            ZStack {\n                                Circle()\n                                    .fill(Color(red: 0.90, green: 0.24, blue: 0.27).opacity(0.08))\n                                    .frame(width: 38, height: 38)\n                                Circle()\n                                    .fill(Color(red: 0.90, green: 0.24, blue: 0.27).opacity(0.18))\n                                    .frame(width: 25, height: 25)\n                                Circle()\n                                    .fill(Color(red: 0.90, green: 0.24, blue: 0.27).opacity(0.30))\n                                    .frame(width: 17, height: 17)\n                                    .blur(radius: 2.3)\n                                Circle()\n                                    .fill(Color(red: 0.90, green: 0.24, blue: 0.27))\n                                    .frame(width: 12, height: 12)\n                                    .overlay(Circle().stroke(Color.white.opacity(0.94), lineWidth: 1.7))\n                                    .shadow(color: Color(red: 0.90, green: 0.24, blue: 0.27).opacity(0.38), radius: 5)\n                            }\n                        }\n                    }\n'''
if old_active_marker not in map_text:
    raise RuntimeError("active simulated marker not found")
map_text = map_text.replace(old_active_marker, new_active_marker, 1)

# Replace the entire old multi-row selected location card with a 60pt compact bar.
card_start = map_text.index("    private func selectedLocationCard(_ coordinate: CLLocationCoordinate2D) -> some View {")
card_end = map_text.index("    private func isFavorite(_ coordinate: CLLocationCoordinate2D) -> Bool {", card_start)
new_card = r'''    private func selectedLocationCard(_ coordinate: CLLocationCoordinate2D) -> some View {
        HStack(spacing: 7) {
            if session.isSpoofing {
                Button {
                    session.stop(pairing: pairing)
                } label: {
                    Image(systemName: "stop.fill")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 40, height: 44)
                        .background(Color.red.opacity(0.86), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Stop location")
            }

            Button {
                teleportWithUndo(to: coordinate)
            } label: {
                HStack(spacing: 7) {
                    if session.isBusy {
                        ProgressView().tint(.white).controlSize(.small)
                    } else {
                        Image(systemName: "location.fill")
                            .font(.system(size: 14, weight: .bold))
                    }
                    Text("Change Location")
                        .font(.subheadline.weight(.bold))
                        .lineLimit(1)
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(accent, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(session.isBusy)

            Button {
                let name = pinName == "Selected Location" ? session.suggestedFavoriteName(for: coordinate) : pinName
                session.addFavorite(name: name, coordinate: coordinate)
            } label: {
                Image(systemName: isFavorite(coordinate) ? "star.fill" : "star")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(isFavorite(coordinate) ? Color.yellow : Color.white.opacity(0.76))
                    .frame(width: 42, height: 44)
                    .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Favorite")

            Button {
                UIPasteboard.general.string = String(format: "%.6f, %.6f", coordinate.latitude, coordinate.longitude)
                UIImpactFeedbackGenerator(style: .soft).impactOccurred()
            } label: {
                Image(systemName: "doc.on.doc")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.76))
                    .frame(width: 42, height: 44)
                    .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Copy coordinates")
        }
        .padding(7)
        .frame(height: 60)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 19, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 19, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.28), radius: 15, y: 7)
    }

'''
map_text = map_text[:card_start] + new_card + map_text[card_end:]
map_text = map_text.replace("            .padding(.bottom, 10)\n", "            .padding(.bottom, 2)\n", 1)
map_file.write_text(map_text, encoding="utf-8")


# -----------------------------------------------------------------------------
# 4) Settings: remove the top SETTINGS title and duplicate 'by MazenmiX'.
# -----------------------------------------------------------------------------
settings = root / "Locus/Features/Settings/SettingsView.swift"
settings_text = settings.read_text(encoding="utf-8")
settings_text = settings_text.replace(
    '''            .navigationTitle("Settings")\n            .navigationBarTitleDisplayMode(.large)\n''',
    '''            .toolbar(.hidden, for: .navigationBar)\n''',
    1,
)
settings_text = settings_text.replace(
    '''\n            Text("by MazenmiX")\n                .font(.subheadline)\n                .foregroundStyle(.secondary)\n''',
    '''\n''',
    1,
)
settings.write_text(settings_text, encoding="utf-8")


# -----------------------------------------------------------------------------
# 5) 48-hour renewal reminders: every hour until old signing expiry.
#    Tapping any reminder opens SideStore directly. Resync on app activation
#    cancels the old schedule and builds a new one after the user refreshes.
# -----------------------------------------------------------------------------
reminder_source = r'''import Foundation
import UIKit
import UserNotifications

final class MXNotificationRouter: NSObject, UNUserNotificationCenterDelegate {
    static let shared = MXNotificationRouter()

    static func configure() {
        UNUserNotificationCenter.current().delegate = shared
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let request = response.notification.request
        guard request.identifier.hasPrefix(MXExpiryReminder.requestPrefix) else {
            completionHandler()
            return
        }

        DispatchQueue.main.async {
            if let url = URL(string: "sidestore://") {
                UIApplication.shared.open(url, options: [:])
            }
        }
        completionHandler()
    }
}

enum MXExpiryReminder {
    static let requestPrefix = "mx-location-expiry-hourly-"

    static func sync(now: Date = Date()) async {
        MXNotificationRouter.configure()
        let center = UNUserNotificationCenter.current()

        // Remove only MX expiry reminders, preserving any unrelated notifications.
        let pending = await center.pendingNotificationRequests()
        let oldIDs = pending
            .map(\.identifier)
            .filter { $0.hasPrefix(requestPrefix) || $0 == "mx-location-expiry-48-hours" }
        if !oldIDs.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: oldIDs)
        }

        guard let expiration = MXCertificateInfo.expirationDate(), expiration > now else {
            return
        }

        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .notDetermined:
            guard (try? await center.requestAuthorization(options: [.alert, .sound])) == true else {
                return
            }
        case .authorized, .provisional, .ephemeral:
            break
        default:
            return
        }

        let threshold = expiration.addingTimeInterval(-(48 * 60 * 60))
        let firstFire: Date
        if threshold > now {
            firstFire = threshold
        } else {
            let elapsed = max(0, now.timeIntervalSince(threshold))
            let nextHourIndex = floor(elapsed / 3600) + 1
            firstFire = threshold.addingTimeInterval(nextHourIndex * 3600)
        }

        var fireDate = firstFire
        var index = 0
        while fireDate <= expiration && index < 49 {
            let interval = max(5, fireDate.timeIntervalSince(now))

            let content = UNMutableNotificationContent()
            content.title = "MX Location"
            content.body = "Your SideStore signing expires soon. Tap to open SideStore and refresh MX Location."
            content.sound = .default
            content.userInfo = ["mxAction": "openSideStore"]

            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
            let request = UNNotificationRequest(
                identifier: requestPrefix + String(index),
                content: content,
                trigger: trigger
            )
            try? await center.add(request)

            fireDate = fireDate.addingTimeInterval(3600)
            index += 1
        }
    }
}
'''
(root / "Locus/Support/MXExpiryReminder.swift").write_text(reminder_source, encoding="utf-8")


# -----------------------------------------------------------------------------
# 6) Version bump from v1.3.1 / build 24 to v1.3.2 / build 25.
# -----------------------------------------------------------------------------
project = root / "project.yml"
project_text = project.read_text(encoding="utf-8")
project_text = project_text.replace('MARKETING_VERSION: "1.3.1"', 'MARKETING_VERSION: "1.3.2"')
project_text = project_text.replace('CURRENT_PROJECT_VERSION: "24"', 'CURRENT_PROJECT_VERSION: "25"')
project.write_text(project_text, encoding="utf-8")

print("Applied MX Location v1.3.2: compact UI, Favorites-only Saved, white clocks, hourly SideStore reminders, purple/red location state")
