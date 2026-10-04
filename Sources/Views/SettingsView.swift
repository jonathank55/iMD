import SwiftUI

public struct SettingsView: View {
    @ObservedObject public var settings: EditorSettings
    @Environment(\.presentationMode) private var presentationMode

    public init(settings: EditorSettings) {
        self.settings = settings
    }

    public var body: some View {
        #if os(iOS)
        NavigationView {
            formContent
                .navigationTitle("Typografie & Layout")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Fertig") {
                            presentationMode.wrappedValue.dismiss()
                        }
                    }
                }
                .sheet(isPresented: $settings.isShowingFontPicker) {
                    IOSFontPicker(selectedFontFamily: $settings.fontFamily)
                }
        }
        #elseif os(macOS)
        VStack(alignment: .leading, spacing: 16) {
            Text("Typografie & Layout")
                .font(.headline)

            Divider()

            formContent

            HStack {
                Spacer()
                Button("Schließen") {
                    presentationMode.wrappedValue.dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(minWidth: 320, minHeight: 280)
        #endif
    }

    private var formContent: some View {
        Form {
            Section(header: Text("Schriftart")) {
                #if os(iOS)
                HStack {
                    Text("Schriftfamilie")
                    Spacer()
                    Button(action: { settings.isShowingFontPicker = true }) {
                        HStack {
                            Text(settings.fontFamily.isEmpty ? "System" : settings.fontFamily)
                                .foregroundColor(.secondary)
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                #elseif os(macOS)
                Picker("Schriftfamilie", selection: $settings.fontFamily) {
                    Text("PT Serif").tag("PT Serif")
                    Text("System").tag("System")
                    Text("EB Garamond").tag("EB Garamond")
                    Text("Times New Roman").tag("Times New Roman")
                    Text("Helvetica Neue").tag("Helvetica Neue")
                    Text("Menlo").tag("Menlo")
                    Text("Courier New").tag("Courier New")
                }
                #endif

                HStack {
                    Text("Schriftgröße (\(Int(settings.fontSize)) pt)")
                    Spacer()
                    Button(action: { settings.zoomOut() }) {
                        Image(systemName: "minus")
                    }
                    .buttonStyle(.borderless)

                    Slider(value: $settings.fontSize, in: 10...40, step: 1)
                        .frame(width: 120)

                    Button(action: { settings.zoomIn() }) {
                        Image(systemName: "plus")
                    }
                    .buttonStyle(.borderless)
                }
            }

            Section(header: Text("Satz & Typografie")) {
                Toggle("Blocksatz (Typst-Stil)", isOn: $settings.isJustified)
                Toggle("Automatische Silbentrennung", isOn: $settings.isHyphenationEnabled)
                Toggle("Obsidian-Markdown-Vorschau", isOn: $settings.isMarkdownHighlightingEnabled)
            }
        }
    }
}
