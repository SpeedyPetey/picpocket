import AppKit
import QuartzCore

/// Reads where on screen a screenshot was taken. macOS stores the captured
/// area on the file, in global points with the origin at the top left of
/// the main display. Returned in AppKit screen coordinates.
func captureRect(of url: URL) -> CGRect? {
    let name = "com.apple.metadata:kMDItemScreenCaptureGlobalRect"
    let data: Data? = url.withUnsafeFileSystemRepresentation { path in
        guard let path else { return nil }
        let size = getxattr(path, name, nil, 0, 0, 0)
        guard size > 0 else { return nil }
        var buffer = Data(count: size)
        let read = buffer.withUnsafeMutableBytes { getxattr(path, name, $0.baseAddress, size, 0, 0) }
        return read == size ? buffer : nil
    }
    guard let data,
          let values = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [NSNumber],
          values.count == 4, let main = NSScreen.screens.first else { return nil }
    let x = CGFloat(truncating: values[0]), y = CGFloat(truncating: values[1])
    let w = CGFloat(truncating: values[2]), h = CGFloat(truncating: values[3])
    guard w > 2, h > 2 else { return nil }
    return CGRect(x: x, y: main.frame.maxY - y - h, width: w, height: h)
}

/// The macOS grab cursor closes around a card and carries it out of the pocket.
@MainActor
final class CaptureFlight {
    static let duration: TimeInterval = 0.65
    private static var current: [CaptureFlight] = []

    private let window: NSPanel
    private let card = CALayer()
    private let hand = CALayer()
    private let openHand = NSCursor.openHand.image.cgImage(forProposedRect: nil, context: nil, hints: nil)
    private let closedHand = NSCursor.closedHand.image.cgImage(forProposedRect: nil, context: nil, hints: nil)
    private let from: CGRect
    private let direction: CGFloat
    private let completion: () -> Void
    private let reduceMotion: Bool
    private var timer: Timer?
    private var start: CFTimeInterval = 0

    static func steal(image: CGImage, card: CGRect, on screen: NSScreen,
                      direction: CGFloat, completion: @escaping () -> Void) {
        let animation = CaptureFlight(image: image, frame: card, screen: screen,
                                      direction: direction, completion: completion)
        current.append(animation)
        animation.run()
    }

    private init(image: CGImage, frame: CGRect, screen: NSScreen,
                 direction: CGFloat, completion: @escaping () -> Void) {
        self.direction = direction
        self.completion = completion
        from = frame.offsetBy(dx: -screen.frame.minX, dy: -screen.frame.minY)
        reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        window = NSPanel(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel],
                         backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 1)
        window.collectionBehavior = [.canJoinAllSpaces, .canJoinAllApplications, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        let host = NSView(frame: NSRect(origin: .zero, size: screen.frame.size))
        host.wantsLayer = true
        window.contentView = host

        card.frame = from
        card.backgroundColor = NSColor(white: 0.97, alpha: 0.85).cgColor
        card.cornerRadius = 16
        card.shadowColor = NSColor.black.cgColor
        card.shadowOpacity = 0.24
        card.shadowRadius = 10
        card.shadowOffset = CGSize(width: 0, height: -5)
        let photo = CALayer()
        photo.frame = card.bounds.insetBy(dx: 4, dy: 4)
        photo.contents = image
        photo.contentsGravity = .resizeAspect
        photo.contentsScale = screen.backingScaleFactor
        photo.cornerRadius = 12
        photo.masksToBounds = true
        card.addSublayer(photo)
        host.layer?.addSublayer(card)

        // Native cursor artwork provides a familiar, compact grab gesture.
        hand.bounds = CGRect(x: 0, y: 0, width: 32, height: 32)
        hand.contents = openHand
        hand.contentsGravity = .resizeAspect
        hand.contentsScale = screen.backingScaleFactor
        hand.shadowColor = NSColor.black.cgColor
        hand.shadowOpacity = 0.16
        hand.shadowRadius = 2
        hand.shadowOffset = CGSize(width: 0, height: -1)
        host.layer?.addSublayer(hand)
    }

    private func run() {
        update(0)
        window.orderFrontRegardless()
        start = CACurrentMediaTime()
        let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func tick() {
        let duration = reduceMotion ? 0.2 : Self.duration
        let progress = min(1, (CACurrentMediaTime() - start) / duration)
        update(progress)
        if progress >= 1 {
            timer?.invalidate()
            timer = nil
            window.orderOut(nil)
            Self.current.removeAll { $0 === self }
            completion()
        }
    }

    private func update(_ progress: Double) {
        func ease(_ value: Double) -> CGFloat {
            let t = max(0, min(1, value))
            return CGFloat(t * t * (3 - 2 * t))
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if reduceMotion {
            hand.isHidden = true
            card.opacity = Float(1 - progress)
        } else {
            let reach = ease(progress / 0.32)
            let retreat = ease((progress - 0.4) / 0.6)
            let travel = direction * 110 * retreat
            card.position = CGPoint(x: from.midX + travel, y: from.midY + 6 * retreat)
            let gripX = direction < 0 ? from.minX + 8 : from.maxX - 8
            hand.position = CGPoint(x: gripX + direction * 48 * (1 - reach) + travel,
                                    y: from.midY + 6 * retreat)
            hand.contents = progress < 0.32 ? openHand : closedHand
            let opacity = Float(1 - ease((progress - 0.55) / 0.45))
            card.opacity = opacity
            hand.opacity = opacity * Float(ease(progress / 0.12))
        }
        CATransaction.commit()
    }
}
