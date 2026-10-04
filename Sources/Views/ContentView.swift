import SwiftUI

public struct PrintDialogSheet: View {
    @ObservedObject public var settings: EditorSettings
    public let documentName: String
    public let onPrint: () -> Void
    public let onCancel: () -> Void

    public init(
        settings: EditorSettings,
        documentName: String,
        onPrint: @escaping () -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.settings = settings
        self.documentName = documentName
        self.onPrint = onPrint
        self.onCancel = onCancel
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Dokument drucken")
                .font(.headline)

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                Text("Dokument: \(documentName)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                HStack {
                    Text("Papierformat:")
                    Spacer()
                    Picker("", selection: $settings.paperFormat) {
                        Text("A4 (210 × 297 mm)").tag("a4")
                        Text("US Letter (8.5 × 11 in)").tag("us-letter")
                        Text("A5 (148 × 210 mm)").tag("a5")
                        Text("A3 (297 × 420 mm)").tag("a3")
                        Text("US Legal (8.5 × 14 in)").tag("us-legal")
                    }
                    .labelsHidden()
                    .frame(width: 190)
                }

                HStack {
                    Text("Zeilenabstand:")
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("\(Int(settings.lineSpacing)) pt (übernommen)")
                        .foregroundColor(.secondary)
                }

                HStack {
                    Text("Schriftgröße:")
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("\(Int(settings.fontSize)) pt (übernommen)")
                        .foregroundColor(.secondary)
                }
            }

            Divider()

            HStack {
                Button("Abbrechen") {
                    onCancel()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Drucken…") {
                    onPrint()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 340)
    }
}

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

    private func executePrint(with paperFormat: String) {
        let title = fileURL?.deletingPathExtension().lastPathComponent
        settings.paperFormat = paperFormat
        PrintService.shared.printDocument(
            text: document.text,
            isMarkdown: isMarkdown,
            title: title,
            paperFormat: paperFormat,
            settings: settings
        )
    }

    public var body: some View {
        EditorView(text: $document.text, isMarkdown: isMarkdown, settings: settings)
            .frame(minWidth: 320, idealWidth: 375, minHeight: 480, idealHeight: 664)
            .onReceive(NotificationCenter.default.publisher(for: .iTextPrintRequested)) { _ in
                if controlActiveState == .key {
                    settings.isShowingPrintDialog = true
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
            .sheet(isPresented: $settings.isShowingPrintDialog) {
                PrintDialogSheet(
                    settings: settings,
                    documentName: documentName,
                    onPrint: {
                        settings.isShowingPrintDialog = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                            executePrint(with: settings.paperFormat)
                        }
                    },
                    onCancel: {
                        settings.isShowingPrintDialog = false
                    }
                )
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
