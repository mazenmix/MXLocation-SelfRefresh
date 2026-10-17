#!/usr/bin/env python3
"""v4.28 UI: Apple/OSM selection in Settings, 3D & native Apple Transit,
and a lighter, license-compliant attribution label.

Only changes MapHomeView / SettingsView; not GPS engine or location persistence.
"""
from pathlib import Path
import sys
root=Path(sys.argv[1]).resolve()
maps=root/"Locus/Features/Map/MapHomeView.swift"
settings=root/"Locus/Features/Settings/SettingsView.swift"
a=maps.read_text(encoding="utf-8")
b=settings.read_text(encoding="utf-8")

# Remove provider UI from the map while leaving engine selection and switching functional.
start=a.index("    private var mapLayerMenu: some View {")
end=a.index("    private var locateButton: some View {",start)
assert start>0 and end>start
a=a[:start]+a[end:]
old="""                HStack(spacing: 8) {
                    Spacer()
                    mapLayerMenu
                    locateButton
                }"""
new="""                HStack {
                    Spacer()
                    locateButton
                }"""
assert a.count(old)==1
a=a.replace(old,new,1)

# Keep visible attribution to comply with OSMF tile licensing, but compress
# the giant bottom-left capsule to a tiny low-contrast footer.
old_attr='''                        Link("© OpenStreetMap contributors",
                             destination: URL(string: "https://www.openstreetmap.org/copyright")!)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.primary)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 5)
                            .background(.regularMaterial, in: Capsule())
                            .padding(.leading, 9)
                            .padding(.bottom, 95)'''
new_attr='''                        Link("© OpenStreetMap contributors",
                             destination: URL(string: "https://www.openstreetmap.org/copyright")!)
                            .font(.system(size: 9, weight: .regular))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .background(.thinMaterial,
                                        in: RoundedRectangle(cornerRadius: 4))
                            .padding(.leading, 5)
                            .padding(.bottom, 84)'''
assert a.count(old_attr)==1
a=a.replace(old_attr,new_attr,1)
# While Apple Maps is selected, enable full realistic geometry. Native 3D requires
# sufficient camera pitch and zoom, requested separately by settings action.
assert ".mapStyle(.standard(elevation: .realistic))" in a
state='    @AppStorage("mx.map.provider") private var mapProvider = "apple"'
assert a.count(state)==1
a=a.replace(state,state+'''
    @AppStorage("mx.map.3dRequest") private var apple3DRequest = 0
    @AppStorage("mx.map.3dHandled") private var apple3DHandled = 0''',1)
needle='''            if session.requestedMapPreview == nil {
                cameraMemory.lock($position)
            }'''
insert='''            if session.requestedMapPreview == nil {
                cameraMemory.lock($position)
            }
            if mapProvider == "apple", apple3DRequest != apple3DHandled {
                enableRealistic3DCamera()
            }'''
assert a.count(needle)==1
a=a.replace(needle,insert,1)
method_anchor="    private var searchBar: some View {"
assert a.count(method_anchor)==1
a=a.replace(method_anchor,'''    private func enableRealistic3DCamera() {
        defer { apple3DHandled = apple3DRequest }
        guard let current = cameraMemory.lastCamera ?? position.camera else { return }
        let next = MapCamera(centerCoordinate: current.centerCoordinate,
                             distance: min(current.distance, 1500),
                             heading: current.heading,
                             pitch: 57)
        cameraMemory.observe(next)
        cameraMemory.save()
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) { position = .camera(next) }
    }

'''+method_anchor,1)
# MapHome is re-created on tab changes, so only handle a fresh explicit settings
# action, never force pitch on ordinary tab switches.
assert "apple3DRequest != apple3DHandled" in a
assert "mapLayerMenu" not in a
assert "Map(position: $position)" in a and "session.teleport(to: coordinate, pairing: pairing)" in a

# Settings: add persistent display choices and Apple's real Transit map in Maps app.
state_line='    @State private var checkingInstalledProfile = false'
assert b.count(state_line)==1
b=b.replace(state_line,state_line+'''
    @AppStorage("mx.map.provider") private var mapProvider = "apple"
    @AppStorage("mx.map.3dRequest") private var apple3DRequest = 0''',1)
old_vstack='''                        activationCard
                        sideStoreButton

                        Text("MazenmiX")'''
new_vstack='''                        activationCard
                        sideStoreButton
                        mapSettingsCard

                        Text("MazenmiX")'''
assert b.count(old_vstack)==1
b=b.replace(old_vstack,new_vstack,1)

# A separate map provider control avoids any overlay obscuring the user's map.
anchor="    private var sideStoreButton: some View {"
assert b.count(anchor)==1
block='''    private var mapSettingsCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Map Settings", systemImage: "map")
                .font(.headline.weight(.bold))
                .foregroundStyle(.white)

            Picker("Map Provider", selection: $mapProvider) {
                Text("Apple Maps").tag("apple")
                Text("OpenStreetMap").tag("osm")
            }
            .pickerStyle(.segmented)
            .accessibilityLabel("Choose Apple Maps or OpenStreetMap")

            if mapProvider == "apple" {
                Button {
                    apple3DRequest += 1
                } label: {
                    Label("Show 3D Buildings", systemImage: "building.2.crop.circle")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white)
                Text("3D buildings appear where Apple Maps supports them. Return to Map to see the tilted close-up.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Button {
                    openAppleTransit()
                } label: {
                    HStack {
                        Label("Transit Map", systemImage: "tram.fill")
                        Spacer()
                        Image(systemName: "arrow.up.right.square")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white)
                Text("Opens Apple's genuine Transit map for your last viewed location.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("OpenStreetMap displays colorful 2D map tiles for smoother zooming.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Link("© OpenStreetMap contributors",
                     destination: URL(string: "https://www.openstreetmap.org/copyright")!)
                    .font(.caption)
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous)
            .fill(Color.white.opacity(0.07)))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
            .stroke(Color.white.opacity(0.07), lineWidth: 1))
    }

    private func openAppleTransit() {
        let saved = UserDefaults.standard.dictionary(forKey: "mxlocation.map.lastCamera.v1")
        guard let lat = saved?["latitude"] as? Double,
              let lon = saved?["longitude"] as? Double,
              (-90...90).contains(lat), (-180...180).contains(lon)
        else { return }
        let distance = min(max(saved?["distance"] as? Double ?? 4500, 600), 30000)
        var parts = URLComponents()
        parts.scheme = "https"
        parts.host = "maps.apple.com"
        parts.path = "/frame"
        parts.queryItems = [
            URLQueryItem(name: "map", value: "transit"),
            URLQueryItem(name: "center", value: "\\(lat),\\(lon)"),
            URLQueryItem(name: "distance", value: "\\(Int(distance))")
        ]
        guard let url = parts.url else { return }
        UIApplication.shared.open(url)
    }

'''
b=b.replace(anchor,block+anchor,1)
assert "Text(\"Renew Certificate\")" in b
assert "openAppleTransit()" in b
assert "Picker(\"Map Provider\", selection: $mapProvider)" in b
assert "© OpenStreetMap contributors" in a and "© OpenStreetMap contributors" in b
settings.write_text(b,encoding="utf-8")
maps.write_text(a,encoding="utf-8")
print("PASS v4.28: chooser in Settings, Apple 3D button, native Apple Transit mode, tiny OSM credit, original GPS intact")
