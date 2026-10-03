from pathlib import Path
import sys

root = Path(sys.argv[1]).resolve()


def replace_required(path: Path, old: str, new: str, count: int = 1) -> None:
    text = path.read_text(encoding="utf-8")
    if old not in text:
        raise RuntimeError(f"Required source fragment not found in {path}: {old[:220]!r}")
    path.write_text(text.replace(old, new, count), encoding="utf-8")


# -----------------------------------------------------------------------------
# MX Location v1.3.1
# Replace the system-blue user location indicator with a softer premium red dot.
# Keep the selected/favorite destination marker unchanged.
# -----------------------------------------------------------------------------
map_file = root / "Locus/Features/Map/MapHomeView.swift"

old_user_marker = '''                    UserAnnotation()\n'''
new_user_marker = '''                    if let realCoordinate = session.realCoordinate {\n                        Annotation("", coordinate: realCoordinate, anchor: .center) {\n                            ZStack {\n                                Circle()\n                                    .fill(Color.red.opacity(0.055))\n                                    .frame(width: 32, height: 32)\n                                Circle()\n                                    .fill(Color.red.opacity(0.12))\n                                    .frame(width: 22, height: 22)\n                                Circle()\n                                    .fill(Color(red: 0.93, green: 0.25, blue: 0.28).opacity(0.28))\n                                    .frame(width: 15, height: 15)\n                                    .blur(radius: 2.2)\n                                Circle()\n                                    .fill(Color(red: 0.93, green: 0.25, blue: 0.28))\n                                    .frame(width: 9, height: 9)\n                                    .overlay(\n                                        Circle()\n                                            .stroke(Color.white.opacity(0.92), lineWidth: 1.4)\n                                    )\n                                    .shadow(\n                                        color: Color(red: 0.93, green: 0.25, blue: 0.28).opacity(0.55),\n                                        radius: 5\n                                    )\n                            }\n                            .accessibilityLabel("My location")\n                        }\n                    }\n'''
replace_required(map_file, old_user_marker, new_user_marker)


# Version bump from v1.3.0 / build 23 to v1.3.1 / build 24.
project = root / "project.yml"
text = project.read_text(encoding="utf-8")
text = text.replace('MARKETING_VERSION: "1.3.0"', 'MARKETING_VERSION: "1.3.1"')
text = text.replace('CURRENT_PROJECT_VERSION: "23"', 'CURRENT_PROJECT_VERSION: "24"')
project.write_text(text, encoding="utf-8")

print("Applied MX Location v1.3.1: soft red premium user-location dot")
