import AppKit
import Foundation

let outPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "MXAppIcon1024.png"
let sourceSize: CGFloat = 1254
let targetSize: CGFloat = 1024
let scale = targetSize / sourceSize

func point(_ x: CGFloat, _ yFromTop: CGFloat) -> NSPoint {
    NSPoint(x: x * scale, y: (sourceSize - yFromTop) * scale)
}

func fillPolygon(_ points: [(CGFloat, CGFloat)]) {
    guard let first = points.first else { return }
    let path = NSBezierPath()
    path.move(to: point(first.0, first.1))
    for p in points.dropFirst() {
        path.line(to: point(p.0, p.1))
    }
    path.close()
    NSColor.white.setFill()
    path.fill()
}

let image = NSImage(size: NSSize(width: targetSize, height: targetSize))
image.lockFocus()
NSGraphicsContext.current?.shouldAntialias = true
NSColor.black.setFill()
NSBezierPath(rect: NSRect(x: 0, y: 0, width: targetSize, height: targetSize)).fill()

// Traced directly from the user's supplied MX icon image.
fillPolygon([
    (208, 816), (278, 816), (279, 564), (440, 730), (597, 565),
    (597, 731), (513, 816), (551, 816), (738, 625), (591, 471),
    (440, 627), (258, 438), (208, 438)
])
fillPolygon([
    (622, 453), (966, 816), (1067, 816), (707, 438), (635, 438)
])
fillPolygon([
    (809, 696), (763, 648), (598, 816), (693, 816)
])
fillPolygon([
    (1058, 438), (961, 438), (858, 545), (859, 548), (905, 596)
])

image.unlockFocus()

guard let tiff = image.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else {
    fatalError("Could not render MX icon")
}
try png.write(to: URL(fileURLWithPath: outPath))
print("Rendered user MX icon to \(outPath)")
