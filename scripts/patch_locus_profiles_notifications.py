from pathlib import Path
import sys

root = Path(sys.argv[1]).resolve()


def replace_required(path: Path, old: str, new: str, count: int = 1) -> None:
    text = path.read_text(encoding="utf-8")
    if old not in text:
        raise RuntimeError(f"Required source fragment not found in {path}: {old[:120]!r}")
    path.write_text(text.replace(old, new, count), encoding="utf-8")


def replace_block(path: Path, start: str, end: str, replacement: str) -> None:
    text = path.read_text(encoding="utf-8")
    start_index = text.find(start)
    if start_index < 0:
        raise RuntimeError(f"Start marker not found in {path}: {start!r}")
    end_index = text.find(end, start_index)
    if end_index < 0:
        raise RuntimeError(f"End marker not found in {path}: {end!r}")
    text = text[:start_index] + replacement + text[end_index:]
    path.write_text(text, encoding="utf-8")


# Version bump for this feature build.
project = root / "project.yml"
replace_required(project, 'MARKETING_VERSION: "1.0.2"', 'MARKETING_VERSION: "1.0.3"')

# 1) Certificate countdown: refresh immediately and show a live countdown.
renewal = root / "Locus/Support/MXCertificateRenewal.swift"
replace_required(
    renewal,
    '''    static func remainingText(until expiration: Date?, now: Date = Date()) -> String {
        guard let expiration else { return "Unavailable" }
        let remaining = expiration.timeIntervalSince(now)
        guard remaining > 0 else { return "Expired" }
        let totalHours = Int(remaining / 3600)
        return "\\(totalHours / 24) days, \\(totalHours % 24) hours"
    }
''',
    '''    static func remainingText(until expiration: Date?, now: Date = Date()) -> String {
        guard let expiration else { return "Unavailable" }
        let remaining = Int(expiration.timeIntervalSince(now))
        guard remaining > 0 else { return "Expired" }

        let days = remaining / 86_400
        let hours = (remaining % 86_400) / 3_600
        let minutes = (remaining % 3_600) / 60
        let seconds = remaining % 60
        return String(format: "%dd %02d:%02d:%02d", days, hours, minutes, seconds)
    }
''',
)

settings = root / "Locus/Features/Settings/SettingsView.swift"
settings_text = settings.read_text(encoding="utf-8")
settings_text = settings_text.replace(
    'TimelineView(.periodic(from: .now, by: 60))',
    'TimelineView(.periodic(from: .now, by: 1))',
)
settings_text = settings_text.replace(
    'Text("MazenmiX (Mazen Mozh) Products")',
    'Text("MazenmiX")',
)
settings_text = settings_text.replace(
    'Text("Fully on-device. Favorites and recents stay in UserDefaults. No analytics, no accounts, nothing uploaded.")',
    'Text("Fully on-device. Profiles, favorites, and recents stay in UserDefaults. No analytics, no accounts, nothing uploaded.")',
)

on_appear = '''            .onAppear {
                localDevVPNInstalled = LocalDevVPN.isInstalled
                reloadCertificateInfo()
            }
'''
if on_appear not in settings_text:
    raise RuntimeError("Unable to locate certificate onAppear block")
settings_text = settings_text.replace(
    on_appear,
    on_appear + '''            .task {
                // The embedded renewal host can publish its metadata a fraction
                // after Settings first appears. Retry automatically so the
                // countdown never depends on an unrelated UI/theme refresh.
                reloadCertificateInfo()
                try? await Task.sleep(nanoseconds: 250_000_000)
                reloadCertificateInfo()
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                reloadCertificateInfo()
            }
''',
    1,
)
settings.write_text(settings_text, encoding="utf-8")

# 2) GPS Profiles: separate one-tap presets stored beside favorites/recents.
spoof = root / "Locus/Engine/SpoofSession.swift"
spoof_text = spoof.read_text(encoding="utf-8")

published_old = '''    @Published var favorites: [SavedPlace] = []
    @Published var recents: [SavedPlace] = []
'''
published_new = '''    @Published var profiles: [SavedPlace] = []
    @Published var favorites: [SavedPlace] = []
    @Published var recents: [SavedPlace] = []
'''
if published_old not in spoof_text:
    raise RuntimeError("Unable to locate saved places published properties")
spoof_text = spoof_text.replace(published_old, published_new, 1)

keys_old = '''    private let favoritesKey = "locus.favorites"
    private let recentsKey = "locus.recents"

    init() {
        favorites = SavedPlace.load(key: favoritesKey)
        recents = SavedPlace.load(key: recentsKey)
    }
'''
keys_new = '''    private let profilesKey = "mx.location.profiles"
    private let favoritesKey = "locus.favorites"
    private let recentsKey = "locus.recents"

    init() {
        profiles = SavedPlace.load(key: profilesKey)
        favorites = SavedPlace.load(key: favoritesKey)
        recents = SavedPlace.load(key: recentsKey)
    }
'''
if keys_old not in spoof_text:
    raise RuntimeError("Unable to locate SavedPlace persistence setup")
spoof_text = spoof_text.replace(keys_old, keys_new, 1)

remove_recent = '''    func removeRecent(_ place: SavedPlace) {
        recents.removeAll { $0.id == place.id }
        SavedPlace.save(recents, key: recentsKey)
    }
'''
profile_methods = remove_recent + '''
    func addProfile(name: String? = nil, coordinate: CLLocationCoordinate2D) {
        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let displayName = trimmed.isEmpty ? "Profile \\(profiles.count + 1)" : trimmed
        let profile = SavedPlace(
            name: displayName,
            latitude: coordinate.latitude,
            longitude: coordinate.longitude
        )
        profiles.removeAll { $0.id == profile.id }
        profiles.insert(profile, at: 0)
        SavedPlace.save(profiles, key: profilesKey)
    }

    func renameProfile(_ profile: SavedPlace, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let index = profiles.firstIndex(where: { $0.id == profile.id }) else { return }
        profiles[index].name = trimmed
        SavedPlace.save(profiles, key: profilesKey)
    }

    func removeProfile(_ profile: SavedPlace) {
        profiles.removeAll { $0.id == profile.id }
        SavedPlace.save(profiles, key: profilesKey)
    }
'''
if remove_recent not in spoof_text:
    raise RuntimeError("Unable to locate recent removal method")
spoof_text = spoof_text.replace(remove_recent, profile_methods, 1)

keeper_old = '''    private var joystickVector: CGVector = .zero
    private let locationKeeper = BackgroundKeepAlive()
'''
keeper_new = '''    private var joystickVector: CGVector = .zero
    private let locationKeeper = BackgroundKeepAlive()
    private var lastDropNotificationAt = Date.distantPast
    private var lastDropNotificationMessage = ""
'''
if keeper_old not in spoof_text:
    raise RuntimeError("Unable to locate SpoofSession keep-alive state")
spoof_text = spoof_text.replace(keeper_old, keeper_new, 1)

health_old = '''                } else if !LocationEngine.isSessionActive, self.isSpoofing {
                    self.status = .reconnecting
                    self.apply(sim, pairing: pairing, markRecent: false)
                }
'''
health_new = '''                } else if !LocationEngine.isSessionActive, self.isSpoofing {
                    let reason = LocalDevVPN.isConnected
                        ? "The simulated location session stopped unexpectedly. MX Location is reconnecting now."
                        : "LocalDevVPN disconnected, so the simulated location stopped. Reconnect LocalDevVPN and MX Location will retry."
                    self.lastError = reason
                    self.status = .dropped(reason)
                    self.postDropNotification(reason)
                    self.apply(sim, pairing: pairing, markRecent: false)
                }
'''
if health_old not in spoof_text:
    raise RuntimeError("Unable to locate spoof health monitor")
spoof_text = spoof_text.replace(health_old, health_new, 1)
spoof.write_text(spoof_text, encoding="utf-8")

replace_block(
    spoof,
    '    private func postDropNotification(_ message: String) {\n',
    '    private func offset(coordinate:',
    '''    private func postDropNotification(_ message: String) {
        let now = Date()
        if lastDropNotificationMessage == message,
           now.timeIntervalSince(lastDropNotificationAt) < 45 {
            return
        }
        lastDropNotificationMessage = message
        lastDropNotificationAt = now

        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
        let content = UNMutableNotificationContent()
        content.title = "MX Location Stopped"
        content.body = message
        content.sound = .default
        if #available(iOS 15.0, *) {
            content.interruptionLevel = .timeSensitive
        }
        let request = UNNotificationRequest(
            identifier: "mx.location.spoof.stopped.\\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }

''',
)

# Add Profiles UI to the existing Places screen and reuse the rename dialog.
settings_text = settings.read_text(encoding="utf-8")
state_old = '''    @State private var placeToRename: SavedPlace?
    @State private var renameText = ""
'''
state_new = '''    @State private var placeToRename: SavedPlace?
    @State private var renameText = ""
    @State private var renamingProfile = false
'''
if state_old not in settings_text:
    raise RuntimeError("Unable to locate PlacesView rename state")
settings_text = settings_text.replace(state_old, state_new, 1)

favorites_marker = '                Section("Favorites") {\n'
profiles_section = '''                Section {
                    Button {
                        if let coordinate = session.simulated ?? session.pin ?? session.realCoordinate {
                            session.addProfile(coordinate: coordinate)
                        }
                    } label: {
                        Label("Save Current as Profile", systemImage: "person.crop.circle.badge.plus")
                    }
                    .disabled(session.simulated == nil && session.pin == nil && session.realCoordinate == nil)

                    if session.profiles.isEmpty {
                        Text("Profiles are one-tap GPS presets. Pick or change a location first, then save it here.")
                            .foregroundStyle(.secondary)
                    }

                    ForEach(session.profiles) { profile in
                        placeButton(profile)
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    session.removeProfile(profile)
                                } label: {
                                    Label("Delete", systemImage: "trash.fill")
                                }
                                Button {
                                    renamingProfile = true
                                    placeToRename = profile
                                    renameText = profile.name
                                } label: {
                                    Label("Rename", systemImage: "pencil")
                                }
                                .tint(.gray)
                            }
                    }
                } header: {
                    Text("Profiles")
                } footer: {
                    Text("Use names such as Philippines 🇵🇭, USA 🇺🇸, or Japan 🇯🇵. Activating a profile changes the GPS preset immediately; it does not create separate simultaneous GPS locations per app.")
                }

'''
if favorites_marker not in settings_text:
    raise RuntimeError("Unable to locate Favorites section")
settings_text = settings_text.replace(favorites_marker, profiles_section + favorites_marker, 1)

favorite_rename_action = '''                                Button {
                                    placeToRename = place
                                    renameText = place.name
                                } label: {
'''
if favorite_rename_action not in settings_text:
    raise RuntimeError("Unable to locate favorite rename action")
settings_text = settings_text.replace(
    favorite_rename_action,
    '''                                Button {
                                    renamingProfile = false
                                    placeToRename = place
                                    renameText = place.name
                                } label: {
''',
    1,
)

alert_old = '''            .alert("Rename Favorite", isPresented: Binding(
                get: { placeToRename != nil },
                set: { if !$0 { placeToRename = nil } }
            )) {
                TextField("Name", text: $renameText)
                Button("Cancel", role: .cancel) {
                    placeToRename = nil
                }
                Button("Save") {
                    if let place = placeToRename {
                        session.renameFavorite(place, to: renameText)
                    }
                    placeToRename = nil
                }
            } message: {
                Text("Choose a name you’ll recognize later.")
            }
'''
alert_new = '''            .alert(renamingProfile ? "Rename Profile" : "Rename Favorite", isPresented: Binding(
                get: { placeToRename != nil },
                set: { if !$0 { placeToRename = nil } }
            )) {
                TextField("Name", text: $renameText)
                Button("Cancel", role: .cancel) {
                    placeToRename = nil
                }
                Button("Save") {
                    if let place = placeToRename {
                        if renamingProfile {
                            session.renameProfile(place, to: renameText)
                        } else {
                            session.renameFavorite(place, to: renameText)
                        }
                    }
                    placeToRename = nil
                }
            } message: {
                Text(renamingProfile
                     ? "Give this GPS profile a clear country or city name."
                     : "Choose a name you’ll recognize later.")
            }
'''
if alert_old not in settings_text:
    raise RuntimeError("Unable to locate PlacesView rename alert")
settings_text = settings_text.replace(alert_old, alert_new, 1)
settings.write_text(settings_text, encoding="utf-8")

# 3) Pair-code notification: explicit and time-sensitive while entering the PIN.
pairing_service = root / "Locus/Engine/PairOnDeviceService.swift"
replace_block(
    pairing_service,
    '    private static func postPINNotification(_ pin: String) {\n',
    '    private static func postPlainNotification',
    '''    private static func postPINNotification(_ pin: String) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: ["locus.pairing.pin"])

        let content = UNMutableNotificationContent()
        content.title = "MX Location Pairing Code"
        content.subtitle = "Enter this code in Developer Mode"
        content.body = pin
        content.sound = .default
        content.threadIdentifier = "mx.location.pairing"
        if #available(iOS 15.0, *) {
            content.interruptionLevel = .timeSensitive
            content.relevanceScore = 1.0
        }

        let request = UNNotificationRequest(
            identifier: "locus.pairing.pin",
            content: content,
            trigger: nil
        )
        center.add(request)
    }

''',
)

print("Applied MX Location profiles, live countdown, and notification reliability patch at", root)
