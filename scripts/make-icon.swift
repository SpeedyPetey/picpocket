// Draws PicPocket's app icon: screenshot cards tucked into a blue pocket.
// Usage: swift scripts/make-icon.swift out.png
import AppKit

let out = CommandLine.arguments.dropFirst().first ?? "icon.png"
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1024, pixelsHigh: 1024,
                          bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                          colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let ctx = NSGraphicsContext.current!.cgContext
let body = NSBezierPath(roundedRect: NSRect(x: 100, y: 100, width: 824, height: 824), xRadius: 185, yRadius: 185)
NSGradient(colors: [NSColor(red: 0.89, green: 0.94, blue: 1, alpha: 1), .white])!.draw(in: body, angle: 90)

func card(x: CGFloat, y: CGFloat, angle: CGFloat, color: NSColor) {
    ctx.saveGState()
    ctx.translateBy(x: x, y: y)
    ctx.rotate(by: angle * .pi / 180)
    NSColor.white.setFill()
    NSBezierPath(roundedRect: NSRect(x: -160, y: -155, width: 320, height: 310), xRadius: 28, yRadius: 28).fill()
    color.setFill()
    NSBezierPath(roundedRect: NSRect(x: -140, y: -130, width: 280, height: 250), xRadius: 15, yRadius: 15).fill()
    NSColor.white.withAlphaComponent(0.85).setFill()
    NSBezierPath(ovalIn: NSRect(x: 40, y: 25, width: 52, height: 52)).fill()
    let mountain = NSBezierPath()
    mountain.move(to: NSPoint(x: -140, y: -130))
    mountain.line(to: NSPoint(x: -30, y: 20))
    mountain.line(to: NSPoint(x: 65, y: -85))
    mountain.line(to: NSPoint(x: 140, y: -20))
    mountain.line(to: NSPoint(x: 140, y: -130))
    mountain.close()
    mountain.fill()
    ctx.restoreGState()
}
card(x: 425, y: 645, angle: 10, color: NSColor(red: 0.56, green: 0.47, blue: 0.88, alpha: 1))
card(x: 610, y: 615, angle: -9, color: NSColor(red: 0.95, green: 0.62, blue: 0.37, alpha: 1))

let pocket = NSBezierPath()
pocket.move(to: NSPoint(x: 245, y: 585))
pocket.line(to: NSPoint(x: 779, y: 585))
pocket.line(to: NSPoint(x: 749, y: 340))
pocket.curve(to: NSPoint(x: 512, y: 220), controlPoint1: NSPoint(x: 740, y: 285), controlPoint2: NSPoint(x: 595, y: 220))
pocket.curve(to: NSPoint(x: 275, y: 340), controlPoint1: NSPoint(x: 429, y: 220), controlPoint2: NSPoint(x: 284, y: 285))
pocket.close()
NSGradient(colors: [NSColor(red: 0.15, green: 0.34, blue: 0.72, alpha: 1), NSColor(red: 0.29, green: 0.55, blue: 0.95, alpha: 1)])!.draw(in: pocket, angle: 90)
let seam = pocket.copy() as! NSBezierPath
seam.transform(using: AffineTransform(translationByX: -512, byY: -402))
seam.transform(using: AffineTransform(scale: 0.88))
seam.transform(using: AffineTransform(translationByX: 512, byY: 402))
seam.lineWidth = 4
seam.setLineDash([9, 8], count: 2, phase: 0)
NSColor.white.withAlphaComponent(0.7).setStroke()
seam.stroke()
NSGraphicsContext.restoreGraphicsState()
try rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
