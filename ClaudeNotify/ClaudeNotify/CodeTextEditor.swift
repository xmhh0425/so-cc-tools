import SwiftUI
import AppKit

/// Plain-text code editor for JSON/script content.
///
/// Wraps NSTextView and disables every "helpful" macOS text feature that
/// corrupts code: smart quotes, smart dashes, autocorrect, link detection,
/// text replacement. Uses a monospaced font.
struct CodeTextEditor: NSViewRepresentable {
    @Binding var text: String
    var font: NSFont = .monospacedSystemFont(ofSize: 12, weight: .regular)

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

        // Kill every auto-correction feature. This is what causes
        // "I changed a string and now JSON is invalid" — TextEditor was
        // replacing ASCII quotes with curly quotes.
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

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        if textView.string != text {
            // Preserve selection where possible.
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
