import SwiftUI
import AppKit

extension Notification.Name {
    public static let iTextDocumentSaved = Notification.Name("iTextDocumentSaved")
    public static let iTextFormatBoldRequested = Notification.Name("iTextFormatBoldRequested")
    public static let iTextFormatItalicRequested = Notification.Name("iTextFormatItalicRequested")
    public static let iTextFormatStrikethroughRequested = Notification.Name("iTextFormatStrikethroughRequested")
    public static let iTextFormatCodeRequested = Notification.Name("iTextFormatCodeRequested")
    public static let iTextFormatHeading1Requested = Notification.Name("iTextFormatHeading1Requested")
    public static let iTextFormatHeading2Requested = Notification.Name("iTextFormatHeading2Requested")
    public static let iTextFormatHeading3Requested = Notification.Name("iTextFormatHeading3Requested")
}

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

        let coordinator = context.coordinator
        coordinator.textView = textView
        coordinator.updateContent(textView, newText: text, settings: settings, force: true)

        DispatchQueue.main.async { [weak textView, weak coordinator] in
            guard let tv = textView, let window = tv.window, let coord = coordinator else { return }
            if window.delegate !== coord {
                coord.previousWindowDelegate = window.delegate
                window.delegate = coord
            }
        }

        return scrollView
    }

    public func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? NSTextView else { return }
        context.coordinator.updateContent(textView, newText: text, settings: settings, force: false)

        let coordinator = context.coordinator
        if let window = textView.window, window.delegate !== coordinator {
            coordinator.previousWindowDelegate = window.delegate
            window.delegate = coordinator
        }
    }

    public final class Coordinator: NSObject, NSTextViewDelegate, NSWindowDelegate {
        var parent: MacTextEditor
        weak var textView: NSTextView?
        weak var previousWindowDelegate: NSWindowDelegate?

        private var isUpdatingInternal = false
        private var lastRenderedText: String = ""
        private var lastRenderedFamily: String = ""
        private var lastRenderedSize: Double = 0
        private var lastRenderedLineSpacing: Double = 3.0
        private var lastRenderedJustified: Bool = true
        private var lastRenderedHyphenation: Bool = true
        private var lastRenderedMarkdownEnabled: Bool = true
        private var lastActiveLineRange: NSRange = NSRange(location: NSNotFound, length: 0)
        private var initialLoadedText: String?

        init(_ parent: MacTextEditor) {
            self.parent = parent
            super.init()

            let nc = NotificationCenter.default
            nc.addObserver(self, selector: #selector(handleDocumentSaved), name: .iTextDocumentSaved, object: nil)
            nc.addObserver(self, selector: #selector(handleFormatBold), name: .iTextFormatBoldRequested, object: nil)
            nc.addObserver(self, selector: #selector(handleFormatItalic), name: .iTextFormatItalicRequested, object: nil)
            nc.addObserver(self, selector: #selector(handleFormatStrikethrough), name: .iTextFormatStrikethroughRequested, object: nil)
            nc.addObserver(self, selector: #selector(handleFormatCode), name: .iTextFormatCodeRequested, object: nil)
            nc.addObserver(self, selector: #selector(handleFormatHeading1), name: .iTextFormatHeading1Requested, object: nil)
            nc.addObserver(self, selector: #selector(handleFormatHeading2), name: .iTextFormatHeading2Requested, object: nil)
            nc.addObserver(self, selector: #selector(handleFormatHeading3), name: .iTextFormatHeading3Requested, object: nil)
        }

        deinit {
            NotificationCenter.default.removeObserver(self)
        }

        @objc private func handleDocumentSaved() {
            DispatchQueue.main.async { [weak self] in
                guard let self = self, let tv = self.textView else { return }
                tv.window?.isDocumentEdited = false
                self.initialLoadedText = tv.string
                if let doc = tv.window?.windowController?.document as? NSDocument {
                    doc.updateChangeCount(.changeCleared)
                }
            }
        }

        @objc private func handleFormatBold() {
            guard isWindowActive else { return }
            applyMarkdownWrap(prefix: "**", suffix: "**")
        }

        @objc private func handleFormatItalic() {
            guard isWindowActive else { return }
            applyMarkdownWrap(prefix: "*", suffix: "*")
        }

        @objc private func handleFormatStrikethrough() {
            guard isWindowActive else { return }
            applyMarkdownWrap(prefix: "~~", suffix: "~~")
        }

        @objc private func handleFormatCode() {
            guard isWindowActive else { return }
            applyMarkdownWrap(prefix: "`", suffix: "`")
        }

        @objc private func handleFormatHeading1() {
            guard isWindowActive else { return }
            applyHeadingPrefix(level: 1)
        }

        @objc private func handleFormatHeading2() {
            guard isWindowActive else { return }
            applyHeadingPrefix(level: 2)
        }

        @objc private func handleFormatHeading3() {
            guard isWindowActive else { return }
            applyHeadingPrefix(level: 3)
        }

        private var isWindowActive: Bool {
            guard let window = textView?.window else { return false }
            return window.isKeyWindow
        }

        public func applyMarkdownWrap(prefix: String, suffix: String) {
            guard let tv = textView else { return }
            let selectedRange = tv.selectedRange()
            let fullText = (tv.string as NSString)

            if selectedRange.length > 0 {
                let selected = fullText.substring(with: selectedRange)
                if selected.hasPrefix(prefix) && selected.hasSuffix(suffix) && selected.count >= (prefix.count + suffix.count) {
                    let start = selected.index(selected.startIndex, offsetBy: prefix.count)
                    let end = selected.index(selected.endIndex, offsetBy: -suffix.count)
                    let unwrapped = String(selected[start..<end])

                    if tv.shouldChangeText(in: selectedRange, replacementString: unwrapped) {
                        tv.replaceCharacters(in: selectedRange, with: unwrapped)
                        tv.didChangeText()
                        tv.setSelectedRange(NSRange(location: selectedRange.location, length: (unwrapped as NSString).length))
                    }
                } else {
                    let wrapped = "\(prefix)\(selected)\(suffix)"
                    if tv.shouldChangeText(in: selectedRange, replacementString: wrapped) {
                        tv.replaceCharacters(in: selectedRange, with: wrapped)
                        tv.didChangeText()
                        tv.setSelectedRange(NSRange(location: selectedRange.location, length: (wrapped as NSString).length))
                    }
                }
            } else {
                let wrapped = "\(prefix)\(suffix)"
                if tv.shouldChangeText(in: selectedRange, replacementString: wrapped) {
                    tv.replaceCharacters(in: selectedRange, with: wrapped)
                    tv.didChangeText()
                    tv.setSelectedRange(NSRange(location: selectedRange.location + prefix.count, length: 0))
                }
            }
        }

        public func applyHeadingPrefix(level: Int) {
            guard let tv = textView else { return }
            let selectedRange = tv.selectedRange()
            let fullText = (tv.string as NSString)
            let lineRange = fullText.lineRange(for: selectedRange)
            let lineText = fullText.substring(with: lineRange)

            let hashes = String(repeating: "#", count: level)
            let targetPrefix = "\(hashes) "

            var cleanLine = lineText
            while cleanLine.hasPrefix("#") {
                cleanLine.removeFirst()
            }
            cleanLine = cleanLine.trimmingCharacters(in: .whitespaces)

            let newLine = "\(targetPrefix)\(cleanLine)\n"
            if tv.shouldChangeText(in: lineRange, replacementString: newLine) {
                tv.replaceCharacters(in: lineRange, with: newLine)
                tv.didChangeText()
            }
        }

        public override func responds(to aSelector: Selector!) -> Bool {
            if aSelector == #selector(NSWindowDelegate.windowShouldClose(_:)) {
                return true
            }
            if super.responds(to: aSelector) {
                return true
            }
            return previousWindowDelegate?.responds(to: aSelector) ?? false
        }

        public override func forwardingTarget(for aSelector: Selector!) -> Any? {
            if let prev = previousWindowDelegate, prev.responds(to: aSelector) {
                return prev
            }
            return super.forwardingTarget(for: aSelector)
        }

        public func windowShouldClose(_ sender: NSWindow) -> Bool {
            guard sender.isDocumentEdited else {
                return previousWindowDelegate?.windowShouldClose?(sender) ?? true
            }

            let alert = NSAlert()
            let rawTitle = sender.title
                .replacingOccurrences(of: " — Bearbeitet", with: "")
                .replacingOccurrences(of: " — Edited", with: "")
                .trimmingCharacters(in: .whitespaces)
            let docName = rawTitle.isEmpty ? "Dokument" : rawTitle

            alert.messageText = "Möchten Sie die Änderungen am Dokument „\(docName)“ sichern?"
            alert.informativeText = "Ihre Änderungen gehen verloren, wenn Sie sie nicht sichern."
            alert.alertStyle = .warning
            alert.addButton(withTitle: "Sichern")
            alert.addButton(withTitle: "Nicht sichern")
            alert.addButton(withTitle: "Abbrechen")

            let response = alert.runModal()
            switch response {
            case .alertFirstButtonReturn: // Sichern
                NSApp.sendAction(#selector(NSDocument.save(_:)), to: nil, from: nil)
                sender.isDocumentEdited = false
                return true
            case .alertSecondButtonReturn: // Nicht sichern
                sender.isDocumentEdited = false
                if let doc = sender.windowController?.document as? NSDocument {
                    doc.updateChangeCount(.changeCleared)
                }
                return true
            default: // Abbrechen
                return false
            }
        }

        func updateContent(_ textView: NSTextView, newText: String, settings: EditorSettings, force: Bool) {
            guard !isUpdatingInternal else { return }

            if initialLoadedText == nil {
                initialLoadedText = newText
            }

            let settingsChanged = (settings.fontFamily != lastRenderedFamily) ||
                                  (settings.fontSize != lastRenderedSize) ||
                                  (settings.lineSpacing != lastRenderedLineSpacing) ||
                                  (settings.isJustified != lastRenderedJustified) ||
                                  (settings.isHyphenationEnabled != lastRenderedHyphenation) ||
                                  (settings.isMarkdownHighlightingEnabled != lastRenderedMarkdownEnabled)

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
                    lineSpacing: settings.lineSpacing,
                    isJustified: settings.isJustified,
                    isHyphenationEnabled: settings.isHyphenationEnabled,
                    isMarkdownHighlightingEnabled: settings.isMarkdownHighlightingEnabled
                )

                textView.undoManager?.disableUndoRegistration()
                textView.textStorage?.beginEditing()
                textView.textStorage?.setAttributedString(attributed)
                textView.textStorage?.endEditing()
                textView.undoManager?.enableUndoRegistration()

                if selectedRange.location != NSNotFound && (selectedRange.location + selectedRange.length) <= (newText as NSString).length {
                    textView.selectedRanges = savedRanges
                }

                lastRenderedText = newText
                lastRenderedFamily = settings.fontFamily
                lastRenderedSize = settings.fontSize
                lastRenderedLineSpacing = settings.lineSpacing
                lastRenderedJustified = settings.isJustified
                lastRenderedHyphenation = settings.isHyphenationEnabled
                lastRenderedMarkdownEnabled = settings.isMarkdownHighlightingEnabled

                let nsText = newText as NSString
                if selectedRange.location != NSNotFound && selectedRange.location <= nsText.length {
                    lastActiveLineRange = nsText.lineRange(for: selectedRange)
                } else {
                    lastActiveLineRange = NSRange(location: NSNotFound, length: 0)
                }

                isUpdatingInternal = false
            }
        }

        public func textDidChange(_ notification: Notification) {
            guard !isUpdatingInternal, let tv = textView else { return }
            isUpdatingInternal = true

            let currentText = tv.string
            parent.text = currentText
            lastRenderedText = currentText

            if let window = tv.window {
                let hasChanges = (initialLoadedText != nil) ? (currentText != initialLoadedText) : !currentText.isEmpty
                window.isDocumentEdited = hasChanges
                if let doc = window.windowController?.document as? NSDocument {
                    if hasChanges {
                        doc.updateChangeCount(.changeDone)
                    } else {
                        doc.updateChangeCount(.changeCleared)
                    }
                }
            }

            let selectedRange = tv.selectedRange()
            let attributed = MarkdownHighlighter.shared.highlight(
                text: currentText,
                isMarkdown: parent.isMarkdown,
                selectedRange: selectedRange,
                fontFamily: parent.settings.fontFamily,
                fontSize: parent.settings.fontSize,
                lineSpacing: parent.settings.lineSpacing,
                isJustified: parent.settings.isJustified,
                isHyphenationEnabled: parent.settings.isHyphenationEnabled,
                isMarkdownHighlightingEnabled: parent.settings.isMarkdownHighlightingEnabled
            )

            tv.undoManager?.disableUndoRegistration()
            tv.textStorage?.beginEditing()
            tv.textStorage?.setAttributedString(attributed)
            tv.textStorage?.endEditing()
            tv.undoManager?.enableUndoRegistration()

            if selectedRange.location != NSNotFound && (selectedRange.location + selectedRange.length) <= (currentText as NSString).length {
                tv.setSelectedRange(selectedRange)
            }

            let nsText = currentText as NSString
            if selectedRange.location != NSNotFound && selectedRange.location <= nsText.length {
                lastActiveLineRange = nsText.lineRange(for: selectedRange)
            } else {
                lastActiveLineRange = NSRange(location: NSNotFound, length: 0)
            }

            isUpdatingInternal = false
        }

        public func textViewDidChangeSelection(_ notification: Notification) {
            guard !isUpdatingInternal, parent.isMarkdown, parent.settings.isMarkdownHighlightingEnabled, let tv = textView else { return }

            let selectedRange = tv.selectedRange()
            let currentText = tv.string
            let nsText = currentText as NSString

            guard selectedRange.location != NSNotFound && selectedRange.location <= nsText.length else { return }
            let currentLineRange = nsText.lineRange(for: selectedRange)

            if currentLineRange.location == lastActiveLineRange.location &&
               currentLineRange.length == lastActiveLineRange.length {
                return
            }

            lastActiveLineRange = currentLineRange
            isUpdatingInternal = true

            let attributed = MarkdownHighlighter.shared.highlight(
                text: currentText,
                isMarkdown: parent.isMarkdown,
                selectedRange: selectedRange,
                fontFamily: parent.settings.fontFamily,
                fontSize: parent.settings.fontSize,
                lineSpacing: parent.settings.lineSpacing,
                isJustified: parent.settings.isJustified,
                isHyphenationEnabled: parent.settings.isHyphenationEnabled,
                isMarkdownHighlightingEnabled: parent.settings.isMarkdownHighlightingEnabled
            )

            tv.undoManager?.disableUndoRegistration()
            tv.textStorage?.beginEditing()
            tv.textStorage?.setAttributedString(attributed)
            tv.textStorage?.endEditing()
            tv.undoManager?.enableUndoRegistration()

            if selectedRange.location != NSNotFound && (selectedRange.location + selectedRange.length) <= nsText.length {
                tv.setSelectedRange(selectedRange)
            }
            isUpdatingInternal = false
        }
    }
}
