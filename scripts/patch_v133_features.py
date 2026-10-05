from pathlib import Path
import sys

root = Path(sys.argv[1]).resolve()


def replace_required(path: Path, old: str, new: str, count: int = 1) -> None:
    text = path.read_text(encoding="utf-8")
    if old not in text:
        raise RuntimeError(f"Required source fragment not found in {path}: {old[:220]!r}")
    path.write_text(text.replace(old, new, count), encoding="utf-8")


# -----------------------------------------------------------------------------
# MX Location v1.3.3
# Fix Favorites -> Map preview when using the compact custom tab shell.
# The compact shell recreates MapHomeView when switching tabs, so a preview
# request can already exist before MapHomeView's onChange observer is attached.
# Consume any pending request from onAppear as well as the existing onChange.
# -----------------------------------------------------------------------------
map_file = root / "Locus/Features/Map/MapHomeView.swift"

old_on_appear = '''        .onAppear {\n            session.startLocationUpdates()\n            if let pin = session.pin {\n                resolvePin(pin)\n            }\n        }\n'''
new_on_appear = '''        .onAppear {\n            session.startLocationUpdates()\n\n            if let pendingFavorite = session.requestedMapPreview {\n                // Saved -> Map may recreate this view after the request was set.\n                // Consume it here so tapping a Favorite always jumps/zooms to it.\n                DispatchQueue.main.async {\n                    beginFavoriteJumpPreview(pendingFavorite)\n                    session.requestedMapPreview = nil\n                }\n            } else if let pin = session.pin {\n                resolvePin(pin)\n            }\n        }\n'''
replace_required(map_file, old_on_appear, new_on_appear)

# Bump version from v1.3.2 / build 25 to v1.3.3 / build 26.
project = root / "project.yml"
text = project.read_text(encoding="utf-8")
text = text.replace('MARKETING_VERSION: "1.3.2"', 'MARKETING_VERSION: "1.3.3"')
text = text.replace('CURRENT_PROJECT_VERSION: "25"', 'CURRENT_PROJECT_VERSION: "26"')
project.write_text(text, encoding="utf-8")

print("Applied MX Location v1.3.3: Favorite tap reliably jumps/zooms to saved place")
