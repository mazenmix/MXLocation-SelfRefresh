#!/usr/bin/env python3
"""v4.26: strict explicit GPS zoom; installed real signing profile reader."""
from pathlib import Path
import shutil
import sys

root=Path(sys.argv[1]).resolve()
mapdir=root/"Locus/Features/Map"
support=root/"Locus/Support"
settings=root/"Locus/Features/Settings/SettingsView.swift"
spoof=root/"Locus/Engine/SpoofSession.swift"
rootview=mapdir/"RootView.swift"
memory=mapdir/"MXMapCameraMemory.swift"

src=Path(__file__).resolve().parents[1]/"overlays/MXInstalledProvisionReader.swift"
assert src.is_file()
shutil.copy2(src, support/"MXInstalledProvisionReader.swift")
assert "MXInstalledProvisionReader.installedExpiration" in settings.read_text(encoding="utf-8")

sp=spoof.read_text(encoding="utf-8")
old="    @Published var simulated: CLLocationCoordinate2D?"
assert sp.count(old)==1
sp=sp.replace(old,old+"\n    // Bumps only on an explicit, successful Change Location action, never GPS heartbeat/joystick.\n    @Published var manualTeleportRevision: UInt64 = 0",1)
old_action="""        pin = coordinate
        apply(coordinate, pairing: pairing, markRecent: true)
    }

    func stop(pairing: PairingStore) {"""
new_action="""        pin = coordinate
        apply(coordinate, pairing: pairing, markRecent: true)
        if isSpoofing {
            manualTeleportRevision &+= 1
        }
    }

    func stop(pairing: PairingStore) {"""
assert sp.count(old_action)==1
sp=sp.replace(old_action,new_action,1)
spoof.write_text(sp,encoding="utf-8")

root_text=rootview.read_text(encoding="utf-8")
old_listener="""        // Real phone GPS updates must never re-center this map by themselves.
        // An explicit simulated-location change may switch countries without changing zoom.
        .onChange(of: session.simulated?.latitude) { previousLatitude, newLatitude in
            guard previousLatitude != newLatitude,
                  let target = session.simulated else { return }
            mapCameraMemory.moveToChosenLocation(target, position: $retainedMapCamera)
        }"""
new_listener="""        // Only the *explicit successful Change Location* button changes zoom.
        // Do not react to background reconnect, GPS location updates,
        // simulated route movement, joystick movement, or switching tabs.
        .onChange(of: session.manualTeleportRevision) { _, _ in
            guard let target = session.simulated else { return }
            mapCameraMemory.moveToChosenLocation(target, position: $retainedMapCamera)
        }"""
assert root_text.count(old_listener)==1
root_text=root_text.replace(old_listener,new_listener,1)
rootview.write_text(root_text,encoding="utf-8")

m=memory.read_text(encoding="utf-8")
old_zoom="""        let before = lastCamera
        let next = MapCamera(
            centerCoordinate: target,
            distance: before?.distance ?? 2500,
            heading: before?.heading ?? 0,
            pitch: before?.pitch ?? 0
        )"""
new_zoom="""        let next = MapCamera(
            centerCoordinate: target,
            distance: 1800,
            heading: 0,
            pitch: 0
        )"""
assert m.count(old_zoom)==1
m=m.replace(old_zoom,new_zoom,1)
memory.write_text(m,encoding="utf-8")

assert 'session.manualTeleportRevision' in root_text
assert 'session.simulated?.latitude' not in root_text
assert 'manualTeleportRevision &+= 1' in sp
assert 'MXInstalledProvisionReader.swift' in str(support/"MXInstalledProvisionReader.swift")
assert '@Binding var position: MapCameraPosition' in (mapdir/"MapHomeView.swift").read_text(encoding="utf-8")
assert 'MapCamera(' in m and 'distance: 1800' in m
print("PASS v4.26: only explicit successful teleport zooms to 1.8 km. Installed profile expiry query added.")
