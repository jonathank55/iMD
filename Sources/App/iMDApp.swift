import SwiftUI

@main
public struct iMDApp: App {
    public init() {
        DispatchQueue.global(qos: .userInteractive).async {
            let settings = EditorSettings.shared
            _ = MarkdownHighlighter.resolveFont(family: settings.fontFamily, size: settings.fontSize)
            _ = MarkdownHighlighter.resolveFont(family: settings.fontFamily, size: settings.fontSize + 6.0, bold: true)
        }
    }

    public var body: some Scene {
        DocumentGroup(newDocument: PlainTextDocument(text: "", isMarkdown: EditorSettings.shared.defaultFormat == "md")) { file in
            ContentView(document: file.$document, fileURL: file.fileURL)
        }
        .defaultSize(width: 375, height: 664)
        .commands {
            iMDCommands()
        }

        Settings {
            SettingsView(settings: EditorSettings.shared)
        }
    }
}
