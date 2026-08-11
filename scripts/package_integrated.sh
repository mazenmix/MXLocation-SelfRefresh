#!/bin/bash
set -euo pipefail

if [[ $# -ne 4 ]]; then
  echo "usage: package_integrated.sh LIVE_CONTAINER_ROOT LOCUS_ROOT DYLIBIFY OUTPUT_IPA" >&2
  exit 64
fi

LC_ROOT=$(cd "$1" && pwd)
LOCUS_ROOT=$(cd "$2" && pwd)
DYLIBIFY=$(cd "$(dirname "$3")" && pwd)/$(basename "$3")
OUTPUT_IPA=$(cd "$(dirname "$4")" && pwd)/$(basename "$4")
WORK_DIR=$(mktemp -d)
trap 'rm -rf "$WORK_DIR"' EXIT

HOST_APP="$LC_ROOT/archive.xcarchive/Products/Applications/LiveContainer.app"
LOCUS_APP=$(find "$LOCUS_ROOT/build/Build/Products/Release-iphoneos" -maxdepth 1 -name '*.app' -print -quit)

test -d "$HOST_APP"
test -n "$LOCUS_APP"
test -d "$LOCUS_APP"
test -x "$DYLIBIFY"

mkdir -p "$WORK_DIR/Payload"
cp -R "$HOST_APP" "$WORK_DIR/Payload/MXLocationHost.app"
APP="$WORK_DIR/Payload/MXLocationHost.app"

# SideStore host metadata required by the integrated engine.
/usr/libexec/PlistBuddy -c 'Add :ALTAppGroups array' "$APP/Info.plist" || true
/usr/libexec/PlistBuddy -c 'Add :ALTAppGroups: string group.com.SideStore.SideStore' "$APP/Info.plist" || true

/usr/libexec/PlistBuddy -c 'Add :CFBundleURLTypes:1 dict' "$APP/Info.plist" || true
/usr/libexec/PlistBuddy -c 'Add :CFBundleURLTypes:1:CFBundleURLName string com.mazenmix.mxlocation.sidestore' "$APP/Info.plist" || true
/usr/libexec/PlistBuddy -c 'Add :CFBundleURLTypes:1:CFBundleURLSchemes array' "$APP/Info.plist" || true
/usr/libexec/PlistBuddy -c 'Add :CFBundleURLTypes:1:CFBundleURLSchemes:0 string sidestore' "$APP/Info.plist" || true

/usr/libexec/PlistBuddy -c 'Add :CFBundleURLTypes:2 dict' "$APP/Info.plist" || true
/usr/libexec/PlistBuddy -c 'Add :CFBundleURLTypes:2:CFBundleURLName string com.mazenmix.mxlocation.sidestorebackup' "$APP/Info.plist" || true
/usr/libexec/PlistBuddy -c 'Add :CFBundleURLTypes:2:CFBundleURLSchemes array' "$APP/Info.plist" || true
/usr/libexec/PlistBuddy -c 'Add :CFBundleURLTypes:2:CFBundleURLSchemes:0 string sidestore-com.mazenmix.mxlocation' "$APP/Info.plist" || true

/usr/libexec/PlistBuddy -c 'Add :INIntentsSupported array' "$APP/Info.plist" || true
/usr/libexec/PlistBuddy -c 'Add :INIntentsSupported:0 string RefreshAllIntent' "$APP/Info.plist" || true
/usr/libexec/PlistBuddy -c 'Add :INIntentsSupported:1 string ViewAppIntent' "$APP/Info.plist" || true
/usr/libexec/PlistBuddy -c 'Add :NSUserActivityTypes array' "$APP/Info.plist" || true
/usr/libexec/PlistBuddy -c 'Add :NSUserActivityTypes:0 string RefreshAllIntent' "$APP/Info.plist" || true
/usr/libexec/PlistBuddy -c 'Add :NSUserActivityTypes:1 string ViewAppIntent' "$APP/Info.plist" || true

/usr/libexec/PlistBuddy -c 'Set :CFBundleDisplayName MX Location' "$APP/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundleName MXLocation' "$APP/Info.plist"

# Bundle MX Location as a built-in guest framework.
MX_FRAMEWORK="$APP/Frameworks/MXLocationApp.framework"
cp -R "$LOCUS_APP" "$MX_FRAMEWORK"
MX_EXECUTABLE=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$MX_FRAMEWORK/Info.plist")
"$DYLIBIFY" "$MX_FRAMEWORK/$MX_EXECUTABLE" "$MX_FRAMEWORK/$MX_EXECUTABLE.dylib"
rm "$MX_FRAMEWORK/$MX_EXECUTABLE"
mv "$MX_FRAMEWORK/$MX_EXECUTABLE.dylib" "$MX_FRAMEWORK/$MX_EXECUTABLE"
ldid -S"" "$MX_FRAMEWORK/$MX_EXECUTABLE"
cp "$(dirname "$0")/LCAppInfo-MX.plist" "$MX_FRAMEWORK/LCAppInfo.plist"

# Download and embed the LiveContainer-compatible SideStore build.
mkdir -p "$WORK_DIR/sidestore"
curl -fL --retry 3 \
  -o "$WORK_DIR/sidestore/SideStore.ipa" \
  https://github.com/LiveContainer/SideStore/releases/download/nightly/SideStore.ipa
unzip -q "$WORK_DIR/sidestore/SideStore.ipa" -d "$WORK_DIR/sidestore/unpacked"
SIDE_APP="$WORK_DIR/sidestore/unpacked/Payload/SideStore.app"
test -d "$SIDE_APP"

SIDE_FRAMEWORK="$APP/Frameworks/SideStoreApp.framework"
mv "$SIDE_APP" "$SIDE_FRAMEWORK"
"$DYLIBIFY" "$SIDE_FRAMEWORK/SideStore" "$SIDE_FRAMEWORK/SideStore.dylib"
rm "$SIDE_FRAMEWORK/SideStore"
mv "$SIDE_FRAMEWORK/SideStore.dylib" "$SIDE_FRAMEWORK/SideStore"
ldid -S"" "$SIDE_FRAMEWORK/SideStore"
cp "$LC_ROOT/.github/sidelc/LCAppInfo.plist" "$SIDE_FRAMEWORK/LCAppInfo.plist"

# Copy intents used by the on-device/background refresh bridge.
cp "$SIDE_FRAMEWORK/Intents.intentdefinition" "$APP/"
cp "$SIDE_FRAMEWORK/ViewApp.intentdefinition" "$APP/"
cp -R "$SIDE_FRAMEWORK/Metadata.appintents" "$APP/Metadata.appintents"
sed -i '' 's/9SideStore20RefreshAllAppsIntentV/16SideStoreSupport20RefreshAllAppsIntentV/g' "$APP/Metadata.appintents/extract.actionsdata"
sed -i '' 's/9SideStore26RefreshAllAppsWidgetIntentV/16SideStoreSupport26RefreshAllAppsWidgetIntentV/g' "$APP/Metadata.appintents/extract.actionsdata"

# Keep the refresh widget extension under the host app.
if [[ -d "$SIDE_FRAMEWORK/PlugIns/AltWidgetExtension.appex" ]]; then
  mkdir -p "$APP/PlugIns"
  mv "$SIDE_FRAMEWORK/PlugIns/AltWidgetExtension.appex" "$APP/PlugIns/LiveWidgetExtension.appex"
  cp -R "$SIDE_FRAMEWORK/Frameworks" "$APP/PlugIns/LiveWidgetExtension.appex/"
  # Every embedded extension ID must use the host bundle ID as its prefix.
  # Sideloadly appends a per-account suffix to com.kdt.livecontainer while
  # signing and only rewrites extensions that already share that prefix.
  /usr/libexec/PlistBuddy -c 'Set :CFBundleIdentifier com.kdt.livecontainer.LiveWidgetExtension' "$APP/PlugIns/LiveWidgetExtension.appex/Info.plist"
  /usr/libexec/PlistBuddy -c 'Set :CFBundleExecutable LiveWidgetExtension' "$APP/PlugIns/LiveWidgetExtension.appex/Info.plist"
  mv "$APP/PlugIns/LiveWidgetExtension.appex/AltWidgetExtension" "$APP/PlugIns/LiveWidgetExtension.appex/LiveWidgetExtension"
  ldid -S"$LC_ROOT/.github/sidelc/LiveWidgetExtension_adhoc.xml" "$APP/PlugIns/LiveWidgetExtension.appex/LiveWidgetExtension"
fi

# Remove stale signatures. The output intentionally remains unsigned so the
# user's on-device signing identity and app-group entitlements can be applied.
find "$APP" -type d -name _CodeSignature -prune -exec rm -rf {} +
find "$APP" -name embedded.mobileprovision -type f -delete

(
  cd "$WORK_DIR"
  /usr/bin/zip -qry "$OUTPUT_IPA" Payload -x '._*' '.DS_Store' '__MACOSX/*'
)

echo "Created $OUTPUT_IPA"
