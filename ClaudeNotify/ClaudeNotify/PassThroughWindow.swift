import AppKit
import SwiftUI

/// Shared hover state — updated by AppKit tracking events, observed by SwiftUI.
@Observable
final class HoverState {
    var isHovering = false
    var onDismiss: (() -> Void)?
}

/// An `NSHostingView` that reports hover and drives the cursor via an
/// `NSTrackingArea`. Using `.activeAlways` means `mouseEntered/Moved/Exited`
/// and `cursorUpdate` fire even when the window is **not** key — so the close
/// (×) button can appear and the cursor can switch to a pointing hand without
/// the banner ever stealing focus or requiring a click.
final class HoverTrackingHostingView<Content: View>: NSHostingView<Content> {
    /// Called with `true`/`false` as the cursor enters/leaves the view.
    var onHoverChange: ((Bool) -> Void)?

    /// Top-right hit area (in points) treated as the close (×) button.
    var closeHitArea = NSSize(width: 56, height: 48)

    private var hoverTracking: NSTrackingArea?

    // `NSHostingView.init(rootView:)` is a `required` initializer, so it must
    // be satisfied with `required` (not `override`).
    required init(rootView: Content) {
        super.init(rootView: rootView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverTracking { removeTrackingArea(hoverTracking) }
        let tracking = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .mouseMoved, .cursorUpdate, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(tracking)
        hoverTracking = tracking
    }

    override func mouseEntered(with event: NSEvent) {
        onHoverChange?(true)
        applyCursor(for: event)
    }

    override func mouseMoved(with event: NSEvent) {
        onHoverChange?(true)
        applyCursor(for: event)
    }

    override func mouseExited(with event: NSEvent) {
        onHoverChange?(false)
        NSCursor.arrow.set()
    }

    /// System-driven cursor refresh — claim authority so SwiftUI/AppKit don't
    /// reset us back to the arrow while we're over the × button.
    override func cursorUpdate(with event: NSEvent) {
        applyCursor(for: event)
    }

    private func applyCursor(for event: NSEvent) {
        // `locationInWindow` is bottom-left origin and flip-agnostic; the
        // content view fills the window, so it maps straight onto `bounds`.
        let loc = event.locationInWindow
        let overClose = loc.x >= bounds.width - closeHitArea.width
            && loc.y >= bounds.height - closeHitArea.height
        if overClose {
            NSCursor.pointingHand.set()
        } else {
            NSCursor.arrow.set()
        }
    }
}
