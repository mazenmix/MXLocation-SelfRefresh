from pathlib import Path
import base64
import json
import shutil
import subprocess
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

# Build the user's exact black/white MX icon from the supplied source before
# Xcode compiles Assets.car. iOS uses the compiled asset catalog for the Home
# Screen icon, so replacing loose AppIcon PNGs after the build is not enough.
exact_b64 = repo_root / "assets/MXExactIconSource.jpg.b64"
icon_source = repo_root / "assets/MXAppIcon1024.png"
if not exact_b64.exists():
    raise RuntimeError(f"Missing exact MX icon source: {exact_b64}")

raw_jpg = repo_root / "assets/.MXExactIconSource.jpg"
cropped_jpg = repo_root / "assets/.MXExactIconCropped.jpg"
resized_jpg = repo_root / "assets/.MXExactIcon1024.jpg"
raw_jpg.write_bytes(base64.b64decode(exact_b64.read_text(encoding="utf-8").strip()))

try:
    subprocess.run(
        ["sips", "-c", "1179", "1179", str(raw_jpg), "--out", str(cropped_jpg)],
        check=True,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.STDOUT,
    )
    subprocess.run(
        ["sips", "-z", "1024", "1024", str(cropped_jpg), "--out", str(resized_jpg)],
        check=True,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.STDOUT,
    )
    subprocess.run(
        ["sips", "-s", "format", "png", str(resized_jpg), "--out", str(icon_source)],
        check=True,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.STDOUT,
    )
finally:
    for temporary in (raw_jpg, cropped_jpg, resized_jpg):
        temporary.unlink(missing_ok=True)

if not icon_source.exists():
    raise RuntimeError(f"Failed to generate exact MX icon: {icon_source}")

# Reuse the exact icon inside Settings too.
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

# Version this exact-icon build as 1.2.2 / build 15 while preserving bundle ID.
project = root / "project.yml"
text = project.read_text(encoding="utf-8")
text = text.replace('MARKETING_VERSION: "1.0.2"', 'MARKETING_VERSION: "1.2.2"')
text = text.replace('CURRENT_PROJECT_VERSION: "3"', 'CURRENT_PROJECT_VERSION: "15"')
project.write_text(text, encoding="utf-8")

print("Applied MX Location clean UI v1.2.2 with exact MX icon at", root)
