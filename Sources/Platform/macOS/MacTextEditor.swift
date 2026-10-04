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
    public static let iTextUndoRequested = Notification.Name("iTextUndoRequested")
    public static let iTextRedoRequested = Notification.Name("iTextRedoRequested")
}

/// Zeichnet echte Tabellenraster und horizontale Trennlinien (Obsidian-Vorbild) hinter dem Text.
public final class iTextLayoutManager: NSLayoutManager {
    public override func drawBackground(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        super.drawBackground(forGlyphRange: glyphsToShow, at: origin)
        guard let storage = textStorage, let container = textContainers.first else { return }
        let charRange = characterRange(forGlyphRange: glyphsToShow, actualGlyphRange: nil)
        let pad = container.lineFragmentPadding
        let lineColor = NSColor.separatorColor

        storage.enumerateAttribute(.iTextRule, in: charRange, options: []) { value, range, _ in
            guard value != nil else { return }
            let glyphRange = self.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            guard glyphRange.length > 0 else { return }
            let used = self.lineFragmentUsedRect(forGlyphAt: glyphRange.location, effectiveRange: nil)
            let frag = self.lineFragmentRect(forGlyphAt: glyphRange.location, effectiveRange: nil)
            let y = (origin.y + used.midY).rounded() + 0.5
            let path = NSBezierPath()
            let viewport = MarkdownHighlighter.shared.viewportTextWidth
            let right = viewport > 0 ? min(frag.maxX, viewport) : frag.maxX
            path.move(to: NSPoint(x: origin.x + frag.minX + pad, y: y))
            path.line(to: NSPoint(x: origin.x + right - pad, y: y))
            path.lineWidth = 1
            lineColor.setStroke()
            path.stroke()
        }

        storage.enumerateAttribute(.iTextTableRow, in: charRange, options: []) { value, range, _ in
            guard let info = value as? iTextTableRowInfo, info.colX.count >= 2 else { return }
            let glyphRange = self.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            guard glyphRange.length > 0 else { return }
            let frag = self.lineFragmentRect(forGlyphAt: glyphRange.location, effectiveRange: nil)
            let x0 = origin.x + frag.minX + pad
            let top = origin.y + frag.minY
            let bottom = origin.y + frag.maxY
            let width = info.colX.last ?? 0
            let rowRect = NSRect(x: x0, y: top, width: width, height: bottom - top)

            if info.isHeader {
                NSColor.quaternaryLabelColor.withAlphaComponent(0.35).setFill()
                rowRect.fill()
            }
            lineColor.setStroke()
            let path = NSBezierPath()
            path.lineWidth = 1
            // Obere und untere Kante
            path.move(to: NSPoint(x: x0, y: top.rounded() + 0.5))
            path.line(to: NSPoint(x: x0 + width, y: top.rounded() + 0.5))
            path.move(to: NSPoint(x: x0, y: bottom.rounded() - 0.5))
            path.line(to: NSPoint(x: x0 + width, y: bottom.rounded() - 0.5))
            // Spaltenlinien
            for cx in info.colX {
                let x = (x0 + cx).rounded() + 0.5
                path.move(to: NSPoint(x: x, y: top))
                path.line(to: NSPoint(x: x, y: bottom))
            }
            path.stroke()
        }
    }

    /// Tabellenzeilen werden nicht als Rohtext gezeichnet, sondern zellweise mit Umbruch in die Spaltenbreite.
    public override func drawGlyphs(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        guard let storage = textStorage else {
            super.drawGlyphs(forGlyphRange: glyphsToShow, at: origin)
            return
        }
        let charRange = characterRange(forGlyphRange: glyphsToShow, actualGlyphRange: nil)
        let end = charRange.location + charRange.length
        var tableRuns: [NSRange] = []
        storage.enumerateAttribute(.iTextTableRow, in: charRange, options: []) { value, range, _ in
            if value is iTextTableRowInfo { tableRuns.append(range) }
        }

        func drawNormal(_ from: Int, _ to: Int) {
            guard to > from else { return }
            let gr = self.glyphRange(forCharacterRange: NSRange(location: from, length: to - from), actualCharacterRange: nil)
            super.drawGlyphs(forGlyphRange: gr, at: origin)
        }

        var cursor = charRange.location
        for run in tableRuns {
            drawNormal(cursor, run.location)
            cursor = run.location + run.length
        }
        drawNormal(cursor, end)

        guard let container = textContainers.first else { return }
        let pad = container.lineFragmentPadding
        for run in tableRuns {
            var full = NSRange(location: 0, length: 0)
            guard let info = storage.attribute(.iTextTableRow, at: run.location, longestEffectiveRange: &full, in: NSRange(location: 0, length: storage.length)) as? iTextTableRowInfo else { continue }
            let glyphRange = self.glyphRange(forCharacterRange: run, actualCharacterRange: nil)
            guard glyphRange.length > 0 else { continue }
            let frag = self.lineFragmentRect(forGlyphAt: glyphRange.location, effectiveRange: nil)
            let x0 = origin.x + frag.minX + pad
            let top = origin.y + frag.minY
            for (k, rel) in info.cells.enumerated() where k + 1 < info.colX.count {
                let cellRange = NSRange(location: full.location + rel.location, length: rel.length)
                let str: NSAttributedString
                if let cachedString = info.cellStringCache[k] {
                    str = cachedString
                } else {
                    str = iTextTableRowInfo.cellString(from: storage, range: cellRange)
                    info.cellStringCache[k] = str
                }
                guard str.length > 0 else { continue }
                let w = max(10, info.colX[k + 1] - info.colX[k] - 2 * info.padX)
                let rect = NSRect(x: x0 + info.colX[k] + info.padX, y: top + info.padY, width: w, height: frag.height - info.padY)
                str.draw(with: rect, options: [.usesLineFragmentOrigin, .usesFontLeading])
            }
        }
    }
}

public final class iTextEditorTextView: NSTextView {
    public override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags == .command {
            if let chars = event.charactersIgnoringModifiers?.lowercased() {
                if chars == "y" {
                    if let um = self.undoManager, um.canRedo {
                        um.redo()
                    } else if let win = self.window, win.undoManager?.canRedo == true {
                        win.undoManager?.redo()
                    }
                    return true
                } else if chars == "z" {
                    if let um = self.undoManager, um.canUndo {
                        um.undo()
                    } else if let win = self.window, win.undoManager?.canUndo == true {
                        win.undoManager?.undo()
                    }
                    return true
                }
            }
        } else if flags == [.command, .shift] {
            if let chars = event.charactersIgnoringModifiers?.lowercased(), chars == "z" {
                if let um = self.undoManager, um.canRedo {
                    um.redo()
                } else if let win = self.window, win.undoManager?.canRedo == true {
                    win.undoManager?.redo()
                }
                return true
            }
        }
        return super.performKeyEquivalent(with: event)
    }
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
        let textStorage = NSTextStorage()
        let layoutManager = iTextLayoutManager()
        layoutManager.usesDefaultHyphenation = settings.isHyphenationEnabled
        layoutManager.delegate = context.coordinator
        textStorage.addLayoutManager(layoutManager)
        let textContainer = NSTextContainer(containerSize: NSSize(width: 600, height: CGFloat.greatestFiniteMagnitude))
        textContainer.widthTracksTextView = false
        layoutManager.addTextContainer(textContainer)

        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder

        let textView = iTextEditorTextView(frame: .zero, textContainer: textContainer)
        textView.minSize = NSSize(width: 0.0, height: 0.0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = []

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

        scrollView.documentView = textView
        scrollView.contentView.postsFrameChangedNotifications = true
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.handleViewportResize),
            name: NSView.frameDidChangeNotification,
            object: scrollView.contentView
        )

        let coordinator = context.coordinator
        coordinator.textView = textView
        coordinator.updateContent(textView, newText: text, settings: settings, force: true)

        DispatchQueue.main.async { [weak textView, weak coordinator] in
            guard let tv = textView, let window = tv.window, let coord = coordinator else { return }
            if window.delegate !== coord {
                coord.previousWindowDelegate = window.delegate
                window.delegate = coord
            }
            window.makeFirstResponder(tv)
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

    public final class Coordinator: NSObject, NSTextViewDelegate, NSWindowDelegate, NSLayoutManagerDelegate {
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
            nc.addObserver(self, selector: #selector(handleUndoRequested), name: .iTextUndoRequested, object: nil)
            nc.addObserver(self, selector: #selector(handleRedoRequested), name: .iTextRedoRequested, object: nil)
        }

        deinit {
            NotificationCenter.default.removeObserver(self)
        }

        @objc private func handleDocumentSaved() {
            DispatchQueue.main.async { [weak self] in
                guard let self = self, let tv = self.textView else { return }
                tv.window?.isDocumentEdited = false
                self.initialLoadedText = tv.string
                let doc = (tv.window?.windowController?.document as? NSDocument) ?? (tv.window.flatMap { NSDocumentController.shared.document(for: $0) })
                doc?.updateChangeCount(.changeCleared)
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

        @objc private func handleUndoRequested() {
            guard isWindowActive, let tv = textView else { return }
            if let um = tv.undoManager, um.canUndo {
                um.undo()
            } else if let win = tv.window, win.undoManager?.canUndo == true {
                win.undoManager?.undo()
            }
        }

        @objc private func handleRedoRequested() {
            guard isWindowActive, let tv = textView else { return }
            if let um = tv.undoManager, um.canRedo {
                um.redo()
            } else if let win = tv.window, win.undoManager?.canRedo == true {
                win.undoManager?.redo()
            }
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
            let doc = (sender.windowController?.document as? NSDocument) ?? NSDocumentController.shared.document(for: sender)
            let isEdited = sender.isDocumentEdited || (doc?.isDocumentEdited ?? false)
            guard isEdited else {
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
                if let doc = doc {
                    if doc.fileURL != nil {
                        doc.save(nil)
                        sender.isDocumentEdited = false
                        return true
                    } else {
                        NSApp.sendAction(#selector(NSDocument.save(_:)), to: nil, from: nil)
                        return false
                    }
                } else {
                    NSApp.sendAction(#selector(NSDocument.save(_:)), to: nil, from: nil)
                    sender.isDocumentEdited = false
                    return true
                }
            case .alertSecondButtonReturn: // Nicht sichern
                sender.isDocumentEdited = false
                doc?.updateChangeCount(.changeCleared)
                return true
            default: // Abbrechen
                return false
            }
        }

        private var lastViewportWidth: CGFloat = 0
        private var resizeWorkItem: DispatchWorkItem?

        /// Teilt dem Highlighter die aktuelle Sichtbreite mit (vor jedem Highlighting).
        private func syncViewportWidth(_ tv: NSTextView) {
            guard let clip = tv.enclosingScrollView?.contentView else { return }
            let width = max(0, clip.bounds.width - tv.textContainerInset.width * 2)
            MarkdownHighlighter.shared.viewportTextWidth = width
            lastViewportWidth = clip.bounds.width
        }

        /// Setzt Container- und Ansichtsbreite passend zur Fenstergröße.
        private func applyLayoutWidth(_ tv: NSTextView) {
            guard let clip = tv.enclosingScrollView?.contentView, let container = tv.textContainer else { return }
            let inset = tv.textContainerInset.width
            let viewport = max(0, clip.bounds.width - inset * 2)
            guard viewport > 0 else { return }
            let containerWidth = viewport
            if abs(container.size.width - containerWidth) > 0.5 {
                container.size = NSSize(width: containerWidth, height: CGFloat.greatestFiniteMagnitude)
            }
            let frameWidth = containerWidth + inset * 2
            if abs(tv.frame.width - frameWidth) > 0.5 {
                tv.setFrameSize(NSSize(width: frameWidth, height: tv.frame.height))
            }
            tv.needsDisplay = true
        }

        @objc func handleViewportResize() {
            guard !isUpdatingInternal, let tv = textView, let clip = tv.enclosingScrollView?.contentView else { return }
            guard abs(clip.bounds.width - lastViewportWidth) > 0.5 else { return }
            // Beim Aufziehen des Fensters werden Neuberechnungen gebündelt, damit die Bedienung flüssig bleibt
            resizeWorkItem?.cancel()
            let work = DispatchWorkItem { [weak self] in
                guard let self = self, let tv = self.textView else { return }
                self.updateContent(tv, newText: tv.string, settings: self.parent.settings, force: true)
            }
            resizeWorkItem = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: work)
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

                syncViewportWidth(textView)
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

                if let lm = textView.layoutManager {
                    if lm.usesDefaultHyphenation != settings.isHyphenationEnabled {
                        lm.usesDefaultHyphenation = settings.isHyphenationEnabled
                    }
                    if lm.delegate !== self {
                        lm.delegate = self
                    }
                }

                textView.undoManager?.disableUndoRegistration()
                textView.textStorage?.beginEditing()
                textView.textStorage?.setAttributedString(attributed)
                textView.textStorage?.endEditing()
                textView.undoManager?.enableUndoRegistration()
                applyLayoutWidth(textView)

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

        public func layoutManager(_ layoutManager: NSLayoutManager, shouldBreakLineByHyphenatingBeforeCharacterAt charIndex: Int) -> Bool {
            return parent.settings.isHyphenationEnabled
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
                let doc = (window.windowController?.document as? NSDocument) ?? NSDocumentController.shared.document(for: window)
                if let doc = doc {
                    if hasChanges {
                        doc.updateChangeCount(.changeDone)
                    } else {
                        doc.updateChangeCount(.changeCleared)
                    }
                }
            }

            let selectedRange = tv.selectedRange()
            syncViewportWidth(tv)
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
            applyLayoutWidth(tv)

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

            syncViewportWidth(tv)
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
            applyLayoutWidth(tv)

            if selectedRange.location != NSNotFound && (selectedRange.location + selectedRange.length) <= nsText.length {
                tv.setSelectedRange(selectedRange)
            }
            isUpdatingInternal = false
        }
    }
}
