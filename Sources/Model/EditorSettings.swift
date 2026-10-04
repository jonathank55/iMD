import SwiftUI
import Combine

public final class EditorSettings: ObservableObject {
    public static let shared = EditorSettings()

    private enum Keys {
        static let fontFamily = "iText.fontFamily"
        static let fontSize = "iText.fontSize"
        static let isJustified = "iText.isJustified"
        static let isHyphenationEnabled = "iText.isHyphenationEnabled"
        static let isMarkdownHighlightingEnabled = "iText.isMarkdownHighlightingEnabled"
    }

    @Published public var fontFamily: String {
        didSet { UserDefaults.standard.set(fontFamily, forKey: Keys.fontFamily) }
    }

    @Published public var fontSize: Double {
        didSet { UserDefaults.standard.set(fontSize, forKey: Keys.fontSize) }
    }

    @Published public var isJustified: Bool {
        didSet { UserDefaults.standard.set(isJustified, forKey: Keys.isJustified) }
    }

    @Published public var isHyphenationEnabled: Bool {
        didSet { UserDefaults.standard.set(isHyphenationEnabled, forKey: Keys.isHyphenationEnabled) }
    }

    @Published public var isMarkdownHighlightingEnabled: Bool {
        didSet { UserDefaults.standard.set(isMarkdownHighlightingEnabled, forKey: Keys.isMarkdownHighlightingEnabled) }
    }

    @Published public var isShowingSettings: Bool = false
    @Published public var isShowingFontPicker: Bool = false

    public init() {
        let defaults = UserDefaults.standard
        self.fontFamily = defaults.string(forKey: Keys.fontFamily) ?? "PT Serif"
        let savedSize = defaults.double(forKey: Keys.fontSize)
        self.fontSize = savedSize > 0 ? savedSize : 16.0
        self.isJustified = defaults.object(forKey: Keys.isJustified) as? Bool ?? true
        self.isHyphenationEnabled = defaults.object(forKey: Keys.isHyphenationEnabled) as? Bool ?? true
        self.isMarkdownHighlightingEnabled = defaults.object(forKey: Keys.isMarkdownHighlightingEnabled) as? Bool ?? true
    }

    public func zoomIn() {
        fontSize = min(fontSize + 1.0, 48.0)
    }

    public func zoomOut() {
        fontSize = max(fontSize - 1.0, 10.0)
    }

    public func resetZoom() {
        fontSize = 16.0
    }
}
