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

    private var documentName: String {
        fileURL?.lastPathComponent ?? "Ohne Titel"
    }

    private var wordsCount: Int {
        document.text.split { $0.isWhitespace || $0.isNewline }.count
    }

    private var charactersCount: Int {
        document.text.count
    }

    private var linesCount: Int {
        let lines = document.text.split(omittingEmptySubsequences: false) { $0.isNewline }
        return max(1, lines.count)
    }

    private var readingTimeMinutes: Int {
        max(1, Int(ceil(Double(wordsCount) / 200.0)))
    }

    private func triggerPrint() {
        let title = fileURL?.deletingPathExtension().lastPathComponent
        PrintService.shared.printDocument(
            text: document.text,
            isMarkdown: isMarkdown,
            title: title,
            settings: settings,
            window: NSApp.keyWindow
        )
    }

    private func closeUntouchedUntitledDocuments() {
        for doc in NSDocumentController.shared.documents {
            if doc.fileURL == nil && !doc.isDocumentEdited {
                doc.close()
            }
        }
        for win in NSApp.windows {
            let title = win.title.trimmingCharacters(in: .whitespaces)
            if (title == "Ohne Titel" || title == "Untitled") && !win.isDocumentEdited {
                win.close()
            }
        }
    }

    public var body: some View {
        EditorView(text: $document.text, isMarkdown: isMarkdown, settings: settings)
            .frame(minWidth: 320, idealWidth: 375, minHeight: 480, idealHeight: 664)
            .onAppear {
                if fileURL != nil {
                    DispatchQueue.main.async {
                        closeUntouchedUntitledDocuments()
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        closeUntouchedUntitledDocuments()
                    }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .iTextPrintRequested)) { _ in
                if controlActiveState == .key {
                    triggerPrint()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .iTextShowStatisticsRequested)) { _ in
                if controlActiveState == .key {
                    settings.isShowingStatistics = true
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .iTextShowSettingsRequested)) { _ in
                if controlActiveState == .key {
                    settings.isShowingSettings = true
                }
            }
            .sheet(isPresented: $settings.isShowingStatistics) {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Dokument-Statistik")
                        .font(.headline)

                    Divider()

                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Dokument:")
                                .foregroundColor(.secondary)
                            Spacer()
                            Text(documentName)
                                .fontWeight(.medium)
                        }
                        HStack {
                            Text("Format:")
                                .foregroundColor(.secondary)
                            Spacer()
                            Text(isMarkdown ? "Markdown (.md)" : "Reiner Text (.txt)")
                        }
                        HStack {
                            Text("Wörter:")
                                .foregroundColor(.secondary)
                            Spacer()
                            Text("\(wordsCount)")
                        }
                        HStack {
                            Text("Zeichen:")
                                .foregroundColor(.secondary)
                            Spacer()
                            Text("\(charactersCount)")
                        }
                        HStack {
                            Text("Zeilen:")
                                .foregroundColor(.secondary)
                            Spacer()
                            Text("\(linesCount)")
                        }
                        HStack {
                            Text("Lesezeit:")
                                .foregroundColor(.secondary)
                            Spacer()
                            Text("ca. \(readingTimeMinutes) Min.")
                        }
                    }

                    Divider()

                    HStack {
                        Spacer()
                        Button("Schließen") {
                            settings.isShowingStatistics = false
                        }
                        .keyboardShortcut(.defaultAction)
                    }
                }
                .padding(20)
                .frame(width: 300)
            }
            .sheet(isPresented: $settings.isShowingSettings) {
                SettingsView(settings: settings)
            }
    }
}
