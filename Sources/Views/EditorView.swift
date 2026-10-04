import SwiftUI

public struct EditorView: View {
    @Binding public var text: String
    @ObservedObject public var settings: EditorSettings

    public init(text: Binding<String>, settings: EditorSettings) {
        self._text = text
        self.settings = settings
    }

    public var body: some View {
        #if os(iOS)
        IOSTextEditor(text: $text, settings: settings)
            .edgesIgnoringSafeArea(.bottom)
        #elseif os(macOS)
        MacTextEditor(text: $text, settings: settings)
        #endif
    }
}
