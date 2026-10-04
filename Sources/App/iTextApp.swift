import SwiftUI

@main
public struct iTextApp: App {
    public init() {}

    public var body: some Scene {
        DocumentGroup(newDocument: PlainTextDocument(text: "", isMarkdown: EditorSettings.shared.defaultFormat == "md")) { file in
            ContentView(document: file.$document, fileURL: file.fileURL)
        }
        .defaultSize(width: 375, height: 664)
        .commands {
            iTextCommands()
        }

        Settings {
            SettingsView(settings: EditorSettings.shared)
        }
    }
}
