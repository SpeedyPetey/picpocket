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

    func testDedicatedFolderAcceptsVideosButDesktopRejectsUntaggedFiles() {
        let folder = ScreenshotWatcher(folder: URL(fileURLWithPath: "/tmp/pocket-tests"),
                                       onNew: { _ in true }, onChange: {})
        let desktop = ScreenshotWatcher(folder: ScreenshotWatcher.desktop,
                                        onNew: { _ in true }, onChange: {})
        for name in ["recording.mov", "recording.MP4", "recording.m4v", "capture.png"] {
            let url = URL(fileURLWithPath: "/tmp/pocket-tests/" + name)
            XCTAssertTrue(folder.isCandidate(url))
            XCTAssertFalse(desktop.isCandidate(url))
        }
        XCTAssertFalse(folder.isCandidate(URL(fileURLWithPath: "/tmp/pocket-tests/file.txt")))
    }

    @MainActor func testWatcherRetriesCaptureUntilItIsReady() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        var attempts = 0
        let ready = expectation(description: "Unfinished recording retried")
        let watcher = ScreenshotWatcher(folder: folder, onNew: { _ in
            attempts += 1
            if attempts == 2 { ready.fulfill() }
            return attempts >= 2
        }, onChange: {})
        try Data().write(to: folder.appendingPathComponent("recording.mov"))
        watcher.start()
        defer { watcher.stop() }
        wait(for: [ready], timeout: 4)
        XCTAssertEqual(attempts, 2)
    }

    func testVideoThumbnailAndBadgeClassification() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "recording", withExtension: "mov"))
        let thumbnail = try XCTUnwrap(makeThumbnail(url, maxPixels: 80))
        XCTAssertLessThanOrEqual(max(thumbnail.size.width, thumbnail.size.height), 80)
        XCTAssertTrue(Pegged(url: url, thumb: thumbnail).isVideo)
        XCTAssertFalse(Pegged(url: url.deletingPathExtension().appendingPathExtension("png"), thumb: thumbnail).isVideo)
    }

    @MainActor func testHoverUsesCurrentPositionsAfterRemovalAndPointerReturn() {
        let thumb = NSImage(size: CGSize(width: 160, height: 90))
        let older = Pegged(url: URL(fileURLWithPath: "/tmp/older.png"), thumb: thumb)
        var newer = Pegged(url: URL(fileURLWithPath: "/tmp/newer.png"), thumb: thumb)
        let left = Layout.cardCenter(index: 0)
        let right = Layout.cardCenter(index: 1)
        XCTAssertEqual(Layout.hoveredID(in: [older, newer], at: left), newer.id)
        XCTAssertNil(Layout.hoveredID(in: [older, newer], at: .zero))
        XCTAssertEqual(Layout.hoveredID(in: [older, newer], at: left), newer.id)
        newer.falling = true
        XCTAssertNil(Layout.hoveredID(in: [older, newer], at: left))
        XCTAssertEqual(Layout.hoveredID(in: [older, newer], at: right), older.id)
        XCTAssertEqual(Layout.hoveredID(in: [older], at: left), older.id)
        XCTAssertNil(Layout.hoveredID(in: [older], at: right))
    }

}
