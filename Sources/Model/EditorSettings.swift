import SwiftUI
import Combine

public struct AppConfig: Codable, Equatable {
    public var fontFamily: String
    public var fontSize: Double
    public var lineSpacing: Double
    public var isJustified: Bool
    public var isHyphenationEnabled: Bool
    public var isMarkdownHighlightingEnabled: Bool
    public var defaultFormat: String
    public var paperFormat: String

    public init(
        fontFamily: String = "PT Serif",
        fontSize: Double = 16.0,
        lineSpacing: Double = 3.0,
        isJustified: Bool = true,
        isHyphenationEnabled: Bool = true,
        isMarkdownHighlightingEnabled: Bool = true,
        defaultFormat: String = "md",
        paperFormat: String = "a4"
    ) {
        self.fontFamily = fontFamily
        self.fontSize = fontSize
        self.lineSpacing = lineSpacing
        self.isJustified = isJustified
        self.isHyphenationEnabled = isHyphenationEnabled
        self.isMarkdownHighlightingEnabled = isMarkdownHighlightingEnabled
        self.defaultFormat = defaultFormat
        self.paperFormat = paperFormat
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.fontFamily = try container.decodeIfPresent(String.self, forKey: .fontFamily) ?? "PT Serif"
        self.fontSize = try container.decodeIfPresent(Double.self, forKey: .fontSize) ?? 16.0
        self.lineSpacing = try container.decodeIfPresent(Double.self, forKey: .lineSpacing) ?? 3.0
        self.isJustified = try container.decodeIfPresent(Bool.self, forKey: .isJustified) ?? true
        self.isHyphenationEnabled = try container.decodeIfPresent(Bool.self, forKey: .isHyphenationEnabled) ?? true
        self.isMarkdownHighlightingEnabled = try container.decodeIfPresent(Bool.self, forKey: .isMarkdownHighlightingEnabled) ?? true
        self.defaultFormat = try container.decodeIfPresent(String.self, forKey: .defaultFormat) ?? "md"
        self.paperFormat = try container.decodeIfPresent(String.self, forKey: .paperFormat) ?? "a4"
    }
}

public final class EditorSettings: ObservableObject {
    public static let shared = EditorSettings()

    public static var configDirectoryURL: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent(".config/iText", isDirectory: true)
    }

    public static var configFileURL: URL {
        configDirectoryURL.appendingPathComponent("config.json", isDirectory: false)
    }

    @Published public var fontFamily: String {
        didSet { persist() }
    }

    @Published public var fontSize: Double {
        didSet { persist() }
    }

    @Published public var lineSpacing: Double {
        didSet { persist() }
    }

    @Published public var isJustified: Bool {
        didSet { persist() }
    }

    @Published public var isHyphenationEnabled: Bool {
        didSet { persist() }
    }

    @Published public var isMarkdownHighlightingEnabled: Bool {
        didSet { persist() }
    }

    @Published public var defaultFormat: String {
        didSet { persist() }
    }

    @Published public var paperFormat: String {
        didSet { persist() }
    }

    @Published public var isShowingSettings: Bool = false
    @Published public var isShowingStatistics: Bool = false
    @Published public var isShowingPrintDialog: Bool = false

    private var isInitializing = false

    public init() {
        self.isInitializing = true
        let fileExists = FileManager.default.fileExists(atPath: Self.configFileURL.path)
        let config = Self.loadConfigFile()
        self.fontFamily = config.fontFamily
        self.fontSize = config.fontSize
        self.lineSpacing = config.lineSpacing >= 0 ? config.lineSpacing : 3.0
        self.isJustified = config.isJustified
        self.isHyphenationEnabled = config.isHyphenationEnabled
        self.isMarkdownHighlightingEnabled = config.isMarkdownHighlightingEnabled
        self.defaultFormat = config.defaultFormat
        self.paperFormat = config.paperFormat
        self.isInitializing = false

        if !fileExists {
            self.persist()
        }
    }

    public static func loadConfigFile() -> AppConfig {
        let fileURL = configFileURL
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return AppConfig()
        }
        do {
            let data = try Data(contentsOf: fileURL)
            let decoder = JSONDecoder()
            return try decoder.decode(AppConfig.self, from: data)
        } catch {
            return AppConfig()
        }
    }

    public func persist() {
        guard !isInitializing else { return }

        let config = AppConfig(
            fontFamily: fontFamily,
            fontSize: fontSize,
            lineSpacing: lineSpacing,
            isJustified: isJustified,
            isHyphenationEnabled: isHyphenationEnabled,
            isMarkdownHighlightingEnabled: isMarkdownHighlightingEnabled,
            defaultFormat: defaultFormat,
            paperFormat: paperFormat
        )

        let dirURL = Self.configDirectoryURL
        let fileURL = Self.configFileURL

        DispatchQueue.global(qos: .utility).async {
            do {
                if !FileManager.default.fileExists(atPath: dirURL.path) {
                    try FileManager.default.createDirectory(at: dirURL, withIntermediateDirectories: true, attributes: nil)
                }
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                let data = try encoder.encode(config)
                try data.write(to: fileURL, options: .atomic)
            } catch {
                // Fehler beim Schreiben der Konfiguration wird lautlos abgefangen
            }
        }
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

    public func openConfigFileInDefaultEditor() {
        persist()
        NSWorkspace.shared.open(Self.configFileURL)
    }

    public func openConfigDirectoryInFinder() {
        persist()
        NSWorkspace.shared.open(Self.configDirectoryURL)
    }
}
