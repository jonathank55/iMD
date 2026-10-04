#if os(iOS)
import SwiftUI
import UIKit

public struct IOSTextEditor: UIViewRepresentable {
    @Binding public var text: String
    @ObservedObject public var settings: EditorSettings

    public init(text: Binding<String>, settings: EditorSettings) {
        self._text = text
        self.settings = settings
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    public func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.delegate = context.coordinator
        textView.isEditable = true
        textView.isSelectable = true
        textView.isScrollEnabled = true
        textView.alwaysBounceVertical = true
        textView.backgroundColor = .systemBackground
        textView.textColor = .label
        textView.textContainerInset = UIEdgeInsets(top: 16, left: 16, bottom: 32, right: 16)
        textView.autocapitalizationType = .none
        textView.autocorrectionType = .yes
        textView.spellCheckingType = .yes
        textView.smartDashesType = .no
        textView.smartQuotesType = .no

        textView.inputAccessoryView = IOSToolbarAccessory(textView: textView)

        context.coordinator.textView = textView
        context.coordinator.updateContent(textView, newText: text, settings: settings, force: true)

        return textView
    }

    public func updateUIView(_ uiView: UITextView, context: Context) {
        context.coordinator.updateContent(uiView, newText: text, settings: settings, force: false)
    }

    public final class Coordinator: NSObject, UITextViewDelegate {
        var parent: IOSTextEditor
        weak var textView: UITextView?
        private var isUpdatingInternal = false
        private var lastRenderedText: String = ""
        private var lastRenderedFamily: String = ""
        private var lastRenderedSize: Double = 0
        private var lastRenderedJustified: Bool = true
        private var lastRenderedHyphenation: Bool = true

        init(_ parent: IOSTextEditor) {
            self.parent = parent
        }

        func updateContent(_ textView: UITextView, newText: String, settings: EditorSettings, force: Bool) {
            guard !isUpdatingInternal else { return }

            let settingsChanged = (settings.fontFamily != lastRenderedFamily) ||
                                  (settings.fontSize != lastRenderedSize) ||
                                  (settings.isJustified != lastRenderedJustified) ||
                                  (settings.isHyphenationEnabled != lastRenderedHyphenation)

            if force || settingsChanged || (newText != lastRenderedText) {
                isUpdatingInternal = true
                let savedRange = textView.selectedRange

                let attributed = MarkdownHighlighter.shared.highlight(
                    text: newText,
                    selectedRange: savedRange,
                    fontFamily: settings.fontFamily,
                    fontSize: settings.fontSize,
                    isJustified: settings.isJustified,
                    isHyphenationEnabled: settings.isHyphenationEnabled,
                    isMarkdownHighlightingEnabled: settings.isMarkdownHighlightingEnabled
                )

                textView.attributedText = attributed

                if savedRange.location != NSNotFound && (savedRange.location + savedRange.length) <= (newText as NSString).length {
                    textView.selectedRange = savedRange
                }

                lastRenderedText = newText
                lastRenderedFamily = settings.fontFamily
                lastRenderedSize = settings.fontSize
                lastRenderedJustified = settings.isJustified
                lastRenderedHyphenation = settings.isHyphenationEnabled
                isUpdatingInternal = false
            }
        }

        public func textViewDidChange(_ textView: UITextView) {
            guard !isUpdatingInternal else { return }
            isUpdatingInternal = true

            let currentText = textView.text ?? ""
            parent.text = currentText
            lastRenderedText = currentText

            let selectedRange = textView.selectedRange
            let attributed = MarkdownHighlighter.shared.highlight(
                text: currentText,
                selectedRange: selectedRange,
                fontFamily: parent.settings.fontFamily,
                fontSize: parent.settings.fontSize,
                isJustified: parent.settings.isJustified,
                isHyphenationEnabled: parent.settings.isHyphenationEnabled,
                isMarkdownHighlightingEnabled: parent.settings.isMarkdownHighlightingEnabled
            )

            textView.attributedText = attributed
            if selectedRange.location != NSNotFound && (selectedRange.location + selectedRange.length) <= (currentText as NSString).length {
                textView.selectedRange = selectedRange
            }

            isUpdatingInternal = false
        }

        public func textViewDidChangeSelection(_ textView: UITextView) {
            guard !isUpdatingInternal, parent.settings.isMarkdownHighlightingEnabled else { return }

            // Re-render highlight when cursor changes lines (Obsidian-style live preview)
            let selectedRange = textView.selectedRange
            let currentText = textView.text ?? ""

            isUpdatingInternal = true
            let attributed = MarkdownHighlighter.shared.highlight(
                text: currentText,
                selectedRange: selectedRange,
                fontFamily: parent.settings.fontFamily,
                fontSize: parent.settings.fontSize,
                isJustified: parent.settings.isJustified,
                isHyphenationEnabled: parent.settings.isHyphenationEnabled,
                isMarkdownHighlightingEnabled: parent.settings.isMarkdownHighlightingEnabled
            )

            textView.attributedText = attributed
            if selectedRange.location != NSNotFound && (selectedRange.location + selectedRange.length) <= (currentText as NSString).length {
                textView.selectedRange = selectedRange
            }
            isUpdatingInternal = false
        }
    }
}
#endif
