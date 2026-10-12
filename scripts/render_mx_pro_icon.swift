import AppKit
import Foundation

let destination = CommandLine.arguments.dropFirst().first ?? "assets/MXAppIcon1024.png"
let size = 1024
let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
                             bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                             isPlanar: false, colorSpaceName: .deviceRGB,
                             bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
let rect = NSRect(x:0,y:0,width:size,height:size)
let gradient = NSGradient(starting: NSColor(red:0.04,green:0.13,blue:0.29,alpha:1),
                          ending: NSColor(red:0.01,green:0.03,blue:0.08,alpha:1))!
gradient.draw(in:rect,angle:-65)

NSColor(red:0.11,green:0.78,blue:0.98,alpha:1).setStroke()
let ring=NSBezierPath(ovalIn:NSRect(x:220,y:222,width:585,height:585))
ring.lineWidth=24
ring.stroke()
NSColor(red:0.10,green:0.39,blue:0.58,alpha:0.65).setStroke()
let inner=NSBezierPath(ovalIn:NSRect(x:315,y:317,width:395,height:395))
inner.lineWidth=13
inner.stroke()

let arrow=NSBezierPath()
arrow.move(to:NSPoint(x:701,y:779))
arrow.line(to:NSPoint(x:585,y:292))
arrow.line(to:NSPoint(x:446,y:536))
arrow.close()
NSColor(red:0.55,green:0.94,blue:1,alpha:1).setFill()
arrow.fill()

let badge=NSBezierPath(roundedRect:NSRect(x:541,y:110,width:346,height:149),xRadius:36,yRadius:36)
NSColor(red:0.02,green:0.27,blue:0.44,alpha:1).setFill()
badge.fill()
NSColor(red:0.23,green:0.88,blue:1,alpha:1).setStroke()
badge.lineWidth=12
badge.stroke()

let label="PRO" as NSString
let attrs:[NSAttributedString.Key:Any]=[
    .font:NSFont.systemFont(ofSize:86,weight:.heavy),
    .foregroundColor:NSColor.white
]
label.draw(at:NSPoint(x:603,y:140),withAttributes:attrs)
NSGraphicsContext.restoreGraphicsState()
let url=URL(fileURLWithPath:destination)
try FileManager.default.createDirectory(at:url.deletingLastPathComponent(),withIntermediateDirectories:true)
try bitmap.representation(using:.png,properties:[:])!.write(to:url)
print("Created separate MX Pro icon: \(url.path)")
