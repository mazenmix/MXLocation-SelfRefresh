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

# The exact MX icon is rendered by render_user_mx_icon.swift before this patch runs.
icon_source = repo_root / "assets/MXAppIcon1024.png"
if not icon_source.exists():
    raise RuntimeError(f"Missing rendered MX icon: {icon_source}")

# Reuse the same exact icon inside Settings.
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

# Critical Home Screen icon fix:
# Upstream also includes an Icon Composer package named AppIcon.icon. It was
# winning over Assets.xcassets/AppIcon.appiconset, so SideStore could show the
# new MX icon while SpringBoard still displayed the old colored Locus icon.
# Remove AppIcon.icon from the generated Xcode project and compile only the
# AppIcon.appiconset that the workflow replaces with the MX image.
project = root / "project.yml"
text = project.read_text(encoding="utf-8")
text = text.replace("      - path: AppIcon.icon\n", "")
text = text.replace('MARKETING_VERSION: "1.0.2"', 'MARKETING_VERSION: "1.2.5"')
text = text.replace('CURRENT_PROJECT_VERSION: "3"', 'CURRENT_PROJECT_VERSION: "18"')
project.write_text(text, encoding="utf-8")

print("Applied MX Location clean UI v1.2.5 with favorite rename and compiled Home Screen MX icon at", root)
