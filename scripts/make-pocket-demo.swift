// An illustrated, privacy-safe demo of PicPocket's current layout and gestures.
// Usage: swift scripts/make-pocket-demo.swift
import AppKit
import ImageIO
import UniformTypeIdentifiers

_ = NSApplication.shared

let width = 800, height = 460, fps = 20, count = 160
func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> NSColor {
    NSColor(srgbRed: r / 255, green: g / 255, blue: b / 255, alpha: 1)
}
func ease(_ t: CGFloat) -> CGFloat {
    let t = max(0, min(1, t)); return t * t * (3 - 2 * t)
}
func label(_ text: String, _ x: CGFloat, _ y: CGFloat, _ size: CGFloat, _ ink: NSColor) {
    (text as NSString).draw(at: NSPoint(x: x, y: y), withAttributes: [
        .font: NSFont.systemFont(ofSize: size, weight: .medium), .foregroundColor: ink])
}
func roundRect(_ rect: CGRect, _ radius: CGFloat, _ ink: NSColor) {
    ink.setFill(); NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
}
let destination = CGImageDestinationCreateWithURL(
    URL(fileURLWithPath: "docs/picpocket-demo.gif") as CFURL,
    UTType.gif.identifier as CFString, count, nil)!
CGImageDestinationSetProperties(destination,
    [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
let frameProperties = [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 1.0 / Double(fps)]] as CFDictionary
let icon = NSImage(contentsOfFile: "docs/icon.png")!
for frame in 0..<count {
    autoreleasepool {
        let t = CGFloat(frame) / CGFloat(fps)
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        let context = NSGraphicsContext.current!.cgContext
        NSGradient(colors: [color(221, 237, 255), color(244, 239, 255)])!
            .draw(in: CGRect(x: 0, y: 0, width: width, height: height), angle: 35)
        let ink = color(30, 49, 77)
        icon.draw(in: CGRect(x: 32, y: 330, width: 64, height: 64))
        label("PicPocket", 34, 282, 32, ink)
        label("Your screenshots.", 34, 246, 19, ink)
        label("Within reach.", 34, 220, 19, ink)
        let caption = t < 1.6 ? "Rest in the corner to open" : t < 3.5 ? "Click to copy" : t < 5.1 ? "Remove with a little pull" : t < 6.8 ? "The others move into place" : "Move away to tuck it away"
        label(caption, 34, 148, 14, ink)
        let reveal = ease((t - 0.65) / 0.35) * (1 - ease((t - 7) / 0.35))
        context.saveGState()
        context.setAlpha(reveal)
        context.translateBy(x: 0, y: -16 * (1 - reveal))
        roundRect(CGRect(x: 408, y: 20, width: 380, height: 380), 22, color(245, 248, 254))
        icon.draw(in: CGRect(x: 425, y: 357, width: 28, height: 28),
                  from: .zero, operation: .sourceOver, fraction: reveal)
        label("Your PicPocket", 462, 364, 13, ink)
        NSImage(systemSymbolName: "gearshape", accessibilityDescription: nil)?.draw(in: CGRect(x: 750, y: 361, width: 18, height: 18),
                                                                                  from: .zero, operation: .sourceOver, fraction: reveal)
        let retreat = ease((t - 4.4) / 0.65)
        let reflow = ease((t - 5.05) / 0.25)
        for index in 0..<6 {
            if index == 1 && t >= 5.05 { continue }
            let newIndex = index > 1 ? index - 1 : index
            let x0 = CGFloat(index % 2) * 180, y0 = CGFloat(index / 2) * 108
            let x1 = CGFloat(newIndex % 2) * 180, y1 = CGFloat(newIndex / 2) * 108
            let x = 440 + x0 + (x1 - x0) * reflow + (index == 1 ? 110 * retreat : 0)
            let y = 267 - y0 - (y1 - y0) * reflow
            context.saveGState()
            if index == 1 { context.setAlpha(reveal * (1 - retreat)) }
            roundRect(CGRect(x: x, y: y, width: 136, height: 78), 12, .white)
            let colors = [color(127, 166, 240), color(239, 169, 138), color(160, 143, 224)]
            roundRect(CGRect(x: x + 4, y: y + 4, width: 128, height: 70), 9, colors[index % 3])
            for row in 0..<3 {
                roundRect(CGRect(x: x + 16, y: y + 18 + CGFloat(row) * 14,
                                 width: CGFloat(65 + row * 13), height: 5), 2, .white.withAlphaComponent(0.65))
            }
            if index == 0 && t > 2.2 && t < 3.2 {
                roundRect(CGRect(x: x + 24, y: y - 12, width: 90, height: 26), 13, .white)
                label("✓ Copied", x + 35, y - 6, 12, ink)
            }
            if index == 1 && t > 3.5 {
                NSCursor.closedHand.image.draw(in: CGRect(x: x + 112, y: y + 24, width: 32, height: 32))
            }
            context.restoreGState()
        }
        context.restoreGState()
        if t < 3.5 || t > 6.8 {
            let move = ease((t - 1.4) / 0.6)
            let x: CGFloat = t > 6.8 ? 330 : 775 + (505 - 775) * move
            let y: CGFloat = t > 6.8 ? 100 : 8 + (297 - 8) * move
            NSCursor.arrow.image.draw(in: CGRect(x: x, y: y, width: 24, height: 28))
        }
        NSGraphicsContext.restoreGraphicsState()
        CGImageDestinationAddImage(destination, bitmap.cgImage!, frameProperties)
        if frame == 0 || frame == 55 || frame == 93 || frame == 112 || frame == 155 {
            try! bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "/private/tmp/picpocket-demo-\(frame).png"))
        }
    }
}
precondition(CGImageDestinationFinalize(destination), "Could not write GIF")
print("Wrote docs/picpocket-demo.gif")
