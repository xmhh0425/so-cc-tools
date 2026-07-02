import SwiftUI
import AppKit

/// Plain-text code editor with per-line background color support.
///
/// Wraps NSTextView, disables macOS "helpful" text features (smart quotes
/// etc.), and applies colored backgrounds to specified line ranges via the
/// layout manager.
struct CodeTextEditor: NSViewRepresentable {
    @Binding var text: String
    var font: NSFont = .monospacedSystemFont(ofSize: 12, weight: .regular)
    /// Line-range → color mapping. Lines are 1-based.
    var lineHighlights: [Int: Color] = [:]

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false

        guard let textView = scrollView.documentView as? NSTextView else {
            return scrollView
        }

        textView.delegate = context.coordinator
        textView.isEditable = true
        textView.isSelectable = true
        textView.allowsUndo = true
        textView.isRichText = false
        textView.importsGraphics = false

        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isAutomaticDataDetectionEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.isGrammarCheckingEnabled = false
        textView.smartInsertDeleteEnabled = false
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true

        textView.font = font
        textView.textColor = .labelColor
        textView.backgroundColor = .clear
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 4, height: 6)

        textView.string = text
        applyHighlights(textView)

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        if textView.string != text {
            let selected = textView.selectedRanges
            textView.string = text
            textView.selectedRanges = selected.compactMap { value in
                let range = value.rangeValue
                let max = textView.string.utf16.count
                guard range.location <= max else { return nil }
                let length = min(range.length, max - range.location)
                return NSValue(range: NSRange(location: range.location, length: length))
            }
        }
        if textView.font != font {
            textView.font = font
        }
        applyHighlights(textView)
    }

    /// Apply colored backgrounds to individual lines via the layout manager.
    /// Uses the character range of each line to set the `backgroundColor`
    /// attribute on the text storage — this is a visual-only attribute and
    /// does NOT trigger textDidChange or interfere with editing.
    private func applyHighlights(_ textView: NSTextView) {
        guard let storage = textView.textStorage,
              let layoutManager = textView.layoutManager else { return }

        let text = textView.string as NSString
        let fullRange = NSRange(location: 0, length: text.length)

        // Clear all background colors first.
        storage.removeAttribute(.backgroundColor, range: fullRange)

        guard !lineHighlights.isEmpty else {
            layoutManager.invalidateDisplay(forCharacterRange: fullRange)
            return
        }

        // For each highlighted line, set background color on its character range.
        var line = 1
        var start = 0
        while start < text.length {
            let end = text.range(of: "\n", range: NSRange(location: start, length: text.length - start))
            let lineEnd = end.location == NSNotFound ? text.length : end.location
            if let color = lineHighlights[line] {
                let charRange = NSRange(location: start, length: lineEnd - start)
                storage.addAttribute(.backgroundColor, value: NSColor(color), range: charRange)
            }
            start = lineEnd + 1
            line += 1
        }

        layoutManager.invalidateDisplay(forCharacterRange: fullRange)
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: CodeTextEditor

        init(_ parent: CodeTextEditor) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
        }
    }
}
