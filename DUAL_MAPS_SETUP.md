# MX Location Pro — Apple Maps + Google Maps (v4.6)

Native rendering is provided by MapKit and Google Maps SDK for iOS 11.2.0. The search/autocomplete provider currently remains Apple MapKit for BOTH base-map choices. Changing map tiles does not change SpoofSession, pairing, or saved locations.

## Google API key setup (on iPhone)

1. Open [Google Cloud Console](https://console.cloud.google.com/google/maps-apis/credentials), select/create a project, link a billing account, and enable **Maps SDK for iOS**.
2. Create an **API key**; application restriction **iOS apps** → **com.mazenmix.mxlocationpro**. API restriction → **Maps SDK for iOS** only. Use a budget/alert if concerned about usage.
3. Install the app's unsigned IPA after signing with SideStore. Open **Explore** → **Apple | Google** selector → gear icon.
4. Paste the key into **Map Settings** → **Save Google API key**. The app stores the key in the iPhone Keychain and switches to Google Maps, if accepted locally.
5. Select **Remember my choice** to retain Google or Apple across app launches. With it off, the app starts on Apple each time.

**Important:** the app validates only basic key formatting and does not confirm that Google Cloud billing or restrictions are correctly configured until tiles load. Missing/invalid key: choose Apple Maps. A key provided to a client-side Google SDK cannot be made entirely secret; protect it with Google Cloud application/API restrictions. The app does not upload the key to this repository or to ChatGPT.

## Google Maps billing and limitations

Google Maps Platform is a billed service with product-specific usage terms. Google Maps SDK for iOS does not itself replace the Apple MKLocalSearch autocomplete, the location-simulation engine, or Apple Look Around. Places SDK for iOS would require a separate product enablement/implementation.

## iOS details

The Google Maps switch uses a real `GMSMapView` in a SwiftUI `UIViewRepresentable`. An Apple `MapReader` remains fully intact for Apple mode. Both modes set `SpoofSession.pin` and display `SpoofSession.simulated`. Signing/bundle ID remain `com.mazenmix.mxlocationpro`; neither the original `com.mazenmix.mxlocation` nor its pairing/registration is changed.

**Test matrix** after installing: Apple base map (without key), Google map selection before key prompts settings, save key, map tiles displayed, tap Google location changes pin, change back to Apple, re-open and verify remember on/off, search and dismiss keyboard, GPS Change Location and Stop, saved favorites and weather. These are device-level checks beyond compile success.
