import SwiftUI

public struct SettingsView: View {
    @ObservedObject public var settings: EditorSettings
    @Environment(\.presentationMode) private var presentationMode

    public init(settings: EditorSettings) {
        self.settings = settings
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Typografie & Layout")
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
                        Text("EB Garamond").tag("EB Garamond")
                        Text("Times New Roman").tag("Times New Roman")
                        Text("Helvetica Neue").tag("Helvetica Neue")
                        Text("Menlo").tag("Menlo")
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
            }

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                Text("Satz & Modus")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                Toggle("Blocksatz (Typst)", isOn: $settings.isJustified)
                Toggle("Automatische Silbentrennung", isOn: $settings.isHyphenationEnabled)
                Toggle("Obsidian Live-Vorschau", isOn: $settings.isMarkdownHighlightingEnabled)
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
        .padding(18)
        .frame(width: 320)
    }
}
