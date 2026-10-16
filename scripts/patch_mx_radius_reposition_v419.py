#!/usr/bin/env python3
"""v4.19: move the existing km capsule to the old green-GPS-dot position.
Position-only change: preserve menu choices, search logic, radius ring and GPS engine.
"""
from pathlib import Path
import sys

root = Path(sys.argv[1]).resolve()
folder = root / "Locus" / "Features" / "Map" if (root / "Locus" / "Features" / "Map").is_dir() else root
p = folder / "MXPlaceExplorer.swift"
s = p.read_text(encoding="utf-8")
old = """                .overlay(alignment: .bottomTrailing) {
                    floatingRadiusMenu
                        .padding(.trailing, 18)
                        .padding(.bottom, 17)
                }"""
new = """                .overlay(alignment: .topTrailing) {
                    // Position of the former green GPS indicator, below the category chips.
                    // Anchored to the top, not to the moving results bottom sheet.
                    floatingRadiusMenu
                        .padding(.trailing, 64)
                        .padding(.top, 92)
                }"""
assert s.count(old) == 1, "Expected one existing bottom-right km control"
assert s.count("private var floatingRadiusMenu: some View") == 1, "Missing km control"
assert r"ForEach([1.0, 3.0, 5.0, 10.0, 15.0], id: \.self)" in s, "Radius options changed unexpectedly"
assert "MapCircle(center: selectedCenter, radius: radiusKM * 1_000)" in s, "Radius ring changed unexpectedly"
assert "session.teleport(to: place.coordinate, pairing: pairing)" in s, "GPS location operation missing"
s = s.replace(old, new, 1)
assert ".overlay(alignment: .bottomTrailing)" not in s
assert s.count(".overlay(alignment: .topTrailing)") >= 1
p.write_text(s, encoding="utf-8")
print("v4.19 PASS: moved km selector only; preserved five choices and original GPS behavior")
