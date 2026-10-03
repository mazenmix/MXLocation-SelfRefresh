from pathlib import Path
import sys

root = Path(sys.argv[1]).resolve()


def replace_required(path: Path, old: str, new: str) -> None:
    text = path.read_text(encoding="utf-8")
    if old not in text:
        raise RuntimeError(f"Required source fragment not found in {path}: {old[:160]!r}")
    path.write_text(text.replace(old, new, 1), encoding="utf-8")


# 1) Long-press directly on the map to move the simulated location there.
map_file = root / "Locus/Features/Map/MapHomeView.swift"
old_map_gesture = '''                .onTapGesture { point in
                    searchFocused = false
                    guard !suppressNextMapTap,
                          let coordinate = proxy.convert(point, from: .local) else { return }
                    choosePin(coordinate, name: nil, subtitle: nil, zoom: false)
                }
'''
new_map_gesture = '''                .onTapGesture { point in
                    searchFocused = false
                    guard !suppressNextMapTap,
                          let coordinate = proxy.convert(point, from: .local) else { return }
                    choosePin(coordinate, name: nil, subtitle: nil, zoom: false)
                }
                .simultaneousGesture(
                    LongPressGesture(minimumDuration: 0.55, maximumDistance: 18)
                        .simultaneously(with: DragGesture(minimumDistance: 0, coordinateSpace: .local))
                        .onEnded { value in
                            guard value.first == true,
                                  let touch = value.second,
                                  let coordinate = proxy.convert(touch.location, from: .local) else { return }

                            suppressNextMapTap = true
                            searchFocused = false
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            choosePin(coordinate, name: nil, subtitle: nil, zoom: false)
                            session.teleport(to: coordinate, pairing: pairing)

                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                                suppressNextMapTap = false
                            }
                        }
                )
'''
replace_required(map_file, old_map_gesture, new_map_gesture)


# 2) Local notification exactly at the 48-hour renewal threshold.
reminder_source = r'''import Foundation
import UserNotifications

enum MXExpiryReminder {
    private static let requestIdentifier = "mx-location-expiry-48-hours"

    static func sync(now: Date = Date()) async {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [requestIdentifier])

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

        let reminderDate = expiration.addingTimeInterval(-(48 * 60 * 60))
        let fireDate = reminderDate > now ? reminderDate : now.addingTimeInterval(5)
        let interval = max(5, fireDate.timeIntervalSince(now))

        let content = UNMutableNotificationContent()
        content.title = "MX Location"
        content.body = "Your 7-day signing expires within 48 hours. Open SideStore and refresh MX Location."
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        let request = UNNotificationRequest(
            identifier: requestIdentifier,
            content: content,
            trigger: trigger
        )
        try? await center.add(request)
    }
}
'''
(root / "Locus/Support/MXExpiryReminder.swift").write_text(reminder_source, encoding="utf-8")


# Schedule/reschedule on first launch and whenever the app becomes active after a SideStore refresh.
root_file = root / "Locus/Features/Map/RootView.swift"
replace_required(
    root_file,
    '''struct RootView: View {\n    @EnvironmentObject private var session: SpoofSession\n    @State private var selectedTab = 0\n''',
    '''struct RootView: View {\n    @EnvironmentObject private var session: SpoofSession\n    @Environment(\\.scenePhase) private var scenePhase\n    @State private var selectedTab = 0\n'''
)
replace_required(
    root_file,
    '''        .tint(Color(red: 0.18, green: 0.55, blue: 1.0))\n        .preferredColorScheme(.dark)\n        .alert("MX Location", isPresented: Binding(\n''',
    '''        .tint(Color(red: 0.18, green: 0.55, blue: 1.0))\n        .preferredColorScheme(.dark)\n        .task {\n            await MXExpiryReminder.sync()\n        }\n        .onChange(of: scenePhase) { _, phase in\n            if phase == .active {\n                Task {\n                    await MXExpiryReminder.sync()\n                }\n            }\n        }\n        .alert("MX Location", isPresented: Binding(\n'''
)


# 3) Bump build version for this feature set. patch_clean_ui_v123 sets 1.2.5 / 18 first.
project = root / "project.yml"
text = project.read_text(encoding="utf-8")
text = text.replace('MARKETING_VERSION: "1.2.5"', 'MARKETING_VERSION: "1.2.6"')
text = text.replace('CURRENT_PROJECT_VERSION: "18"', 'CURRENT_PROJECT_VERSION: "19"')
project.write_text(text, encoding="utf-8")

print("Applied MX Location v1.2.6: favorite rename, long-press teleport, 48h expiry reminder")
