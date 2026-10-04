import SwiftUI

public struct SettingsView: View {
    @ObservedObject public var settings: EditorSettings
    @Environment(\.presentationMode) private var presentationMode

    public init(settings: EditorSettings) {
        self.settings = settings
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Typografie & Einstellungen")
                .font(.headline)

            Divider()

            VStack(alignment: .leading, spacing: 12) {
                Text("Schriftart")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                HStack {
                    Text("Familie:")
                    Spacer()
                    Picker("", selection: $settings.fontFamily) {
                        Text("PT Serif").tag("PT Serif")
                        Text("System").tag("System")
                        Text("New York").tag("New York")
                        Text("Helvetica Neue").tag("Helvetica Neue")
                        Text("Georgia").tag("Georgia")
                        Text("Palatino").tag("Palatino")
                        Text("Times New Roman").tag("Times New Roman")
                        Text("Menlo").tag("Menlo")
                        Text("SF Mono").tag("SF Mono")
                        Text("Courier New").tag("Courier New")
                    }
                    .labelsHidden()
                    .frame(width: 170)
                }

                HStack {
                    Text("Größe: \(Int(settings.fontSize)) pt")
                    Spacer()
                    Button(action: { settings.zoomOut() }) {
                        Image(systemName: "minus")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Slider(value: $settings.fontSize, in: 10...36, step: 1)
                        .frame(width: 90)

                    Button(action: { settings.zoomIn() }) {
                        Image(systemName: "plus")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                HStack {
                    Text("Zeilenabstand: \(Int(settings.lineSpacing)) pt")
                    Spacer()
                    Button(action: { settings.lineSpacing = max(0.0, settings.lineSpacing - 1.0) }) {
                        Image(systemName: "minus")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Slider(value: $settings.lineSpacing, in: 0...16, step: 1)
                        .frame(width: 90)

                    Button(action: { settings.lineSpacing = min(24.0, settings.lineSpacing + 1.0) }) {
                        Image(systemName: "plus")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                Text("Satz & Modus")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                Toggle("Blocksatz", isOn: $settings.isJustified)
                Toggle("Automatische Silbentrennung", isOn: $settings.isHyphenationEnabled)
                Toggle("Obsidian Live-Vorschau", isOn: $settings.isMarkdownHighlightingEnabled)
            }

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                Text("Standardformate")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                Picker("Neues Dokument:", selection: $settings.defaultFormat) {
                    Text("Markdown (.md)").tag("md")
                    Text("Reiner Text (.txt)").tag("txt")
                }
                .pickerStyle(.segmented)

                HStack {
                    Text("Papierformat (Drucken):")
                    Spacer()
                    Picker("", selection: $settings.paperFormat) {
                        Text("A4").tag("a4")
                        Text("US Letter").tag("us-letter")
                        Text("A5").tag("a5")
                        Text("A3").tag("a3")
                        Text("US Legal").tag("us-legal")
                    }
                    .labelsHidden()
                    .frame(width: 130)
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("Konfiguration")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                Text("Gespeichert in: ~/.config/iText/config.json")
                    .font(.caption)
                    .foregroundColor(.secondary)

                HStack {
                    Button("Datei öffnen") {
                        settings.openConfigFileInDefaultEditor()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Button("Im Finder anzeigen") {
                        settings.openConfigDirectoryInFinder()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }

            Divider()

            HStack {
                Spacer()
                Button("Fertig") {
                    presentationMode.wrappedValue.dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 350)
    }
}
