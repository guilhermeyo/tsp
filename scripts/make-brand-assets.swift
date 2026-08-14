import Cocoa

// make-brand-assets.swift — renders every brand raster from ONE definition.
//
// WHY A SCRIPT AND NOT A DESIGN FILE: the mark is three rectangles. Committing
// six hand-exported PNGs means six chances for them to drift apart, and the
// drift is invisible until an icon looks subtly wrong on one surface. Here the
// geometry exists once, below, and every raster is a projection of it.
//
// Run:  swift scripts/make-brand-assets.swift
// Deps: none. CoreGraphics ships with macOS; this deliberately avoids
//       rsvg/cairo/PIL so it still runs on a clean machine years from now.

// ---------------------------------------------------------------------------
// The mark
// ---------------------------------------------------------------------------
// Three bars, EQUAL WIDTH, fully rounded. The previous version had three
// different widths (576 / 768 / 480) and square corners, which read as three
// unrelated blocks rather than one mark.
//
// Equal width is what makes it a logo instead of a paragraph: the eye stops
// looking for meaning in the ragged edge. 640 of 1024 leaves symmetric 192pt
// margins, wide enough to survive iOS's icon mask and the widget's corner
// radius without the bars touching a rounded edge.
//
// Radius is half the bar height, i.e. a full stadium. At 40pt on a home screen
// a softer radius reads as an accident of anti-aliasing; a full pill reads as
// intentional.
private let canvas: CGFloat = 1024
private let barWidth: CGFloat = 640
private let barHeight: CGFloat = 160
private let barX: CGFloat = (canvas - barWidth) / 2          // 192
private let barTops: [CGFloat] = [168, 432, 696]             // unchanged rhythm
private let radius: CGFloat = barHeight / 2                  // 80, full stadium

private let ink = NSColor.white
private let paper = NSColor.black

/// `background: nil` leaves the mark on transparency — what the splash logo
/// needs, since its backdrop comes from SplashScreenBackground.colorset.
private func drawMark(size: CGFloat, background: NSColor?) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size),
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    let scale = size / canvas
    if let background {
        background.setFill()
        NSRect(x: 0, y: 0, width: size, height: size).fill()
    }

    ink.setFill()
    for top in barTops {
        // CoreGraphics is bottom-left origin; the constants above read top-down
        // the way the SVG does, so flip here rather than in the numbers.
        let y = canvas - top - barHeight
        let r = NSRect(x: barX * scale, y: y * scale,
                       width: barWidth * scale, height: barHeight * scale)
        NSBezierPath(roundedRect: r,
                     xRadius: radius * scale,
                     yRadius: radius * scale).fill()
    }

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

private func write(_ rep: NSBitmapImageRep, to path: String) {
    guard let data = rep.representation(using: .png, properties: [:]) else {
        FileHandle.standardError.write("cannot encode \(path)\n".data(using: .utf8)!); exit(1)
    }
    let url = URL(fileURLWithPath: path)
    try? FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    do { try data.write(to: url); print("  wrote \(path) (\(rep.pixelsWide)px)") }
    catch { FileHandle.standardError.write("cannot write \(path): \(error)\n".data(using: .utf8)!); exit(1) }
}

// ---------------------------------------------------------------------------
// Outputs
// ---------------------------------------------------------------------------
let root = FileManager.default.currentDirectoryPath

// The app icon. iOS 18 asks for a single 1024 and masks it itself, so the
// black plate is part of the image.
write(drawMark(size: 1024, background: paper),
      to: "\(root)/ios/SimplePhone/Images.xcassets/AppIcon.appiconset/tsp-icon-1024.png")

// The Expo-side icon, kept in step so the two never disagree.
write(drawMark(size: 1024, background: paper), to: "\(root)/assets/images/icon.png")

// The splash logo: TRANSPARENT, because the colorset paints behind it.
for (suffix, px) in [("", 76), ("@2x", 152), ("@3x", 228)] {
    write(drawMark(size: CGFloat(px), background: nil),
          to: "\(root)/ios/SimplePhone/Images.xcassets/SplashScreenLogo.imageset/image\(suffix).png")
}

// The SVG stays the human-readable source of truth, regenerated from the same
// constants so it can never describe a different mark than the PNGs do.
let bars = barTops.map {
    "    <rect x=\"\(Int(barX))\" y=\"\(Int($0))\" width=\"\(Int(barWidth))\" "
    + "height=\"\(Int(barHeight))\" rx=\"\(Int(radius))\"/>"
}.joined(separator: "\n")

let svg = """
<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">
  <title>TSP</title>
  <!-- Generated by scripts/make-brand-assets.swift. Edit the constants there. -->
  <rect x="0" y="0" width="1024" height="1024" fill="#000000"/>
  <g fill="#FFFFFF">
\(bars)
  </g>
</svg>

"""
try! svg.write(toFile: "\(root)/assets/brand/tsp-icon.svg", atomically: true, encoding: .utf8)
print("  wrote assets/brand/tsp-icon.svg")
