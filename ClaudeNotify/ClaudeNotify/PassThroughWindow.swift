import AppKit
import SwiftUI

/// Shared hover state bridging AppKit mouse tracking to SwiftUI.
@Observable
final class HoverState {
    var isHovering = false
}
