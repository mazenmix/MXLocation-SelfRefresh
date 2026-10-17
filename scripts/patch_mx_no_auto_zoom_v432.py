#!/usr/bin/env python3
"""v4.32: no implicit zoom, ever. Search, tabs, Settings and Change Location preserve it."""
from pathlib import Path
import sys
root = Path(sys.argv[1]).resolve()
memory = root/"Locus/Features/Map/MXMapCameraMemory.swift"
s = memory.read_text(encoding="utf-8")
old = "distance: max(5400, min(11000, lastCamera?.distance ?? 5400)),"
new = "distance: max(10, lastCamera?.distance ?? position.wrappedValue.camera?.distance ?? 5500),"
assert s.count(old) == 1, "Expected former auto-zoom clamp was not found"
s = s.replace(old, new, 1)
assert "heading: 0" in s and "pitch: 0" in s
# Even teleporting must not silently reset compass heading or map tilt.
s = s.replace("""            heading: 0,
            pitch: 0
        )
        observe(next)""", """            heading: lastCamera?.heading ?? position.wrappedValue.camera?.heading ?? 0,
            pitch: lastCamera?.pitch ?? position.wrappedValue.camera?.pitch ?? 0
        )
        observe(next)""", 1)
assert "pitch: lastCamera?.pitch" in s
memory.write_text(s, encoding="utf-8")
print("PASS v4.32: manual teleport preserves exact user zoom, bearing and pitch")
