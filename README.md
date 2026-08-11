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
- Shows whether the bundled renewal engine is ready and what one-time setup is
  missing instead of leaving **Renewing...** stuck indefinitely.
- Stops a stalled renewal after four minutes with a useful error.
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

An IPA installed directly by Sideloadly is not automatically registered in the
bundled renewal engine. Complete these steps once:

1. Download the same MX Location IPA to the iPhone Files app.
2. Open MX Location > Settings > **Set Up Renewal Engine**. This switches to the
   signing engine bundled inside the same MX Location app; it does not require a
   separately installed SideStore app.
3. Sign in with the Apple Account used for free/paid developer signing and
   select a valid pairing file.
4. Tap **+** in the bundled engine and install the same MX Location IPA from
   Files once. iOS may close the app while it replaces the Sideloadly-installed
   copy.
5. Reopen MX Location. In Settings, **Renewal engine** should show **Ready**.

In MX Location Settings, use **Renew Certificate Now** while LocalDevVPN is
connected. A normal renewal is usually much shorter than four minutes. A
successful self-refresh may close the running app while iOS replaces it; reopen
MX Location to see the updated certificate details. If the attempt reaches four
minutes, the app reports a timeout instead of remaining stuck.

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
