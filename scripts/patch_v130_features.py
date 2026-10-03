from pathlib import Path
import sys

root = Path(sys.argv[1]).resolve()


def replace_required(path: Path, old: str, new: str, count: int = 1) -> None:
    text = path.read_text(encoding="utf-8")
    if old not in text:
        raise RuntimeError(f"Required source fragment not found in {path}: {old[:220]!r}")
    path.write_text(text.replace(old, new, count), encoding="utf-8")


# -----------------------------------------------------------------------------
# 1) Favorites: premium persistent note under each favorite.
# -----------------------------------------------------------------------------
root_view = root / "Locus/Features/Map/RootView.swift"

old_states = '''    @State private var segment = 0\n    @State private var placeToRename: SavedPlace?\n    @State private var renameText = ""\n'''
new_states = '''    @State private var segment = 0\n    @State private var placeToRename: SavedPlace?\n    @State private var renameText = ""\n    @State private var placeToEditNote: SavedPlace?\n    @State private var noteText = ""\n    @State private var favoriteNotes: [String: String] =\n        (UserDefaults.standard.dictionary(forKey: "mx.favoriteNotes.v1") as? [String: String]) ?? [:]\n'''
replace_required(root_view, old_states, new_states)

old_coordinate_text = '''                    Text(String(format: "%.5f, %.5f", place.latitude, place.longitude))\n                        .font(.caption.monospaced())\n                        .foregroundStyle(.secondary)\n'''
new_coordinate_text = '''                    Text(String(format: "%.5f, %.5f", place.latitude, place.longitude))\n                        .font(.caption.monospaced())\n                        .foregroundStyle(.secondary)\n\n                    if segment == 0,\n                       let note = favoriteNotes[place.id],\n                       !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {\n                        HStack(spacing: 5) {\n                            Image(systemName: "note.text")\n                                .font(.system(size: 10, weight: .semibold))\n                            Text(note)\n                                .lineLimit(2)\n                        }\n                        .font(.caption.weight(.medium))\n                        .foregroundStyle(Color.orange.opacity(0.94))\n                    }\n'''
replace_required(root_view, old_coordinate_text, new_coordinate_text)

old_edit_name = '''                        Button {\n                            placeToRename = place\n                            renameText = place.name\n                        } label: {\n                            Label("Edit Name", systemImage: "pencil")\n                        }\n\n                        Button(role: .destructive) {\n                            session.removeFavorite(place)\n                        } label: {\n                            Label("Remove Favorite", systemImage: "star.slash")\n                        }\n'''
new_edit_name = '''                        Button {\n                            placeToRename = place\n                            renameText = place.name\n                        } label: {\n                            Label("Edit Name", systemImage: "pencil")\n                        }\n\n                        Button {\n                            placeToEditNote = place\n                            noteText = favoriteNotes[place.id] ?? ""\n                        } label: {\n                            Label(favoriteNotes[place.id]?.isEmpty == false ? "Edit Note" : "Add Note", systemImage: "note.text")\n                        }\n\n                        Button(role: .destructive) {\n                            session.removeFavorite(place)\n                            if favoriteNotes.removeValue(forKey: place.id) != nil {\n                                saveFavoriteNotes()\n                            }\n                        } label: {\n                            Label("Remove Favorite", systemImage: "star.slash")\n                        }\n'''
replace_required(root_view, old_edit_name, new_edit_name)

# Add an elegant compact note editor as a bottom sheet. It does not add any
# permanent controls or visual clutter to the Saved screen.
old_after_name_alert = '''            } message: {\n                Text("Give this favorite a short, clear name.")\n            }\n        }\n    }\n'''
new_after_name_alert = '''            } message: {\n                Text("Give this favorite a short, clear name.")\n            }\n            .sheet(item: $placeToEditNote) { place in\n                NavigationStack {\n                    VStack(alignment: .leading, spacing: 14) {\n                        VStack(alignment: .leading, spacing: 4) {\n                            Text(place.name)\n                                .font(.headline)\n                            Text("Add a short reminder so you instantly remember this place.")\n                                .font(.caption)\n                                .foregroundStyle(.secondary)\n                        }\n\n                        ZStack(alignment: .topLeading) {\n                            RoundedRectangle(cornerRadius: 16, style: .continuous)\n                                .fill(Color.white.opacity(0.065))\n                                .overlay(\n                                    RoundedRectangle(cornerRadius: 16, style: .continuous)\n                                        .stroke(Color.orange.opacity(0.18), lineWidth: 1)\n                                )\n\n                            if noteText.isEmpty {\n                                Text("e.g. Hotel near the station")\n                                    .font(.subheadline)\n                                    .foregroundStyle(.tertiary)\n                                    .padding(.horizontal, 14)\n                                    .padding(.vertical, 15)\n                                    .allowsHitTesting(false)\n                            }\n\n                            TextEditor(text: $noteText)\n                                .font(.body)\n                                .foregroundStyle(Color.orange.opacity(0.98))\n                                .scrollContentBackground(.hidden)\n                                .padding(9)\n                        }\n                        .frame(height: 105)\n\n                        Spacer(minLength: 0)\n                    }\n                    .padding(18)\n                    .background(Color.black.ignoresSafeArea())\n                    .navigationTitle("Favorite Note")\n                    .navigationBarTitleDisplayMode(.inline)\n                    .toolbar {\n                        ToolbarItem(placement: .cancellationAction) {\n                            Button("Cancel") {\n                                placeToEditNote = nil\n                            }\n                        }\n                        ToolbarItem(placement: .confirmationAction) {\n                            Button("Save") {\n                                setFavoriteNote(noteText, for: place)\n                                placeToEditNote = nil\n                            }\n                            .fontWeight(.semibold)\n                        }\n                    }\n                }\n                .presentationDetents([.height(280)])\n                .presentationDragIndicator(.visible)\n                .preferredColorScheme(.dark)\n            }\n        }\n    }\n'''
replace_required(root_view, old_after_name_alert, new_after_name_alert)

# Persistent note helpers live beside the existing URL helper methods.
helper_anchor = '''    private func appleMapsURL(for place: SavedPlace) -> URL {\n'''
note_helpers = '''    private func setFavoriteNote(_ note: String, for place: SavedPlace) {\n        let clean = note.trimmingCharacters(in: .whitespacesAndNewlines)\n        if clean.isEmpty {\n            favoriteNotes.removeValue(forKey: place.id)\n        } else {\n            favoriteNotes[place.id] = clean\n        }\n        saveFavoriteNotes()\n    }\n\n    private func saveFavoriteNotes() {\n        UserDefaults.standard.set(favoriteNotes, forKey: "mx.favoriteNotes.v1")\n    }\n\n    private func appleMapsURL(for place: SavedPlace) -> URL {\n'''
replace_required(root_view, helper_anchor, note_helpers)


# -----------------------------------------------------------------------------
# 2) Favorite local clock: strict 24-hour format + soft luminous yellow styling.
# -----------------------------------------------------------------------------
old_clock_style = '''            HStack(spacing: 4) {\n                Image(systemName: "clock")\n                    .font(.system(size: 10, weight: .semibold))\n                Text(timeText(for: context.date))\n                    .font(.caption2.monospacedDigit().weight(.semibold))\n            }\n            .foregroundStyle(.secondary)\n            .padding(.horizontal, 8)\n            .frame(height: 27)\n            .background(Color.white.opacity(0.055), in: Capsule())\n            .overlay(Capsule().stroke(Color.white.opacity(0.055), lineWidth: 1))\n'''
new_clock_style = '''            HStack(spacing: 4) {\n                Image(systemName: "clock")\n                    .font(.system(size: 10, weight: .semibold))\n                    .foregroundStyle(Color.yellow.opacity(0.78))\n                Text(timeText(for: context.date))\n                    .font(.caption2.monospacedDigit().weight(.bold))\n                    .foregroundStyle(Color.yellow.opacity(0.98))\n                    .shadow(color: Color.yellow.opacity(0.72), radius: 4)\n            }\n            .padding(.horizontal, 8)\n            .frame(height: 27)\n            .background(Color.yellow.opacity(0.045), in: Capsule())\n            .overlay(Capsule().stroke(Color.yellow.opacity(0.13), lineWidth: 1))\n            .shadow(color: Color.yellow.opacity(0.08), radius: 7)\n'''
replace_required(root_view, old_clock_style, new_clock_style)


# -----------------------------------------------------------------------------
# 3) Version bump from v1.2.9 / build 22 to v1.3.0 / build 23.
# -----------------------------------------------------------------------------
project = root / "project.yml"
text = project.read_text(encoding="utf-8")
text = text.replace('MARKETING_VERSION: "1.2.9"', 'MARKETING_VERSION: "1.3.0"')
text = text.replace('CURRENT_PROJECT_VERSION: "22"', 'CURRENT_PROJECT_VERSION: "23"')
project.write_text(text, encoding="utf-8")

print("Applied MX Location v1.3.0: glowing 24h favorite clocks + persistent orange notes")
