import SwiftUI

public struct iTextCommands: Commands {
    @ObservedObject private var settings = EditorSettings.shared

    public init() {}

    public var body: some Commands {
        CommandMenu("Formatierung") {
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
            Toggle("Obsidian-Markdown-Vorschau", isOn: $settings.isMarkdownHighlightingEnabled)

            #if os(macOS)
            Divider()

            Button("Schriften einblenden…") {
                MacFontManager.shared.showFontPanel()
            }
            .keyboardShortcut("t", modifiers: .command)
            #endif
        }
    }
}
