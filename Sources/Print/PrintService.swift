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

        var candidates: [String] = []
        if let bundleTypst = Bundle.main.url(forAuxiliaryExecutable: "typst")?.path {
            candidates.append(bundleTypst)
        }
        candidates.append(Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/typst").path)
        candidates.append(Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/typst").path)
        candidates.append(contentsOf: [
            "/opt/homebrew/bin/typst",
            "/usr/local/bin/typst",
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/bin/typst").path,
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".cargo/bin/typst").path
        ])
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
        if let paperName = printInfo.paperName {
            let name = paperName.rawValue.lowercased()
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

    func buildTypstDocument(
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
            resolvedFont = "(\"\(family)\", \"Bookerly\", \"PT Serif\", \"Times New Roman\")"
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
            } else if let callout = matchCallout(trimmed) {
                // 3. Callouts (> [!NOTE], etc.)
                let (label, strokeColor, fillColor) = resolveCalloutTheme(callout.type)
                let body = convertInlineMarkdown(callout.content)
                processed = "#block(fill: \(fillColor), stroke: (left: 3pt + \(strokeColor)), inset: 8pt, radius: (right: 3pt), width: 100%)[#text(weight: \"bold\", fill: \(strokeColor))[\(label)] \(body)]"
            } else if trimmed.hasPrefix(">") {
                // 4. Zitate
                var quoteBody = trimmed.dropFirst(1)
                if quoteBody.hasPrefix(" ") { quoteBody = quoteBody.dropFirst(1) }
                let formattedQuote = convertInlineMarkdown(String(quoteBody))
                processed = "#quote[\(formattedQuote)]"
            } else if let taskChecked = matchTaskChecked(line) {
                // 5. Aufgabenliste (erledigt)
                let body = convertInlineMarkdown(taskChecked.content)
                processed = "\(taskChecked.indent)- #box(stroke: 0.8pt + luma(100), width: 0.85em, height: 0.85em, fill: luma(60), baseline: 10%)[] #strike[\(body)]"
            } else if let taskUnchecked = matchTaskUnchecked(line) {
                // 6. Aufgabenliste (offen)
                let body = convertInlineMarkdown(taskUnchecked.content)
                processed = "\(taskUnchecked.indent)- #box(stroke: 0.8pt + luma(100), width: 0.85em, height: 0.85em, baseline: 10%)[] \(body)"
            } else if let bullet = matchBulletList(line) {
                // 7. Ungeordnete Aufzählungsliste
                let body = convertInlineMarkdown(bullet.content)
                processed = "\(bullet.indent)- \(body)"
            } else if let numbered = matchNumberedList(line) {
                // 8. Nummerierte Liste (Typst + nummeriert automatisch fortlaufend)
                let body = convertInlineMarkdown(numbered.content)
                processed = "\(numbered.indent)+ \(body)"
            } else {
                // 9. Normaler Fließtext mit Einzügen und Inline-Markdown
                processed = processLineIndentsAndEscaping(processed, isMarkdown: true)
            }

            resultLines.append(processed)
        }

        flushTable()
        return resultLines.joined(separator: "\n")
    }

    private func matchCallout(_ line: String) -> (type: String, content: String)? {
        let pattern = "^>[ \t]*\\[!([a-zA-Z]+)\\][ \t]*(.*)$"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return nil }
        let nsLine = line as NSString
        guard let match = regex.firstMatch(in: line, options: [], range: NSRange(location: 0, length: nsLine.length)), match.numberOfRanges >= 2 else { return nil }
        let typeStr = nsLine.substring(with: match.range(at: 1))
        var trailing = ""
        if match.numberOfRanges >= 3 && match.range(at: 2).location != NSNotFound {
            trailing = nsLine.substring(with: match.range(at: 2)).trimmingCharacters(in: .whitespaces)
        }
        return (typeStr, trailing)
    }

    private func resolveCalloutTheme(_ type: String) -> (label: String, strokeColor: String, fillColor: String) {
        switch type.uppercased() {
        case "NOTE", "INFO", "HINWEIS":
            return ("Hinweis:", "rgb(\"1d4ed8\")", "rgb(\"eff6ff\")")
        case "TIP", "TIPP", "SUCCESS", "ERFOLG":
            return ("Tipp:", "rgb(\"15803d\")", "rgb(\"f0fdf4\")")
        case "WARNING", "WARNUNG", "ACHTUNG":
            return ("Warnung:", "rgb(\"c2410c\")", "rgb(\"fff7ed\")")
        case "CAUTION", "DANGER", "FEHLER":
            return ("Achtung:", "rgb(\"b91c1c\")", "rgb(\"fef2f2\")")
        case "IMPORTANT", "WICHTIG":
            return ("Wichtig:", "rgb(\"7e22ce\")", "rgb(\"faf5ff\")")
        default:
            return ("\(type.capitalized):", "rgb(\"0969da\")", "rgb(\"f8fafc\")")
        }
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

    private func prepareCellForWrapping(_ text: String) -> String {
        var res = text

        // 1. Markdown Links schützen [Text](URL), damit URLs nicht durch ZWS korrumpiert werden
        var linkPlaceholders: [String] = []
        let linkPattern = "\\[([^\\]]+)\\]\\(([^\\)]+)\\)"
        if let linkRegex = try? NSRegularExpression(pattern: linkPattern, options: []) {
            let matches = linkRegex.matches(in: res, options: [], range: NSRange(location: 0, length: (res as NSString).length))
            for match in matches.reversed() {
                let linkText = (res as NSString).substring(with: match.range(at: 1))
                let linkUrl = (res as NSString).substring(with: match.range(at: 2))
                let sanitizedText = prepareCellForWrapping(linkText)
                let placeholder = "\u{FFF5}LNK\(linkPlaceholders.count)\u{FFF6}"
                linkPlaceholders.append("[\(sanitizedText)](\(linkUrl))")
                res = (res as NSString).replacingCharacters(in: match.range, with: placeholder)
            }
        }

        // 2. Inline-Codeblöcke (`...`)
        // Typst trennt Monospace-Codeblöcke standardmäßig nicht an Unterstrichen oder Punkten.
        // Durch Einfügen von ZWS (\u{200B}) nach Trennzeichen können Monospace-Codes
        // bei schmalen Spalten exakt umbrechen, ohne in Nachbarzellen zu ragen.
        let codePattern = "`([^`]+)`"
        if let codeRegex = try? NSRegularExpression(pattern: codePattern, options: []) {
            let matches = codeRegex.matches(in: res, options: [], range: NSRange(location: 0, length: (res as NSString).length))
            for match in matches.reversed() {
                let code = (res as NSString).substring(with: match.range(at: 1))
                var broken = ""
                var countSinceBreak = 0
                for char in code {
                    broken.append(char)
                    countSinceBreak += 1
                    if "_-./:\\@?&=".contains(char) {
                        broken.append("\u{200B}")
                        countSinceBreak = 0
                    } else if countSinceBreak >= 12 {
                        broken.append("\u{200B}")
                        countSinceBreak = 0
                    }
                }
                let replacement = "`\(broken)`"
                res = (res as NSString).replacingCharacters(in: match.range, with: replacement)
            }
        }

        // 3. Pfade und Punkte im Freitext
        let pathPattern = "(?<=[a-zA-Z0-9_])([/.])(?=[a-zA-Z0-9_])"
        if let pathRegex = try? NSRegularExpression(pattern: pathPattern, options: []) {
            let matches = pathRegex.matches(in: res, options: [], range: NSRange(location: 0, length: (res as NSString).length))
            for match in matches.reversed() {
                let sep = (res as NSString).substring(with: match.range(at: 1))
                let replacement = "\(sep)\u{200B}"
                res = (res as NSString).replacingCharacters(in: match.range, with: replacement)
            }
        }

        // 4. Links wiederherstellen
        for (idx, originalLink) in linkPlaceholders.enumerated() {
            res = res.replacingOccurrences(of: "\u{FFF5}LNK\(idx)\u{FFF6}", with: originalLink)
        }

        return res
    }

    private func convertMarkdownTableToTypst(_ tableLines: [String]) -> String {
        var rawRows: [[String]] = []
        for line in tableLines {
            let clean = line.replacingOccurrences(of: "|", with: "").replacingOccurrences(of: "-", with: "").replacingOccurrences(of: ":", with: "").trimmingCharacters(in: .whitespaces)
            if clean.isEmpty && line.contains("-") {
                // Trennzeile überspringen
                continue
            }
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            // Maskierte Pipes (\|) bleiben Zellinhalt und trennen keine Spalten
            let sentinel = "\u{FFF4}"
            let protected = trimmed.replacingOccurrences(of: "\\|", with: sentinel)
            var parts = protected.components(separatedBy: "|")
            if parts.first?.trimmingCharacters(in: .whitespaces).isEmpty == true { parts.removeFirst() }
            if parts.last?.trimmingCharacters(in: .whitespaces).isEmpty == true { parts.removeLast() }

            let cells = parts.map {
                $0.replacingOccurrences(of: sentinel, with: "|").trimmingCharacters(in: .whitespaces)
            }
            if !cells.isEmpty {
                rawRows.append(cells)
            }
        }

        guard !rawRows.isEmpty else { return "" }
        let colCount = rawRows.map { $0.count }.max() ?? 1

        // 1. Spaltenbreiten-Berechnung basierend auf dem unformatierten Textinhalt
        var colMaxLengths = [Int](repeating: 1, count: colCount)
        var colAvgLengths = [Double](repeating: 1.0, count: colCount)

        for c in 0..<colCount {
            var sum = 0
            var count = 0
            var maxLen = 1
            for row in rawRows {
                if c < row.count {
                    let len = row[c].count
                    maxLen = max(maxLen, len)
                    sum += len
                    count += 1
                }
            }
            colMaxLengths[c] = maxLen
            colAvgLengths[c] = count > 0 ? Double(sum) / Double(count) : Double(maxLen)
        }

        // Gewichtsbestimmung über glatte Potenzfunktion (0.65):
        // Sehr kurze Spalten (<= 8 Zeichen) erhalten 'auto'.
        // Längere Spalten teilen die Seitenbreite harmonisch auf.
        var weights: [String] = []
        var frCount = 0
        for c in 0..<colCount {
            let maxL = colMaxLengths[c]
            let avgL = colAvgLengths[c]
            let effectiveL = (Double(maxL) * 0.7) + (avgL * 0.3)

            if maxL <= 8 && colCount > 1 {
                weights.append("auto")
            } else {
                let w = max(1.0, pow(effectiveL, 0.65))
                weights.append(String(format: "%.2ffr", w))
                frCount += 1
            }
        }
        if frCount == 0 {
            weights = [String](repeating: "1fr", count: colCount)
        }

        // 2. Zellinhalte für Typst umwandeln und Umbruchstellen injizieren
        var parsedRows: [[String]] = []
        for row in rawRows {
            var formattedRow: [String] = []
            for cellText in row {
                let prepared = prepareCellForWrapping(cellText)
                let converted = convertInlineMarkdown(prepared)
                    .replacingOccurrences(of: "\\_", with: "\\_#sym.zws;")
                formattedRow.append(converted)
            }
            parsedRows.append(formattedRow)
        }

        var typstCode = "\n#block(width: 100%)[\n#set text(size: 9.5pt, hyphenate: true)\n#set par(justify: false, leading: 0.45em)\n#table(\n  columns: (\(weights.joined(separator: ", "))),\n  inset: (x: 5.5pt, y: 5.0pt),\n  align: left + top,\n  stroke: 0.5pt + luma(170),\n  fill: (x, y) => if y == 0 { luma(235) } else if calc.even(y) { luma(248) } else { none },\n"
        for (idx, row) in parsedRows.enumerated() {
            var paddedRow = row
            while paddedRow.count < colCount {
                paddedRow.append("")
            }
            let cellsCode = paddedRow.map { cell in
                idx == 0 ? "[*\(cell)*]" : "[\(cell)]"
            }.joined(separator: ", ")
            if idx == 0 {
                typstCode += "  table.header(\(cellsCode)),\n"
            } else {
                typstCode += "  \(cellsCode),\n"
            }
        }
        typstCode += ")\n]\n"
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
        guard !text.isEmpty else { return "" }

        // 1. Raw Inline-Codeblöcke schützen (`...`)
        var rawPlaceholders: [String] = []
        var res = text
        let rawPattern = "`([^`]+)`"
        if let rawRegex = try? NSRegularExpression(pattern: rawPattern, options: []) {
            let matches = rawRegex.matches(in: res, options: [], range: NSRange(location: 0, length: (res as NSString).length))
            for match in matches.reversed() {
                let matchedStr = (res as NSString).substring(with: match.range)
                let placeholder = "\u{FFF0}RAW\(rawPlaceholders.count)\u{FFF1}"
                rawPlaceholders.append(matchedStr)
                res = (res as NSString).replacingCharacters(in: match.range, with: placeholder)
            }
        }

        // 2. Inline-Math schützen ($...$)
        var mathPlaceholders: [String] = []
        let mathPattern = "(?<!\\$)\\$([^\\$\n]+?)\\$(?!\\$)"
        if let mathRegex = try? NSRegularExpression(pattern: mathPattern, options: []) {
            let matches = mathRegex.matches(in: res, options: [], range: NSRange(location: 0, length: (res as NSString).length))
            for match in matches.reversed() {
                let formula = (res as NSString).substring(with: match.range(at: 1))
                let placeholder = "\u{FFF0}MTH\(mathPlaceholders.count)\u{FFF1}"
                mathPlaceholders.append("$ \(formula) $")
                res = (res as NSString).replacingCharacters(in: match.range, with: placeholder)
            }
        }

        // 3. Wiki-Links schützen ([[Ziel|Titel]] und [[Ziel]])
        var wikiPlaceholders: [String] = []
        let wikiPattern = "\\[\\[([^\\]|]+)(?:\\|([^\\]]+))?\\]\\]"
        if let wikiRegex = try? NSRegularExpression(pattern: wikiPattern, options: []) {
            let matches = wikiRegex.matches(in: res, options: [], range: NSRange(location: 0, length: (res as NSString).length))
            for match in matches.reversed() {
                let hasAlias = match.numberOfRanges >= 3 && match.range(at: 2).location != NSNotFound
                let textToShow = hasAlias ? (res as NSString).substring(with: match.range(at: 2)) : (res as NSString).substring(with: match.range(at: 1))
                let formatted = convertInlineMarkdown(textToShow)
                let placeholder = "\u{FFF0}WIKI\(wikiPlaceholders.count)\u{FFF1}"
                wikiPlaceholders.append("#underline[#text(fill: rgb(\"0969da\"))[\(formatted)]]")
                res = (res as NSString).replacingCharacters(in: match.range, with: placeholder)
            }
        }

        // 4. Links schützen ([Text](URL))
        var linkPlaceholders: [String] = []
        let linkPattern = "\\[([^\\]]+)\\]\\(([^\\)]+)\\)"
        if let linkRegex = try? NSRegularExpression(pattern: linkPattern, options: []) {
            let matches = linkRegex.matches(in: res, options: [], range: NSRange(location: 0, length: (res as NSString).length))
            for match in matches.reversed() {
                let linkText = (res as NSString).substring(with: match.range(at: 1))
                let linkUrl = (res as NSString).substring(with: match.range(at: 2))
                let formattedLinkText = convertInlineMarkdown(linkText)
                let typstLink = "#link(\"\(linkUrl)\")[\(formattedLinkText)]"
                let placeholder = "\u{FFF0}LNK\(linkPlaceholders.count)\u{FFF1}"
                linkPlaceholders.append(typstLink)
                res = (res as NSString).replacingCharacters(in: match.range, with: placeholder)
            }
        }

        // 5. Autolinks schützen (<https://...>)
        let autolinkPattern = "<(https?://[^>]+|mailto:[^>]+)>"
        if let autoRegex = try? NSRegularExpression(pattern: autolinkPattern, options: []) {
            let matches = autoRegex.matches(in: res, options: [], range: NSRange(location: 0, length: (res as NSString).length))
            for match in matches.reversed() {
                let url = (res as NSString).substring(with: match.range(at: 1))
                let placeholder = "\u{FFF0}LNK\(linkPlaceholders.count)\u{FFF1}"
                linkPlaceholders.append("#link(\"\(url)\")[\(url)]")
                res = (res as NSString).replacingCharacters(in: match.range, with: placeholder)
            }
        }

        // 6. Typst-Sonderzeichen im verbleibenden Text maskieren
        res = res
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "#", with: "\\#")
            .replacingOccurrences(of: "$", with: "\\$")
            .replacingOccurrences(of: "@", with: "\\@")
            .replacingOccurrences(of: "<", with: "\\<")
            .replacingOccurrences(of: ">", with: "\\>")
            .replacingOccurrences(of: "[", with: "\\[")
            .replacingOccurrences(of: "]", with: "\\]")

        // 7. Markdown-Formatierungen anwenden
        // Highlights: ==Text== -> #highlight[Text]
        if let regex = try? NSRegularExpression(pattern: "==([^=]+?)==", options: []) {
            res = regex.stringByReplacingMatches(in: res, options: [], range: NSRange(location: 0, length: (res as NSString).length), withTemplate: "#highlight[$1]")
        }

        // Durchgestrichen: ~~text~~ -> #strike[text]
        if let regex = try? NSRegularExpression(pattern: "~~(.+?)~~", options: []) {
            res = regex.stringByReplacingMatches(in: res, options: [], range: NSRange(location: 0, length: (res as NSString).length), withTemplate: "#strike[$1]")
        }

        // Formatierungen werden zunächst als private Marker gesetzt (Fett U+FFF2, Kursiv U+FFF3),
        // damit verbleibende einzelne Steuerzeichen (z. B. [[_INDEX]]) anschließend maskiert werden können.
        // Fett-Kursiv: ***text*** und ___text___
        if let regex = try? NSRegularExpression(pattern: "(\\*\\*\\*|___)(.+?)\\1", options: []) {
            res = regex.stringByReplacingMatches(in: res, options: [], range: NSRange(location: 0, length: (res as NSString).length), withTemplate: "\u{FFF2}\u{FFF3}$2\u{FFF3}\u{FFF2}")
        }

        // Fett: **text** und __text__
        if let regex = try? NSRegularExpression(pattern: "(\\*\\*|__)(.+?)\\1", options: []) {
            res = regex.stringByReplacingMatches(in: res, options: [], range: NSRange(location: 0, length: (res as NSString).length), withTemplate: "\u{FFF2}$2\u{FFF2}")
        }

        // Kursiv: *text* und _text_
        if let regex = try? NSRegularExpression(pattern: "(?<!\\*)\\*([^*]+?)\\*(?!\\*)", options: []) {
            res = regex.stringByReplacingMatches(in: res, options: [], range: NSRange(location: 0, length: (res as NSString).length), withTemplate: "\u{FFF3}$1\u{FFF3}")
        }
        if let regex = try? NSRegularExpression(pattern: "(?<![\\w_])_([^_]+?)_(?![\\w_])", options: []) {
            res = regex.stringByReplacingMatches(in: res, options: [], range: NSRange(location: 0, length: (res as NSString).length), withTemplate: "\u{FFF3}$1\u{FFF3}")
        }

        // Nicht gepaarte Steuerzeichen als Klartext maskieren, danach Marker in Typst-Syntax umsetzen
        res = res
            .replacingOccurrences(of: "*", with: "\\*")
            .replacingOccurrences(of: "_", with: "\\_")
            .replacingOccurrences(of: "\u{FFF2}", with: "*")
            .replacingOccurrences(of: "\u{FFF3}", with: "_")

        // 8. Platzhalter wieder einsetzen
        for (idx, typstLink) in linkPlaceholders.enumerated() {
            res = res.replacingOccurrences(of: "\u{FFF0}LNK\(idx)\u{FFF1}", with: typstLink)
        }

        for (idx, wikiLink) in wikiPlaceholders.enumerated() {
            res = res.replacingOccurrences(of: "\u{FFF0}WIKI\(idx)\u{FFF1}", with: wikiLink)
        }

        for (idx, mth) in mathPlaceholders.enumerated() {
            res = res.replacingOccurrences(of: "\u{FFF0}MTH\(idx)\u{FFF1}", with: mth)
        }

        for (idx, rawStr) in rawPlaceholders.enumerated() {
            res = res.replacingOccurrences(of: "\u{FFF0}RAW\(idx)\u{FFF1}", with: rawStr)
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
