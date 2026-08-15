from pathlib import Path
import re
import sys


root = Path(sys.argv[1]).resolve()
settings = root / "Locus/Features/Settings/SettingsView.swift"
text = settings.read_text(encoding="utf-8")


# Keep Developer pairing controls, but remove the long instructional footer.
pairing_footer = re.compile(
    r'''(                \} header: \{\n                    Text\("Developer pairing"\)\n                \}) footer: \{\n                    Text\(supportsOnDevicePairing\n.*?                \}\n''',
    re.DOTALL,
)
text, count = pairing_footer.subn(r"\1\n", text, count=1)
if count != 1:
    raise RuntimeError("Unable to remove Developer pairing footer")


# Hide tunnel diagnostics/settings from the Settings UI. The underlying tunnel
# configuration remains intact and continues using its stored/default value.
tunnel_section = '''                Section {
                    TextField("Device tunnel IP", text: $tunnelIP)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .onSubmit {
                            TunnelConfig.setTargetIP(tunnelIP)
                        }
                    LabeledContent("Status") {
                        Text(LocalDevVPN.isConnected ? "Connected" : "Not connected")
                            .foregroundStyle(LocalDevVPN.isConnected ? LocusTheme.statusGood : LocusTheme.statusWarn)
                    }
                    Button("Save tunnel IP") {
                        TunnelConfig.setTargetIP(tunnelIP)
                    }
                    Button {
                        if localDevVPNInstalled {
                            LocalDevVPN.openInstalled()
                        } else {
                            LocalDevVPN.openAppStore()
                        }
                    } label: {
                        Label(
                            localDevVPNInstalled ? "Open LocalDevVPN" : "Get LocalDevVPN (App Store)",
                            systemImage: localDevVPNInstalled ? "lock.shield.fill" : "arrow.down.app.fill"
                        )
                    }
                } header: {
                    Text("Tunnel")
                } footer: {
                    Text("Connect LocalDevVPN before teleporting. Default tunnel IP is 10.7.0.1. Start a spoof on Wi‑Fi first; it can keep working on cellular afterward.")
                }

'''
if tunnel_section not in text:
    raise RuntimeError("Unable to remove Tunnel section")
text = text.replace(tunnel_section, "", 1)


privacy_section = '''                Section("Privacy") {
                    Text("Fully on-device. Favorites and recents stay in UserDefaults. No analytics, no accounts, nothing uploaded.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

'''
if privacy_section not in text:
    raise RuntimeError("Unable to remove Privacy section")
text = text.replace(privacy_section, "", 1)


# Keep only the useful countdown. Renewal/status machinery stays active in the
# background; errors, engine state and manual renewal controls are not shown.
certificate_section = '''                Section {
                    TimelineView(.periodic(from: .now, by: 60)) { context in
                        LabeledContent(
                            "Time remaining",
                            value: MXCertificateRenewal.remainingText(
                                until: certificateExpiration,
                                now: context.date
                            )
                        )
                    }

                    LabeledContent(
                        "Expires",
                        value: MXCertificateRenewal.dateText(certificateExpiration)
                    )

                    LabeledContent(
                        "Last successful renewal",
                        value: MXCertificateRenewal.dateText(certificateLastSuccess)
                    )

                    LabeledContent("Refresh status") {
                        Text(certificateStatus)
                            .foregroundStyle(
                                certificateStatus.hasPrefix("Succeeded")
                                    ? LocusTheme.statusGood
                                    : certificateStatus.hasPrefix("Failed")
                                        ? LocusTheme.statusBad
                                        : LocusTheme.statusWarn
                            )
                    }

                    LabeledContent("Renewal engine") {
                        Text(certificateEngineStatus)
                            .foregroundStyle(
                                certificateEngineReady
                                    ? LocusTheme.statusGood
                                    : LocusTheme.statusWarn
                            )
                    }

                    Button {
                        _ = MXCertificateRenewal.openRenewalSetup()
                    } label: {
                        Label(
                            certificateEngineReady ? "MX Signing Settings" : "Open MX Signing Setup",
                            systemImage: "key.fill"
                        )
                    }

                    Button {
                        guard LocalDevVPN.isConnected else {
                            MXCertificateRenewal.markFailed("Connect LocalDevVPN first")
                            reloadCertificateInfo()
                            return
                        }
                        if MXCertificateRenewal.renewNow() {
                            certificateRefreshRunning = true
                            certificateStatus = "Renewing…"
                        } else {
                            certificateRefreshRunning = false
                        }
                        reloadCertificateInfo()
                    } label: {
                        Label(
                            certificateRefreshRunning ? "Renewing Certificate…" : "Renew Certificate Now",
                            systemImage: "checkmark.shield.fill"
                        )
                    }
                    .disabled(certificateRefreshRunning)
                } header: {
                    Text("Certificate")
                } footer: {
                    Text("One-time setup: open the signing engine built into MX Location, sign in, choose the pairing file, then use + to install this same IPA from Files once. A separate SideStore app is not required. After setup, connect LocalDevVPN before renewing. Renewal stops with an error after 4 minutes instead of hanging.")
                }

'''
minimal_certificate_section = '''                Section {
                    TimelineView(.periodic(from: .now, by: 60)) { context in
                        LabeledContent(
                            "Time remaining",
                            value: MXCertificateRenewal.remainingText(
                                until: certificateExpiration,
                                now: context.date
                            )
                        )
                    }
                }

'''
if certificate_section not in text:
    raise RuntimeError("Unable to simplify Certificate section")
text = text.replace(certificate_section, minimal_certificate_section, 1)

settings.write_text(text, encoding="utf-8")
print("Cleaned MX Location Settings UI at", settings)
