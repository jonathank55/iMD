import AppKit
import PDFKit

public final class PrintService {
    public static let shared = PrintService()

    private init() {}

    public func printDocument(text: String, isMarkdown: Bool, title: String? = nil, window: NSWindow? = nil) {
        let tempDir = FileManager.default.temporaryDirectory
        let uniqueID = UUID().uuidString
        let ext = isMarkdown ? "md" : "txt"
        let inputFileURL = tempDir.appendingPathComponent("iText_print_\(uniqueID).\(ext)")
        let outputFileURL = tempDir.appendingPathComponent("iText_print_\(uniqueID).pdf")

        do {
            try text.write(to: inputFileURL, atomically: true, encoding: .utf8)
        } catch {
            showErrorAlert(message: "Konnte Druckdatei nicht schreiben: \(error.localizedDescription)", window: window)
            return
        }

        let candidates = [
            "/Users/yonaklatchko/.local/bin/txt2pdf",
            "/opt/homebrew/bin/txt2pdf",
            "/usr/local/bin/txt2pdf"
        ]
        var txt2pdfPath: String?
        for c in candidates {
            if FileManager.default.isExecutableFile(atPath: c) {
                txt2pdfPath = c
                break
            }
        }

        guard let executable = txt2pdfPath else {
            showErrorAlert(
                message: "txt2pdf wurde nicht im Pfad gefunden. Bitte installieren Sie txt2pdf über das Installationsskript.",
                window: window
            )
            return
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        var arguments = [inputFileURL.path, "-o", outputFileURL.path]
        if let docTitle = title, !docTitle.isEmpty {
            arguments.append(contentsOf: ["-t", docTitle])
        }
        process.arguments = arguments

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
                let errMsg = String(data: errData, encoding: .utf8) ?? "Fehler beim Kompilieren via txt2pdf."
                showErrorAlert(message: "Druckaufbereitung fehlgeschlagen:\n\(errMsg)", window: window)
                return
            }

            guard FileManager.default.fileExists(atPath: outputFileURL.path) else {
                showErrorAlert(message: "Das PDF-Dokument wurde nicht erzeugt.", window: window)
                return
            }

            guard let pdfDoc = PDFDocument(url: outputFileURL) else {
                showErrorAlert(message: "Das erzeugte PDF konnte nicht geladen werden.", window: window)
                return
            }

            let printInfo = NSPrintInfo.shared
            printInfo.horizontalPagination = .fit
            printInfo.verticalPagination = .automatic
            printInfo.isHorizontallyCentered = true
            printInfo.isVerticallyCentered = true

            guard let printOp = pdfDoc.printOperation(for: printInfo, scalingMode: .pageScaleDownToFit, autoRotate: true) else {
                showErrorAlert(message: "Druckoperation konnte nicht initialisiert werden.", window: window)
                return
            }

            printOp.showsPrintPanel = true
            printOp.showsProgressPanel = true

            if let targetWindow = window ?? NSApp.keyWindow {
                printOp.runModal(for: targetWindow, delegate: nil, didRun: nil, contextInfo: nil)
            } else {
                printOp.run()
            }

        } catch {
            showErrorAlert(message: "Fehler beim Ausführen von txt2pdf: \(error.localizedDescription)", window: window)
        }
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
