#!/usr/bin/env python3
"""v4.21 Signing status UI: prevent stale provisioning profiles from emitting false 48h/hourly expiry alerts.

The installed embedded.mobileprovision does not prove current SideStore refresh state.
Keep SideStore responsible for refreshing and notifications; leave location engine unchanged.
"""
from pathlib import Path
import sys
root=Path(sys.argv[1]).resolve()
view=root/"Locus/Features/Settings/SettingsView.swift"
reminder=root/"Locus/Support/MXExpiryReminder.swift"
src=view.read_text(encoding="utf-8")
assert 'Text("SideStore Signing")' in src
assert 'Text("7-Day Activation")' not in src
assert "Reference only. This date may remain unchanged after a successful SideStore refresh." in src
assert 'Open SideStore' in src
assert 'private func openSideStore()' in src
assert 'MXCertificateInfo.expirationDate()' in src
old=reminder.read_text(encoding="utf-8")
assert "enum MXExpiryReminder" in old and "requestPrefix" in old
assert "Your SideStore signing expires soon." in old
safe=String.raw'''import Foundation
import UIKit
import UserNotifications

// Keep the existing notification delegate so tapping any already-delivered MX
// reminder still routes to SideStore.
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
        let identifier = response.notification.request.identifier
        if identifier.hasPrefix(MXExpiryReminder.requestPrefix)
            || identifier == "mx-location-expiry-48-hours" {
            DispatchQueue.main.async {
                if let url = URL(string: "sidestore://") {
                    UIApplication.shared.open(url, options: [:])
                }
            }
        }
        completionHandler()
    }
}

enum MXExpiryReminder {
    static let requestPrefix = "mx-location-expiry-hourly-"

    // The embedded profile is not an authoritative expiry after a SideStore
    // profile-only refresh. Remove old incorrect alerts, do not schedule new
    // expiry warnings until verified signing data is available.
    static func sync(now: Date = Date()) async {
        MXNotificationRouter.configure()
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        let obsoleteIDs = pending.map(\.identifier).filter {
            $0.hasPrefix(requestPrefix) || $0 == "mx-location-expiry-48-hours"
        }
        if !obsoleteIDs.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: obsoleteIDs)
        }
    }
}
'''
reminder.write_text(safe, encoding="utf-8")
assert 'Your SideStore signing expires soon' not in reminder.read_text(encoding="utf-8")
assert "MXExpiryReminder.sync()" in (root/"Locus/Features/Map/RootView.swift").read_text(encoding="utf-8")
print("PASS v4.21: certificate card no longer claims definitive signing status; old false expiry alerts cancelled")
