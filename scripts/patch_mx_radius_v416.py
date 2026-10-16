#!/usr/bin/env python3
"""Compact GPS toolbar: distance menu with 1/5/10/15 km beside GPS; no green dot.
Deliberately touch only MXPlaceExplorer toolbar, retaining GPS mechanics and MapKit.
"""
from pathlib import Path
import sys

root = Path(sys.argv[1])
src_dir = root / 'Locus' / 'Features' / 'Map' if (root / 'Locus' / 'Features' / 'Map').is_dir() else root
path = src_dir / 'MXPlaceExplorer.swift'
s = path.read_text(encoding='utf-8')
old = '''            Button { showingGPSHistory = true } label: {
                HStack(spacing: 4) {
                    Image(systemName: "location.fill")
                    Text("GPS")
                    Circle().fill(gpsIndicator.color)
                        .frame(width: 7, height: 7)
                }
                .font(.caption.bold())
            }
            .accessibilityLabel("GPS: \\(gpsIndicator.label). Open simulation history")
            Button { showingRoute = true } label: {
                Image(systemName: "point.topleft.down.curvedto.point.bottomright.up")
                    .font(.subheadline.bold())
                    .overlay(alignment: .topTrailing) {
                        if !travelLibrary.itinerary.isEmpty {
                            Circle().fill(.blue).frame(width: 7, height: 7)
                        }
                    }
            }
            .accessibilityLabel("MX Route Planner")
            Menu {
                ForEach([1.0, 3.0, 5.0, 10.0, 25.0], id: \\.self) { value in
                    Button("\\(Int(value)) km") { radiusKM = value }
                }
            } label: {
                Label("\\(Int(radiusKM)) km", systemImage: "slider.horizontal.3")
                    .font(.caption.bold())
            }'''
new = '''            Button { showingGPSHistory = true } label: {
                HStack(spacing: 4) {
                    Image(systemName: "location.fill")
                    Text("GPS")
                }
                .font(.caption.bold())
            }
            .accessibilityLabel("GPS: \\(gpsIndicator.label). Open simulation history")
            Menu {
                ForEach([1.0, 5.0, 10.0, 15.0], id: \\.self) { value in
                    Button {
                        radiusKM = value
                    } label: {
                        if radiusKM == value {
                            Label("\\(Int(value)) km", systemImage: "checkmark.circle.fill")
                        } else {
                            Text("\\(Int(value)) km")
                        }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "scope")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(selectedColor)
                        .frame(width: 25, height: 25)
                        .background(selectedColor.opacity(0.16), in: Circle())
                    Text("\\(Int(radiusKM)) km")
                        .font(.caption.bold())
                        .monospacedDigit()
                        .lineLimit(1)
                }
            }
            .accessibilityLabel("Search radius: \\(Int(radiusKM)) kilometers. Choose 1, 5, 10, or 15 kilometers")
            Button { showingRoute = true } label: {
                Image(systemName: "point.topleft.down.curvedto.point.bottomright.up")
                    .font(.subheadline.bold())
                    .overlay(alignment: .topTrailing) {
                        if !travelLibrary.itinerary.isEmpty {
                            Circle().fill(.blue).frame(width: 7, height: 7)
                        }
                    }
            }
            .accessibilityLabel("MX Route Planner")'''
assert s.count(old) == 1, f'Unexpected source toolbar shape: expected 1, found {s.count(old)}'
s = s.replace(old, new, 1)
assert s.count('@State private var radiusKM: Double = 5') == 1
assert 'ForEach([1.0, 5.0, 10.0, 15.0], id: \\.self)' in s
assert 'Circle().fill(gpsIndicator.color)' not in s.split('private var radiusToolbar: some View {', 1)[1].split('private func results(', 1)[0], 'GPS green dot still visible in toolbar'
assert 'session.teleport(to: place.coordinate, pairing: pairing)' in s
# Keep the Discover tab's existing quick-range choices consistent with Places.
discovery_path = src_dir / 'MXProDiscovery.swift'
d = discovery_path.read_text(encoding='utf-8')
discover_before = 'ForEach([1.0, 5.0, 10.0, 25.0], id: \\.self)'
discover_after = 'ForEach([1.0, 5.0, 10.0, 15.0], id: \\.self)'
assert d.count(discover_before) == 1, 'Unexpected Discover range selector'
d = d.replace(discover_before, discover_after, 1)
feature_before = 'Limit nearby discovery to 1, 5, 10 or 25 kilometres.'
assert d.count(feature_before) == 1
# Commit both files only after their assertions have passed.
discovery_path.write_text(d.replace(feature_before, 'Limit nearby discovery to 1, 5, 10 or 15 kilometres.'), encoding='utf-8')
path.write_text(s, encoding='utf-8')
print('MX Location Pro v4.16: 1 / 5 / 10 / 15 km; selected circular icon beside GPS; green toolbar dot removed. GPS untouched.')