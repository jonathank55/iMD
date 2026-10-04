import SwiftUI

public struct ContentView: View {
    @Binding public var document: PlainTextDocument
    public var fileURL: URL?
    @ObservedObject private var settings = EditorSettings.shared
    @Environment(\.controlActiveState) private var controlActiveState

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

    private func triggerPrint() {
        let title = fileURL?.deletingPathExtension().lastPathComponent
        PrintService.shared.printDocument(
            text: document.text,
            isMarkdown: isMarkdown,
            title: title
        )
    }

    public var body: some View {
        EditorView(text: $document.text, isMarkdown: isMarkdown, settings: settings)
            .frame(minWidth: 320, idealWidth: 375, minHeight: 480, idealHeight: 664)
            .toolbar {
                ToolbarItemGroup(placement: .automatic) {
                    Text(statisticsText)
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Button(action: { triggerPrint() }) {
                        Label("Drucken", systemImage: "printer")
                    }
                    .help("Dokument via txt2pdf drucken (⌘P)")

                    Button(action: { settings.isShowingSettings.toggle() }) {
                        Label("Typografie", systemImage: "textformat.size")
                    }
                    .help("Typografie & Layout anpassen")
                    .popover(isPresented: $settings.isShowingSettings) {
                        SettingsView(settings: settings)
                    }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .iTextPrintRequested)) { _ in
                if controlActiveState == .key {
                    triggerPrint()
                }
            }
    }
}
