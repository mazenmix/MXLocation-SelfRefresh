from pathlib import Path
import sys

path = Path(sys.argv[1]).resolve()
text = path.read_text(encoding="utf-8")

old = '''struct MXNearbyResult: Identifiable {\n    let id = UUID()\n    let name: String\n    let subtitle: String\n    let coordinate: CLLocationCoordinate2D\n}\n\nstruct MXNearbyHotspotsView: View {\n'''
new = '''struct MXNearbyResult: Identifiable {\n    let id = UUID()\n    let name: String\n    let subtitle: String\n    let coordinate: CLLocationCoordinate2D\n}\n\nstruct MXNearbyCategory: Identifiable {\n    let id = UUID()\n    let title: String\n    let query: String\n    let icon: String\n}\n\nstruct MXNearbyHotspotsView: View {\n'''
if old not in text:
    raise RuntimeError("Unable to locate MXNearbyResult")
text = text.replace(old, new, 1)

old = '''    private let categories: [(String, String, String)] = [\n        ("Cafés", "Cafe", "cup.and.saucer.fill"),\n        ("Restaurants", "Restaurant", "fork.knife"),\n        ("Malls", "Shopping Mall", "bag.fill"),\n        ("Hotels", "Hotel", "bed.double.fill"),\n        ("Airports", "Airport", "airplane"),\n        ("Nightlife", "Nightclub Bar", "moon.stars.fill")\n    ]\n'''
new = '''    private let categories: [MXNearbyCategory] = [\n        MXNearbyCategory(title: "Cafés", query: "Cafe", icon: "cup.and.saucer.fill"),\n        MXNearbyCategory(title: "Restaurants", query: "Restaurant", icon: "fork.knife"),\n        MXNearbyCategory(title: "Malls", query: "Shopping Mall", icon: "bag.fill"),\n        MXNearbyCategory(title: "Hotels", query: "Hotel", icon: "bed.double.fill"),\n        MXNearbyCategory(title: "Airports", query: "Airport", icon: "airplane"),\n        MXNearbyCategory(title: "Nightlife", query: "Nightclub Bar", icon: "moon.stars.fill")\n    ]\n'''
if old not in text:
    raise RuntimeError("Unable to locate nearby categories")
text = text.replace(old, new, 1)

old = '''                        ForEach(categories, id: \\.0) { item in\n                            Button {\n                                selectedQuery = item.0\n                                search(item.1)\n                            } label: {\n                                Label(item.0, systemImage: item.2)\n                            }\n'''
new = '''                        ForEach(categories) { item in\n                            Button {\n                                selectedQuery = item.title\n                                search(item.query)\n                            } label: {\n                                Label(item.title, systemImage: item.icon)\n                            }\n'''
if old not in text:
    raise RuntimeError("Unable to locate nearby category ForEach")
text = text.replace(old, new, 1)

path.write_text(text, encoding="utf-8")
print("Hardened travel suite template", path)
