import AppKit

@MainActor
enum HistoryAnchor {
    static func panelFrame(anchor: NSRect, preferredSize: NSSize = NSSize(width: 420, height: 580), visibleFrame: NSRect) -> NSRect {
        let gap: CGFloat = 8
        let bounds = visibleFrame.insetBy(dx: gap, dy: gap)
        let size = NSSize(width: min(preferredSize.width, bounds.width), height: min(preferredSize.height, bounds.height))
        let below = anchor.minY - gap - size.height
        let desiredY = below >= bounds.minY ? below : anchor.maxY + gap
        let x = min(max(anchor.minX, bounds.minX), bounds.maxX - size.width)
        let y = min(max(desiredY, bounds.minY), bounds.maxY - size.height)
        return NSRect(origin: NSPoint(x: x, y: y), size: size)
    }
}
