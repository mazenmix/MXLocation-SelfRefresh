#!/usr/bin/env python3
"""Install reviewed, image-free GPS-first venue UI into the isolated Xcode workspace."""
import base64
import hashlib
import json
from pathlib import Path
import sys
import zlib

root = Path(sys.argv[1]).resolve()
packed = Path(__file__).resolve().parents[1] / "polish_src_payload.json"
files = json.loads(packed.read_text(encoding="utf-8"))
expected = {"Sources/MXPlaceExplorer.swift", "Sources/MXPlacePhotos.swift", "Sources/MXPlaceTaxonomy.swift",
            "Sources/MXProDataServices.swift", "Sources/MXProDiscovery.swift",
            "Sources/MXProPrivateTools.swift", "Sources/MXProSinglesAccount.swift",
            "Sources/MXProToolbox.swift", "Assets/MXProIcon1024.png"}
assert set(files) == expected, "Unexpected file set in bundled polish update"
for rel, content in files.items():
    path = root / rel
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(zlib.decompress(base64.b64decode(content, validate=True)))
    print("Installed", rel, len(path.read_bytes()), "bytes")
sources = [p.read_text(encoding="utf-8") for p in (root/"Sources").glob("*.swift")]
combined = "\n".join(sources)
assert "MXPlacePhotoView(" not in combined, "Photo thumbnails must be disabled"
assert "MKMapSnapshotter" not in combined, "No satellite snapshots may be requested"
assert "MXPlacePhotoSettingsView" not in combined, "Photo settings must not appear"
assert "session.teleport(to: place.coordinate, pairing: pairing)" in combined, "Keep place GPS teleport control"
assert "session.teleport(to: recent.coordinate, pairing: pairing)" in combined, "Keep GPS history"
assert "DragGesture(" in combined and ".updating($handleDrag)" not in combined, "Only snapped gestures for sheet"
assert hashlib.sha256((root/"Assets/MXProIcon1024.png").read_bytes()).hexdigest() == "912a967aec30e560ebb5ba9dd584670173348a82adee4f42bbe27c4d5da19180"
print("Verified GPS First UI contract + supplied MX logo")
