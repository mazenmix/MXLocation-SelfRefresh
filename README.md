# MX Location Self-Refresh Builder

This builder creates a single **MX Location** IPA with the SideStore refresh
engine bundled inside it. The installed app opens the MX Location GPS interface
after its one-time signing setup, and exposes certificate controls from MX
Location Settings.

## What this build does

- Keeps the Locus/MX Location iOS 27 location-simulation engine.
- Bundles LiveContainer + SideStore into the same installed app.
- Opens MX Location directly as the normal app interface.
- Adds **Renew Certificate Now** to MX Location Settings.
- Shows the real certificate time remaining, expiration date, last successful
  renewal, and refresh result directly in MX Location Settings.
- Attempts a refresh on app launch when at least 24 hours have passed since the
  last attempt.
- Keeps the system **Refresh All Apps** App Intent supplied by SideStore, so an
  optional daily Shortcuts automation can refresh while the app is closed.
- Keeps every embedded extension under the host bundle-ID prefix so Sideloadly
  can rewrite and sign the complete app without an IXErrorDomain placeholder
  failure.

## Unavoidable requirements

SideStore does not bypass Apple's signing system. The integrated engine still
requires:

1. A free or paid Apple Developer identity.
2. Developer Mode enabled on the iPhone.
3. LocalDevVPN connected while refreshing.
4. A valid SideStore pairing file. Initial placement or replacement may require
   iLoader and a computer. iOS can invalidate pairing after an update or reset.

The integrated engine removes the need to keep a separate SideStore app. It
cannot remove the VPN/pairing requirements SideStore itself uses.

## Build with GitHub Actions

1. Upload this folder to a GitHub repository.
2. Open **Actions**.
3. Run **Build MX Location Self Refresh IPA**.
4. Download the `MX-Location-Self-Refresh` artifact.
5. Install `MX-Location-Self-Refresh-unsigned.ipa` once with iLoader, SideStore,
   or another compatible signer that preserves app extensions and app groups.

## First-time setup

1. Open the installed MX Location app. The signing setup interface appears
   until a certificate has been imported.
2. Open the built-in SideStore, sign in on-device, and add/verify its pairing
   file.
3. Connect LocalDevVPN and refresh the app once.
4. Return to Settings and choose **Import Certificate from SideStore**.
5. Reopen MX Location. The map opens directly from then on.

In MX Location Settings, use **Renew Certificate Now** while LocalDevVPN is
connected. Renewal can take several minutes, so keep MX Location open while it
shows **Renewing…**. A successful self-refresh may close the running app while
iOS replaces it; reopen MX Location to see the updated certificate details.

## Security

Enter the Apple Account and two-factor code only on the iPhone inside the
built-in signing manager. Do not put credentials, certificates, pairing files,
or passwords in this repository or in GitHub Actions secrets.

## Source and licensing

- MX Location is derived from `ChrisMack32/Locus` at commit
  `83c8fb324983728e8f44759cfd834dc637ee38b5` (MIT).
- The host and integrated signing engine are derived from
  `LiveContainer/LiveContainer` and `LiveContainer/SideStore` (AGPL-3.0).

This builder preserves upstream license files in the generated source/build
workspace. Distribution of the combined build must comply with AGPL-3.0.
