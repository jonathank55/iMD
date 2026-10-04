import AppKit
import PDFKit

public final class PrintService {
    public static let shared = PrintService()

    private init() {}

    public func printDocument(
        text: String,
        isMarkdown: Bool,
        title: String? = nil,
        settings: EditorSettings = EditorSettings.shared,
        window: NSWindow? = nil
    ) {
        let printInfo = NSPrintInfo.shared
        printInfo.horizontalPagination = .fit
        printInfo.verticalPagination = .automatic
        printInfo.isHorizontallyCentered = true
        printInfo.isVerticallyCentered = true

        let detectedPaper = resolvePaperFormat(from: printInfo, fallback: settings.paperFormat)

        let tempDir = FileManager.default.temporaryDirectory
        let uniqueID = UUID().uuidString
        let typFileURL = tempDir.appendingPathComponent("iText_print_\(uniqueID).typ")
        let pdfFileURL = tempDir.appendingPathComponent("iText_print_\(uniqueID).pdf")

        let typstContent = buildTypstDocument(
            text: text,
            isMarkdown: isMarkdown,
            title: title,
            paperFormat: detectedPaper,
            printInfo: printInfo,
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

            guard let printOp = pdfDoc.printOperation(for: printInfo, scalingMode: .pageScaleDownToFit, autoRotate: true) else {
                showErrorAlert(message: "Druckoperation konnte nicht initialisiert werden.", window: window)
                try? FileManager.default.removeItem(at: typFileURL)
                try? FileManager.default.removeItem(at: pdfFileURL)
                return
            }

            // Vollständig natives macOS-Druckmenü anzeigen
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

    private func resolvePaperFormat(from printInfo: NSPrintInfo, fallback: String) -> String {
        if let name = printInfo.paperName?.lowercased() {
            if name.contains("letter") { return "us-letter" }
            if name.contains("legal") { return "us-legal" }
            if name.contains("a5") { return "a5" }
            if name.contains("a3") { return "a3" }
            if name.contains("a4") { return "a4" }
        }

        let size = printInfo.paperSize
        let w = min(size.width, size.height)
        let h = max(size.width, size.height)

        if abs(w - 595) < 30 && abs(h - 842) < 30 { return "a4" }
        if abs(w - 612) < 30 && abs(h - 792) < 30 { return "us-letter" }
        if abs(w - 420) < 30 && abs(h - 595) < 30 { return "a5" }
        if abs(w - 842) < 30 && abs(h - 1191) < 30 { return "a3" }

        return fallback.isEmpty ? "a4" : fallback
    }

    private func buildTypstDocument(
        text: String,
        isMarkdown: Bool,
        title: String?,
        paperFormat: String,
        printInfo: NSPrintInfo,
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

        let isLandscape = (printInfo.orientation == .landscape)
        let orientationAttr = isLandscape ? ", flipped: true" : ""

        var headerCode = ""
        if let docTitle = title, !docTitle.isEmpty {
            let escapedTitle = escapeTypstContent(docTitle)
            headerCode = "header: align(right)[#text(8pt, fill: luma(120))[\(escapedTitle)]],"
        }

        var doc = """
        #set page(
          paper: "\(validPaper)"\(orientationAttr),
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
        let rawLines = markdown.components(separatedBy: "\n")
        var resultLines: [String] = []
        var inCodeBlock = false
        var tableBuffer: [String] = []

        let flushTable = {
            guard !tableBuffer.isEmpty else { return }
            let typstTable = self.convertMarkdownTableToTypst(tableBuffer)
            resultLines.append(typstTable)
            tableBuffer.removeAll()
        }

        let isTableLine = { (line: String) -> Bool in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            return trimmed.hasPrefix("|") && trimmed.hasSuffix("|") && trimmed.contains("|")
        }

        for line in rawLines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Fenced Code-Blöcke
            if trimmed.hasPrefix("```") {
                flushTable()
                inCodeBlock.toggle()
                resultLines.append(line)
                continue
            }
            if inCodeBlock {
                resultLines.append(line)
                continue
            }

            // Tabellen-Pufferung
            if isTableLine(line) {
                tableBuffer.append(line)
                continue
            } else {
                flushTable()
            }

            var processed = line

            // 1. Überschriften: # -> =
            if processed.hasPrefix("# ") {
                let headingText = convertInlineMarkdown(String(processed.dropFirst(2)))
                processed = "= " + headingText
            } else if processed.hasPrefix("## ") {
                let headingText = convertInlineMarkdown(String(processed.dropFirst(3)))
                processed = "== " + headingText
            } else if processed.hasPrefix("### ") {
                let headingText = convertInlineMarkdown(String(processed.dropFirst(4)))
                processed = "=== " + headingText
            } else if processed.hasPrefix("#### ") {
                let headingText = convertInlineMarkdown(String(processed.dropFirst(5)))
                processed = "==== " + headingText
            } else if processed.hasPrefix("##### ") {
                let headingText = convertInlineMarkdown(String(processed.dropFirst(6)))
                processed = "===== " + headingText
            } else if processed.hasPrefix("###### ") {
                let headingText = convertInlineMarkdown(String(processed.dropFirst(7)))
                processed = "====== " + headingText
            } else if isHorizontalRule(trimmed) {
                // 2. Horizontale Trennlinie
                processed = "#line(length: 100%, stroke: 0.5pt + luma(180))"
            } else if trimmed.hasPrefix(">") {
                // 3. Zitate
                var quoteBody = trimmed.dropFirst(1)
                if quoteBody.hasPrefix(" ") { quoteBody = quoteBody.dropFirst(1) }
                let formattedQuote = convertInlineMarkdown(String(quoteBody))
                processed = "#quote[\(formattedQuote)]"
            } else if let taskChecked = matchTaskChecked(line) {
                // 4. Aufgabenliste (erledigt)
                let body = convertInlineMarkdown(taskChecked.content)
                processed = "\(taskChecked.indent)- #box(stroke: 0.8pt + luma(100), width: 0.85em, height: 0.85em, fill: luma(60), baseline: 10%)[] #strike[\(body)]"
            } else if let taskUnchecked = matchTaskUnchecked(line) {
                // 5. Aufgabenliste (offen)
                let body = convertInlineMarkdown(taskUnchecked.content)
                processed = "\(taskUnchecked.indent)- #box(stroke: 0.8pt + luma(100), width: 0.85em, height: 0.85em, baseline: 10%)[] \(body)"
            } else if let bullet = matchBulletList(line) {
                // 6. Ungeordnete Aufzählungsliste
                let body = convertInlineMarkdown(bullet.content)
                processed = "\(bullet.indent)- \(body)"
            } else if let numbered = matchNumberedList(line) {
                // 7. Nummerierte Liste (Typst + nummeriert automatisch fortlaufend)
                let body = convertInlineMarkdown(numbered.content)
                processed = "\(numbered.indent)+ \(body)"
            } else {
                // 8. Normaler Fließtext mit Einzügen und Inline-Markdown
                processed = processLineIndentsAndEscaping(processed, isMarkdown: true)
            }

            resultLines.append(processed)
        }

        flushTable()
        return resultLines.joined(separator: "\n")
    }

    private func isHorizontalRule(_ trimmed: String) -> Bool {
        guard trimmed.count >= 3 else { return false }
        let set = Set(trimmed)
        return (set == ["-"] || set == ["*"] || set == ["_"])
    }

    private func matchTaskChecked(_ line: String) -> (indent: String, content: String)? {
        let pattern = "^([ \t]*)[-*+][ \t]+\\[[xX]\\][ \t]+(.*)$"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return nil }
        let nsLine = line as NSString
        guard let match = regex.firstMatch(in: line, options: [], range: NSRange(location: 0, length: nsLine.length)), match.numberOfRanges >= 3 else { return nil }
        let indent = nsLine.substring(with: match.range(at: 1))
        let content = nsLine.substring(with: match.range(at: 2))
        return (indent, content)
    }

    private func matchTaskUnchecked(_ line: String) -> (indent: String, content: String)? {
        let pattern = "^([ \t]*)[-*+][ \t]+\\[ \\][ \t]+(.*)$"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return nil }
        let nsLine = line as NSString
        guard let match = regex.firstMatch(in: line, options: [], range: NSRange(location: 0, length: nsLine.length)), match.numberOfRanges >= 3 else { return nil }
        let indent = nsLine.substring(with: match.range(at: 1))
        let content = nsLine.substring(with: match.range(at: 2))
        return (indent, content)
    }

    private func matchBulletList(_ line: String) -> (indent: String, content: String)? {
        let pattern = "^([ \t]*)[-*+][ \t]+(.*)$"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return nil }
        let nsLine = line as NSString
        guard let match = regex.firstMatch(in: line, options: [], range: NSRange(location: 0, length: nsLine.length)), match.numberOfRanges >= 3 else { return nil }
        let indent = nsLine.substring(with: match.range(at: 1))
        let content = nsLine.substring(with: match.range(at: 2))
        return (indent, content)
    }

    private func matchNumberedList(_ line: String) -> (indent: String, content: String)? {
        let pattern = "^([ \t]*)[0-9]+[.)][ \t]+(.*)$"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return nil }
        let nsLine = line as NSString
        guard let match = regex.firstMatch(in: line, options: [], range: NSRange(location: 0, length: nsLine.length)), match.numberOfRanges >= 3 else { return nil }
        let indent = nsLine.substring(with: match.range(at: 1))
        let content = nsLine.substring(with: match.range(at: 2))
        return (indent, content)
    }

    private func convertMarkdownTableToTypst(_ tableLines: [String]) -> String {
        var parsedRows: [[String]] = []
        for line in tableLines {
            let clean = line.replacingOccurrences(of: "|", with: "").replacingOccurrences(of: "-", with: "").replacingOccurrences(of: ":", with: "").trimmingCharacters(in: .whitespaces)
            if clean.isEmpty && line.contains("-") {
                // Trennzeile überspringen
                continue
            }
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            var parts = trimmed.components(separatedBy: "|")
            if parts.first?.trimmingCharacters(in: .whitespaces).isEmpty == true { parts.removeFirst() }
            if parts.last?.trimmingCharacters(in: .whitespaces).isEmpty == true { parts.removeLast() }
            let cells = parts.map { convertInlineMarkdown($0.trimmingCharacters(in: .whitespaces)) }
            if !cells.isEmpty {
                parsedRows.append(cells)
            }
        }

        guard !parsedRows.isEmpty else { return "" }
        let colCount = parsedRows.map { $0.count }.max() ?? 1

        var typstCode = "\n#table(\n  columns: \(colCount),\n  stroke: 0.5pt + luma(180),\n"
        for (idx, row) in parsedRows.enumerated() {
            var paddedRow = row
            while paddedRow.count < colCount {
                paddedRow.append("")
            }
            let isHeader = (idx == 0)
            for cell in paddedRow {
                if isHeader {
                    typstCode += "  [*\(cell)*],\n"
                } else {
                    typstCode += "  [\(cell)],\n"
                }
            }
        }
        typstCode += ")\n"
        return typstCode
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

        // Links: [Text](URL) -> #link("URL")[Text]
        if let regex = try? NSRegularExpression(pattern: "\\[([^\\]]+)\\]\\(([^\\)]+)\\)", options: []) {
            res = regex.stringByReplacingMatches(in: res, options: [], range: NSRange(location: 0, length: (res as NSString).length), withTemplate: "#link(\"$2\")[$1]")
        }

        // Highlights: ==Text== -> #highlight[Text]
        if let regex = try? NSRegularExpression(pattern: "==([^=]+?)==", options: []) {
            res = regex.stringByReplacingMatches(in: res, options: [], range: NSRange(location: 0, length: (res as NSString).length), withTemplate: "#highlight[$1]")
        }

        // Durchgestrichen: ~~text~~ -> #strike[text]
        if let regex = try? NSRegularExpression(pattern: "~~(.+?)~~", options: []) {
            res = regex.stringByReplacingMatches(in: res, options: [], range: NSRange(location: 0, length: (res as NSString).length), withTemplate: "#strike[$1]")
        }

        // Fett-Kursiv: ***text*** -> *_\(text)_*
        if let regex = try? NSRegularExpression(pattern: "\\*\\*\\*(.+?)\\*\\*\\*", options: []) {
            res = regex.stringByReplacingMatches(in: res, options: [], range: NSRange(location: 0, length: (res as NSString).length), withTemplate: "*_$1_*")
        }

        // Fett: **text** -> *text*
        if let regex = try? NSRegularExpression(pattern: "\\*\\*(.+?)\\*\\*", options: []) {
            res = regex.stringByReplacingMatches(in: res, options: [], range: NSRange(location: 0, length: (res as NSString).length), withTemplate: "*$1*")
        }

        // Kursiv: *text* -> _text_ (nur wenn nicht Teil eines Worts)
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
