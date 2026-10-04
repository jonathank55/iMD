import SwiftUI

public struct ContentView: View {
    @Binding public var document: PlainTextDocument
    public var fileURL: URL?
    @ObservedObject private var settings = EditorSettings.shared

    public init(document: Binding<PlainTextDocument>, fileURL: URL? = nil) {
        self._document = document
        self.fileURL = fileURL
    }

    private var isMarkdown: Bool {
        if let ext = fileURL?.pathExtension.lowercased(), !ext.isEmpty {
            return ext == "md" || ext == "markdown"
        }
        return document.isMarkdown
    }

    private var statisticsText: String {
        let text = document.text
        let chars = text.count
        let words = text.split { $0.isWhitespace || $0.isNewline }.count
        return "\(words) Wörter · \(chars) Zeichen"
    }

    public var body: some View {
        EditorView(text: $document.text, isMarkdown: isMarkdown, settings: settings)
            .frame(minWidth: 320, idealWidth: 375, minHeight: 480, idealHeight: 664)
            .toolbar {
                ToolbarItemGroup(placement: .automatic) {
                    #if os(macOS)
                    Text(statisticsText)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    #endif

                    Button(action: { settings.isShowingSettings.toggle() }) {
                        Label("Typografie", systemImage: "textformat.size")
                    }
                    .popover(isPresented: $settings.isShowingSettings) {
                        SettingsView(settings: settings)
                    }
                }
            }
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
    }
}
