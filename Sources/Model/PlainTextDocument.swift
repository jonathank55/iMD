import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    public static var markdownDocument: UTType {
        UTType(importedAs: "net.daringfireball.markdown", conformingTo: .plainText)
    }
}

public struct PlainTextDocument: FileDocument {
    public static var readableContentTypes: [UTType] {
        [.plainText, .markdownDocument, UTType(filenameExtension: "md") ?? .plainText]
    }
    public static var writableContentTypes: [UTType] {
        [.plainText, .markdownDocument, UTType(filenameExtension: "md") ?? .plainText]
    }

    public var text: String
    public var isMarkdown: Bool = false

    public init(text: String = "", isMarkdown: Bool = false) {
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
            self.isMarkdown = filename.hasSuffix(".md") || filename.hasSuffix(".markdown")
        }
    }

    public func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let data = Data(text.utf8)
        return FileWrapper(regularFileWithContents: data)
    }
}
