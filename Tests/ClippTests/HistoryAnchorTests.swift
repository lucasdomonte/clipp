import AppKit
import XCTest
@testable import Clipp

final class HistoryAnchorTests: XCTestCase {
    @MainActor
    func testPanelOpensBelowAnchorOrAboveWhenThereIsMoreRoom() {
        let screen = NSRect(x: -1440, y: 0, width: 1440, height: 900)
        XCTAssertEqual(HistoryAnchor.panelFrame(anchor: NSRect(x: -1000, y: 800, width: 0, height: 20), visibleFrame: screen),
                       NSRect(x: -1000, y: 212, width: 420, height: 580))
        XCTAssertEqual(HistoryAnchor.panelFrame(anchor: NSRect(x: -1000, y: 100, width: 0, height: 20), visibleFrame: screen),
                       NSRect(x: -1000, y: 128, width: 420, height: 580))
    }

    @MainActor
    func testWholePanelStaysVisibleAtCornersEdgesAndCenterAcrossMonitors() {
        for origin in [NSPoint.zero, NSPoint(x: -1440, y: 0), NSPoint(x: 0, y: 900), NSPoint(x: 0, y: -900)] {
            let screen = NSRect(origin: origin, size: NSSize(width: 1440, height: 900))
            for x in [screen.minX, screen.midX, screen.maxX] {
                for y in [screen.minY, screen.midY, screen.maxY] {
                    let frame = HistoryAnchor.panelFrame(anchor: NSRect(x: x, y: y, width: 1, height: 1), visibleFrame: screen)
                    XCTAssertTrue(screen.insetBy(dx: 8, dy: 8).contains(frame), "Panel \(frame) escaped screen \(screen) at mouse \(x), \(y)")
                    XCTAssertEqual(frame.size, NSSize(width: 420, height: 580))
                }
            }
        }
    }

    @MainActor
    func testPanelShrinksToKeepAllControlsInsideSmallerScreen() {
        let screen = NSRect(x: -400, y: -200, width: 300, height: 400)
        for x in [screen.minX, screen.midX, screen.maxX] {
            for y in [screen.minY, screen.midY, screen.maxY] {
                let frame = HistoryAnchor.panelFrame(anchor: NSRect(x: x, y: y, width: 1, height: 1), visibleFrame: screen)
                XCTAssertEqual(frame, NSRect(x: -392, y: -192, width: 284, height: 384))
            }
        }
    }
}
