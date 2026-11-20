import AppKit
import ImageIO
import CoreGraphics

let sourcePath = "/Users/franktriolo/Desktop/Gemini_Generated_Image_x1xmmtx1xmmtx1xm.jpg"
guard let source = NSImage(contentsOfFile: sourcePath) else {
    fatalError("cannot read source icon")
}
guard let cg = source.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
    fatalError("cannot get CGImage")
}

// The generated artwork is 2048x2048 with a checkerboard outside the icon.
// These bounds are the rounded-square icon, including the PRINT HUB plate.
let cropRect = CGRect(x: 274, y: 2048 - (236 + 1581), width: 1493, height: 1581)
guard let cropped = cg.cropping(to: cropRect) else {
    fatalError("cannot crop icon")
}

let pixels = 1024
let colorSpace = CGColorSpaceCreateDeviceRGB()
guard let context = CGContext(
    data: nil,
    width: pixels,
    height: pixels,
    bitsPerComponent: 8,
    bytesPerRow: 0,
    space: colorSpace,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) else {
    fatalError("cannot create context")
}

let canvas = CGRect(x: 0, y: 0, width: pixels, height: pixels)
let rounded = CGPath(
    roundedRect: canvas,
    cornerWidth: 330,
    cornerHeight: 330,
    transform: nil
)
context.addPath(rounded)
context.clip()
context.interpolationQuality = .high
context.draw(cropped, in: canvas)

guard let outputImage = context.makeImage() else {
    fatalError("cannot create output image")
}

let output = URL(fileURLWithPath: "docs/PrintHub-icon-1024.png")
guard let destination = CGImageDestinationCreateWithURL(
    output as CFURL,
    "public.png" as CFString,
    1,
    nil
) else {
    fatalError("cannot create destination")
}
CGImageDestinationAddImage(destination, outputImage, nil)
guard CGImageDestinationFinalize(destination) else {
    fatalError("cannot write icon")
}
print("Wrote \(output.path)")
