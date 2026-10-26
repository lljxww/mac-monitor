import AppKit

let output = CommandLine.arguments[1]
let size = 1024
let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
                              bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                              isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
let background = NSBezierPath(roundedRect: NSRect(x: 100, y: 100, width: 824, height: 824), xRadius: 182, yRadius: 182)
NSGradient(starting: NSColor(srgbRed: 0.12, green: 0.19, blue: 0.26, alpha: 1),
           ending: NSColor(srgbRed: 0.04, green: 0.07, blue: 0.12, alpha: 1))!.draw(in: background, angle: -75)
NSColor.white.withAlphaComponent(0.12).setStroke()
background.lineWidth = 2
background.stroke()
let colors: [NSColor] = [NSColor(srgbRed: 0.20, green: 0.69, blue: 0.91, alpha: 1),
                         NSColor(srgbRed: 0.64, green: 0.47, blue: 0.94, alpha: 1),
                         NSColor(srgbRed: 0.91, green: 0.61, blue: 0.22, alpha: 1)]
for column in 0..<3 {
    for segment in 0..<7 {
        let active = segment < [4, 7, 5][column]
        colors[column].withAlphaComponent(active ? 1 : 0.12).setFill()
        NSBezierPath(roundedRect: NSRect(x: 270 + column * 172, y: 258 + segment * 72, width: 140, height: 54),
                     xRadius: 12, yRadius: 12).fill()
    }
}
NSGraphicsContext.restoreGraphicsState()
try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: output))
