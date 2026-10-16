#!/usr/bin/env python3
"""v4.22 – small visual-only Short Stay turquoise accent on Places mode chip."""
from pathlib import Path
import sys
base=Path(sys.argv[1]).resolve()
path=base/"Locus"/"Features"/"Map"/"MXPlaceExplorer.swift"
s=path.read_text(encoding="utf-8")
key='    private let spaBlue = Color(red: 0.1, green: 0.59, blue: 1.0)'
assert s.count(key)==1, "Could not find shared category colors"
s=s.replace(key, key+'\n    private let shortStayTurquoise = Color(red: 0.30, green: 0.78, blue: 0.77)',1)
old='    private var selectedColor: Color { category == .spa ? spaBlue : (category == .stripClubs ? Color.pink : Color(red: 0.58, green: 0.40, blue: 0.99)) }'
new='    private var selectedColor: Color { category == .shortStayHotels ? shortStayTurquoise : (category == .spa ? spaBlue : (category == .stripClubs ? Color.pink : Color(red: 0.58, green: 0.40, blue: 0.99))) }'
assert s.count(old)==1, "Unable to update category accent"
s=s.replace(old,new,1)
# Always distinguish Short Stay subtly, even when not selected.
old='.background(mode == option ? selectedColor : .black.opacity(0.7), in: Capsule())'
new='.background(option == .shortStay ? (mode == option ? shortStayTurquoise : shortStayTurquoise.opacity(0.23)) : (mode == option ? selectedColor : Color.black.opacity(0.7)), in: Capsule())'
assert s.count(old)==1, "Unable to identify category mode chip"
s=s.replace(old,new,1)
assert 'session.teleport(to: place.coordinate, pairing: pairing)' in s
assert 'MapCircle(center: selectedCenter, radius: radiusKM * 1_000)' in s
assert 'private var placesRadiusMenu' not in s
assert 'selectedColor : Color.black.opacity(0.7)' in s
assert s.count('shortStayTurquoise') >= 4
path.write_text(s,encoding="utf-8")
print("PASS: Short Stay chip light turquoise, unchanged GPS and bottom-tab radius selector")
