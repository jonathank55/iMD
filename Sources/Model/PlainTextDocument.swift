import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    public static var markdownDocument: UTType {
        UTType("net.daringfireball.markdown") ?? UTType(importedAs: "net.daringfireball.markdown", conformingTo: .plainText)
    }
}

public struct PlainTextDocument: FileDocument {
    // Markdown als primäres Standardformat vor Plain Text
    public static var readableContentTypes: [UTType] {
        [.markdownDocument, .plainText]
    }
    public static var writableContentTypes: [UTType] {
        [.markdownDocument, .plainText]
    }

    public var text: String
    public var isMarkdown: Bool

    public init(text: String = "", isMarkdown: Bool = true) {
        self.text = text
        self.isMarkdown = isMarkdown
    }

    public init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        if let utf8String = String(data: data, encoding: .utf8) {
            self.text = utf8String
        } else if let latin1String = String(data: data, encoding: .isoLatin1) {
            self.text = latin1String
        } else {
            self.text = String(decoding: data, as: UTF8.self)
        }

        let contentType = configuration.contentType
        self.isMarkdown = contentType.conforms(to: .markdownDocument) || (contentType.preferredFilenameExtension?.lowercased() == "md")
        if !self.isMarkdown, let filename = configuration.file.filename {
            let lower = filename.lowercased()
            self.isMarkdown = lower.hasSuffix(".md") || lower.hasSuffix(".markdown")
        }
    }

    public func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let data = Data(text.utf8)
        return FileWrapper(regularFileWithContents: data)
    }
}
