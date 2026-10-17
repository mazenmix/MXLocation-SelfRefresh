#!/usr/bin/env python3
"""Regression checks: SideStore profile-only refresh cannot update a bundled profile."""
from pathlib import Path
import sys
root=Path(sys.argv[1]).resolve()
settings=(root/"Locus/Features/Settings/SettingsView.swift").read_text(encoding="utf-8")
root_view=(root/"Locus/Features/Map/RootView.swift").read_text(encoding="utf-8")
map_view=(root/"Locus/Features/Map/MapHomeView.swift").read_text(encoding="utf-8")
checks={
    "Seven-day green reference progress UI": 'Text("7-Day Activation")' in settings and "ProgressView(value: progress)" in settings and "0.84, blue: 0.45" in settings,
    "No fabricated automatic SideStore refresh success": 'Yes, refresh succeeded' in settings and 'Verify the actual expiry in SideStore' in settings,
    "User-confirmed renewal retained between launches": '@AppStorage("mx.signing.userConfirmedRefreshAt")' in settings,
    "Only after explicit confirmation" : 'userConfirmedRefreshAt = Date().timeIntervalSince1970' in settings and 'showRefreshConfirmation = true' in settings,
    "Actual embedded profile reading retained": 'MXCertificateInfo.expirationDate()' in settings,
    "Return from SideStore checks profile change": 'current.timeIntervalSince(previous) > 60' in settings,
    "Signing estimate marked clearly": '"Estimated until"' in settings,
    "Orange Renew Certificate remains": 'Text("Renew Certificate")' in settings and '0.98, green: 0.48, blue: 0.16' in settings,
    "Do not change GPS engine": 'session.teleport(to: coordinate, pairing: pairing)' in map_view,
    "Keep physical GPS camera regression fix": 'MapHomeView(position: $retainedMapCamera, cameraMemory: mapCameraMemory)' in root_view and 'cameraMemory.lock($position)' in map_view,
    "Keep 1/3/5/10/15 radius": 'ForEach([1.0, 3.0, 5.0, 10.0, 15.0]' in root_view,
    "Keep Short Stay turquoise": 'shortStayTurquoise' in (root/"Locus/Features/Map/MXPlaceExplorer.swift").read_text(encoding="utf-8"),
}
for name,ok in checks.items():
    print(("PASS " if ok else "FAIL ")+name)
assert all(checks.values()),"Regression contract failed"
print("v4.25 signing countdown refresh + GPS regression contracts passed.")
