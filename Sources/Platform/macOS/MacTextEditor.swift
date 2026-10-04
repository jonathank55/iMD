import SwiftUI
import AppKit

public struct MacTextEditor: NSViewRepresentable {
    @Binding public var text: String
    public var isMarkdown: Bool
    @ObservedObject public var settings: EditorSettings

    public init(text: Binding<String>, isMarkdown: Bool, settings: EditorSettings) {
        self._text = text
        self.isMarkdown = isMarkdown
        self.settings = settings
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    public func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        guard let textView = scrollView.documentView as? NSTextView else {
            return scrollView
        }

        textView.delegate = context.coordinator
        textView.isRichText = true
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.isEditable = true
        textView.isSelectable = true
        textView.backgroundColor = .textBackgroundColor
        textView.textColor = .labelColor
        textView.textContainerInset = NSSize(width: 24, height: 24)
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false

        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true

        context.coordinator.textView = textView
        context.coordinator.updateContent(textView, newText: text, settings: settings, force: true)

        return scrollView
    }

    public func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? NSTextView else { return }
        context.coordinator.updateContent(textView, newText: text, settings: settings, force: false)
    }

    public final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: MacTextEditor
        weak var textView: NSTextView?
        private var isUpdatingInternal = false
        private var lastRenderedText: String = ""
        private var lastRenderedFamily: String = ""
        private var lastRenderedSize: Double = 0
        private var lastRenderedJustified: Bool = true
        private var lastRenderedHyphenation: Bool = true

        init(_ parent: MacTextEditor) {
            self.parent = parent
        }

        func updateContent(_ textView: NSTextView, newText: String, settings: EditorSettings, force: Bool) {
            guard !isUpdatingInternal else { return }

            let settingsChanged = (settings.fontFamily != lastRenderedFamily) ||
                                  (settings.fontSize != lastRenderedSize) ||
                                  (settings.isJustified != lastRenderedJustified) ||
                                  (settings.isHyphenationEnabled != lastRenderedHyphenation)

            if force || settingsChanged || (newText != lastRenderedText) {
                isUpdatingInternal = true
                let savedRanges = textView.selectedRanges

                let selectedRange = savedRanges.first?.rangeValue ?? NSRange(location: NSNotFound, length: 0)
                let attributed = MarkdownHighlighter.shared.highlight(
                    text: newText,
                    isMarkdown: parent.isMarkdown,
                    selectedRange: selectedRange,
                    fontFamily: settings.fontFamily,
                    fontSize: settings.fontSize,
                    isJustified: settings.isJustified,
                    isHyphenationEnabled: settings.isHyphenationEnabled,
                    isMarkdownHighlightingEnabled: settings.isMarkdownHighlightingEnabled
                )

                textView.textStorage?.setAttributedString(attributed)

                if selectedRange.location != NSNotFound && (selectedRange.location + selectedRange.length) <= (newText as NSString).length {
                    textView.selectedRanges = savedRanges
                }

                lastRenderedText = newText
                lastRenderedFamily = settings.fontFamily
                lastRenderedSize = settings.fontSize
                lastRenderedJustified = settings.isJustified
                lastRenderedHyphenation = settings.isHyphenationEnabled
                isUpdatingInternal = false
            }
        }

        public func textDidChange(_ notification: Notification) {
            guard !isUpdatingInternal, let tv = textView else { return }
            isUpdatingInternal = true

            let currentText = tv.string
            parent.text = currentText
            lastRenderedText = currentText

            let selectedRange = tv.selectedRange()
            let attributed = MarkdownHighlighter.shared.highlight(
                text: currentText,
                isMarkdown: parent.isMarkdown,
                selectedRange: selectedRange,
                fontFamily: parent.settings.fontFamily,
                fontSize: parent.settings.fontSize,
                isJustified: parent.settings.isJustified,
                isHyphenationEnabled: parent.settings.isHyphenationEnabled,
                isMarkdownHighlightingEnabled: parent.settings.isMarkdownHighlightingEnabled
            )

            tv.textStorage?.setAttributedString(attributed)
            if selectedRange.location != NSNotFound && (selectedRange.location + selectedRange.length) <= (currentText as NSString).length {
                tv.setSelectedRange(selectedRange)
            }

            isUpdatingInternal = false
        }

        public func textViewDidChangeSelection(_ notification: Notification) {
            guard !isUpdatingInternal, parent.isMarkdown, parent.settings.isMarkdownHighlightingEnabled, let tv = textView else { return }

            let selectedRange = tv.selectedRange()
            let currentText = tv.string

            isUpdatingInternal = true
            let attributed = MarkdownHighlighter.shared.highlight(
                text: currentText,
                isMarkdown: parent.isMarkdown,
                selectedRange: selectedRange,
                fontFamily: parent.settings.fontFamily,
                fontSize: parent.settings.fontSize,
                isJustified: parent.settings.isJustified,
                isHyphenationEnabled: parent.settings.isHyphenationEnabled,
                isMarkdownHighlightingEnabled: parent.settings.isMarkdownHighlightingEnabled
            )

            tv.textStorage?.setAttributedString(attributed)
            if selectedRange.location != NSNotFound && (selectedRange.location + selectedRange.length) <= (currentText as NSString).length {
                tv.setSelectedRange(selectedRange)
            }
            isUpdatingInternal = false
        }
    }
}
