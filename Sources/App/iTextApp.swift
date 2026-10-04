import SwiftUI

@main
public struct iTextApp: App {
    public init() {}

    public var body: some Scene {
        DocumentGroup(newDocument: PlainTextDocument()) { file in
            ContentView(document: file.$document, fileURL: file.fileURL)
        }
        .defaultSize(width: 375, height: 664)
        .commands {
            iTextCommands()
        }
    }
}
