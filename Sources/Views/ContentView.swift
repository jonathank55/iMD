import SwiftUI

public struct ContentView: View {
    @Binding public var document: PlainTextDocument
    @ObservedObject private var settings = EditorSettings.shared

    public init(document: Binding<PlainTextDocument>) {
        self._document = document
    }

    private var statisticsText: String {
        let text = document.text
        let chars = text.count
        let words = text.split { $0.isWhitespace || $0.isNewline }.count
        return "\(words) Wörter · \(chars) Zeichen"
    }

    public var body: some View {
        EditorView(text: $document.text, settings: settings)
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
