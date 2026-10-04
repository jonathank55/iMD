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
            Button("Fett") {
                NotificationCenter.default.post(name: .iTextFormatBoldRequested, object: nil)
            }
            .keyboardShortcut("b", modifiers: .command)

            Button("Kursiv") {
                NotificationCenter.default.post(name: .iTextFormatItalicRequested, object: nil)
            }
            .keyboardShortcut("i", modifiers: .command)

            Button("Durchgestrichen") {
                NotificationCenter.default.post(name: .iTextFormatStrikethroughRequested, object: nil)
            }
            .keyboardShortcut("x", modifiers: [.command, .shift])

            Button("Code") {
                NotificationCenter.default.post(name: .iTextFormatCodeRequested, object: nil)
            }
            .keyboardShortcut("c", modifiers: [.command, .shift])

            Divider()

            Button("Überschrift 1") {
                NotificationCenter.default.post(name: .iTextFormatHeading1Requested, object: nil)
            }
            .keyboardShortcut("1", modifiers: [.command, .option])

            Button("Überschrift 2") {
                NotificationCenter.default.post(name: .iTextFormatHeading2Requested, object: nil)
            }
            .keyboardShortcut("2", modifiers: [.command, .option])

            Button("Überschrift 3") {
                NotificationCenter.default.post(name: .iTextFormatHeading3Requested, object: nil)
            }
            .keyboardShortcut("3", modifiers: [.command, .option])

            Divider()

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

            Menu("Zeilenabstand") {
                Button(action: { settings.lineSpacing = 0.0 }) {
                    HStack {
                        Text("Kompakt (0 pt)")
                        if settings.lineSpacing == 0.0 {
                            Spacer()
                            Image(systemName: "checkmark")
                        }
                    }
                }
                Button(action: { settings.lineSpacing = 3.0 }) {
                    HStack {
                        Text("Standard (3 pt)")
                        if settings.lineSpacing == 3.0 {
                            Spacer()
                            Image(systemName: "checkmark")
                        }
                    }
                }
                Button(action: { settings.lineSpacing = 6.0 }) {
                    HStack {
                        Text("Großzügig (6 pt)")
                        if settings.lineSpacing == 6.0 {
                            Spacer()
                            Image(systemName: "checkmark")
                        }
                    }
                }
                Button(action: { settings.lineSpacing = 10.0 }) {
                    HStack {
                        Text("Weit (10 pt)")
                        if settings.lineSpacing == 10.0 {
                            Spacer()
                            Image(systemName: "checkmark")
                        }
                    }
                }
                Button(action: { settings.lineSpacing = 14.0 }) {
                    HStack {
                        Text("Doppelt (14 pt)")
                        if settings.lineSpacing == 14.0 {
                            Spacer()
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }

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
