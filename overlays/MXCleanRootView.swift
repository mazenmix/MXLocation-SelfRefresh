import SwiftUI

struct RootView: View {
    @EnvironmentObject private var session: SpoofSession
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            MapHomeView()
                .tabItem {
                    Label("Map", systemImage: "map.fill")
                }
                .tag(0)

            MXSavedView(selectedTab: $selectedTab)
                .tabItem {
                    Label("Saved", systemImage: "star.fill")
                }
                .tag(1)

            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gearshape.fill")
                }
                .tag(2)
        }
        .tint(Color(red: 0.18, green: 0.55, blue: 1.0))
        .preferredColorScheme(.dark)
        .alert("MX Location", isPresented: Binding(
            get: { session.lastError != nil },
            set: { if !$0 { session.lastError = nil } }
        )) {
            Button("OK", role: .cancel) {
                session.lastError = nil
            }
        } message: {
            Text(session.lastError ?? "")
        }
    }
}

struct MXSavedView: View {
    @EnvironmentObject private var session: SpoofSession
    @Binding var selectedTab: Int

    @State private var segment = 0
    @State private var placeToRename: SavedPlace?
    @State private var renameText = ""

    private var places: [SavedPlace] {
        segment == 0 ? session.favorites : session.recents
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                VStack(spacing: 14) {
                    Picker("Saved places", selection: $segment) {
                        Text("Favorites").tag(0)
                        Text("Recent").tag(1)
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 16)

                    if places.isEmpty {
                        VStack(spacing: 10) {
                            Image(systemName: segment == 0 ? "star" : "clock.arrow.circlepath")
                                .font(.system(size: 34, weight: .medium))
                                .foregroundStyle(.secondary)
                            Text(segment == 0 ? "No favorites yet" : "No recent places yet")
                                .font(.headline)
                            Text(segment == 0 ? "Save a location from the map and it will appear here." : "Places you use will appear here automatically.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 28)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        ScrollView {
                            LazyVStack(spacing: 10) {
                                ForEach(places) { place in
                                    placeRow(place)
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.bottom, 20)
                        }
                    }
                }
                .padding(.top, 10)
            }
            .navigationTitle("Saved")
            .navigationBarTitleDisplayMode(.large)
            .alert("Edit Favorite Name", isPresented: Binding(
                get: { placeToRename != nil },
                set: { if !$0 { placeToRename = nil } }
            )) {
                TextField("Place name", text: $renameText)
                Button("Cancel", role: .cancel) {
                    placeToRename = nil
                }
                Button("Save") {
                    let cleanName = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
                    if let place = placeToRename, !cleanName.isEmpty {
                        session.renameFavorite(place, to: cleanName)
                    }
                    placeToRename = nil
                }
            } message: {
                Text("Give this favorite a short, clear name.")
            }
        }
    }

    @ViewBuilder
    private func placeRow(_ place: SavedPlace) -> some View {
        Button {
            session.pin = place.coordinate
            selectedTab = 0
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.white.opacity(0.08))
                    Image(systemName: segment == 0 ? "star.fill" : "mappin.and.ellipse")
                        .foregroundStyle(segment == 0 ? Color.yellow : Color(red: 0.18, green: 0.55, blue: 1.0))
                }
                .frame(width: 44, height: 44)

                VStack(alignment: .leading, spacing: 4) {
                    Text(place.name)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(String(format: "%.5f, %.5f", place.latitude, place.longitude))
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 8)

                Menu {
                    if segment == 0 {
                        Button {
                            placeToRename = place
                            renameText = place.name
                        } label: {
                            Label("Edit Name", systemImage: "pencil")
                        }

                        Button(role: .destructive) {
                            session.removeFavorite(place)
                        } label: {
                            Label("Remove Favorite", systemImage: "star.slash")
                        }
                    } else {
                        Button {
                            session.addFavorite(name: place.name, coordinate: place.coordinate)
                        } label: {
                            Label("Add to Favorites", systemImage: "star")
                        }
                        Button(role: .destructive) {
                            session.removeRecent(place)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 36, height: 36)
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.white.opacity(0.07))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.white.opacity(0.06), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}
