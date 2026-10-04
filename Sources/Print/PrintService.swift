import AppKit
import PDFKit

public final class PrintService {
    public static let shared = PrintService()

    private init() {}

    public func printDocument(
        text: String,
        isMarkdown: Bool,
        title: String? = nil,
        paperFormat: String? = nil,
        settings: EditorSettings = EditorSettings.shared,
        window: NSWindow? = nil
    ) {
        let tempDir = FileManager.default.temporaryDirectory
        let uniqueID = UUID().uuidString
        let typFileURL = tempDir.appendingPathComponent("iText_print_\(uniqueID).typ")
        let pdfFileURL = tempDir.appendingPathComponent("iText_print_\(uniqueID).pdf")

        let effectivePaper = (paperFormat ?? settings.paperFormat).lowercased()
        let typstContent = buildTypstDocument(
            text: text,
            isMarkdown: isMarkdown,
            title: title,
            paperFormat: effectivePaper,
            settings: settings
        )

        do {
            try typstContent.write(to: typFileURL, atomically: true, encoding: .utf8)
        } catch {
            showErrorAlert(message: "Konnte Druckdatei nicht schreiben: \(error.localizedDescription)", window: window)
            return
        }

        let candidates = [
            "/opt/homebrew/bin/typst",
            "/usr/local/bin/typst",
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".cargo/bin/typst").path
        ]
        var typstExecutable: String?
        for c in candidates {
            if FileManager.default.isExecutableFile(atPath: c) {
                typstExecutable = c
                break
            }
        }

        if typstExecutable == nil {
            let whichProc = Process()
            whichProc.executableURL = URL(fileURLWithPath: "/usr/bin/which")
            whichProc.arguments = ["typst"]
            let whichPipe = Pipe()
            whichProc.standardOutput = whichPipe
            try? whichProc.run()
            whichProc.waitUntilExit()
            if whichProc.terminationStatus == 0 {
                let outData = whichPipe.fileHandleForReading.readDataToEndOfFile()
                if let str = String(data: outData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines), !str.isEmpty {
                    typstExecutable = str
                }
            }
        }

        guard let executable = typstExecutable else {
            showErrorAlert(
                message: "Typst wurde nicht gefunden. Bitte installieren Sie Typst via Homebrew: brew install typst",
                window: window
            )
            return
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = ["compile", typFileURL.path, pdfFileURL.path]

        var env = ProcessInfo.processInfo.environment
        let currentPath = env["PATH"] ?? ""
        env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:" + currentPath
        process.environment = env

        let pipe = Pipe()
        process.standardError = pipe
        process.standardOutput = pipe

        do {
            try process.run()
            process.waitUntilExit()

            if process.terminationStatus != 0 {
                let errData = pipe.fileHandleForReading.readDataToEndOfFile()
                let errMsg = String(data: errData, encoding: .utf8) ?? "Unbekannter Kompilierungsfehler."
                showErrorAlert(message: "Typst-Druckaufbereitung fehlgeschlagen:\n\(errMsg)", window: window)
                try? FileManager.default.removeItem(at: typFileURL)
                return
            }

            guard FileManager.default.fileExists(atPath: pdfFileURL.path) else {
                showErrorAlert(message: "Das PDF-Dokument wurde nicht erzeugt.", window: window)
                try? FileManager.default.removeItem(at: typFileURL)
                return
            }

            guard let pdfDoc = PDFDocument(url: pdfFileURL) else {
                showErrorAlert(message: "Das erzeugte PDF konnte nicht geladen werden.", window: window)
                try? FileManager.default.removeItem(at: typFileURL)
                try? FileManager.default.removeItem(at: pdfFileURL)
                return
            }

            let printInfo = NSPrintInfo.shared
            printInfo.horizontalPagination = .fit
            printInfo.verticalPagination = .automatic
            printInfo.isHorizontallyCentered = true
            printInfo.isVerticallyCentered = true

            guard let printOp = pdfDoc.printOperation(for: printInfo, scalingMode: .pageScaleDownToFit, autoRotate: true) else {
                showErrorAlert(message: "Druckoperation konnte nicht initialisiert werden.", window: window)
                try? FileManager.default.removeItem(at: typFileURL)
                try? FileManager.default.removeItem(at: pdfFileURL)
                return
            }

            printOp.showsPrintPanel = true
            printOp.showsProgressPanel = true

            DispatchQueue.main.async {
                if let targetWindow = window ?? NSApp.keyWindow {
                    printOp.runModal(for: targetWindow, delegate: nil, didRun: nil, contextInfo: nil)
                } else {
                    printOp.run()
                }
            }

            // Temporäre Dateien nach Druckaufbereitung aufräumen
            DispatchQueue.global(qos: .background).asyncAfter(deadline: .now() + 8.0) {
                try? FileManager.default.removeItem(at: typFileURL)
                try? FileManager.default.removeItem(at: pdfFileURL)
            }

        } catch {
            showErrorAlert(message: "Fehler beim Ausführen von Typst: \(error.localizedDescription)", window: window)
            try? FileManager.default.removeItem(at: typFileURL)
        }
    }

    private func buildTypstDocument(
        text: String,
        isMarkdown: Bool,
        title: String?,
        paperFormat: String,
        settings: EditorSettings
    ) -> String {
        let family = settings.fontFamily
        let resolvedFont: String
        if family.isEmpty || family == "System" || family == ".AppleSystemUIFont" {
            resolvedFont = "(\"Helvetica Neue\", \"Arial\")"
        } else {
            resolvedFont = "(\"\(family)\", \"PT Serif\", \"Times New Roman\")"
        }

        let sizePt = String(format: "%.1fpt", settings.fontSize)

        // Der Zeilenabstand beim Drucken entspricht exakt der im Editor sichtbaren Zeilenhöhe
        let calculatedLeading = (settings.fontSize * 0.65) + settings.lineSpacing
        let leadingPt = String(format: "%.2fpt", max(4.0, calculatedLeading))

        let justifyStr = settings.isJustified ? "true" : "false"
        let hyphenateStr = settings.isHyphenationEnabled ? "true" : "false"

        // Gültige Papierformate und angepasste Ränder
        let validPaper: String
        let marginStr: String
        switch paperFormat {
        case "a5":
            validPaper = "a5"
            marginStr = "(top: 1.8cm, bottom: 1.8cm, left: 2.0cm, right: 2.0cm)"
        case "a3":
            validPaper = "a3"
            marginStr = "(top: 3.5cm, bottom: 3.5cm, left: 4.0cm, right: 4.0cm)"
        case "us-letter", "letter":
            validPaper = "us-letter"
            marginStr = "(top: 2.8cm, bottom: 2.8cm, left: 3.0cm, right: 3.0cm)"
        case "us-legal", "legal":
            validPaper = "us-legal"
            marginStr = "(top: 2.8cm, bottom: 2.8cm, left: 3.0cm, right: 3.0cm)"
        default:
            validPaper = "a4"
            marginStr = "(top: 2.8cm, bottom: 2.8cm, left: 3.0cm, right: 3.0cm)"
        }

        var headerCode = ""
        if let docTitle = title, !docTitle.isEmpty {
            let escapedTitle = escapeTypstContent(docTitle)
            headerCode = "header: align(right)[#text(8pt, fill: luma(120))[\(escapedTitle)]],"
        }

        var doc = """
        #set page(
          paper: "\(validPaper)",
          margin: \(marginStr),
          \(headerCode)
          numbering: "1"
        )
        #set text(
          font: \(resolvedFont),
          size: \(sizePt),
          lang: "de",
          hyphenate: \(hyphenateStr)
        )
        #set par(
          justify: \(justifyStr),
          leading: \(leadingPt)
        )

        """

        if isMarkdown {
            doc += convertMarkdownToTypst(text)
        } else {
            doc += convertPlainTextToTypst(text)
        }

        return doc
    }

    private func convertPlainTextToTypst(_ plainText: String) -> String {
        let lines = plainText.components(separatedBy: "\n")
        var resultLines: [String] = []

        for line in lines {
            let processedLine = processLineIndentsAndEscaping(line, isMarkdown: false)
            resultLines.append(processedLine)
        }

        return resultLines.joined(separator: "\n")
    }

    private func convertMarkdownToTypst(_ markdown: String) -> String {
        let lines = markdown.components(separatedBy: "\n")
        var inCodeBlock = false
        var resultLines: [String] = []

        for line in lines {
            if line.hasPrefix("```") {
                inCodeBlock.toggle()
                resultLines.append(line)
                continue
            }
            if inCodeBlock {
                resultLines.append(line)
                continue
            }

            var processed = line

            // Überschriften: # -> =
            if processed.hasPrefix("# ") {
                processed = "= " + escapeTypstContent(String(processed.dropFirst(2)))
            } else if processed.hasPrefix("## ") {
                processed = "== " + escapeTypstContent(String(processed.dropFirst(3)))
            } else if processed.hasPrefix("### ") {
                processed = "=== " + escapeTypstContent(String(processed.dropFirst(4)))
            } else if processed.hasPrefix("#### ") {
                processed = "==== " + escapeTypstContent(String(processed.dropFirst(5)))
            } else if processed.hasPrefix("##### ") {
                processed = "===== " + escapeTypstContent(String(processed.dropFirst(6)))
            } else if processed.hasPrefix("###### ") {
                processed = "====== " + escapeTypstContent(String(processed.dropFirst(7)))
            } else if processed.hasPrefix("> ") {
                // Zitat
                let quoteContent = escapeTypstContent(String(processed.dropFirst(2)))
                processed = "#quote[\(quoteContent)]"
            } else {
                // Fließtext mit Einzügen und Inline-Markdown
                processed = processLineIndentsAndEscaping(processed, isMarkdown: true)
            }

            resultLines.append(processed)
        }

        return resultLines.joined(separator: "\n")
    }

    private func processLineIndentsAndEscaping(_ line: String, isMarkdown: Bool) -> String {
        guard !line.isEmpty else { return "" }

        var remainder = line
        var tabCount = 0

        // Führende Tabulatoren zählen und entfernen
        while remainder.hasPrefix("\t") {
            tabCount += 1
            remainder.removeFirst()
        }

        // Führende 4-Leerzeichen-Blöcke zählen
        var spaceIndentCount = 0
        if tabCount == 0 {
            while remainder.hasPrefix("    ") {
                spaceIndentCount += 1
                remainder.removeFirst(4)
            }
        }

        let totalLevels = tabCount + spaceIndentCount
        var prefix = ""
        if totalLevels > 0 {
            prefix = "#h(\(Double(totalLevels) * 2.2)em)"
        }

        var content: String
        if isMarkdown {
            content = convertInlineMarkdown(remainder)
        } else {
            content = escapeTypstContent(remainder)
        }

        // Tabulatoren innerhalb des Textkörpers ebenfalls als horizontalen Abstand auflösen
        content = content.replacingOccurrences(of: "\t", with: "#h(2.2em)")

        return prefix + content
    }

    private func convertInlineMarkdown(_ text: String) -> String {
        var res = text
        // Strikethrough: ~~text~~ -> #strike[text]
        if let regex = try? NSRegularExpression(pattern: "~~(.+?)~~", options: []) {
            res = regex.stringByReplacingMatches(in: res, options: [], range: NSRange(location: 0, length: (res as NSString).length), withTemplate: "#strike[$1]")
        }
        // Bold: **text** -> *text*
        if let regex = try? NSRegularExpression(pattern: "\\*\\*(.+?)\\*\\*", options: []) {
            res = regex.stringByReplacingMatches(in: res, options: [], range: NSRange(location: 0, length: (res as NSString).length), withTemplate: "*$1*")
        }
        // Italic: *text* -> _text_ (nur wenn nicht Teil eines Worts)
        if let regex = try? NSRegularExpression(pattern: "(?<!\\*)\\*([^*]+?)\\*(?!\\*)", options: []) {
            res = regex.stringByReplacingMatches(in: res, options: [], range: NSRange(location: 0, length: (res as NSString).length), withTemplate: "_$1_")
        }
        return res
    }

    private func escapeTypstContent(_ str: String) -> String {
        return str
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "#", with: "\\#")
            .replacingOccurrences(of: "$", with: "\\$")
            .replacingOccurrences(of: "*", with: "\\*")
            .replacingOccurrences(of: "_", with: "\\_")
            .replacingOccurrences(of: "`", with: "\\`")
            .replacingOccurrences(of: "@", with: "\\@")
            .replacingOccurrences(of: "<", with: "\\<")
            .replacingOccurrences(of: ">", with: "\\>")
    }

    private func showErrorAlert(message: String, window: NSWindow?) {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "Drucken fehlgeschlagen"
            alert.informativeText = message
            alert.alertStyle = .warning
            alert.addButton(withTitle: "OK")
            if let targetWindow = window ?? NSApp.keyWindow {
                alert.beginSheetModal(for: targetWindow, completionHandler: nil)
            } else {
                alert.runModal()
            }
        }
    }
}
