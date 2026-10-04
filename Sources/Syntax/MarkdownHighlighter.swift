import AppKit

public typealias PlatformFont = NSFont
public typealias PlatformColor = NSColor

public final class MarkdownHighlighter {
    public static let shared = MarkdownHighlighter()

    private static var fontCache: [String: PlatformFont] = [:]
    private static let cacheLock = NSLock()

    // Vorkompilierte reguläre Ausdrücke für maximale Performance
    private static let boldItalicRegex: NSRegularExpression = {
        (try? NSRegularExpression(pattern: "\\*\\*\\*(.+?)\\*\\*\\*", options: [])) ?? NSRegularExpression()
    }()

    private static let boldRegex: NSRegularExpression = {
        (try? NSRegularExpression(pattern: "\\*\\*(.+?)\\*\\*", options: [])) ?? NSRegularExpression()
    }()

    private static let italicRegex: NSRegularExpression = {
        (try? NSRegularExpression(pattern: "(?<!\\*)\\*([^*]+?)\\*(?!\\*)", options: [])) ?? NSRegularExpression()
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

    private static let taskUncheckedRegex: NSRegularExpression = {
        (try? NSRegularExpression(pattern: "^([ \t]*[-*+])[ \t]+(\\[ \\])[ \t]+(.*)$", options: [])) ?? NSRegularExpression()
    }()

    private static let taskCheckedRegex: NSRegularExpression = {
        (try? NSRegularExpression(pattern: "^([ \t]*[-*+])[ \t]+(\\[[xX]\\])[ \t]+(.*)$", options: [])) ?? NSRegularExpression()
    }()

    private static let bulletListRegex: NSRegularExpression = {
        (try? NSRegularExpression(pattern: "^([ \t]*)([-*+])[ \t]+(.*)$", options: [])) ?? NSRegularExpression()
    }()

    private static let numberedListRegex: NSRegularExpression = {
        (try? NSRegularExpression(pattern: "^([ \t]*)([0-9]+[.)])[ \t]+(.*)$", options: [])) ?? NSRegularExpression()
    }()

    private static let quoteRegex: NSRegularExpression = {
        (try? NSRegularExpression(pattern: "^([ \t]*>)[ \t]?(.*)$", options: [])) ?? NSRegularExpression()
    }()

    private static let hrRegex: NSRegularExpression = {
        (try? NSRegularExpression(pattern: "^[ \t]*([-*_])[ \t]*\\1[ \t]*\\1[ \t]*$", options: [])) ?? NSRegularExpression()
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
            var base: NSFont
            if !targetFamily.isEmpty, let custom = NSFont(name: targetFamily, size: size) {
                base = custom
            } else {
                base = NSFont.systemFont(ofSize: size)
            }

            var mask: NSFontTraitMask = []
            if bold { mask.insert(.boldFontMask) }
            if italic { mask.insert(.italicFontMask) }

            if !mask.isEmpty {
                base = NSFontManager.shared.convert(base, toHaveTrait: mask)
            }
            font = base
        }

        cacheLock.lock()
        fontCache[cacheKey] = font
        cacheLock.unlock()

        return font
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

        while searchIndex < nsString.length {
            let lineRange = nsString.lineRange(for: NSRange(location: searchIndex, length: 0))
            guard lineRange.length > 0 else { break }

            let lineText = nsString.substring(with: lineRange)
            let trimmed = lineText.trimmingCharacters(in: .whitespacesAndNewlines)

            // Fenced Code-Block Erkennung (```)
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

            let cursorIntersects = (selectedRange.location != NSNotFound) &&
                (selectedRange.location >= lineRange.location && selectedRange.location <= (lineRange.location + lineRange.length))

            if !cursorIntersects {
                // Live Preview: Alle Markdown-Elemente formatiert und Marker ausgeblendet

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

                if !isHeading {
                    // 2. Trennlinie (---, ***, ___)
                    let isHR = applyHorizontalRuleIfPresent(
                        lineText: lineText,
                        lineRange: lineRange,
                        attributed: attributed,
                        secondaryColor: secondaryColor
                    )

                    // 3. Zitat (> ...)
                    let isQuote = !isHR && applyQuoteIfPresent(
                        lineText: lineText,
                        lineRange: lineRange,
                        attributed: attributed,
                        fontFamily: fontFamily,
                        fontSize: fontSize,
                        hiddenFont: hiddenFont,
                        hiddenColor: hiddenColor,
                        secondaryColor: secondaryColor
                    )

                    // 4. Aufgabenlisten (- [ ] und - [x])
                    let isTask = !isHR && !isQuote && applyTaskListIfPresent(
                        lineText: lineText,
                        lineRange: lineRange,
                        attributed: attributed,
                        secondaryColor: secondaryColor
                    )

                    // 5. Ungeordnete Listen (- , * , + )
                    let isBullet = !isHR && !isQuote && !isTask && applyBulletListIfPresent(
                        lineText: lineText,
                        lineRange: lineRange,
                        attributed: attributed
                    )

                    // 6. Nummerierte Listen (1. , 2. )
                    _ = !isHR && !isQuote && !isTask && !isBullet && applyNumberedListIfPresent(
                        lineText: lineText,
                        lineRange: lineRange,
                        attributed: attributed,
                        secondaryColor: secondaryColor
                    )

                    // 7. Tabellen (| ... |)
                    let isTable = !isHR && !isQuote && applyTableIfPresent(
                        lineText: lineText,
                        lineRange: lineRange,
                        attributed: attributed,
                        fontFamily: fontFamily,
                        fontSize: fontSize
                    )

                    // 8. Inline-Stile (Fett, Kursiv, Code, Durchgestrichen, Highlight, Links)
                    if !isHR && !isTable {
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

        attributed.addAttribute(.foregroundColor, value: secondaryColor, range: lineRange)
        attributed.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: lineRange)
        attributed.addAttribute(.strikethroughColor, value: secondaryColor, range: lineRange)
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

    private func applyTableIfPresent(
        lineText: String,
        lineRange: NSRange,
        attributed: NSMutableAttributedString,
        fontFamily: String,
        fontSize: Double
    ) -> Bool {
        let trimmed = lineText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("|") && trimmed.hasSuffix("|") && trimmed.contains("|") else { return false }

        let monoFont = Self.resolveFont(family: fontFamily, size: fontSize - 0.5, mono: true)
        attributed.addAttribute(.font, value: monoFont, range: lineRange)
        return true
    }

    private func applyActiveLineStyling(
        lineText: String,
        lineRange: NSRange,
        attributed: NSMutableAttributedString,
        secondaryColor: PlatformColor
    ) {
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
        guard lineText.contains("*") || lineText.contains("`") || lineText.contains("~") || lineText.contains("=") || lineText.contains("[") else { return }

        // Links: [Text](URL)
        applyCachedRegex(
            regex: Self.linkRegex,
            lineText: lineText,
            lineOffset: lineRange.location
        ) { fullRange, matchRange in
            guard matchRange.count >= 2 else { return }
            let textMatch = matchRange[0]
            let urlMatch = matchRange[1]

            let openBracket = NSRange(location: fullRange.location, length: 1)
            let midBrackets = NSRange(location: textMatch.location + textMatch.length, length: urlMatch.location + urlMatch.length + 1 - (textMatch.location + textMatch.length))

            attributed.addAttribute(.foregroundColor, value: hiddenColor, range: openBracket)
            attributed.addAttribute(.font, value: hiddenFont, range: openBracket)
            attributed.addAttribute(.foregroundColor, value: hiddenColor, range: midBrackets)
            attributed.addAttribute(.font, value: hiddenFont, range: midBrackets)

            attributed.addAttribute(.foregroundColor, value: linkColor, range: textMatch)
            attributed.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: textMatch)
        }

        // Fett-Kursiv: ***text***
        applyCachedRegex(
            regex: Self.boldItalicRegex,
            lineText: lineText,
            lineOffset: lineRange.location
        ) { fullRange, matchRange in
            guard let textMatch = matchRange.first else { return }
            let openRange = NSRange(location: fullRange.location, length: 3)
            let closeRange = NSRange(location: fullRange.location + fullRange.length - 3, length: 3)

            attributed.addAttribute(.foregroundColor, value: hiddenColor, range: openRange)
            attributed.addAttribute(.font, value: hiddenFont, range: openRange)
            attributed.addAttribute(.foregroundColor, value: hiddenColor, range: closeRange)
            attributed.addAttribute(.font, value: hiddenFont, range: closeRange)

            let boldItalicFont = Self.resolveFont(family: fontFamily, size: fontSize, bold: true, italic: true)
            attributed.addAttribute(.font, value: boldItalicFont, range: textMatch)
        }

        // Hervorhebung: ==text==
        applyCachedRegex(
            regex: Self.highlightRegex,
            lineText: lineText,
            lineOffset: lineRange.location
        ) { fullRange, matchRange in
            guard let textMatch = matchRange.first else { return }
            let openRange = NSRange(location: fullRange.location, length: 2)
            let closeRange = NSRange(location: fullRange.location + fullRange.length - 2, length: 2)

            attributed.addAttribute(.foregroundColor, value: hiddenColor, range: openRange)
            attributed.addAttribute(.font, value: hiddenFont, range: openRange)
            attributed.addAttribute(.foregroundColor, value: hiddenColor, range: closeRange)
            attributed.addAttribute(.font, value: hiddenFont, range: closeRange)

            attributed.addAttribute(.backgroundColor, value: highlightYellow, range: textMatch)
        }

        // Fett: **text**
        applyCachedRegex(
            regex: Self.boldRegex,
            lineText: lineText,
            lineOffset: lineRange.location
        ) { fullRange, matchRange in
            guard let textMatch = matchRange.first else { return }
            let openRange = NSRange(location: fullRange.location, length: 2)
            let closeRange = NSRange(location: fullRange.location + fullRange.length - 2, length: 2)

            attributed.addAttribute(.foregroundColor, value: hiddenColor, range: openRange)
            attributed.addAttribute(.font, value: hiddenFont, range: openRange)
            attributed.addAttribute(.foregroundColor, value: hiddenColor, range: closeRange)
            attributed.addAttribute(.font, value: hiddenFont, range: closeRange)

            let boldFont = Self.resolveFont(family: fontFamily, size: fontSize, bold: true)
            attributed.addAttribute(.font, value: boldFont, range: textMatch)
        }

        // Kursiv: *text*
        applyCachedRegex(
            regex: Self.italicRegex,
            lineText: lineText,
            lineOffset: lineRange.location
        ) { fullRange, matchRange in
            guard let textMatch = matchRange.first else { return }
            let openRange = NSRange(location: fullRange.location, length: 1)
            let closeRange = NSRange(location: fullRange.location + fullRange.length - 1, length: 1)

            attributed.addAttribute(.foregroundColor, value: hiddenColor, range: openRange)
            attributed.addAttribute(.font, value: hiddenFont, range: openRange)
            attributed.addAttribute(.foregroundColor, value: hiddenColor, range: closeRange)
            attributed.addAttribute(.font, value: hiddenFont, range: closeRange)

            let italicFont = Self.resolveFont(family: fontFamily, size: fontSize, italic: true)
            attributed.addAttribute(.font, value: italicFont, range: textMatch)
        }

        // Inline-Code: `code`
        applyCachedRegex(
            regex: Self.codeRegex,
            lineText: lineText,
            lineOffset: lineRange.location
        ) { fullRange, matchRange in
            guard let textMatch = matchRange.first else { return }
            let openRange = NSRange(location: fullRange.location, length: 1)
            let closeRange = NSRange(location: fullRange.location + fullRange.length - 1, length: 1)

            attributed.addAttribute(.foregroundColor, value: hiddenColor, range: openRange)
            attributed.addAttribute(.font, value: hiddenFont, range: openRange)
            attributed.addAttribute(.foregroundColor, value: hiddenColor, range: closeRange)
            attributed.addAttribute(.font, value: hiddenFont, range: closeRange)

            let monoFont = Self.resolveFont(family: fontFamily, size: fontSize, mono: true)
            attributed.addAttribute(.font, value: monoFont, range: textMatch)
            attributed.addAttribute(.backgroundColor, value: codeBgColor, range: textMatch)
        }

        // Durchgestrichen: ~~text~~
        applyCachedRegex(
            regex: Self.strikeRegex,
            lineText: lineText,
            lineOffset: lineRange.location
        ) { fullRange, matchRange in
            guard let textMatch = matchRange.first else { return }
            let openRange = NSRange(location: fullRange.location, length: 2)
            let closeRange = NSRange(location: fullRange.location + fullRange.length - 2, length: 2)

            attributed.addAttribute(.foregroundColor, value: hiddenColor, range: openRange)
            attributed.addAttribute(.font, value: hiddenFont, range: openRange)
            attributed.addAttribute(.foregroundColor, value: hiddenColor, range: closeRange)
            attributed.addAttribute(.font, value: hiddenFont, range: closeRange)

            attributed.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: textMatch)
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
                }
            }

            let fullGlobalRange = NSRange(location: lineOffset + fullLineRange.location, length: fullLineRange.length)
            handler(fullGlobalRange, groupRanges)
        }
    }
}
