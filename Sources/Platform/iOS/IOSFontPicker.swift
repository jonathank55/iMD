#if os(iOS)
import SwiftUI
import UIKit

public struct IOSFontPicker: UIViewControllerRepresentable {
    @Binding public var selectedFontFamily: String
    @Environment(\.presentationMode) private var presentationMode

    public init(selectedFontFamily: Binding<String>) {
        self._selectedFontFamily = selectedFontFamily
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    public func makeUIViewController(context: Context) -> UIFontPickerViewController {
        let configuration = UIFontPickerViewController.Configuration()
        configuration.includeFaces = false
        configuration.displayUsingSystemFont = false

        let picker = UIFontPickerViewController(configuration: configuration)
        picker.delegate = context.coordinator
        return picker
    }

    public func updateUIViewController(_ uiViewController: UIFontPickerViewController, context: Context) {}

    public final class Coordinator: NSObject, UIFontPickerViewControllerDelegate {
        private let parent: IOSFontPicker

        init(_ parent: IOSFontPicker) {
            self.parent = parent
        }

        public func fontPickerViewControllerDidPickFont(_ viewController: UIFontPickerViewController) {
            guard let descriptor = viewController.selectedFontDescriptor else { return }
            let font = UIFont(descriptor: descriptor, size: 16)
            parent.selectedFontFamily = font.familyName
            parent.presentationMode.wrappedValue.dismiss()
        }

        public func fontPickerViewControllerDidCancel(_ viewController: UIFontPickerViewController) {
            parent.presentationMode.wrappedValue.dismiss()
        }
    }
}
#endif
