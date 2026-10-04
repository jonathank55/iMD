import SwiftUI

extension Notification.Name {
    public static let iTextPrintRequested = Notification.Name("iTextPrintRequested")
    public static let iTextShowStatisticsRequested = Notification.Name("iTextShowStatisticsRequested")
    public static let iTextShowSettingsRequested = Notification.Name("iTextShowSettingsRequested")
}

public struct iTextCommands: Commands {
    @ObservedObject private var settings = EditorSettings.shared

    private let standardFonts: [String] = [
        "PT Serif",
        "System",
        "New York",
        "Helvetica Neue",
        "Georgia",
        "Palatino",
        "Times New Roman",
        "Menlo",
        "SF Mono",
        "Courier New"
    ]

    public init() {}

    public var body: some Commands {
        CommandGroup(replacing: .appSettings) {
            Button("Einstellungen…") {
                NotificationCenter.default.post(name: .iTextShowSettingsRequested, object: nil)
            }
            .keyboardShortcut(",", modifiers: .command)
        }

        CommandGroup(replacing: .printItem) {
            Button("Drucken…") {
                NotificationCenter.default.post(name: .iTextPrintRequested, object: nil)
            }
            .keyboardShortcut("p", modifiers: .command)
        }

        CommandMenu("Formatierung") {
            Button("Schriften einblenden…") {
                MacFontManager.shared.showFontPanel()
            }
            .keyboardShortcut("t", modifiers: .command)

            Menu("Schriftart") {
                ForEach(standardFonts, id: \.self) { fontName in
                    Button(action: {
                        settings.fontFamily = fontName
                    }) {
                        HStack {
                            Text(fontName)
                            if settings.fontFamily == fontName {
                                Spacer()
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            }

            Divider()

            Button("Schrift vergrößern") {
                settings.zoomIn()
            }
            .keyboardShortcut("+", modifiers: .command)

            Button("Schrift verkleinern") {
                settings.zoomOut()
            }
            .keyboardShortcut("-", modifiers: .command)

            Button("Standardgröße") {
                settings.resetZoom()
            }
            .keyboardShortcut("0", modifiers: .command)

            Divider()

            Toggle("Blocksatz (Typst)", isOn: $settings.isJustified)
            Toggle("Automatische Silbentrennung", isOn: $settings.isHyphenationEnabled)
            Toggle("Obsidian Live-Vorschau", isOn: $settings.isMarkdownHighlightingEnabled)

            Divider()

            Button("Konfigurationsdatei öffnen…") {
                settings.openConfigFileInDefaultEditor()
            }

            Button("Konfigurationsordner im Finder anzeigen") {
                settings.openConfigDirectoryInFinder()
            }
        }

        CommandMenu("Ansicht") {
            Button("Dokument-Statistik anzeigen…") {
                NotificationCenter.default.post(name: .iTextShowStatisticsRequested, object: nil)
            }
            .keyboardShortcut("i", modifiers: [.command, .option])
        }
    }
}
