import Foundation

#if os(iOS)
import UIKit
public typealias PlatformFont = UIFont
public typealias PlatformColor = UIColor
#elseif os(macOS)
import AppKit
public typealias PlatformFont = NSFont
public typealias PlatformColor = NSColor
#endif

public final class MarkdownHighlighter {
    public static let shared = MarkdownHighlighter()

    private init() {}

    public static func resolveFont(
        family: String,
        size: Double,
        bold: Bool = false,
        italic: Bool = false,
        mono: Bool = false
    ) -> PlatformFont {
        #if os(iOS)
        if mono {
            return UIFont.monospacedSystemFont(ofSize: size, weight: bold ? .bold : .regular)
        }
        var traits: UIFontDescriptor.SymbolicTraits = []
        if bold { traits.insert(.traitBold) }
        if italic { traits.insert(.traitItalic) }

        let targetFamily = (family.isEmpty || family == "System" || family == ".AppleSystemUIFont") ? "" : family
        if !targetFamily.isEmpty, let base = UIFont(name: targetFamily, size: size) {
            if !traits.isEmpty, let desc = base.fontDescriptor.withSymbolicTraits(traits) {
                return UIFont(descriptor: desc, size: size)
            }
            return base
        }

        let sys = UIFont.systemFont(ofSize: size)
        if !traits.isEmpty, let desc = sys.fontDescriptor.withSymbolicTraits(traits) {
            return UIFont(descriptor: desc, size: size)
        }
        return bold ? UIFont.boldSystemFont(ofSize: size) : (italic ? UIFont.italicSystemFont(ofSize: size) : sys)
        #elseif os(macOS)
        if mono {
            return NSFont.monospacedSystemFont(ofSize: size, weight: bold ? .bold : .regular)
        }
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
        return base
        #endif
    }

    public static func makeParagraphStyle(isJustified: Bool, isHyphenationEnabled: Bool) -> NSMutableParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.alignment = isJustified ? .justified : .left
        style.hyphenationFactor = isHyphenationEnabled ? 1.0 : 0.0
        style.lineSpacing = 3.0
        return style
    }

    public func highlight(
        text: String,
        isMarkdown: Bool,
        selectedRange: NSRange,
        fontFamily: String,
        fontSize: Double,
        isJustified: Bool,
        isHyphenationEnabled: Bool,
        isMarkdownHighlightingEnabled: Bool
    ) -> NSAttributedString {
        let attributed = NSMutableAttributedString(string: text)
        let fullRange = NSRange(location: 0, length: (text as NSString).length)
        guard fullRange.length > 0 else { return attributed }

        let regularFont = Self.resolveFont(family: fontFamily, size: fontSize)
        let paragraphStyle = Self.makeParagraphStyle(isJustified: isJustified, isHyphenationEnabled: isHyphenationEnabled)

        #if os(iOS)
        let textColor = UIColor.label
        let hiddenColor = UIColor.clear
        let codeBgColor = UIColor.systemGray.withAlphaComponent(0.15)
        let secondaryColor = UIColor.secondaryLabel
        #elseif os(macOS)
        let textColor = NSColor.labelColor
        let hiddenColor = NSColor.clear
        let codeBgColor = NSColor.quaternaryLabelColor
        let secondaryColor = NSColor.secondaryLabelColor
        #endif

        attributed.addAttribute(.font, value: regularFont, range: fullRange)
        attributed.addAttribute(.foregroundColor, value: textColor, range: fullRange)
        attributed.addAttribute(.paragraphStyle, value: paragraphStyle, range: fullRange)

        // For plain text (.txt files): do not format markdown, show pure normal text!
        guard isMarkdown && isMarkdownHighlightingEnabled else { return attributed }

        let hiddenFont = Self.resolveFont(family: fontFamily, size: 0.001)
        let nsString = text as NSString
        var searchIndex = 0

        while searchIndex < nsString.length {
            let lineRange = nsString.lineRange(for: NSRange(location: searchIndex, length: 0))
            guard lineRange.length > 0 else { break }

            let lineText = nsString.substring(with: lineRange)
            let cursorIntersects = (selectedRange.location != NSNotFound) &&
                (selectedRange.location >= lineRange.location && selectedRange.location <= (lineRange.location + lineRange.length))

            if !cursorIntersects {
                // Obsidian Live Preview: Hide markdown marks and show styled text
                applyHeadingIfPresent(
                    lineText: lineText,
                    lineRange: lineRange,
                    attributed: attributed,
                    fontFamily: fontFamily,
                    fontSize: fontSize,
                    hiddenFont: hiddenFont,
                    hiddenColor: hiddenColor
                )

                applyInlineStyles(
                    lineRange: lineRange,
                    nsString: nsString,
                    attributed: attributed,
                    fontFamily: fontFamily,
                    fontSize: fontSize,
                    hiddenFont: hiddenFont,
                    hiddenColor: hiddenColor,
                    codeBgColor: codeBgColor
                )
            } else {
                // Active line: Show raw markdown syntax, style # prefix in muted color for clarity
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
    ) {
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

                // Hide the "# " mark like Obsidian
                attributed.addAttribute(.foregroundColor, value: hiddenColor, range: prefixRange)
                attributed.addAttribute(.font, value: hiddenFont, range: prefixRange)

                // Format the heading content in bold and scaled size
                let bonus: Double
                switch count {
                case 1: bonus = 5.0
                case 2: bonus = 3.0
                case 3: bonus = 1.5
                default: bonus = 0.5
                }
                let headingFont = Self.resolveFont(family: fontFamily, size: fontSize + bonus, bold: true)
                attributed.addAttribute(.font, value: headingFont, range: textRange)
            }
        }
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
        codeBgColor: PlatformColor
    ) {
        let lineText = nsString.substring(with: lineRange)
        guard lineText.contains("*") || lineText.contains("`") || lineText.contains("~") else { return }

        // Bold: **text**
        applyRegex(
            pattern: "\\*\\*(.+?)\\*\\*",
            lineText: lineText,
            lineOffset: lineRange.location,
            attributed: attributed
        ) { fullRange, matchRange in
            let openRange = NSRange(location: fullRange.location, length: 2)
            let closeRange = NSRange(location: fullRange.location + fullRange.length - 2, length: 2)
            attributed.addAttribute(.foregroundColor, value: hiddenColor, range: openRange)
            attributed.addAttribute(.font, value: hiddenFont, range: openRange)
            attributed.addAttribute(.foregroundColor, value: hiddenColor, range: closeRange)
            attributed.addAttribute(.font, value: hiddenFont, range: closeRange)

            let boldFont = Self.resolveFont(family: fontFamily, size: fontSize, bold: true)
            attributed.addAttribute(.font, value: boldFont, range: matchRange)
        }

        // Italic: *text*
        applyRegex(
            pattern: "(?<!\\*)\\*([^*]+?)\\*(?!\\*)",
            lineText: lineText,
            lineOffset: lineRange.location,
            attributed: attributed
        ) { fullRange, matchRange in
            let openRange = NSRange(location: fullRange.location, length: 1)
            let closeRange = NSRange(location: fullRange.location + fullRange.length - 1, length: 1)
            attributed.addAttribute(.foregroundColor, value: hiddenColor, range: openRange)
            attributed.addAttribute(.font, value: hiddenFont, range: openRange)
            attributed.addAttribute(.foregroundColor, value: hiddenColor, range: closeRange)
            attributed.addAttribute(.font, value: hiddenFont, range: closeRange)

            let italicFont = Self.resolveFont(family: fontFamily, size: fontSize, italic: true)
            attributed.addAttribute(.font, value: italicFont, range: matchRange)
        }

        // Inline Code: `code`
        applyRegex(
            pattern: "`([^`]+?)`",
            lineText: lineText,
            lineOffset: lineRange.location,
            attributed: attributed
        ) { fullRange, matchRange in
            let openRange = NSRange(location: fullRange.location, length: 1)
            let closeRange = NSRange(location: fullRange.location + fullRange.length - 1, length: 1)
            attributed.addAttribute(.foregroundColor, value: hiddenColor, range: openRange)
            attributed.addAttribute(.font, value: hiddenFont, range: openRange)
            attributed.addAttribute(.foregroundColor, value: hiddenColor, range: closeRange)
            attributed.addAttribute(.font, value: hiddenFont, range: closeRange)

            let monoFont = Self.resolveFont(family: fontFamily, size: fontSize, mono: true)
            attributed.addAttribute(.font, value: monoFont, range: matchRange)
            attributed.addAttribute(.backgroundColor, value: codeBgColor, range: matchRange)
        }

        // Strikethrough: ~~text~~
        applyRegex(
            pattern: "~~([^~]+?)~~",
            lineText: lineText,
            lineOffset: lineRange.location,
            attributed: attributed
        ) { fullRange, matchRange in
            let openRange = NSRange(location: fullRange.location, length: 2)
            let closeRange = NSRange(location: fullRange.location + fullRange.length - 2, length: 2)
            attributed.addAttribute(.foregroundColor, value: hiddenColor, range: openRange)
            attributed.addAttribute(.font, value: hiddenFont, range: openRange)
            attributed.addAttribute(.foregroundColor, value: hiddenColor, range: closeRange)
            attributed.addAttribute(.font, value: hiddenFont, range: closeRange)

            attributed.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: matchRange)
        }
    }

    private func applyRegex(
        pattern: String,
        lineText: String,
        lineOffset: Int,
        attributed: NSMutableAttributedString,
        handler: (NSRange, NSRange) -> Void
    ) {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return }
        let nsLine = lineText as NSString
        let matches = regex.matches(in: lineText, options: [], range: NSRange(location: 0, length: nsLine.length))

        for match in matches {
            guard match.numberOfRanges >= 2 else { continue }
            let fullLineRange = match.range(at: 0)
            let contentLineRange = match.range(at: 1)

            let fullGlobalRange = NSRange(location: lineOffset + fullLineRange.location, length: fullLineRange.length)
            let contentGlobalRange = NSRange(location: lineOffset + contentLineRange.location, length: contentLineRange.length)

            handler(fullGlobalRange, contentGlobalRange)
        }
    }
}
