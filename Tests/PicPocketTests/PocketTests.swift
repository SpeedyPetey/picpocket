import AppKit
import XCTest
@testable import PicPocket

final class PocketTests: XCTestCase {
    @MainActor func testPocketSitsAtBottomRightAndSupportsFullScreen() throws {
        let screen = try XCTUnwrap(NSScreen.screens.first)
        let panel = LinePanel(content: NSView())
        panel.placeOnScreen(screen)
        XCTAssertEqual(panel.frame.width, panel.frame.height)
        XCTAssertEqual(panel.frame.maxX, screen.visibleFrame.maxX - 12)
        XCTAssertEqual(panel.frame.minY, screen.visibleFrame.minY + 12)
        XCTAssertTrue(panel.collectionBehavior.contains(.fullScreenAuxiliary))
        XCTAssertFalse(panel.canBecomeKey)
    }
    func testCornerTriggerOnDisplayWithNegativeOrigin() {
        let screen = CGRect(x: -1920, y: -200, width: 1920, height: 1080)
        let zone = Layout.hotZone(in: screen)
        XCTAssertTrue(zone.contains(CGPoint(x: -1, y: -199)))
        XCTAssertFalse(zone.contains(CGPoint(x: -100, y: -199)))
        XCTAssertFalse(zone.contains(CGPoint(x: -1, y: 879)))
    }

    @MainActor func testMenuUsesPocketBranding() {
        let delegate = AppDelegate()
        let menu = NSMenu()
        delegate.menuNeedsUpdate(menu)
        let titles = menu.items.filter { !$0.isSeparatorItem }.map(\.title)
        XCTAssertEqual(titles, ["Show pocket", "Empty pocket", "Handle screenshots",
                                "Open screenshots folder", "Sounds", "Open at login", "Quit PicPocket"])
    }

    func testCaptureCountResetsOnNewDayAndPersists() throws {
        let suite = "PicPocketStatsTests-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let stats = PocketStats(defaults: defaults)
        let today = Date()
        let tomorrow = try XCTUnwrap(Calendar.current.date(byAdding: .day, value: 1, to: today))
        XCTAssertEqual(stats.count(on: today), 0)
        stats.recordCapture(on: today)
        stats.recordCapture(on: today)
        XCTAssertEqual(PocketStats(defaults: defaults).count(on: today), 2)
        XCTAssertEqual(stats.count(on: tomorrow), 0)
        stats.recordCapture(on: tomorrow)
        XCTAssertEqual(stats.count(on: tomorrow), 1)
    }

}
