import AppKit

// Renders the HeadmouseHelper app icon (emerald squircle + white tracker glyph —
// a rounded rectangle with a big circle and two small top-corner circles knocked
// out) to a 1024×1024 PNG. Mirrors the approved SVG (tools/AppIcon.svg). Run:
//   swiftc make-icon.swift -o make-icon && ./make-icon out.png

let size = 1024
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                           isPlanar: false, colorSpaceName: .deviceRGB,
                           bytesPerRow: 0, bitsPerPixel: 0)!
let ctx = NSGraphicsContext(bitmapImageRep: rep)!
NSGraphicsContext.current = ctx
let cg = ctx.cgContext

func rgb(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) -> CGColor {
    CGColor(red: r, green: g, blue: b, alpha: a)
}
let space = CGColorSpace(name: CGColorSpace.sRGB)!

// Map an SVG-style 200×200 y-down space onto an 832 body inset 96px in the canvas.
let inset: CGFloat = 96
let body: CGFloat = CGFloat(size) - inset * 2
cg.translateBy(x: inset, y: CGFloat(size) - inset)
cg.scaleBy(x: body / 200, y: -body / 200)

// --- Squircle tile: vertical emerald gradient + top sheen ---
let tile = CGPath(roundedRect: CGRect(x: 0, y: 0, width: 200, height: 200),
                  cornerWidth: 46, cornerHeight: 46, transform: nil)
cg.saveGState()
cg.addPath(tile); cg.clip()
let grad = CGGradient(colorsSpace: space,
                      colors: [rgb(0.204, 0.827, 0.600), rgb(0.020, 0.588, 0.412)] as CFArray,
                      locations: [0, 1])!
cg.drawLinearGradient(grad, start: CGPoint(x: 0, y: 0), end: CGPoint(x: 0, y: 200), options: [])
let sheen = CGGradient(colorsSpace: space,
                       colors: [rgb(1, 1, 1, 0.35), rgb(1, 1, 1, 0)] as CFArray,
                       locations: [0, 1])!
cg.drawLinearGradient(sheen, start: CGPoint(x: 0, y: 0), end: CGPoint(x: 0, y: 100), options: [])
cg.restoreGState()

// --- Tracker glyph: rounded rect minus a big circle and two small corner
//     circles (even-odd), white with a subtle gradient and a soft shadow ---
let glyph = CGMutablePath()
glyph.addPath(CGPath(roundedRect: CGRect(x: 30, y: 50, width: 140, height: 100),
                     cornerWidth: 18, cornerHeight: 18, transform: nil))
glyph.addEllipse(in: CGRect(x: 60, y: 60, width: 80, height: 80))   // big circle, r40 @ (100,100)
glyph.addEllipse(in: CGRect(x: 38, y: 58, width: 16, height: 16))   // small @ (46,66)
glyph.addEllipse(in: CGRect(x: 146, y: 58, width: 16, height: 16))  // small @ (154,66)

// Base fill establishes the shape and casts a soft shadow (lifts it off the tile).
cg.saveGState()
cg.setShadow(offset: CGSize(width: 0, height: 6), blur: 9, color: rgb(0.008, 0.239, 0.161, 0.45))
cg.addPath(glyph)
cg.setFillColor(rgb(1, 1, 1))
cg.fillPath(using: .evenOdd)
cg.restoreGState()

// White → mint gradient clipped to the glyph gives it volume.
cg.saveGState()
cg.addPath(glyph)
cg.clip(using: .evenOdd)
let glyphGrad = CGGradient(colorsSpace: space,
                           colors: [rgb(1, 1, 1), rgb(0.749, 0.929, 0.859)] as CFArray,
                           locations: [0, 1])!
cg.drawLinearGradient(glyphGrad, start: CGPoint(x: 0, y: 50), end: CGPoint(x: 0, y: 150),
                      options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
cg.restoreGState()

// --- Save PNG ---
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon_1024.png"
let png = rep.representation(using: .png, properties: [:])!
try! png.write(to: URL(fileURLWithPath: out))
print("wrote \(out)")
