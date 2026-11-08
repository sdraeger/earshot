import AppKit

// Draws the 1024 px Earshot app icon: a cream ear hearing two sound arcs, on
// a green squircle in the app's accent. The ear is drawn here, not taken from
// SF Symbols, whose license excludes app icons.
//
// Regenerate every size of the asset catalog's AppIcon set:
//   scripts/generate_app_icon.sh
let out = CommandLine.arguments[1]
let size = 1024
let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4,
    hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0,
)!
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let ctx = NSGraphicsContext.current!.cgContext
// Author in top-left coordinates like SVG.
ctx.translateBy(x: 0, y: CGFloat(size))
ctx.scaleBy(x: 1, y: -1)

func color(_ hex: Int, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

// Apple's macOS grid: an 824 px body centered in 1024, corner radius 185.
let body = NSRect(x: 100, y: 100, width: 824, height: 824)
let squircle = NSBezierPath(roundedRect: body, xRadius: 185, yRadius: 185)

// Drop shadow under the body.
NSGraphicsContext.saveGraphicsState()
let shadow = NSShadow()
shadow.shadowColor = color(0x000000, 0.28)
shadow.shadowOffset = NSSize(width: 0, height: -10)
shadow.shadowBlurRadius = 22
shadow.set()
color(0x2F6A4A).setFill()
squircle.fill()
NSGraphicsContext.restoreGraphicsState()

NSGraphicsContext.saveGraphicsState()
squircle.addClip()
NSGradient(colors: [color(0x4A9168), color(0x2B5E42)])!.draw(in: body, angle: 90)
NSGraphicsContext.restoreGraphicsState()

let cream = color(0xFBF9F4)

func stroke(_ path: NSBezierPath, width: CGFloat, _ c: NSColor) {
    path.lineWidth = width
    path.lineCapStyle = .round
    path.lineJoinStyle = .round
    c.setStroke()
    path.stroke()
}

func p(_ x: CGFloat, _ y: CGFloat) -> NSPoint { NSPoint(x: x, y: y) }

// The ear: outer helix from the tragus up, around the back and down to the lobe.
let helix = NSBezierPath()
helix.move(to: p(400, 500))
helix.curve(to: p(590, 270), controlPoint1: p(400, 360), controlPoint2: p(480, 270))
helix.curve(to: p(770, 455), controlPoint1: p(700, 270), controlPoint2: p(770, 350))
helix.curve(to: p(675, 650), controlPoint1: p(770, 545), controlPoint2: p(705, 590))
helix.curve(to: p(560, 780), controlPoint1: p(640, 720), controlPoint2: p(630, 780))
helix.curve(to: p(470, 720), controlPoint1: p(510, 780), controlPoint2: p(480, 750))
stroke(helix, width: 62, cream)

// The inner fold.
let fold = NSBezierPath()
fold.move(to: p(510, 490))
fold.curve(to: p(595, 375), controlPoint1: p(510, 420), controlPoint2: p(545, 375))
fold.curve(to: p(672, 455), controlPoint1: p(645, 375), controlPoint2: p(672, 410))
fold.curve(to: p(600, 560), controlPoint1: p(672, 505), controlPoint2: p(630, 525))
stroke(fold, width: 50, cream)

// Sound arriving from the left: two arcs.
for (radius, alpha) in [(CGFloat(150), CGFloat(0.85)), (CGFloat(240), CGFloat(0.5))] {
    let arc = NSBezierPath()
    arc.appendArc(withCenter: p(470, 520), radius: radius, startAngle: 150, endAngle: 210)
    stroke(arc, width: 40, color(0xBFE3CC, alpha))
}

NSGraphicsContext.current = nil
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
