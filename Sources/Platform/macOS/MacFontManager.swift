import AppKit

public final class MacFontManager: NSObject {
    public static let shared = MacFontManager()

    public override init() {
        super.init()
        NSFontManager.shared.target = self
        NSFontManager.shared.action = #selector(changeFont(_:))
    }

    public func availableFamilies() -> [String] {
        let families = NSFontManager.shared.availableFontFamilies
        return families.sorted()
    }

    public func showFontPanel() {
        NSFontManager.shared.orderFrontFontPanel(nil)
    }

    @objc public func changeFont(_ sender: Any?) {
        guard let fontManager = sender as? NSFontManager else { return }
        let currentFont = MarkdownHighlighter.resolveFont(
            family: EditorSettings.shared.fontFamily,
            size: EditorSettings.shared.fontSize
        )
        let newFont = fontManager.convert(currentFont)
        if let family = newFont.familyName, !family.isEmpty {
            EditorSettings.shared.fontFamily = family
        }
        EditorSettings.shared.fontSize = Double(newFont.pointSize)
    }
}
