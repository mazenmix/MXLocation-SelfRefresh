from pathlib import Path
import sys


root = Path(sys.argv[1]).resolve()


def replace_required(path: Path, old: str, new: str) -> None:
    text = path.read_text(encoding="utf-8")
    if old not in text:
        raise RuntimeError(f"Required source fragment not found in {path}: {old[:120]!r}")
    path.write_text(text.replace(old, new), encoding="utf-8")


bootstrap = root / "LiveContainer/LCBootstrap.m"
text = bootstrap.read_text(encoding="utf-8")

replacements = [
    (
        "bool isSideStore = false;\nbool sideStoreExist = false;",
        "bool isSideStore = false;\nbool isBuiltInMXLocation = false;\nbool sideStoreExist = false;\nbool mxLocationExist = false;",
    ),
    (
        "    if (!LCSharedUtils.certificatePassword && !isSideStore) {",
        "    if (!LCSharedUtils.certificatePassword && !isSideStore && !isBuiltInMXLocation) {",
    ),
    (
        '''    NSString *bundlePath = 0;
    if(!isSideStore) {
        bundlePath = [NSString stringWithFormat:@"%@/Applications/%@", docPath, selectedApp];
    } else if (isLiveProcess) {''',
        '''    NSString *bundlePath = 0;
    if(isBuiltInMXLocation) {
        bundlePath = [[NSBundle.mainBundle.bundleURL URLByAppendingPathComponent:@"Frameworks/MXLocationApp.framework"] path];
    } else if(!isSideStore) {
        bundlePath = [NSString stringWithFormat:@"%@/Applications/%@", docPath, selectedApp];
    } else if (isLiveProcess) {''',
    ),
    (
        '''    if(isSideStore) {
        if(isLiveProcess) {''',
        '''    if(isBuiltInMXLocation) {
        newHomePath = [docPath stringByAppendingPathComponent:@"MXLocation"];
    } else if(isSideStore) {
        if(isLiveProcess) {''',
    ),
    (
        '''        if (!isLiveProcess && (isSideStore || ![guestAppInfo[@"dontInjectTweakLoader"] boolValue])) {''',
        '''        if (!isLiveProcess && (isSideStore || isBuiltInMXLocation || ![guestAppInfo[@"dontInjectTweakLoader"] boolValue])) {''',
    ),
    (
        '''    if(isLiveProcess) {
        sideStoreExist = [NSFileManager.defaultManager fileExistsAtPath:[lcMainBundle.bundlePath stringByAppendingPathComponent:@"../../Frameworks/SideStoreApp.framework"]];
    } else {
        sideStoreExist = [NSFileManager.defaultManager fileExistsAtPath:[lcMainBundle.bundlePath stringByAppendingPathComponent:@"Frameworks/SideStoreApp.framework"]];
    }
''',
        '''    if(isLiveProcess) {
        sideStoreExist = [NSFileManager.defaultManager fileExistsAtPath:[lcMainBundle.bundlePath stringByAppendingPathComponent:@"../../Frameworks/SideStoreApp.framework"]];
    } else {
        sideStoreExist = [NSFileManager.defaultManager fileExistsAtPath:[lcMainBundle.bundlePath stringByAppendingPathComponent:@"Frameworks/SideStoreApp.framework"]];
        mxLocationExist = [NSFileManager.defaultManager fileExistsAtPath:[lcMainBundle.bundlePath stringByAppendingPathComponent:@"Frameworks/MXLocationApp.framework"]];
    }

    if([selectedApp isEqualToString:@"builtinMXLocation"]) {
        isBuiltInMXLocation = mxLocationExist;
        if(isBuiltInMXLocation) {
            [lcUserDefaults removeObjectForKey:@"error"];
        }
    } else if(!selectedApp && mxLocationExist && ![lcUserDefaults boolForKey:@"LCOpenSideStore"]) {
        // MX Location is always the visible app. The integrated signing manager
        // is opened only when the user asks for it from MX Location settings.
        selectedApp = @"builtinMXLocation";
        isBuiltInMXLocation = true;
        [lcUserDefaults removeObjectForKey:@"error"];
        NSLog(@"[MX Location] launching the map as the default UI");
    }
''',
    ),
]

for old, new in replacements:
    if old not in text:
        raise RuntimeError(f"LiveContainer bootstrap source changed; missing fragment: {old[:140]!r}")
    text = text.replace(old, new)

bootstrap.write_text(text, encoding="utf-8")

# C entry point used by the Swift bridge to switch from MX Location to the
# integrated signing manager without installing a separate SideStore app.
hooks = root / "SideStoreSupport/SideStoreHooks.m"
hooks_text = hooks.read_text(encoding="utf-8")
hook_needle = "void installSideStoreHooks(void) {\n"
hook_function = '''void MXOpenSigningManager(void) {
    [NSUserDefaults.lcUserDefaults setObject:@"builtinSideStore" forKey:@"selected"];
    [NSUserDefaults.lcUserDefaults synchronize];
    [LCSharedUtils launchToGuestAppWithClassicMode:0];
}

'''
if hook_needle not in hooks_text:
    raise RuntimeError("Unable to add integrated signing-manager bridge")
hooks.write_text(hooks_text.replace(hook_needle, hook_function + hook_needle), encoding="utf-8")

# Make it explicit in the bundled manager UI that this is an MX Location
# component, not a separately installed SideStore application.
hooks_text = hooks.read_text(encoding="utf-8")
hooks_text = hooks_text.replace(
    'versionLabel.text = [NSString stringWithFormat:@"LC %@, SS %@", LCVersion, SSVersion];',
    'versionLabel.text = @"MX Renewal Engine — built into MX Location";',
)

# SideStore records every extension found in the currently installed host when
# its database starts. If Sideloadly omitted a provisioning profile from an old
# build, that reconciliation used to abort before the one-time setup UI could
# open. Hide only the *installed host's* extensions from foreground database
# bootstrap. An IPA selected from Files has a different bundle URL, so its
# LiveProcess extension remains visible and is signed normally during reinstall.
bundle_end_needle = '''+ (NSBundle*)hook_realMainBundle {
    if (!NSUserDefaults.isLiveProcess) return NSUserDefaults.lcMainBundle;
    
    static NSBundle* lcAppBundle = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        lcAppBundle = [NSBundle bundleWithURL: NSUserDefaults.lcMainBundle.bundleURL.URLByDeletingLastPathComponent.URLByDeletingLastPathComponent];
    });
    return lcAppBundle;
}

@end
'''
bundle_end_replacement = '''+ (NSBundle*)hook_realMainBundle {
    if (!NSUserDefaults.isLiveProcess) return NSUserDefaults.lcMainBundle;
    
    static NSBundle* lcAppBundle = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        lcAppBundle = [NSBundle bundleWithURL: NSUserDefaults.lcMainBundle.bundleURL.URLByDeletingLastPathComponent.URLByDeletingLastPathComponent];
    });
    return lcAppBundle;
}

- (NSURL*)hook_mxRenewalBuiltInPlugInsURL {
    NSURL* plugInsURL = [self hook_mxRenewalBuiltInPlugInsURL];
    BOOL isForegroundSetup = NSUserDefaults.isSideStore && !NSUserDefaults.isLiveProcess;
    BOOL isInstalledHost = [self.bundleURL.path isEqualToString:NSUserDefaults.lcMainBundle.bundleURL.path];
    if (isForegroundSetup && isInstalledHost) {
        return nil;
    }
    return plugInsURL;
}

@end
'''
if bundle_end_needle not in hooks_text:
    raise RuntimeError("Unable to add renewal-engine extension recovery hook")
hooks_text = hooks_text.replace(bundle_end_needle, bundle_end_replacement)

hook_install_needle = '''    swizzleClassMethod(NSBundle.class, @selector(realMainBundle), @selector(hook_realMainBundle));
    
    // replace altStoreSourceURL
'''
hook_install_replacement = '''    swizzleClassMethod(NSBundle.class, @selector(realMainBundle), @selector(hook_realMainBundle));
    swizzle(NSBundle.class, @selector(builtInPlugInsURL), @selector(hook_mxRenewalBuiltInPlugInsURL));
    
    // replace altStoreSourceURL
'''
if hook_install_needle not in hooks_text:
    raise RuntimeError("Unable to install renewal-engine extension recovery hook")
hooks_text = hooks_text.replace(hook_install_needle, hook_install_replacement)
hooks.write_text(hooks_text, encoding="utf-8")

bridging = root / "SideStoreSupport/SideStore-Bridging-Header.h"
bridge_text = bridging.read_text(encoding="utf-8")
bridge_include = '#include "../LiveContainer/LCSharedUtils.h"\n#include <sqlite3.h>\n'
if '#include "../LiveContainer/LCSharedUtils.h"' not in bridge_text:
    bridge_text = bridge_text.replace(
        '#include "../LiveContainer/utils.h"\n',
        '#include "../LiveContainer/utils.h"\n' + bridge_include,
    )
declaration = "\nvoid MXOpenSigningManager(void);\n"
if declaration.strip() not in bridge_text:
    bridge_text = bridge_text.replace(
        "#endif /* SideStore_Bridging_Header_h_h */",
        declaration + "\n#endif /* SideStore_Bridging_Header_h_h */",
    )
bridging.write_text(bridge_text, encoding="utf-8")

# Objective-C-visible bridge invoked dynamically by the bundled MX Location
# guest. RefreshHandler launches built-in SideStore in LiveProcess, allowing the
# host to renew while MX Location is the foreground guest.
side_store_swift = root / "SideStoreSupport/SideStore.swift"
swift_text = side_store_swift.read_text(encoding="utf-8")
if "import SQLite3" not in swift_text:
    swift_text = swift_text.replace("import Foundation\n", "import Foundation\nimport SQLite3\n", 1)

timeout_needle = '''    func updateProgress(_ value: Double) {
'''
timeout_method = '''    func abortRefresh(_ message: String) {
        let error = NSError(
            domain: "MXCertificateBridge",
            code: 408,
            userInfo: [NSLocalizedDescriptionKey: message]
        )

        if let continuation = c {
            continuation.resume(throwing: error)
            c = nil
        }
        if let continuation = launchContinuation {
            continuation.resume(throwing: error)
            launchContinuation = nil
        }

        ext?._kill(9)
        ext = nil
        client = nil
        sideStorePid = 0
    }

    func updateProgress(_ value: Double) {
'''
if "func abortRefresh(_ message: String)" not in swift_text:
    if timeout_needle not in swift_text:
        raise RuntimeError("Unable to add a bounded refresh timeout")
    swift_text = swift_text.replace(timeout_needle, timeout_method)

swift_bridge = r'''

private struct MXManagedCertificateRecord {
    let expirationDate: Date
    let refreshedDate: Date?
}

@objc(MXCertificateBridge)
public final class MXCertificateBridge: NSObject {
    private static let managedExpirationKey = "MXRenewalManagedExpiration"
    private static let engineReadyKey = "MXRenewalEngineReady"
    private static let engineStatusKey = "MXRenewalEngineStatus"
    private static let pendingAttemptKey = "MXCertificatePendingAttempt"
    private static let pendingProcessKey = "MXCertificatePendingProcess"
    private static let expirationBeforeAttemptKey = "MXCertificateExpirationBeforeAttempt"
    private static let lastSuccessfulRefreshKey = "MXCertificateLastSuccessfulRefresh"
    private static let lastResultKey = "MXCertificateLastResult"
    private static let maximumRefreshDuration: TimeInterval = 4 * 60

    @objc(refreshRenewalMetadata)
    public static func refreshRenewalMetadata() {
        _ = updateRenewalMetadata()
    }

    @objc(refreshHostCertificate)
    public static func refreshHostCertificate() {
        let metadata = updateRenewalMetadata()
        guard metadata.ready else {
            finishFailure(metadata.status)
            NotificationCenter.default.post(
                name: Notification.Name("MXCertificateRefreshFailed"),
                object: nil,
                userInfo: ["error": metadata.status]
            )
            return
        }

        NotificationCenter.default.post(name: Notification.Name("MXCertificateRefreshStarted"), object: nil)

        Task {
            let timeout = DispatchWorkItem {
                if #available(iOS 17.0, *) {
                    RefreshHandler.shared.abortRefresh(
                        "Renewal timed out after 4 minutes. Check LocalDevVPN and the pairing file."
                    )
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + maximumRefreshDuration, execute: timeout)
            defer { timeout.cancel() }

            do {
                guard #available(iOS 17.0, *) else {
                    throw NSError(
                        domain: "MXCertificateBridge",
                        code: 17,
                        userInfo: [NSLocalizedDescriptionKey: "Certificate refresh requires iOS 17 or newer."]
                    )
                }

                let refreshProgress = Progress(totalUnitCount: 100)
                try await performIntentRefresh(
                    identifier: "RefreshAllIntent",
                    mangledTypeName: "9SideStore20RefreshAllAppsIntentV",
                    intentProgress: refreshProgress
                )

                let refreshedMetadata = updateRenewalMetadata()
                let defaults = UserDefaults.standard
                let previousExpiration = defaults.object(forKey: expirationBeforeAttemptKey) as? Date
                guard let currentExpiration = refreshedMetadata.expirationDate,
                      previousExpiration == nil || currentExpiration.timeIntervalSince(previousExpiration!) > 1
                else {
                    throw NSError(
                        domain: "MXCertificateBridge",
                        code: 2,
                        userInfo: [NSLocalizedDescriptionKey: "Certificate expiry did not change. Complete Renewal Engine Setup first."]
                    )
                }

                finishSuccess(refreshedDate: refreshedMetadata.refreshedDate)
                await MainActor.run {
                    NotificationCenter.default.post(name: Notification.Name("MXCertificateRefreshSucceeded"), object: nil)
                }
            } catch {
                finishFailure(error.localizedDescription)
                await MainActor.run {
                    NotificationCenter.default.post(
                        name: Notification.Name("MXCertificateRefreshFailed"),
                        object: nil,
                        userInfo: ["error": error.localizedDescription]
                    )
                }
            }
        }
    }

    @objc(openSigningManager)
    public static func openSigningManager() {
        MXOpenSigningManager()
    }

    private struct RenewalMetadata {
        let ready: Bool
        let status: String
        let expirationDate: Date?
        let refreshedDate: Date?
    }

    private static func updateRenewalMetadata() -> RenewalMetadata {
        let defaults = UserDefaults.standard
        let record = managedCertificateRecord()
        let hasPairingFile = pairingFileExists()
        let hasRefreshExtensionProfile = refreshExtensionProfileExists()

        var missing = [String]()
        if !hasRefreshExtensionProfile {
            missing.append("LiveProcess signing profile; reinstall this IPA with app extensions enabled")
        }
        if !hasPairingFile {
            missing.append("pairing file")
        }
        if record == nil {
            missing.append("sign in and install this MX IPA once")
        }

        let ready = missing.isEmpty
        let status = ready ? "Ready" : "Setup required: " + missing.joined(separator: ", ")
        defaults.set(ready, forKey: engineReadyKey)
        defaults.set(status, forKey: engineStatusKey)

        if let record {
            defaults.set(record.expirationDate, forKey: managedExpirationKey)
        } else {
            defaults.removeObject(forKey: managedExpirationKey)
        }

        return RenewalMetadata(
            ready: ready,
            status: status,
            expirationDate: record?.expirationDate,
            refreshedDate: record?.refreshedDate
        )
    }

    private static func refreshExtensionProfileExists() -> Bool {
        guard let plugInsURL = UserDefaults.lcMainBundle().builtInPlugInsURL else {
            return false
        }
        let profileURL = plugInsURL
            .appendingPathComponent("LiveProcess.appex", isDirectory: true)
            .appendingPathComponent("embedded.mobileprovision", isDirectory: false)
        return FileManager.default.fileExists(atPath: profileURL.path)
    }

    private static func pairingFileExists() -> Bool {
        guard let lcHome = getenv("LC_HOME_PATH") else { return false }
        let sideStoreHome = URL(fileURLWithPath: String(cString: lcHome))
            .appendingPathComponent("Documents/SideStore", isDirectory: true)
        guard let enumerator = FileManager.default.enumerator(
            at: sideStoreHome,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return false }

        for case let fileURL as URL in enumerator {
            if fileURL.lastPathComponent == "ALTPairingFile.mobiledevicepairing" {
                return true
            }
        }
        return false
    }

    private static func managedCertificateRecord() -> MXManagedCertificateRecord? {
        guard let appGroupIdentifier = LCSharedUtils.appGroupID(),
              let groupURL = FileManager.default.containerURL(
                forSecurityApplicationGroupIdentifier: appGroupIdentifier
              )
        else { return nil }

        let databaseDirectory = groupURL.appendingPathComponent("Database", isDirectory: true)
        guard let enumerator = FileManager.default.enumerator(
            at: databaseDirectory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return nil }

        var newest: MXManagedCertificateRecord?
        for case let databaseURL as URL in enumerator {
            guard databaseURL.pathExtension == "sqlite" else { continue }
            if let record = readManagedCertificate(from: databaseURL),
               newest == nil || record.expirationDate > newest!.expirationDate {
                newest = record
            }
        }
        return newest
    }

    private static func readManagedCertificate(from databaseURL: URL) -> MXManagedCertificateRecord? {
        var database: OpaquePointer?
        guard sqlite3_open_v2(
            databaseURL.path,
            &database,
            SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX,
            nil
        ) == SQLITE_OK, let database else { return nil }
        defer { sqlite3_close(database) }

        let query = """
            SELECT ZEXPIRATIONDATE, ZREFRESHEDDATE
            FROM ZINSTALLEDAPP
            WHERE ZBUNDLEIDENTIFIER IN ('com.kdt.livecontainer', 'com.mazenmix.mxlocation')
               OR ZRESIGNEDBUNDLEIDENTIFIER LIKE '%com.kdt.livecontainer%'
               OR ZRESIGNEDBUNDLEIDENTIFIER LIKE '%com.mazenmix.mxlocation%'
            ORDER BY ZEXPIRATIONDATE DESC
            LIMIT 1
            """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, query, -1, &statement, nil) == SQLITE_OK,
              let statement
        else { return nil }
        defer { sqlite3_finalize(statement) }

        guard sqlite3_step(statement) == SQLITE_ROW else { return nil }
        let expiration = Date(timeIntervalSinceReferenceDate: sqlite3_column_double(statement, 0))
        let refreshed: Date?
        if sqlite3_column_type(statement, 1) == SQLITE_NULL {
            refreshed = nil
        } else {
            refreshed = Date(timeIntervalSinceReferenceDate: sqlite3_column_double(statement, 1))
        }
        return MXManagedCertificateRecord(expirationDate: expiration, refreshedDate: refreshed)
    }

    private static func finishSuccess(refreshedDate: Date?) {
        let defaults = UserDefaults.standard
        let successfulDate = refreshedDate
            ?? defaults.object(forKey: pendingAttemptKey) as? Date
            ?? Date()
        defaults.set(successfulDate, forKey: lastSuccessfulRefreshKey)
        defaults.set("Succeeded", forKey: lastResultKey)
        clearPendingAttempt(defaults)
    }

    private static func finishFailure(_ message: String) {
        let defaults = UserDefaults.standard
        defaults.set("Failed: \(message)", forKey: lastResultKey)
        clearPendingAttempt(defaults)
    }

    private static func clearPendingAttempt(_ defaults: UserDefaults) {
        defaults.removeObject(forKey: pendingAttemptKey)
        defaults.removeObject(forKey: pendingProcessKey)
        defaults.removeObject(forKey: expirationBeforeAttemptKey)
    }
}
'''
if "@objc(MXCertificateBridge)" not in swift_text:
    swift_text += swift_bridge
side_store_swift.write_text(swift_text, encoding="utf-8")

# Host branding. The executable/target names stay unchanged for compatibility.
info = root / "Resources/Info.plist"
info_text = info.read_text(encoding="utf-8")
info_text = info_text.replace(
    "<key>CFBundleDisplayName</key>\n\t<string>LiveContainer</string>",
    "<key>CFBundleDisplayName</key>\n\t<string>MX Location</string>",
)
info_text = info_text.replace(
    "<key>CFBundleName</key>\n\t<string>LiveContainer</string>",
    "<key>CFBundleName</key>\n\t<string>MXLocation</string>",
)
if "<string>mxlocation</string>" not in info_text:
    info_text = info_text.replace(
        "<string>livecontainer</string>",
        "<string>mxlocation</string>",
        1,
    )
info.write_text(info_text, encoding="utf-8")

print("Patched LiveContainer host at", root)
