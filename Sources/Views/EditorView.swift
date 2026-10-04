import SwiftUI

public struct EditorView: View {
    @Binding public var text: String
    public var isMarkdown: Bool
    @ObservedObject public var settings: EditorSettings

    public init(text: Binding<String>, isMarkdown: Bool, settings: EditorSettings) {
        self._text = text
        self.isMarkdown = isMarkdown
        self.settings = settings
    }

    public var body: some View {
        #if os(iOS)
        IOSTextEditor(text: $text, isMarkdown: isMarkdown, settings: settings)
            .edgesIgnoringSafeArea(.bottom)
        #elseif os(macOS)
        MacTextEditor(text: $text, isMarkdown: isMarkdown, settings: settings)
        #endif
    }
}
