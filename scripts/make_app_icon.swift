import AppKit

let size: CGFloat = 1024
let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()

guard let context = NSGraphicsContext.current else {
    fatalError("no graphics context")
}

let bounds = NSRect(x: 0, y: 0, width: size, height: size)

// Rounded graphite background.
let background = NSBezierPath(
    roundedRect: bounds.insetBy(dx: 30, dy: 30),
    xRadius: 220,
    yRadius: 220
)
background.addClip()

let gradient = NSGradient(colors: [
    NSColor(calibratedRed: 0.16, green: 0.17, blue: 0.19, alpha: 1),
    NSColor(calibratedRed: 0.055, green: 0.06, blue: 0.07, alpha: 1)
])!
gradient.draw(in: background, angle: -90)

// Teal glow/lens ring.
let teal = NSColor(calibratedRed: 0.18, green: 0.70, blue: 0.64, alpha: 1)
let glow = NSBezierPath(ovalIn: NSRect(x: 192, y: 192, width: 640, height: 640))
teal.withAlphaComponent(0.12).setFill()
glow.fill()

let ring = NSBezierPath(ovalIn: NSRect(x: 220, y: 220, width: 584, height: 584))
ring.lineWidth = 34
teal.setStroke()
ring.stroke()

// Printer body.
let body = NSBezierPath(
    roundedRect: NSRect(x: 302, y: 322, width: 420, height: 310),
    xRadius: 54,
    yRadius: 54
)
NSColor.white.setFill()
body.fill()

// Paper slot.
let slot = NSBezierPath(
    roundedRect: NSRect(x: 344, y: 548, width: 336, height: 34),
    xRadius: 17,
    yRadius: 17
)
NSColor(calibratedWhite: 0.10, alpha: 1).setFill()
slot.fill()

// Camera lens on the front.
let lens = NSBezierPath(ovalIn: NSRect(x: 432, y: 390, width: 160, height: 160))
NSColor(calibratedWhite: 0.10, alpha: 1).setFill()
lens.fill()

let lensInner = NSBezierPath(ovalIn: NSRect(x: 470, y: 428, width: 84, height: 84))
teal.setFill()
lensInner.fill()

let lensGlint = NSBezierPath(ovalIn: NSRect(x: 488, y: 470, width: 20, height: 20))
NSColor.white.withAlphaComponent(0.85).setFill()
lensGlint.fill()

// Nozzle.
let nozzle = NSBezierPath()
nozzle.move(to: NSPoint(x: 482, y: 322))
nozzle.line(to: NSPoint(x: 542, y: 322))
nozzle.line(to: NSPoint(x: 526, y: 272))
nozzle.line(to: NSPoint(x: 498, y: 272))
nozzle.close()
teal.setFill()
nozzle.fill()

// Live dot.
let live = NSBezierPath(ovalIn: NSRect(x: 706, y: 700, width: 58, height: 58))
NSColor(calibratedRed: 0.88, green: 0.24, blue: 0.24, alpha: 1).setFill()
live.fill()

image.unlockFocus()

guard let tiff = image.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else {
    fatalError("could not encode icon")
}

let output = URL(fileURLWithPath: "docs/AppIcon-1024.png")
try png.write(to: output)
print("Wrote \(output.path)")
