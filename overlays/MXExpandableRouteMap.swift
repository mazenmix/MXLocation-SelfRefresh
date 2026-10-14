import SwiftUI
import MapKit
import CoreLocation

// One map presentation component used by Party Animal and MX Navigator.
// A shared camera Binding preserves the user's zoom and center in both sizes.
// No navigation data is recalculated when merely expanding the map.
struct MXRouteMapPoint: Identifiable {
    let id: String
    let title: String
    let coordinate: CLLocationCoordinate2D
    var index: Int?
    var color: Color = .purple
}

struct MXExpandableRouteMap: View {
    @Binding var camera: MapCameraPosition
    let points: [MXRouteMapPoint]
    let routes: [MKRoute]
    var compactHeight: CGFloat = 290
    var title: String = "Route map"
    @State private var expanded = false

    private var mapCanvas: some View {
        Map(position: $camera) {
            ForEach(points) { point in
                Annotation(point.title, coordinate: point.coordinate) {
                    Group {
                        if let index = point.index {
                            Text("\(index)")
                                .font(.caption.bold())
                                .foregroundStyle(.white)
                                .frame(width: 32, height: 32)
                                .background(point.color, in: Circle())
                                .overlay(Circle().strokeBorder(.white.opacity(0.85), lineWidth: 1.5))
                        } else {
                            Image(systemName: "mappin.circle.fill")
                                .font(.system(size: 26))
                                .foregroundStyle(point.color)
                                .background(.white, in: Circle())
                        }
                    }
                }
            }
            ForEach(Array(routes.enumerated()), id: \.offset) { _, route in
                MapPolyline(route.polyline)
                    .stroke(MXPremiumStyle.cyan, lineWidth: 5)
            }
        }
        .mapStyle(.standard(elevation: .realistic))
        .mapControlVisibility(.hidden)
        .accessibilityIdentifier("mxSharedRouteMapCanvas")
    }

    private func toggle() {
        // Modal presentation is intentionally NOT applied to Explore's main map.
        // These are small route panels and reuse an identical MapCameraPosition.
        expanded.toggle()
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            mapCanvas
            Button(action: toggle) {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(.black.opacity(0.78), in: Circle())
            }
            .accessibilityLabel("Expand \(title) to full screen")
            .accessibilityIdentifier("mxMapExpandButton")
            .padding(12)
        }
        .frame(height: compactHeight)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .fullScreenCover(isPresented: $expanded) {
            ZStack(alignment: .topTrailing) {
                mapCanvas
                    .ignoresSafeArea(.container, edges: .all)
                Button(action: toggle) {
                    Label("Minimize", systemImage: "arrow.down.right.and.arrow.up.left")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 15)
                        .frame(height: 44)
                        .background(.black.opacity(0.80), in: Capsule())
                }
                .accessibilityIdentifier("mxMapMinimizeButton")
                .padding(.trailing, 17)
                .padding(.top, 58)
            }
            .background(Color.black.ignoresSafeArea())
            .ignoresSafeArea(.container, edges: .all)
            .statusBarHidden(true)
            .persistentSystemOverlays(.hidden)
            .accessibilityIdentifier("mxExpandedRouteMap")
        }
    }
}
