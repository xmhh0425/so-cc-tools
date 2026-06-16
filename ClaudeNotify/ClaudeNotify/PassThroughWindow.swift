import AppKit
import SwiftUI

/// Shared hover state — updated by AppKit tracking events, observed by SwiftUI.
@Observable
final class HoverState {
    var isHovering = false
    var isHoveringClose = false
}

/// An `NSHostingView` that reports hover via an `NSTrackingArea`.
/// `FloatingNotificationManager` also polls global pointer state so hover,
/// cursor, and close clicks work even before the accessory app is active.
final class HoverTrackingHostingView<Content: View>: NSHostingView<Content> {
    /// Called with `true`/`false` as the cursor enters/leaves the view.
    var onHoverChange: ((Bool) -> Void)?

    private var hoverTracking: NSTrackingArea?

    // `NSHostingView.init(rootView:)` is a `required` initializer, so it must
    // be satisfied with `required` (not `override`).
    required init(rootView: Content) {
        super.init(rootView: rootView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverTracking { removeTrackingArea(hoverTracking) }
        let tracking = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(tracking)
        hoverTracking = tracking
    }

    override func mouseEntered(with event: NSEvent) {
        onHoverChange?(true)
    }

    override func mouseMoved(with event: NSEvent) {
        onHoverChange?(true)
    }

    override func mouseExited(with event: NSEvent) {
        onHoverChange?(false)
    }
}
