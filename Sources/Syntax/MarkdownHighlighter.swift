import AppKit

public typealias PlatformFont = NSFont
public typealias PlatformColor = NSColor

public extension NSAttributedString.Key {
    static let iTextRule = NSAttributedString.Key("iTextRule")
    static let iTextTableRow = NSAttributedString.Key("iTextTableRow")
}

public final class iTextTableRowInfo: NSObject {
    public let colX: [CGFloat]
    public let isHeader: Bool
    /// Zellbereiche relativ zum Zeilenanfang (ohne Pipes, ohne Randleerzeichen)
    public let cells: [NSRange]
    public let padX: CGFloat
    public let padY: CGFloat
    /// Zwischenspeicher der aufbereiteten Zelltexte (Info-Objekt lebt nur bis zum nächsten Highlighting)
    public var cellStringCache: [Int: NSAttributedString] = [:]
    public init(colX: [CGFloat], isHeader: Bool, cells: [NSRange], padX: CGFloat, padY: CGFloat) {
        self.colX = colX
        self.isHeader = isHeader
        self.cells = cells
        self.padX = padX
        self.padY = padY
    }

    /// Erzeugt den umbrechenden Zelltext für Zeichnen und Höhenmessung (identische Basis für beides)
    public static func cellString(from source: NSAttributedString, range: NSRange) -> NSAttributedString {
        guard range.length > 0, range.location + range.length <= source.length else { return NSAttributedString() }
        let m = NSMutableAttributedString(attributedString: source.attributedSubstring(from: range))
        let p = NSMutableParagraphStyle()
        p.lineBreakMode = .byWordWrapping
        p.alignment = .left
        p.lineSpacing = 2
        p.hyphenationFactor = 1.0
        m.addAttribute(.paragraphStyle, value: p, range: NSRange(location: 0, length: m.length))
        return m
    }
}

public final class MarkdownHighlighter {
    /// Verfügbare Textbreite des Editors (Container-Breite bei Normaldarstellung). 0 = unbekannt.
    public var viewportTextWidth: CGFloat = 0
    /// Zwischenspeicher der Tabellenmaße (Spaltenbreiten, Zeilenhöhen), damit unveränderte Tabellen nicht erneut vermessen werden.
    private var tableLayoutCache: [String: (colWidths: [CGFloat], rowHeights: [CGFloat])] = [:]

    public static let shared = MarkdownHighlighter()

    private static var fontCache: [String: PlatformFont] = [:]
    private static let cacheLock = NSLock()

    // Vorkompilierte reguläre Ausdrücke für maximale Performance
    private static let boldItalicRegex: NSRegularExpression = {
        (try? NSRegularExpression(pattern: "\\*\\*\\*(.+?)\\*\\*\\*", options: [])) ?? NSRegularExpression()
    }()

    private static let boldItalicUnderscoreRegex: NSRegularExpression = {
        (try? NSRegularExpression(pattern: "___([^_]+?)___", options: [])) ?? NSRegularExpression()
    }()

    private static let boldRegex: NSRegularExpression = {
        (try? NSRegularExpression(pattern: "\\*\\*(.+?)\\*\\*", options: [])) ?? NSRegularExpression()
    }()

    private static let boldUnderscoreRegex: NSRegularExpression = {
        (try? NSRegularExpression(pattern: "__([^_]+?)__", options: [])) ?? NSRegularExpression()
    }()

    private static let italicRegex: NSRegularExpression = {
        (try? NSRegularExpression(pattern: "(?<!\\*)\\*([^*]+?)\\*(?!\\*)", options: [])) ?? NSRegularExpression()
    }()

    private static let italicUnderscoreRegex: NSRegularExpression = {
        (try? NSRegularExpression(pattern: "(?<![\\w_])_([^_]+?)_(?![\\w_])", options: [])) ?? NSRegularExpression()
    }()

    private static let codeRegex: NSRegularExpression = {
        (try? NSRegularExpression(pattern: "`([^`]+?)`", options: [])) ?? NSRegularExpression()
    }()

    private static let strikeRegex: NSRegularExpression = {
        (try? NSRegularExpression(pattern: "~~([^~]+?)~~", options: [])) ?? NSRegularExpression()
    }()

    private static let highlightRegex: NSRegularExpression = {
        (try? NSRegularExpression(pattern: "==([^=]+?)==", options: [])) ?? NSRegularExpression()
    }()

    private static let linkRegex: NSRegularExpression = {
        (try? NSRegularExpression(pattern: "\\[([^\\]]+)\\]\\(([^\\)]+)\\)", options: [])) ?? NSRegularExpression()
    }()

    private static let wikiLinkRegex: NSRegularExpression = {
        (try? NSRegularExpression(pattern: "\\[\\[([^\\]|]+)(?:\\|([^\\]]+))?\\]\\]", options: [])) ?? NSRegularExpression()
    }()

    private static let autolinkRegex: NSRegularExpression = {
        (try? NSRegularExpression(pattern: "<(https?://[^>]+|mailto:[^>]+)>", options: [])) ?? NSRegularExpression()
    }()

    private static let inlineMathRegex: NSRegularExpression = {
        (try? NSRegularExpression(pattern: "(?<!\\$)\\$([^\\$\n]+?)\\$(?!\\$)", options: [])) ?? NSRegularExpression()
    }()

    private static let kbdRegex: NSRegularExpression = {
        (try? NSRegularExpression(pattern: "<kbd>([^<]+?)</kbd>", options: [])) ?? NSRegularExpression()
    }()

    private static let footnoteRefRegex: NSRegularExpression = {
        (try? NSRegularExpression(pattern: "\\[\\^([^\\]]+)\\]", options: [])) ?? NSRegularExpression()
    }()

    private static let imageRegex: NSRegularExpression = {
        (try? NSRegularExpression(pattern: "!\\[([^\\]]*)\\]\\(([^\\)]+)\\)", options: [])) ?? NSRegularExpression()
    }()

    private static let wikiImageRegex: NSRegularExpression = {
        (try? NSRegularExpression(pattern: "!\\[\\[([^\\]]+)\\]\\]", options: [])) ?? NSRegularExpression()
    }()

    private static let calloutRegex: NSRegularExpression = {
        (try? NSRegularExpression(pattern: "^([ \t]*>)[ \t]*\\[!([a-zA-Z]+)\\][ \t]*(.*)$", options: [])) ?? NSRegularExpression()
    }()

    private static let quoteRegex: NSRegularExpression = {
        (try? NSRegularExpression(pattern: "^([ \t]*>)[ \t]?(.*)$", options: [])) ?? NSRegularExpression()
    }()

    private static let hrRegex: NSRegularExpression = {
        (try? NSRegularExpression(pattern: "^[ \t]*([-*_])[ \t]*\\1[ \t]*\\1[ \t]*$", options: [])) ?? NSRegularExpression()
    }()

    private static let taskUncheckedRegex: NSRegularExpression = {
        (try? NSRegularExpression(pattern: "^([ \t]*[-*+])[ \t]+(\\[ \\])[ \t]+(.*)$", options: [])) ?? NSRegularExpression()
    }()

    private static let taskCheckedRegex: NSRegularExpression = {
        (try? NSRegularExpression(pattern: "^([ \t]*[-*+])[ \t]+(\\[[xX]\\])[ \t]+(.*)$", options: [])) ?? NSRegularExpression()
    }()

    private static let taskOtherRegex: NSRegularExpression = {
        (try? NSRegularExpression(pattern: "^([ \t]*[-*+])[ \t]+(\\[[-/]\\])[ \t]+(.*)$", options: [])) ?? NSRegularExpression()
    }()

    private static let bulletListRegex: NSRegularExpression = {
        (try? NSRegularExpression(pattern: "^([ \t]*)([-*+])[ \t]+(.*)$", options: [])) ?? NSRegularExpression()
    }()

    private static let numberedListRegex: NSRegularExpression = {
        (try? NSRegularExpression(pattern: "^([ \t]*)([0-9]+[.)])[ \t]+(.*)$", options: [])) ?? NSRegularExpression()
    }()

    private static let footnoteDefRegex: NSRegularExpression = {
        (try? NSRegularExpression(pattern: "^([ \t]*\\[\\^[^\\]]+\\]:)[ \t]*(.*)$", options: [])) ?? NSRegularExpression()
    }()

    private init() {}

    public static func resolveFont(
        family: String,
        size: Double,
        bold: Bool = false,
        italic: Bool = false,
        mono: Bool = false
    ) -> PlatformFont {
        let cacheKey = "\(family)_\(size)_\(bold)_\(italic)_\(mono)"

        cacheLock.lock()
        if let cached = fontCache[cacheKey] {
            cacheLock.unlock()
            return cached
        }
        cacheLock.unlock()

        let font: PlatformFont
        if mono {
            font = NSFont.monospacedSystemFont(ofSize: size, weight: bold ? .bold : .regular)
        } else {
            let targetFamily = (family.isEmpty || family == "System" || family == ".AppleSystemUIFont") ? "" : family
            if targetFamily.isEmpty {
                var base = NSFont.systemFont(ofSize: size, weight: bold ? .bold : .regular)
                if italic {
                    base = NSFontManager.shared.convert(base, toHaveTrait: .italicFontMask)
                }
                font = base
            } else {
                if targetFamily == "Bookerly" {
                    let psName: String
                    switch (bold, italic) {
                    case (true, true): psName = "Bookerly-BoldItalic"
                    case (true, false): psName = "Bookerly-Bold"
                    case (false, true): psName = "Bookerly-Italic"
                    case (false, false): psName = "Bookerly-Regular"
                    }
                    if let directFont = NSFont(name: psName, size: size) {
                        font = directFont
                    } else {
                        font = resolveViaDescriptor(family: targetFamily, size: size, bold: bold, italic: italic)
                    }
                } else if targetFamily == "Faustina" {
                    let psName: String
                    switch (bold, italic) {
                    case (true, true): psName = "FaustinaItalic-Bold"
                    case (true, false): psName = "FaustinaRoman-Bold"
                    case (false, true): psName = "FaustinaItalic-Regular"
                    case (false, false): psName = "FaustinaRoman-Regular"
                    }
                    if let directFont = NSFont(name: psName, size: size) {
                        font = directFont
                    } else {
                        font = resolveViaDescriptor(family: targetFamily, size: size, bold: bold, italic: italic)
                    }
                } else if targetFamily == "PT Serif" {
                    let psName: String
                    switch (bold, italic) {
                    case (true, true): psName = "PTSerif-BoldItalic"
                    case (true, false): psName = "PTSerif-Bold"
                    case (false, true): psName = "PTSerif-Italic"
                    case (false, false): psName = "PTSerif-Regular"
                    }
                    if let directFont = NSFont(name: psName, size: size) {
                        font = directFont
                    } else {
                        font = resolveViaDescriptor(family: targetFamily, size: size, bold: bold, italic: italic)
                    }
                } else {
                    font = resolveViaDescriptor(family: targetFamily, size: size, bold: bold, italic: italic)
                }
            }
        }

        cacheLock.lock()
        fontCache[cacheKey] = font
        cacheLock.unlock()

        return font
    }

    private static func resolveViaDescriptor(
        family: String,
        size: Double,
        bold: Bool,
        italic: Bool
    ) -> PlatformFont {
        var traits = NSFontDescriptor.SymbolicTraits()
        if bold { traits.insert(.bold) }
        if italic { traits.insert(.italic) }

        let descriptor = NSFontDescriptor(fontAttributes: [
            .family: family,
            .traits: [NSFontDescriptor.TraitKey.symbolic: traits.rawValue]
        ])

        if let resolved = NSFont(descriptor: descriptor, size: size) {
            return resolved
        }

        if let direct = NSFont(name: family, size: size) {
            var mask: NSFontTraitMask = []
            if bold { mask.insert(.boldFontMask) }
            if italic { mask.insert(.italicFontMask) }
            if !mask.isEmpty {
                return NSFontManager.shared.convert(direct, toHaveTrait: mask)
            }
            return direct
        }

        return NSFont.systemFont(ofSize: size, weight: bold ? .bold : .regular)
    }

    public static func makeParagraphStyle(
        isJustified: Bool,
        isHyphenationEnabled: Bool,
        lineSpacing: Double = 3.0
    ) -> NSMutableParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.alignment = isJustified ? .justified : .left
        style.hyphenationFactor = isHyphenationEnabled ? 1.0 : 0.0
        style.lineSpacing = CGFloat(lineSpacing)
        return style
    }

    public static func isTableRow(_ lineText: String) -> Bool {
        let trimmed = lineText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("|") && trimmed.hasSuffix("|") && trimmed.count >= 2 else { return false }
        return true
    }

    public static func isTableDelimiterRow(_ lineText: String) -> Bool {
        let trimmed = lineText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("|") && trimmed.hasSuffix("|") && trimmed.count >= 3 else { return false }
        let inner = trimmed.dropFirst().dropLast()
        guard !inner.isEmpty else { return false }
        var hasDash = false
        for ch in inner {
            if ch == "-" {
                hasDash = true
            } else if ch != "|" && ch != ":" && ch != " " && ch != "\t" {
                return false
            }
        }
        return hasDash
    }

    public func highlight(
        text: String,
        isMarkdown: Bool,
        selectedRange: NSRange,
        fontFamily: String,
        fontSize: Double,
        lineSpacing: Double = 3.0,
        isJustified: Bool,
        isHyphenationEnabled: Bool,
        isMarkdownHighlightingEnabled: Bool
    ) -> NSAttributedString {
        let attributed = NSMutableAttributedString(string: text)
        let fullRange = NSRange(location: 0, length: (text as NSString).length)
        guard fullRange.length > 0 else { return attributed }

        let regularFont = Self.resolveFont(family: fontFamily, size: fontSize)
        let paragraphStyle = Self.makeParagraphStyle(
            isJustified: isJustified,
            isHyphenationEnabled: isHyphenationEnabled,
            lineSpacing: lineSpacing
        )

        let textColor = NSColor.labelColor
        let hiddenColor = NSColor.clear
        let codeBgColor = NSColor.quaternaryLabelColor
        let secondaryColor = NSColor.secondaryLabelColor
        let linkColor = NSColor.linkColor
        let highlightYellow = NSColor.systemYellow.withAlphaComponent(0.35)

        attributed.addAttribute(.font, value: regularFont, range: fullRange)
        attributed.addAttribute(.foregroundColor, value: textColor, range: fullRange)
        attributed.addAttribute(.paragraphStyle, value: paragraphStyle, range: fullRange)

        // Für reine Textdateien (.txt): keine Markdown-Formatierung, Anzeige als normaler Text
        guard isMarkdown && isMarkdownHighlightingEnabled else { return attributed }

        let hiddenFont = Self.resolveFont(family: fontFamily, size: 0.1)
        let nsString = text as NSString
        var searchIndex = 0
        var inCodeBlock = false
        var inMathBlock = false
        var tableRowCounter = 0
        var tableRowsForLayout: [(range: NSRange, isDelimiter: Bool)] = []

        while searchIndex < nsString.length {
            let lineRange = nsString.lineRange(for: NSRange(location: searchIndex, length: 0))
            guard lineRange.length > 0 else { break }

            let lineText = nsString.substring(with: lineRange)
            let trimmed = lineText.trimmingCharacters(in: .whitespacesAndNewlines)

            // 1. Math-Block Erkennung ($$)
            if trimmed.hasPrefix("$$") {
                inMathBlock.toggle()
                let italicFont = Self.resolveFont(family: fontFamily, size: fontSize, italic: true)
                attributed.addAttribute(.font, value: italicFont, range: lineRange)
                attributed.addAttribute(.foregroundColor, value: secondaryColor, range: lineRange)
                searchIndex = lineRange.location + lineRange.length
                continue
            }

            if inMathBlock {
                let mathFont = Self.resolveFont(family: fontFamily, size: fontSize, italic: true)
                attributed.addAttribute(.font, value: mathFont, range: lineRange)
                attributed.addAttribute(.backgroundColor, value: codeBgColor.withAlphaComponent(0.25), range: lineRange)
                searchIndex = lineRange.location + lineRange.length
                continue
            }

            // 2. Fenced Code-Block Erkennung (```)
            if trimmed.hasPrefix("```") {
                inCodeBlock.toggle()
                let monoFont = Self.resolveFont(family: fontFamily, size: fontSize - 1.0, mono: true)
                attributed.addAttribute(.font, value: monoFont, range: lineRange)
                attributed.addAttribute(.foregroundColor, value: secondaryColor, range: lineRange)
                searchIndex = lineRange.location + lineRange.length
                continue
            }

            if inCodeBlock {
                let monoFont = Self.resolveFont(family: fontFamily, size: fontSize - 1.0, mono: true)
                attributed.addAttribute(.font, value: monoFont, range: lineRange)
                attributed.addAttribute(.backgroundColor, value: codeBgColor, range: lineRange)
                searchIndex = lineRange.location + lineRange.length
                continue
            }

            var lineStart = 0
            var lineEnd = 0
            var contentsEnd = 0
            nsString.getLineStart(&lineStart, end: &lineEnd, contentsEnd: &contentsEnd, for: lineRange)

            let cursorIntersects: Bool
            if selectedRange.location == NSNotFound {
                cursorIntersects = false
            } else if selectedRange.length == 0 {
                cursorIntersects = (selectedRange.location >= lineStart && selectedRange.location <= contentsEnd)
            } else {
                let selStart = selectedRange.location
                let selEnd = selectedRange.location + selectedRange.length
                cursorIntersects = (selStart < contentsEnd && selEnd > lineStart) || (contentsEnd == lineStart && selStart == lineStart)
            }

            if !cursorIntersects {
                // Live Preview: Alle Markdown-Elemente typografisch veredelt

                // 1. Überschriften (# bis ######)
                let isHeading = applyHeadingIfPresent(
                    lineText: lineText,
                    lineRange: lineRange,
                    attributed: attributed,
                    fontFamily: fontFamily,
                    fontSize: fontSize,
                    hiddenFont: hiddenFont,
                    hiddenColor: hiddenColor
                )

                if isHeading {
                    tableRowCounter = 0
                    // Auch innerhalb von Überschriften Inline-Stile anwenden
                    applyInlineStyles(
                        lineRange: lineRange,
                        nsString: nsString,
                        attributed: attributed,
                        fontFamily: fontFamily,
                        fontSize: fontSize,
                        hiddenFont: hiddenFont,
                        hiddenColor: hiddenColor,
                        codeBgColor: codeBgColor,
                        linkColor: linkColor,
                        highlightYellow: highlightYellow
                    )
                } else {
                    // 2. Trennlinie (---, ***, ___)
                    let isHR = applyHorizontalRuleIfPresent(
                        lineText: lineText,
                        lineRange: lineRange,
                        attributed: attributed,
                        secondaryColor: secondaryColor
                    )

                    // 3. Callout (> [!NOTE], > [!TIP], etc.)
                    let isCallout = !isHR && applyCalloutIfPresent(
                        lineText: lineText,
                        lineRange: lineRange,
                        attributed: attributed,
                        fontFamily: fontFamily,
                        fontSize: fontSize,
                        hiddenFont: hiddenFont,
                        hiddenColor: hiddenColor
                    )

                    // 4. Standard-Zitat (> ...)
                    let isQuote = !isHR && !isCallout && applyQuoteIfPresent(
                        lineText: lineText,
                        lineRange: lineRange,
                        attributed: attributed,
                        fontFamily: fontFamily,
                        fontSize: fontSize,
                        hiddenFont: hiddenFont,
                        hiddenColor: hiddenColor,
                        secondaryColor: secondaryColor
                    )

                    // 5. Aufgabenlisten (- [ ], - [x], - [-], - [/])
                    let isTask = !isHR && !isCallout && !isQuote && applyTaskListIfPresent(
                        lineText: lineText,
                        lineRange: lineRange,
                        attributed: attributed,
                        secondaryColor: secondaryColor
                    )

                    // 6. Ungeordnete Listen (- , * , + )
                    let isBullet = !isHR && !isCallout && !isQuote && !isTask && applyBulletListIfPresent(
                        lineText: lineText,
                        lineRange: lineRange,
                        attributed: attributed
                    )

                    // 7. Nummerierte Listen (1. , 2. )
                    let isNumbered = !isHR && !isCallout && !isQuote && !isTask && !isBullet && applyNumberedListIfPresent(
                        lineText: lineText,
                        lineRange: lineRange,
                        attributed: attributed,
                        secondaryColor: secondaryColor
                    )

                    // 8. Fußnoten-Definition ([^1]: ...)
                    let isFootnoteDef = !isHR && !isCallout && !isQuote && !isTask && !isBullet && !isNumbered && applyFootnoteDefIfPresent(
                        lineText: lineText,
                        lineRange: lineRange,
                        attributed: attributed,
                        secondaryColor: secondaryColor
                    )

                    // 9. Tabellen (| ... |)
                    let tableResult = (!isHR && !isCallout && !isQuote && !isFootnoteDef) ? applyTableIfPresent(
                        lineText: lineText,
                        lineRange: lineRange,
                        nsString: nsString,
                        tableRowIndex: tableRowCounter,
                        attributed: attributed,
                        fontFamily: fontFamily,
                        fontSize: fontSize,
                        hiddenFont: hiddenFont,
                        hiddenColor: hiddenColor,
                        secondaryColor: secondaryColor
                    ) : (isTable: false, isDelimiter: false)

                    if tableResult.isTable {
                        tableRowsForLayout.append((range: lineRange, isDelimiter: tableResult.isDelimiter))
                        if tableResult.isDelimiter {
                            tableRowCounter = 0
                        } else {
                            tableRowCounter += 1
                        }
                    } else {
                        tableRowCounter = 0
                    }

                    // 10. Inline-Stile (Fett, Kursiv, Code, Durchgestrichen, Highlight, Links, Wiki-Links, Math, etc.)
                    // Gilt für normalen Fließtext, Zitate, Listen und Tabellenzellen (nicht Trennlinien/Delimiter)
                    if !isHR && !tableResult.isDelimiter {
                        applyInlineStyles(
                            lineRange: lineRange,
                            nsString: nsString,
                            attributed: attributed,
                            fontFamily: fontFamily,
                            fontSize: fontSize,
                            hiddenFont: hiddenFont,
                            hiddenColor: hiddenColor,
                            codeBgColor: codeBgColor,
                            linkColor: linkColor,
                            highlightYellow: highlightYellow
                        )
                    }
                }
            } else {
                // Aktive Zeile mit Cursor: Zeige Rohsyntax an, dezent hervorgehoben
                applyActiveLineStyling(
                    lineText: lineText,
                    lineRange: lineRange,
                    attributed: attributed,
                    secondaryColor: secondaryColor
                )
            }

            searchIndex = lineRange.location + lineRange.length
        }

        layoutTables(rows: tableRowsForLayout, attributed: attributed, nsString: nsString, styleKey: "\(fontFamily)|\(fontSize)|\(lineSpacing)")

        return attributed
    }

    private func applyHeadingIfPresent(
        lineText: String,
        lineRange: NSRange,
        attributed: NSMutableAttributedString,
        fontFamily: String,
        fontSize: Double,
        hiddenFont: PlatformFont,
        hiddenColor: PlatformColor
    ) -> Bool {
        var count = 0
        for ch in lineText {
            if ch == "#" { count += 1 } else { break }
        }

        if count >= 1 && count <= 6 {
            let afterHashIndex = lineText.index(lineText.startIndex, offsetBy: count)
            if afterHashIndex < lineText.endIndex && lineText[afterHashIndex] == " " {
                var spaceCount = 0
                var idx = afterHashIndex
                while idx < lineText.endIndex && lineText[idx] == " " {
                    spaceCount += 1
                    idx = lineText.index(after: idx)
                }

                let prefixLength = count + spaceCount
                let prefixRange = NSRange(location: lineRange.location, length: prefixLength)
                let textLength = max(0, lineRange.length - prefixLength)
                let textRange = NSRange(location: lineRange.location + prefixLength, length: textLength)

                // Ausblenden der #-Markierung wie bei Obsidian
                attributed.addAttribute(.foregroundColor, value: hiddenColor, range: prefixRange)
                attributed.addAttribute(.font, value: hiddenFont, range: prefixRange)

                // Vergrößerte und fette Darstellung der Überschrift
                let bonus: Double
                switch count {
                case 1: bonus = 6.0
                case 2: bonus = 4.0
                case 3: bonus = 2.5
                case 4: bonus = 1.5
                case 5: bonus = 0.8
                default: bonus = 0.4
                }
                let headingFont = Self.resolveFont(family: fontFamily, size: fontSize + bonus, bold: true)
                attributed.addAttribute(.font, value: headingFont, range: textRange)
                return true
            }
        }
        return false
    }

    private func applyHorizontalRuleIfPresent(
        lineText: String,
        lineRange: NSRange,
        attributed: NSMutableAttributedString,
        secondaryColor: PlatformColor
    ) -> Bool {
        let nsLine = lineText as NSString
        let match = Self.hrRegex.firstMatch(in: lineText, options: [], range: NSRange(location: 0, length: nsLine.length))
        guard match != nil else { return false }

        // Echte Trennlinie: Rohzeichen unsichtbar, Linie wird vom iTextLayoutManager gezeichnet
        attributed.addAttribute(.foregroundColor, value: NSColor.clear, range: lineRange)
        attributed.addAttribute(.iTextRule, value: true, range: lineRange)
        return true
    }

    private func applyCalloutIfPresent(
        lineText: String,
        lineRange: NSRange,
        attributed: NSMutableAttributedString,
        fontFamily: String,
        fontSize: Double,
        hiddenFont: PlatformFont,
        hiddenColor: PlatformColor
    ) -> Bool {
        let nsLine = lineText as NSString
        guard let match = Self.calloutRegex.firstMatch(in: lineText, options: [], range: NSRange(location: 0, length: nsLine.length)), match.numberOfRanges >= 3 else {
            return false
        }

        let prefixMatch = match.range(at: 1) // >
        let typeMatch = match.range(at: 2)   // NOTE / TIP / ...
        let typeStr = nsLine.substring(with: typeMatch).uppercased()

        let calloutColor: PlatformColor
        switch typeStr {
        case "NOTE", "INFO", "HINWEIS":
            calloutColor = NSColor.systemBlue
        case "TIP", "TIPP", "SUCCESS", "ERFOLG":
            calloutColor = NSColor.systemGreen
        case "WARNING", "WARNUNG", "ACHTUNG":
            calloutColor = NSColor.systemOrange
        case "CAUTION", "DANGER", "FEHLER":
            calloutColor = NSColor.systemRed
        case "IMPORTANT", "WICHTIG":
            calloutColor = NSColor.systemPurple
        default:
            calloutColor = NSColor.controlAccentColor
        }

        let globalPrefix = NSRange(location: lineRange.location + prefixMatch.location, length: prefixMatch.length)
        attributed.addAttribute(.foregroundColor, value: hiddenColor, range: globalPrefix)
        attributed.addAttribute(.font, value: hiddenFont, range: globalPrefix)

        let lineLenWithoutNewline = max(0, lineRange.length - (lineText.hasSuffix("\n") ? 1 : 0))
        let rowRange = NSRange(location: lineRange.location, length: lineLenWithoutNewline)
        attributed.addAttribute(.backgroundColor, value: calloutColor.withAlphaComponent(0.08), range: rowRange)

        let globalType = NSRange(location: lineRange.location + typeMatch.location, length: typeMatch.length)
        let boldFont = Self.resolveFont(family: fontFamily, size: fontSize, bold: true)
        attributed.addAttribute(.foregroundColor, value: calloutColor, range: globalType)
        attributed.addAttribute(.font, value: boldFont, range: globalType)

        return true
    }

    private func applyQuoteIfPresent(
        lineText: String,
        lineRange: NSRange,
        attributed: NSMutableAttributedString,
        fontFamily: String,
        fontSize: Double,
        hiddenFont: PlatformFont,
        hiddenColor: PlatformColor,
        secondaryColor: PlatformColor
    ) -> Bool {
        let nsLine = lineText as NSString
        guard let match = Self.quoteRegex.firstMatch(in: lineText, options: [], range: NSRange(location: 0, length: nsLine.length)) else { return false }
        guard match.numberOfRanges >= 2 else { return false }

        let prefixMatch = match.range(at: 1)
        let globalPrefix = NSRange(location: lineRange.location + prefixMatch.location, length: prefixMatch.length)
        let globalContent = NSRange(location: lineRange.location + prefixMatch.length, length: max(0, lineRange.length - prefixMatch.length))

        // Marker '>' ausblenden
        attributed.addAttribute(.foregroundColor, value: hiddenColor, range: globalPrefix)
        attributed.addAttribute(.font, value: hiddenFont, range: globalPrefix)

        // Zitattext kursiv und in dezenter Sekundärfarbe darstellen
        let italicFont = Self.resolveFont(family: fontFamily, size: fontSize, italic: true)
        attributed.addAttribute(.font, value: italicFont, range: globalContent)
        attributed.addAttribute(.foregroundColor, value: secondaryColor, range: globalContent)
        return true
    }

    private func applyTaskListIfPresent(
        lineText: String,
        lineRange: NSRange,
        attributed: NSMutableAttributedString,
        secondaryColor: PlatformColor
    ) -> Bool {
        let nsLine = lineText as NSString
        let fullLine = NSRange(location: 0, length: nsLine.length)

        if let match = Self.taskCheckedRegex.firstMatch(in: lineText, options: [], range: fullLine), match.numberOfRanges >= 4 {
            let markerRange = match.range(at: 2) // [x]
            let contentRange = match.range(at: 3)
            let globalMarker = NSRange(location: lineRange.location + markerRange.location, length: markerRange.length)
            let globalContent = NSRange(location: lineRange.location + contentRange.location, length: contentRange.length)

            attributed.addAttribute(.foregroundColor, value: NSColor.systemGreen, range: globalMarker)
            attributed.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: globalContent)
            attributed.addAttribute(.foregroundColor, value: secondaryColor, range: globalContent)
            return true
        } else if let match = Self.taskUncheckedRegex.firstMatch(in: lineText, options: [], range: fullLine), match.numberOfRanges >= 4 {
            let markerRange = match.range(at: 2) // [ ]
            let globalMarker = NSRange(location: lineRange.location + markerRange.location, length: markerRange.length)

            attributed.addAttribute(.foregroundColor, value: secondaryColor, range: globalMarker)
            return true
        } else if let match = Self.taskOtherRegex.firstMatch(in: lineText, options: [], range: fullLine), match.numberOfRanges >= 4 {
            let markerRange = match.range(at: 2) // [-] oder [/]
            let contentRange = match.range(at: 3)
            let globalMarker = NSRange(location: lineRange.location + markerRange.location, length: markerRange.length)
            let globalContent = NSRange(location: lineRange.location + contentRange.location, length: contentRange.length)

            attributed.addAttribute(.foregroundColor, value: NSColor.systemOrange, range: globalMarker)
            attributed.addAttribute(.foregroundColor, value: secondaryColor, range: globalContent)
            return true
        }
        return false
    }

    private func applyBulletListIfPresent(
        lineText: String,
        lineRange: NSRange,
        attributed: NSMutableAttributedString
    ) -> Bool {
        let nsLine = lineText as NSString
        guard let match = Self.bulletListRegex.firstMatch(in: lineText, options: [], range: NSRange(location: 0, length: nsLine.length)), match.numberOfRanges >= 3 else { return false }

        let bulletRange = match.range(at: 2)
        let globalBullet = NSRange(location: lineRange.location + bulletRange.location, length: bulletRange.length)

        // Aufzählungspunkt dezent in Akzentfarbe hervorheben
        attributed.addAttribute(.foregroundColor, value: NSColor.controlAccentColor, range: globalBullet)
        return true
    }

    private func applyNumberedListIfPresent(
        lineText: String,
        lineRange: NSRange,
        attributed: NSMutableAttributedString,
        secondaryColor: PlatformColor
    ) -> Bool {
        let nsLine = lineText as NSString
        guard let match = Self.numberedListRegex.firstMatch(in: lineText, options: [], range: NSRange(location: 0, length: nsLine.length)), match.numberOfRanges >= 3 else { return false }

        let numberRange = match.range(at: 2)
        let globalNumber = NSRange(location: lineRange.location + numberRange.location, length: numberRange.length)

        attributed.addAttribute(.foregroundColor, value: secondaryColor, range: globalNumber)
        return true
    }

    private func applyFootnoteDefIfPresent(
        lineText: String,
        lineRange: NSRange,
        attributed: NSMutableAttributedString,
        secondaryColor: PlatformColor
    ) -> Bool {
        let nsLine = lineText as NSString
        guard let match = Self.footnoteDefRegex.firstMatch(in: lineText, options: [], range: NSRange(location: 0, length: nsLine.length)), match.numberOfRanges >= 2 else { return false }

        let markerRange = match.range(at: 1)
        let globalMarker = NSRange(location: lineRange.location + markerRange.location, length: markerRange.length)
        attributed.addAttribute(.foregroundColor, value: secondaryColor, range: globalMarker)
        return true
    }

    private func applyTableIfPresent(
        lineText: String,
        lineRange: NSRange,
        nsString: NSString,
        tableRowIndex: Int,
        attributed: NSMutableAttributedString,
        fontFamily: String,
        fontSize: Double,
        hiddenFont: PlatformFont,
        hiddenColor: PlatformColor,
        secondaryColor: PlatformColor
    ) -> (isTable: Bool, isDelimiter: Bool) {
        guard Self.isTableRow(lineText) else { return (false, false) }

        let lineLenWithoutNewline = max(0, lineRange.length - (lineText.hasSuffix("\n") ? 1 : 0))

        // 1. Fall: Delimiter-Zeile (|---|---|---|)
        if Self.isTableDelimiterRow(lineText) {
            let delimiterRange = NSRange(location: lineRange.location, length: lineLenWithoutNewline)
            // Die Zeichen der Delimiter-Zeile unsichtbar machen und durch eine feine Trennlinie ersetzen
            attributed.addAttribute(.foregroundColor, value: hiddenColor, range: delimiterRange)
            attributed.addAttribute(.font, value: hiddenFont, range: delimiterRange)
            attributed.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: delimiterRange)
            attributed.addAttribute(.strikethroughColor, value: NSColor.separatorColor, range: delimiterRange)
            return (true, true)
        }

        let rowContentRange = NSRange(location: lineRange.location, length: lineLenWithoutNewline)

        // Prüfen, ob dies die Header-Zeile ist (nächste Zeile ist Delimiter)
        let nextLineStart = lineRange.location + lineRange.length
        var isHeader = false
        if nextLineStart < nsString.length {
            let nextLineRange = nsString.lineRange(for: NSRange(location: nextLineStart, length: 0))
            let nextLineText = nsString.substring(with: nextLineRange)
            if Self.isTableDelimiterRow(nextLineText) {
                isHeader = true
            }
        }

        if isHeader {
            // Header-Styling: Dezenter Tabellenkopf-Hintergrund & Fette Schrift
            let headerBg = NSColor.quaternaryLabelColor.withAlphaComponent(0.35)
            let headerFont = Self.resolveFont(family: fontFamily, size: fontSize, bold: true)
            attributed.addAttribute(.backgroundColor, value: headerBg, range: rowContentRange)
            attributed.addAttribute(.font, value: headerFont, range: rowContentRange)

            // Pipes stylen
            styleTablePipes(
                lineText: lineText,
                lineRange: lineRange,
                attributed: attributed,
                outerColor: NSColor.tertiaryLabelColor,
                innerColor: NSColor.separatorColor
            )
        } else {
            // Datenzeilen-Styling: Normale Leseschriftart des Anwenders (kein Monospace!)
            let rowFont = Self.resolveFont(family: fontFamily, size: fontSize)
            attributed.addAttribute(.font, value: rowFont, range: rowContentRange)

            // Dezentes Zebra-Striping für strukturierte Zeilenabgrenzung
            if tableRowIndex % 2 == 1 {
                let zebraBg = NSColor.quaternaryLabelColor.withAlphaComponent(0.12)
                attributed.addAttribute(.backgroundColor, value: zebraBg, range: rowContentRange)
            }

            // Pipes stylen
            styleTablePipes(
                lineText: lineText,
                lineRange: lineRange,
                attributed: attributed,
                outerColor: NSColor.tertiaryLabelColor,
                innerColor: NSColor.separatorColor.withAlphaComponent(0.7)
            )
        }

        return (true, false)
    }

    /// Dynamische Tabellendarstellung: Spaltenbreiten werden an die Fensterbreite angepasst, Zellinhalt umbricht
    /// (wie beim Drucken). Die Rohzeile reserviert nur die Zeilenhöhe, Raster und Zelltext zeichnet der iTextLayoutManager.
    private func layoutTables(
        rows: [(range: NSRange, isDelimiter: Bool)],
        attributed: NSMutableAttributedString,
        nsString: NSString,
        styleKey: String
    ) {
        guard !rows.isEmpty else { return }
        let padX: CGFloat = 7
        let padY: CGFloat = 4.5
        let linePad: CGFloat = 5

        // Gruppen zusammenhängender Zeilen bilden
        var groups: [[(range: NSRange, isDelimiter: Bool)]] = []
        for row in rows {
            if let last = groups.last?.last, last.range.location + last.range.length == row.range.location {
                groups[groups.count - 1].append(row)
            } else {
                groups.append([row])
            }
        }

        func width(of range: NSRange) -> CGFloat {
            guard range.length > 0 else { return 0 }
            return ceil(attributed.attributedSubstring(from: range).size().width)
        }

        for group in groups {
            // Zellbereiche (absolut) je Zeile bestimmen; maskierte Pipes (\|) trennen nicht
            var cellRanges: [[NSRange]] = []
            for row in group {
                var cells: [NSRange] = []
                if !row.isDelimiter {
                    var pipes: [Int] = []
                    var prev: unichar = 0
                    for i in 0..<row.range.length {
                        let ch = nsString.character(at: row.range.location + i)
                        if ch == 0x7C && prev != 0x5C { pipes.append(row.range.location + i) }
                        prev = ch
                    }
                    if pipes.count >= 2 {
                        for k in 0..<(pipes.count - 1) {
                            var start = pipes[k] + 1
                            var end = pipes[k + 1]
                            while start < end, [0x20, 0x09].contains(nsString.character(at: start)) { start += 1 }
                            while end > start, [0x20, 0x09].contains(nsString.character(at: end - 1)) { end -= 1 }
                            cells.append(NSRange(location: start, length: end - start))
                        }
                    }
                }
                cellRanges.append(cells)
            }
            let colCount = cellRanges.map { $0.count }.max() ?? 0
            guard colCount > 0 else { continue }

            let groupEnd = group[group.count - 1].range.location + group[group.count - 1].range.length
            let groupSpan = NSRange(location: group[0].range.location, length: groupEnd - group[0].range.location)
            let cacheKey = nsString.substring(with: groupSpan) + "\u{0}\(Int(viewportTextWidth.rounded()))\u{0}" + styleKey
            let cached = tableLayoutCache[cacheKey]
            var colWidths: [CGFloat] = cached?.colWidths ?? []
            var computedHeights: [CGFloat] = []

            if cached == nil {
            // Natürliche und minimale Spaltenbreiten (längstes unteilbares Wort)
            var nat = [CGFloat](repeating: 2 * padX + 8, count: colCount)
            var minW = [CGFloat](repeating: 2 * padX + 8, count: colCount)
            for cells in cellRanges {
                for (k, cell) in cells.enumerated() {
                    nat[k] = max(nat[k], width(of: cell) + 2 * padX)
                    var tokenStart = cell.location
                    let cellEnd = cell.location + cell.length
                    var i = cell.location
                    while i <= cellEnd {
                        if i == cellEnd || nsString.character(at: i) == 0x20 {
                            let token = NSRange(location: tokenStart, length: i - tokenStart)
                            minW[k] = max(minW[k], width(of: token) + 2 * padX)
                            tokenStart = i + 1
                        }
                        i += 1
                    }
                    minW[k] = min(minW[k], nat[k])
                }
            }

            // Verfügbare Tabellenbreite aus der Fensterbreite
            let natTotal = nat.reduce(0, +)
            let minTotal = minW.reduce(0, +)
            let available = viewportTextWidth > 0 ? max(40, viewportTextWidth - 2 * linePad - 1) : natTotal
            colWidths = nat
            if natTotal > available {
                if minTotal < available {
                    let f = (available - minTotal) / (natTotal - minTotal)
                    colWidths = zip(minW, nat).map { $0 + ($1 - $0) * f }
                } else {
                    let f = available / minTotal
                    colWidths = minW.map { $0 * f }
                }
            } else if natTotal < available {
                let f = available / natTotal
                colWidths = nat.map { $0 * f }
            }
            }

            var colX: [CGFloat] = [0]
            for w in colWidths { colX.append((colX.last ?? 0) + w) }

            for (r, row) in group.enumerated() {
                let paragraph = NSMutableParagraphStyle()
                paragraph.alignment = .left
                paragraph.hyphenationFactor = 0
                paragraph.lineBreakMode = .byClipping
                paragraph.lineSpacing = 0

                if row.isDelimiter {
                    attributed.addAttribute(.paragraphStyle, value: paragraph, range: row.range)
                    attributed.removeAttribute(.strikethroughStyle, range: row.range)
                    continue
                }

                // Zeilenhöhe aus dem höchsten umgebrochenen Zellinhalt (aus dem Zwischenspeicher, falls vorhanden)
                let rowHeight: CGFloat
                if let cachedHeights = cached?.rowHeights, r < cachedHeights.count {
                    rowHeight = cachedHeights[r]
                } else {
                    var maxCellHeight: CGFloat = 0
                    for (k, cell) in cellRanges[r].enumerated() {
                        let str = iTextTableRowInfo.cellString(from: attributed, range: cell)
                        let w = max(10, colWidths[k] - 2 * padX)
                        let h = str.boundingRect(with: NSSize(width: w, height: .greatestFiniteMagnitude), options: [.usesLineFragmentOrigin, .usesFontLeading]).height
                        maxCellHeight = max(maxCellHeight, ceil(h))
                    }
                    if let font = attributed.attribute(.font, at: row.range.location, effectiveRange: nil) as? NSFont {
                        let oneLine = NSAttributedString(string: "M", attributes: [.font: font]).size().height
                        maxCellHeight = max(maxCellHeight, ceil(oneLine))
                    }
                    rowHeight = maxCellHeight + 2 * padY
                }
                while computedHeights.count < r { computedHeights.append(0) }
                computedHeights.append(rowHeight)
                paragraph.minimumLineHeight = rowHeight
                paragraph.maximumLineHeight = rowHeight
                attributed.addAttribute(.paragraphStyle, value: paragraph, range: row.range)
                attributed.removeAttribute(.backgroundColor, range: row.range)

                let isHeader = r + 1 < group.count && group[r + 1].isDelimiter
                let relative = cellRanges[r].map { NSRange(location: $0.location - row.range.location, length: $0.length) }
                let info = iTextTableRowInfo(colX: colX, isHeader: isHeader, cells: relative, padX: padX, padY: padY)
                attributed.addAttribute(.iTextTableRow, value: info, range: row.range)
            }

            if cached == nil {
                if tableLayoutCache.count > 300 { tableLayoutCache.removeAll() }
                tableLayoutCache[cacheKey] = (colWidths, computedHeights)
            }
        }
    }

    private func styleTablePipes(
        lineText: String,
        lineRange: NSRange,
        attributed: NSMutableAttributedString,
        outerColor: PlatformColor,
        innerColor: PlatformColor
    ) {
        let nsLine = lineText as NSString
        var pipeIndices: [Int] = []
        for i in 0..<nsLine.length {
            if nsLine.character(at: i) == 0x7C { // '|'
                pipeIndices.append(i)
            }
        }
        guard !pipeIndices.isEmpty else { return }
        let firstIdx = pipeIndices.first!
        let lastIdx = pipeIndices.last!

        for idx in pipeIndices {
            let globalPipeRange = NSRange(location: lineRange.location + idx, length: 1)
            let color = (idx == firstIdx || idx == lastIdx) ? outerColor : innerColor
            attributed.addAttribute(.foregroundColor, value: color, range: globalPipeRange)
        }
    }

    private func applyActiveLineStyling(
        lineText: String,
        lineRange: NSRange,
        attributed: NSMutableAttributedString,
        secondaryColor: PlatformColor
    ) {
        // Tabellenzeilen: Pipes hervorheben
        if Self.isTableRow(lineText) {
            if Self.isTableDelimiterRow(lineText) {
                attributed.addAttribute(.foregroundColor, value: secondaryColor, range: lineRange)
            } else {
                let nsLine = lineText as NSString
                for i in 0..<nsLine.length {
                    if nsLine.character(at: i) == 0x7C {
                        let r = NSRange(location: lineRange.location + i, length: 1)
                        attributed.addAttribute(.foregroundColor, value: NSColor.controlAccentColor, range: r)
                    }
                }
            }
            return
        }

        // Überschriften: Marker hervorheben
        var count = 0
        for ch in lineText {
            if ch == "#" { count += 1 } else { break }
        }
        if count >= 1 && count <= 6 {
            let afterHashIndex = lineText.index(lineText.startIndex, offsetBy: count)
            if afterHashIndex < lineText.endIndex && lineText[afterHashIndex] == " " {
                let prefixRange = NSRange(location: lineRange.location, length: count + 1)
                attributed.addAttribute(.foregroundColor, value: secondaryColor, range: prefixRange)
            }
            return
        }

        // Zitate & Callouts: '>' hervorheben
        if lineText.hasPrefix(">") {
            let prefixRange = NSRange(location: lineRange.location, length: 1)
            attributed.addAttribute(.foregroundColor, value: secondaryColor, range: prefixRange)
        }
    }

    private func applyInlineStyles(
        lineRange: NSRange,
        nsString: NSString,
        attributed: NSMutableAttributedString,
        fontFamily: String,
        fontSize: Double,
        hiddenFont: PlatformFont,
        hiddenColor: PlatformColor,
        codeBgColor: PlatformColor,
        linkColor: PlatformColor,
        highlightYellow: PlatformColor
    ) {
        let lineText = nsString.substring(with: lineRange)
        guard lineText.contains("*") || lineText.contains("_") || lineText.contains("`") ||
              lineText.contains("~") || lineText.contains("=") || lineText.contains("[") ||
              lineText.contains("<") || lineText.contains("$") || lineText.contains("!") else {
            return
        }

        // 1. Bilder: ![Alt](URL) und ![[Bild]]
        applyCachedRegex(
            regex: Self.imageRegex,
            lineText: lineText,
            lineOffset: lineRange.location
        ) { fullRange, matchRanges in
            guard matchRanges.count >= 2 else { return }
            let altMatch = matchRanges[0]
            attributed.addAttribute(.foregroundColor, value: NSColor.systemTeal, range: fullRange)
            attributed.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: altMatch)
        }

        applyCachedRegex(
            regex: Self.wikiImageRegex,
            lineText: lineText,
            lineOffset: lineRange.location
        ) { fullRange, matchRanges in
            guard let nameMatch = matchRanges.first else { return }
            attributed.addAttribute(.foregroundColor, value: NSColor.systemTeal, range: fullRange)
            attributed.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: nameMatch)
        }

        // 2. Wiki-Links: [[Ziel]] oder [[Ziel|Titel]]
        applyCachedRegex(
            regex: Self.wikiLinkRegex,
            lineText: lineText,
            lineOffset: lineRange.location
        ) { fullRange, matchRanges in
            guard matchRanges.count >= 1 else { return }
            let targetMatch = matchRanges[0]
            let hasAlias = matchRanges.count >= 2 && matchRanges[1].location != NSNotFound

            if hasAlias {
                let aliasMatch = matchRanges[1]
                let prefixLen = aliasMatch.location - fullRange.location
                let prefixRange = NSRange(location: fullRange.location, length: prefixLen)
                attributed.addAttribute(.foregroundColor, value: hiddenColor, range: prefixRange)
                attributed.addAttribute(.font, value: hiddenFont, range: prefixRange)

                let suffixLocation = aliasMatch.location + aliasMatch.length
                let suffixLen = (fullRange.location + fullRange.length) - suffixLocation
                if suffixLen > 0 {
                    let suffixRange = NSRange(location: suffixLocation, length: suffixLen)
                    attributed.addAttribute(.foregroundColor, value: hiddenColor, range: suffixRange)
                    attributed.addAttribute(.font, value: hiddenFont, range: suffixRange)
                }

                attributed.addAttribute(.foregroundColor, value: linkColor, range: aliasMatch)
                attributed.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: aliasMatch)
            } else {
                let openRange = NSRange(location: fullRange.location, length: 2)
                attributed.addAttribute(.foregroundColor, value: hiddenColor, range: openRange)
                attributed.addAttribute(.font, value: hiddenFont, range: openRange)

                let closeRange = NSRange(location: fullRange.location + fullRange.length - 2, length: 2)
                attributed.addAttribute(.foregroundColor, value: hiddenColor, range: closeRange)
                attributed.addAttribute(.font, value: hiddenFont, range: closeRange)

                attributed.addAttribute(.foregroundColor, value: linkColor, range: targetMatch)
                attributed.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: targetMatch)
            }
        }

        // 3. Standard-Links: [Text](URL)
        applyCachedRegex(
            regex: Self.linkRegex,
            lineText: lineText,
            lineOffset: lineRange.location
        ) { fullRange, matchRanges in
            guard matchRanges.count >= 2 else { return }
            let textMatch = matchRanges[0]
            let urlMatch = matchRanges[1]

            let openBracket = NSRange(location: fullRange.location, length: 1)
            let midBrackets = NSRange(location: textMatch.location + textMatch.length, length: urlMatch.location + urlMatch.length + 1 - (textMatch.location + textMatch.length))

            attributed.addAttribute(.foregroundColor, value: hiddenColor, range: openBracket)
            attributed.addAttribute(.font, value: hiddenFont, range: openBracket)
            attributed.addAttribute(.foregroundColor, value: hiddenColor, range: midBrackets)
            attributed.addAttribute(.font, value: hiddenFont, range: midBrackets)

            attributed.addAttribute(.foregroundColor, value: linkColor, range: textMatch)
            attributed.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: textMatch)
        }

        // 4. Autolinks: <https://...> oder <mailto:...>
        applyCachedRegex(
            regex: Self.autolinkRegex,
            lineText: lineText,
            lineOffset: lineRange.location
        ) { fullRange, matchRanges in
            guard let urlMatch = matchRanges.first else { return }
            let openRange = NSRange(location: fullRange.location, length: 1)
            let closeRange = NSRange(location: fullRange.location + fullRange.length - 1, length: 1)

            attributed.addAttribute(.foregroundColor, value: hiddenColor, range: openRange)
            attributed.addAttribute(.font, value: hiddenFont, range: openRange)
            attributed.addAttribute(.foregroundColor, value: hiddenColor, range: closeRange)
            attributed.addAttribute(.font, value: hiddenFont, range: closeRange)

            attributed.addAttribute(.foregroundColor, value: linkColor, range: urlMatch)
            attributed.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: urlMatch)
        }

        // 5. Fußnoten-Referenzen: [^1]
        applyCachedRegex(
            regex: Self.footnoteRefRegex,
            lineText: lineText,
            lineOffset: lineRange.location
        ) { fullRange, _ in
            let smallFont = Self.resolveFont(family: fontFamily, size: max(8.0, fontSize - 3.0), bold: true)
            attributed.addAttribute(.font, value: smallFont, range: fullRange)
            attributed.addAttribute(.foregroundColor, value: linkColor, range: fullRange)
            attributed.addAttribute(.baselineOffset, value: 3.5, range: fullRange)
        }

        // 6. Fett-Kursiv: ***text*** und ___text___
        let applyBoldItalic: (NSRange, [NSRange]) -> Void = { fullRange, matchRanges in
            guard let textMatch = matchRanges.first else { return }
            let openRange = NSRange(location: fullRange.location, length: 3)
            let closeRange = NSRange(location: fullRange.location + fullRange.length - 3, length: 3)

            attributed.addAttribute(.foregroundColor, value: hiddenColor, range: openRange)
            attributed.addAttribute(.font, value: hiddenFont, range: openRange)
            attributed.addAttribute(.foregroundColor, value: hiddenColor, range: closeRange)
            attributed.addAttribute(.font, value: hiddenFont, range: closeRange)

            let boldItalicFont = Self.resolveFont(family: fontFamily, size: fontSize, bold: true, italic: true)
            attributed.addAttribute(.font, value: boldItalicFont, range: textMatch)
        }
        applyCachedRegex(regex: Self.boldItalicRegex, lineText: lineText, lineOffset: lineRange.location, handler: applyBoldItalic)
        applyCachedRegex(regex: Self.boldItalicUnderscoreRegex, lineText: lineText, lineOffset: lineRange.location, handler: applyBoldItalic)

        // 7. Fett: **text** und __text__
        let applyBold: (NSRange, [NSRange]) -> Void = { fullRange, matchRanges in
            guard let textMatch = matchRanges.first else { return }
            let openRange = NSRange(location: fullRange.location, length: 2)
            let closeRange = NSRange(location: fullRange.location + fullRange.length - 2, length: 2)

            attributed.addAttribute(.foregroundColor, value: hiddenColor, range: openRange)
            attributed.addAttribute(.font, value: hiddenFont, range: openRange)
            attributed.addAttribute(.foregroundColor, value: hiddenColor, range: closeRange)
            attributed.addAttribute(.font, value: hiddenFont, range: closeRange)

            let boldFont = Self.resolveFont(family: fontFamily, size: fontSize, bold: true)
            attributed.addAttribute(.font, value: boldFont, range: textMatch)
        }
        applyCachedRegex(regex: Self.boldRegex, lineText: lineText, lineOffset: lineRange.location, handler: applyBold)
        applyCachedRegex(regex: Self.boldUnderscoreRegex, lineText: lineText, lineOffset: lineRange.location, handler: applyBold)

        // 8. Kursiv: *text* und _text_
        let applyItalic: (NSRange, [NSRange]) -> Void = { fullRange, matchRanges in
            guard let textMatch = matchRanges.first else { return }
            let openRange = NSRange(location: fullRange.location, length: 1)
            let closeRange = NSRange(location: fullRange.location + fullRange.length - 1, length: 1)

            attributed.addAttribute(.foregroundColor, value: hiddenColor, range: openRange)
            attributed.addAttribute(.font, value: hiddenFont, range: openRange)
            attributed.addAttribute(.foregroundColor, value: hiddenColor, range: closeRange)
            attributed.addAttribute(.font, value: hiddenFont, range: closeRange)

            let italicFont = Self.resolveFont(family: fontFamily, size: fontSize, italic: true)
            attributed.addAttribute(.font, value: italicFont, range: textMatch)
        }
        applyCachedRegex(regex: Self.italicRegex, lineText: lineText, lineOffset: lineRange.location, handler: applyItalic)
        applyCachedRegex(regex: Self.italicUnderscoreRegex, lineText: lineText, lineOffset: lineRange.location, handler: applyItalic)

        // 9. Inline-Code: `code`
        applyCachedRegex(
            regex: Self.codeRegex,
            lineText: lineText,
            lineOffset: lineRange.location
        ) { fullRange, matchRanges in
            guard let textMatch = matchRanges.first else { return }
            let openRange = NSRange(location: fullRange.location, length: 1)
            let closeRange = NSRange(location: fullRange.location + fullRange.length - 1, length: 1)

            attributed.addAttribute(.foregroundColor, value: hiddenColor, range: openRange)
            attributed.addAttribute(.font, value: hiddenFont, range: openRange)
            attributed.addAttribute(.foregroundColor, value: hiddenColor, range: closeRange)
            attributed.addAttribute(.font, value: hiddenFont, range: closeRange)

            let monoFont = Self.resolveFont(family: fontFamily, size: max(10.0, fontSize - 0.5), mono: true)
            attributed.addAttribute(.font, value: monoFont, range: textMatch)
            attributed.addAttribute(.backgroundColor, value: codeBgColor, range: textMatch)
        }

        // 10. Inline-Mathematik: $formula$
        applyCachedRegex(
            regex: Self.inlineMathRegex,
            lineText: lineText,
            lineOffset: lineRange.location
        ) { fullRange, matchRanges in
            guard let mathMatch = matchRanges.first else { return }
            let openRange = NSRange(location: fullRange.location, length: 1)
            let closeRange = NSRange(location: fullRange.location + fullRange.length - 1, length: 1)

            attributed.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor.withAlphaComponent(0.6), range: openRange)
            attributed.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor.withAlphaComponent(0.6), range: closeRange)

            let mathFont = Self.resolveFont(family: fontFamily, size: fontSize, italic: true)
            attributed.addAttribute(.font, value: mathFont, range: mathMatch)
            attributed.addAttribute(.backgroundColor, value: codeBgColor.withAlphaComponent(0.3), range: mathMatch)
        }

        // 11. Hervorhebung: ==text==
        applyCachedRegex(
            regex: Self.highlightRegex,
            lineText: lineText,
            lineOffset: lineRange.location
        ) { fullRange, matchRanges in
            guard let textMatch = matchRanges.first else { return }
            let openRange = NSRange(location: fullRange.location, length: 2)
            let closeRange = NSRange(location: fullRange.location + fullRange.length - 2, length: 2)

            attributed.addAttribute(.foregroundColor, value: hiddenColor, range: openRange)
            attributed.addAttribute(.font, value: hiddenFont, range: openRange)
            attributed.addAttribute(.foregroundColor, value: hiddenColor, range: closeRange)
            attributed.addAttribute(.font, value: hiddenFont, range: closeRange)

            attributed.addAttribute(.backgroundColor, value: highlightYellow, range: textMatch)
        }

        // 12. Durchgestrichen: ~~text~~
        applyCachedRegex(
            regex: Self.strikeRegex,
            lineText: lineText,
            lineOffset: lineRange.location
        ) { fullRange, matchRanges in
            guard let textMatch = matchRanges.first else { return }
            let openRange = NSRange(location: fullRange.location, length: 2)
            let closeRange = NSRange(location: fullRange.location + fullRange.length - 2, length: 2)

            attributed.addAttribute(.foregroundColor, value: hiddenColor, range: openRange)
            attributed.addAttribute(.font, value: hiddenFont, range: openRange)
            attributed.addAttribute(.foregroundColor, value: hiddenColor, range: closeRange)
            attributed.addAttribute(.font, value: hiddenFont, range: closeRange)

            attributed.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: textMatch)
        }

        // 13. Tastatur-Tags: <kbd>key</kbd>
        applyCachedRegex(
            regex: Self.kbdRegex,
            lineText: lineText,
            lineOffset: lineRange.location
        ) { fullRange, matchRanges in
            guard let textMatch = matchRanges.first else { return }
            let openRange = NSRange(location: fullRange.location, length: 5) // <kbd>
            let closeRange = NSRange(location: fullRange.location + fullRange.length - 6, length: 6) // </kbd>

            attributed.addAttribute(.foregroundColor, value: hiddenColor, range: openRange)
            attributed.addAttribute(.font, value: hiddenFont, range: openRange)
            attributed.addAttribute(.foregroundColor, value: hiddenColor, range: closeRange)
            attributed.addAttribute(.font, value: hiddenFont, range: closeRange)

            let monoFont = Self.resolveFont(family: fontFamily, size: max(10.0, fontSize - 1.0), mono: true)
            attributed.addAttribute(.font, value: monoFont, range: textMatch)
            attributed.addAttribute(.backgroundColor, value: codeBgColor, range: textMatch)
        }
    }

    private func applyCachedRegex(
        regex: NSRegularExpression,
        lineText: String,
        lineOffset: Int,
        handler: (NSRange, [NSRange]) -> Void
    ) {
        let nsLine = lineText as NSString
        let matches = regex.matches(in: lineText, options: [], range: NSRange(location: 0, length: nsLine.length))

        for match in matches {
            guard match.numberOfRanges >= 2 else { continue }
            let fullLineRange = match.range(at: 0)
            var groupRanges: [NSRange] = []
            for i in 1..<match.numberOfRanges {
                let r = match.range(at: i)
                if r.location != NSNotFound {
                    groupRanges.append(NSRange(location: lineOffset + r.location, length: r.length))
                } else {
                    groupRanges.append(NSRange(location: NSNotFound, length: 0))
                }
            }

            let fullGlobalRange = NSRange(location: lineOffset + fullLineRange.location, length: fullLineRange.length)
            handler(fullGlobalRange, groupRanges)
        }
    }
}
