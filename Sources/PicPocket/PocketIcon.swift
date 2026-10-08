import AppKit

/// The original pocket outline, used beside the pocket title.
enum PocketIcon {
    static let image: NSImage = {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
            NSColor.black.setStroke()
            let pocket = NSBezierPath()
            pocket.move(to: NSPoint(x: 2, y: 14))
            pocket.line(to: NSPoint(x: 16, y: 14))
            pocket.line(to: NSPoint(x: 15, y: 5))
            pocket.curve(to: NSPoint(x: 9, y: 2),
                         controlPoint1: NSPoint(x: 15, y: 3), controlPoint2: NSPoint(x: 11, y: 2))
            pocket.curve(to: NSPoint(x: 3, y: 5),
                         controlPoint1: NSPoint(x: 7, y: 2), controlPoint2: NSPoint(x: 3, y: 3))
            pocket.close()
            pocket.lineWidth = 1.5
            pocket.lineJoinStyle = .round
            pocket.stroke()
            let seam = NSBezierPath()
            seam.move(to: NSPoint(x: 3, y: 11))
            seam.line(to: NSPoint(x: 15, y: 11))
            seam.lineWidth = 1
            seam.stroke()
            return true
        }
        image.isTemplate = true
        return image
    }()
}
