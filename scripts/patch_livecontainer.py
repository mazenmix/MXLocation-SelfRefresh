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
    } else if(!selectedApp && mxLocationExist && LCSharedUtils.certificatePassword && ![lcUserDefaults boolForKey:@"LCOpenSideStore"]) {
        // Once JIT-less certificate import is complete, MX Location becomes the
        // default UI. The signing manager remains available through the bridge.
        selectedApp = @"builtinMXLocation";
        isBuiltInMXLocation = true;
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

bridging = root / "SideStoreSupport/SideStore-Bridging-Header.h"
bridge_text = bridging.read_text(encoding="utf-8")
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
swift_bridge = r'''

@objc(MXCertificateBridge)
public final class MXCertificateBridge: NSObject {
    @objc(refreshHostCertificate)
    public static func refreshHostCertificate() {
        NotificationCenter.default.post(name: Notification.Name("MXCertificateRefreshStarted"), object: nil)

        Task {
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

                await MainActor.run {
                    NotificationCenter.default.post(name: Notification.Name("MXCertificateRefreshSucceeded"), object: nil)
                }
            } catch {
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
}
'''
if "@objc(MXCertificateBridge)" not in swift_text:
    side_store_swift.write_text(swift_text + swift_bridge, encoding="utf-8")

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
