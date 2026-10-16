#!/usr/bin/env python3
"""v4.20 - relocate the existing Places kilometre Menu beside Settings in bottom nav.
Keep radius options, MapKit circle, GPS engine and search semantics unchanged.
"""
from pathlib import Path
import sys

root = Path(sys.argv[1]).resolve()
folder = root/"Locus"/"Features"/"Map"
assert folder.is_dir()
places_file = folder/"MXPlaceExplorer.swift"
root_file = folder/"RootView.swift"
places = places_file.read_text(encoding="utf-8")
tabs = root_file.read_text(encoding="utf-8")

old_overlay = """                .overlay(alignment: .topTrailing) {
                    // Position of the former green GPS indicator, below the category chips.
                    // Anchored to the top, not to the moving results bottom sheet.
                    floatingRadiusMenu
                        .padding(.trailing, 64)
                        .padding(.top, 92)
                }"""
assert places.count(old_overlay) == 1, "Missing v4.19 floating control"
places = places.replace(old_overlay, "", 1)

start=places.index("    private var floatingRadiusMenu: some View {")
end=places.index("    private func results(height: CGFloat) -> some View {", start)
assert places.count("private var floatingRadiusMenu: some View") == 1
floating_body=places[start:end]
assert r"ForEach([1.0, 3.0, 5.0, 10.0, 15.0], id: \.self)" in floating_body
places=places[:start]+places[end:]
old_state="@State private var radiusKM: Double = 5"
new_state='@AppStorage("mx.places.radiusKM") private var radiusKM: Double = 5'
assert places.count(old_state) == 1
places=places.replace(old_state, new_state, 1)
# Restore scroll tail to layout from before overlay toolbar.
old_padding=".padding(.horizontal, 12).padding(.top, 8).padding(.bottom, 78)"
new_padding=".padding(.horizontal, 12).padding(.top, 8).padding(.bottom, 22)"
assert places.count(old_padding) == 1
places=places.replace(old_padding,new_padding,1)

# The compactTabBar is owned by RootView, not the Places map.
anchor="    @State private var selectedTab = 0"
assert tabs.count(anchor)==1
tabs=tabs.replace(anchor, anchor+'\n    '+new_state,1)

old_settings='            compactTabButton(title: "Settings", systemImage: "gearshape.fill", tag: 4)'
new_settings='''            compactTabButton(title: "Settings", systemImage: "gearshape.fill", tag: 4)
            if selectedTab == 3 {
                placesRadiusMenu
            }'''
assert tabs.count(old_settings)==1
tabs=tabs.replace(old_settings,new_settings,1)
# Widen capsule to accommodate the sixth tiny control without truncation;
# parent maxWidth respects narrow screens.
old_width=".frame(width: 282, height: 54)"
new_width=".frame(maxWidth: 360)\n        .frame(height: 54)"
assert tabs.count(old_width)==1
tabs=tabs.replace(old_width,new_width,1)

menu=r'''    private var placesRadiusMenu: some View {
        Menu {
            ForEach([1.0, 3.0, 5.0, 10.0, 15.0], id: \.self) { distance in
                Button {
                    // Shared AppStorage triggers nearby search + MapKit circle.
                    // Do not reset camera or alter spoofed GPS position.
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
            VStack(spacing: 2) {
                Image(systemName: "scope")
                    .font(.system(size: 17, weight: .semibold))
                Text("\(Int(radiusKM)) km")
                    .font(.caption2.weight(.semibold))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(Color.white.opacity(0.91))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
        }
        .accessibilityLabel("Search radius \(Int(radiusKM)) kilometers")
        .accessibilityHint("Choose 1, 3, 5, 10 or 15 kilometers")
    }

'''
needle="    private func compactTabButton(title: String, systemImage: String, tag: Int) -> some View {"
assert tabs.count(needle)==1
tabs=tabs.replace(needle,menu+needle,1)

assert "MapCircle(center: selectedCenter, radius: radiusKM * 1_000)" in places
assert "session.teleport(to: place.coordinate, pairing: pairing)" in places
assert "@AppStorage(" in places and "@AppStorage(" in tabs
assert "floatingRadiusMenu" not in places
assert "private var radiusToolbar:" not in places
assert tabs.count("private var placesRadiusMenu: some View") == 1
assert tabs.count(old_settings) == 1
assert "if selectedTab == 3" in tabs
assert r"ForEach([1.0, 3.0, 5.0, 10.0, 15.0], id: \.self)" in tabs
assert ".safeAreaInset(edge: .bottom, spacing: 2)" in tabs
assert "MapHomeView()" in tabs and "SettingsView()" in tabs
places_file.write_text(places, encoding="utf-8")
root_file.write_text(tabs, encoding="utf-8")
print("PASS v4.20: km Menu after Settings inside bottom nav, same five options, MapKit ring and GPS untouched")
