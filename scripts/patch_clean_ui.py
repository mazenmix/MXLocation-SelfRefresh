from pathlib import Path
import json
import shutil
import sys

root = Path(sys.argv[1]).resolve()
repo_root = Path(__file__).resolve().parent.parent

# Replace the visible app shell with the clean Map / Saved / Settings experience.
replacements = {
    repo_root / "overlays/MXCleanRootView.swift": root / "Locus/Features/Map/RootView.swift",
    repo_root / "overlays/MXCleanMapHomeView.swift": root / "Locus/Features/Map/MapHomeView.swift",
    repo_root / "overlays/MXCleanSettingsView.swift": root / "Locus/Features/Settings/SettingsView.swift",
}

for source, destination in replacements.items():
    if not source.exists():
        raise RuntimeError(f"Missing overlay: {source}")
    destination.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(source, destination)

# Use the MX black/white icon for Settings branding.
icon_source = repo_root / "assets/MXAppIcon1024.png"
if not icon_source.exists():
    raise RuntimeError(f"Missing MX icon: {icon_source}")

assets_root = root / "Locus/Resources/Assets.xcassets"
icon_set = assets_root / "MXIcon.imageset"
icon_set.mkdir(parents=True, exist_ok=True)

for filename in ("MXIcon.png", "MXIcon@2x.png", "MXIcon@3x.png"):
    shutil.copy2(icon_source, icon_set / filename)

contents = {
    "images": [
        {"filename": "MXIcon.png", "idiom": "universal", "scale": "1x"},
        {"filename": "MXIcon@2x.png", "idiom": "universal", "scale": "2x"},
        {"filename": "MXIcon@3x.png", "idiom": "universal", "scale": "3x"},
    ],
    "info": {"author": "xcode", "version": 1},
}
(icon_set / "Contents.json").write_text(json.dumps(contents, indent=2) + "\n", encoding="utf-8")

# IMPORTANT: upstream Locus also ships an Icon Composer package named AppIcon.icon.
# That package was overriding the AppIcon.appiconset image on the iPhone Home Screen,
# which is why SideStore showed the new MX icon while iOS still showed the old colored icon.
# Remove the Icon Composer source so Xcode compiles only our AppIcon.appiconset.
project = root / "project.yml"
text = project.read_text(encoding="utf-8")
text = text.replace("      - path: AppIcon.icon\n", "")
text = text.replace('MARKETING_VERSION: "1.0.2"', 'MARKETING_VERSION: "1.2.3"')
text = text.replace('CURRENT_PROJECT_VERSION: "3"', 'CURRENT_PROJECT_VERSION: "16"')
project.write_text(text, encoding="utf-8")

print("Applied MX Location clean UI v1.2.3 with Home Screen MX icon fix at", root)
