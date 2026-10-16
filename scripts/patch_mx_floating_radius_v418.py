#!/usr/bin/env python3
"""MX Pro v4.18: replace Places GPS/coordinate bar with a bottom-right 1/3/5/10/15 km menu.
Keep the existing MapKit radius ring and all GPS engine, pin and session operations intact.
"""
from pathlib import Path
import sys

root = Path(sys.argv[1]).resolve()
folder = root / "Locus" / "Features" / "Map" if (root / "Locus" / "Features" / "Map").is_dir() else root
path = folder / "MXPlaceExplorer.swift"
src = path.read_text(encoding="utf-8")

# Only remove the visual Places toolbar, not the GPS / route models or existing sheets.
needle = """                    modePicker
                    categoryPicker
                    radiusToolbar
                    if needsAreaSearch {"""
replacement = """                    modePicker
                    categoryPicker
                    if needsAreaSearch {"""
assert src.count(needle) == 1, "Cannot locate unique Places toolbar insertion"
src = src.replace(needle, replacement, 1)

start = src.index("    private var radiusToolbar: some View {")
end = src.index("    private func results(height: CGFloat) -> some View {", start)
assert src.count("    private var radiusToolbar: some View {") == 1
toolbar = src[start:end]
assert "showingGPSHistory" in toolbar and "showingRoute" in toolbar
assert "ForEach([1.0, 5.0, 10.0, 15.0]" in toolbar

floating = r'''    private var floatingRadiusMenu: some View {
        Menu {
            ForEach([1.0, 3.0, 5.0, 10.0, 15.0], id: \.self) { distance in
                Button {
                    // Search and the radius ring update without a camera reset/zoom animation.
                    var transaction = Transaction()
                    transaction.disablesAnimations = true
                    withTransaction(transaction) { radiusKM = distance }
                } label: {
                    if radiusKM == distance {
                        Label("\(Int(distance)) km", systemImage: "checkmark")
                    } else {
                        Text("\(Int(distance)) km")
                    }
                }
            }
        } label: {
            HStack(spacing: 7) {
                Image(systemName: "scope")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(selectedColor)
                Text("\(Int(radiusKM)) km")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 15)
            .frame(height: 46)
            .background(Color(red: 0.075, green: 0.105, blue: 0.19).opacity(0.96),
                        in: Capsule())
            .overlay(Capsule().stroke(selectedColor.opacity(0.44), lineWidth: 1))
            .shadow(color: .black.opacity(0.30), radius: 9, x: 0, y: 3)
        }
        .accessibilityLabel("Search radius \(Int(radiusKM)) kilometers")
        .accessibilityHint("Choose 1, 3, 5, 10 or 15 kilometers")
    }

'''
src = src[:start] + floating + src[end:]

# Put the control at the bottom-right of the Places canvas, just above the tab bar.
# Keep it outside ScrollView and Map rendering so sheet drag/scroll never moves the button.
anchor = """                .padding(.horizontal, 12)
                .padding(.top, 9)
                .padding(.bottom, 6)
            }
            .background(background)"""
floating_anchor = """                .padding(.horizontal, 12)
                .padding(.top, 9)
                .padding(.bottom, 6)
                .overlay(alignment: .bottomTrailing) {
                    floatingRadiusMenu
                        .padding(.trailing, 18)
                        .padding(.bottom, 17)
                }
            }
            .background(background)"""
assert src.count(anchor) == 1, "Unable to anchor bottom-right button safely"
src = src.replace(anchor, floating_anchor, 1)

# Reserve a small safe scroll tail so last card remains selectable beneath the floating control.
old_pad = ".padding(.horizontal, 12).padding(.top, 8).padding(.bottom, 22)"
new_pad = ".padding(.horizontal, 12).padding(.top, 8).padding(.bottom, 78)"
assert src.count(old_pad) == 1
src = src.replace(old_pad, new_pad, 1)

# Keep radius ring in map, Search This Area, route sheet, pair status and GPS operations untouched.
assert "MapCircle(center: selectedCenter, radius: radiusKM * 1_000)" in src
assert "session.teleport(to: place.coordinate, pairing: pairing)" in src
assert ".sheet(isPresented: $showingRoute)" in src
assert ".sheet(isPresented: $showingGPSHistory)" in src
assert "private var radiusToolbar" not in src
assert "                    radiusToolbar" not in src
assert "ForEach([1.0, 3.0, 5.0, 10.0, 15.0], id: \\.self)" not in src  # escaping guard
assert r"ForEach([1.0, 3.0, 5.0, 10.0, 15.0], id: \.self)" in src
assert "@State private var radiusKM: Double = 5" in src
path.write_text(src, encoding="utf-8")
print("MX Pro v4.18: removed GPS/coordinate bar, pinned radius menu bottom-right, 1/3/5/10/15 km, MapKit ring retained")
