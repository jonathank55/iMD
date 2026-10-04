#if os(iOS)
import UIKit

public final class IOSToolbarAccessory: UIToolbar {
    private weak var textView: UITextView?

    public init(textView: UITextView) {
        self.textView = textView
        super.init(frame: CGRect(x: 0, y: 0, width: UIScreen.main.bounds.width, height: 44))
        setupToolbar()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupToolbar() {
        barStyle = .default
        isTranslucent = true

        let undoImage = UIImage(systemName: "arrow.uturn.backward")
        let undoItem = UIBarButtonItem(image: undoImage, style: .plain, target: self, action: #selector(handleUndo))
        undoItem.accessibilityLabel = "Rückgängig"

        let redoImage = UIImage(systemName: "arrow.uturn.forward")
        let redoItem = UIBarButtonItem(image: redoImage, style: .plain, target: self, action: #selector(handleRedo))
        redoItem.accessibilityLabel = "Wiederholen"

        let indentImage = UIImage(systemName: "increase.indent")
        let indentItem = UIBarButtonItem(image: indentImage, style: .plain, target: self, action: #selector(handleIndent))
        indentItem.accessibilityLabel = "Einzug"

        let flexibleSpace = UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil)

        let dismissImage = UIImage(systemName: "keyboard.chevron.compact.down")
        let dismissItem = UIBarButtonItem(image: dismissImage, style: .plain, target: self, action: #selector(handleDismiss))
        dismissItem.accessibilityLabel = "Tastatur schließen"

        items = [
            undoItem,
            UIBarButtonItem(barButtonSystemItem: .fixedSpace, target: nil, action: nil),
            redoItem,
            UIBarButtonItem(barButtonSystemItem: .fixedSpace, target: nil, action: nil),
            indentItem,
            flexibleSpace,
            dismissItem
        ]

        sizeToFit()
    }

    @objc private func handleUndo() {
        guard let tv = textView, let um = tv.undoManager, um.canUndo else { return }
        um.undo()
    }

    @objc private func handleRedo() {
        guard let tv = textView, let um = tv.undoManager, um.canRedo else { return }
        um.redo()
    }

    @objc private func handleIndent() {
        guard let tv = textView else { return }
        let selectedRange = tv.selectedRange

        if let textStorage = tv.textStorage {
            let tabString = "\t"
            tv.undoManager?.registerUndo(withTarget: tv, handler: { targetView in
                if let storage = targetView.textStorage {
                    storage.replaceCharacters(in: NSRange(location: selectedRange.location, length: 1), with: "")
                    targetView.selectedRange = selectedRange
                }
            })
            textStorage.replaceCharacters(in: selectedRange, with: tabString)
            tv.selectedRange = NSRange(location: selectedRange.location + 1, length: 0)
            tv.delegate?.textViewDidChange?(tv)
        } else {
            tv.insertText("\t")
        }
    }

    @objc private func handleDismiss() {
        textView?.resignFirstResponder()
    }
}
#endif
