#!/usr/bin/env python3
"""Route MX Location Pro external map actions to Google Maps (native or web fallback).
No changes to built-in MapKit rendering, route calculations, pairing or GPS simulation.
"""
from pathlib import Path
import re
import sys

root = Path(sys.argv[1]) if len(sys.argv) > 1 else Path('/mnt/data/work_mx_quality/Sources')
# Accept either full Locus project root or source overlay directory.
sources = root / 'Locus/Features/Map' if (root / 'Locus/Features/Map').exists() else root
assert sources.is_dir(), sources

helper = r'''import CoreLocation
import Foundation
import UIKit

/// External maps open in Google Maps. If the native application is missing,
/// launch Google Maps in the browser rather than falling back to Apple Maps.
@MainActor
enum MXGoogleMapsLauncher {
    static func open(coordinate: CLLocationCoordinate2D) {
        guard CLLocationCoordinate2DIsValid(coordinate) else { return }
        let location = String(format: "%.6f,%.6f", coordinate.latitude, coordinate.longitude)
        var native = URLComponents(string: "comgooglemaps://")
        native?.queryItems = [URLQueryItem(name: "q", value: location)]
        var web = URLComponents(string: "https://www.google.com/maps/search/")
        web?.queryItems = [URLQueryItem(name: "api", value: "1"),
                           URLQueryItem(name: "query", value: location)]
        guard let webURL = web?.url else { return }
        guard let nativeURL = native?.url else {
            UIApplication.shared.open(webURL)
            return
        }
        UIApplication.shared.open(nativeURL, options: [:]) { didOpen in
            if !didOpen {
                // The native Google Maps app is not installed. Never open Apple Maps.
                UIApplication.shared.open(webURL)
            }
        }
    }
}
'''
(sources / 'MXGoogleMapsLauncher.swift').write_text(helper, encoding='utf-8')

def replace_once(name: str, before: str, after: str):
    file = sources / name
    s = file.read_text(encoding='utf-8')
    n = s.count(before)
    if n != 1:
        raise RuntimeError(f'{name}: expected 1 occurrence, got {n}: {before[:100]!r}')
    file.write_text(s.replace(before, after, 1), encoding='utf-8')

replace_once('MXProDiscovery.swift', '''                Button {
                    let item = MKMapItem(placemark: MKPlacemark(coordinate: place.coordinate))
                    item.name = place.name
                    item.openInMaps(launchOptions: nil)
                } label: { Image(systemName: "arrow.up.right.square") }''', '''                Button {
                    MXGoogleMapsLauncher.open(coordinate: place.coordinate)
                } label: { Image(systemName: "arrow.up.right.square") }
                    .accessibilityLabel("Open in Google Maps")''')

replace_once('MXPlaceExplorer.swift', '''                        Button {
                            let item = MKMapItem(placemark: MKPlacemark(coordinate: place.coordinate))
                            item.name = place.name
                            item.openInMaps(launchOptions: nil)
                        } label: { Label("Directions in Apple Maps", systemImage: "arrow.triangle.turn.up.right.diamond") }
                        if let googleURL = URL(string: "https://www.google.com/maps/search/?api=1&query=\\(place.coordinate.latitude),\\(place.coordinate.longitude)") {
                            Link(destination: googleURL) {
                                Label("Open in Google Maps", systemImage: "map")
                            }
                        }''', '''                        Button {
                            MXGoogleMapsLauncher.open(coordinate: place.coordinate)
                        } label: {
                            Label("Open in Google Maps", systemImage: "map")
                        }''')

p = sources / 'MXProToolbox.swift'
s = p.read_text(encoding='utf-8')
# Each of these is an external Apple Maps launch; local map renderers and MapKit
# routing are deliberately left untouched.
pattern = re.compile(r'MKMapItem\(placemark:\s*MKPlacemark\(coordinate:\s*(\w+(?:\.coordinate)?)\)\)\.openInMaps\(launchOptions:\s*nil\)')
s, count = pattern.subn(lambda m: 'MXGoogleMapsLauncher.open(coordinate: ' + m.group(1) + ')', s)
if count != 6:
    raise RuntimeError(f'Expected 6 external openInMaps calls in MXProToolbox.swift, found {count}')
s = s.replace('Open final stop in Apple Maps', 'Open final stop in Google Maps')
s = s.replace('Button("Open selected area in Maps")', 'Button("Open selected area in Google Maps")')
p.write_text(s, encoding='utf-8')

for file in ('MXProDiscovery.swift', 'MXPlaceExplorer.swift', 'MXProToolbox.swift'):
    s = (sources / file).read_text(encoding='utf-8')
    assert '.openInMaps(' not in s, f'Residual Apple Maps launcher in {file}'
    assert 'MXGoogleMapsLauncher.open' in s
assert 'comgooglemaps://' in helper and 'https://www.google.com/maps/search/' in helper
print('MX Location Pro Google Maps v4.15: 8 external map actions updated; native Google Maps with Google web fallback.')