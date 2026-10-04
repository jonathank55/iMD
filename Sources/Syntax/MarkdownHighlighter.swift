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

    public static func resolveFont(family: String, size: Double, bold: Bool = false) -> PlatformFont {
        #if os(iOS)
        if family.isEmpty || family == "System" || family == ".AppleSystemUIFont" {
            return bold ? UIFont.boldSystemFont(ofSize: size) : UIFont.systemFont(ofSize: size)
        }
        if let baseFont = UIFont(name: family, size: size) {
            if bold {
                if let descriptor = baseFont.fontDescriptor.withSymbolicTraits(.traitBold) {
                    return UIFont(descriptor: descriptor, size: size)
                }
                return UIFont.boldSystemFont(ofSize: size)
            }
            return baseFont
        }
        return bold ? UIFont.boldSystemFont(ofSize: size) : UIFont.systemFont(ofSize: size)
        #elseif os(macOS)
        if family.isEmpty || family == "System" || family == ".AppleSystemUIFont" {
            return bold ? NSFont.boldSystemFont(ofSize: size) : NSFont.systemFont(ofSize: size)
        }
        if let baseFont = NSFont(name: family, size: size) {
            if bold {
                let boldFont = NSFontManager.shared.convert(baseFont, toHaveTrait: .boldFontMask)
                return boldFont
            }
            return baseFont
        }
        return bold ? NSFont.boldSystemFont(ofSize: size) : NSFont.systemFont(ofSize: size)
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

        let regularFont = Self.resolveFont(family: fontFamily, size: fontSize, bold: false)
        let paragraphStyle = Self.makeParagraphStyle(isJustified: isJustified, isHyphenationEnabled: isHyphenationEnabled)

        #if os(iOS)
        let textColor = UIColor.label
        #elseif os(macOS)
        let textColor = NSColor.labelColor
        #endif

        attributed.addAttribute(.font, value: regularFont, range: fullRange)
        attributed.addAttribute(.foregroundColor, value: textColor, range: fullRange)
        attributed.addAttribute(.paragraphStyle, value: paragraphStyle, range: fullRange)

        guard isMarkdownHighlightingEnabled else { return attributed }

        let nsString = text as NSString
        var searchIndex = 0

        while searchIndex < nsString.length {
            let lineRange = nsString.lineRange(for: NSRange(location: searchIndex, length: 0))
            guard lineRange.length > 0 else { break }

            let lineText = nsString.substring(with: lineRange)
            let trimmedLine = lineText.trimmingCharacters(in: .whitespaces)

            if trimmedLine.hasPrefix("#") {
                // Check if cursor intersects this line
                let cursorIntersects = (selectedRange.location != NSNotFound) &&
                    (selectedRange.location >= lineRange.location && selectedRange.location <= (lineRange.location + lineRange.length))

                if !cursorIntersects {
                    var headingLevel = 0
                    for char in trimmedLine {
                        if char == "#" {
                            headingLevel += 1
                        } else {
                            break
                        }
                    }

                    if headingLevel > 0 && headingLevel <= 6 {
                        let bonusSize: Double
                        switch headingLevel {
                        case 1: bonusSize = 4.0
                        case 2: bonusSize = 2.5
                        case 3: bonusSize = 1.5
                        default: bonusSize = 0.5
                        }
                        let headingFont = Self.resolveFont(family: fontFamily, size: fontSize + bonusSize, bold: true)
                        attributed.addAttribute(.font, value: headingFont, range: lineRange)
                    }
                }
            }

            searchIndex = lineRange.location + lineRange.length
        }

        return attributed
    }
}
