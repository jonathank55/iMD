#if os(macOS)
import AppKit

public final class MacFontManager: NSObject {
    public static let shared = MacFontManager()

    public func availableFamilies() -> [String] {
        let families = NSFontManager.shared.availableFontFamilies
        return families.sorted()
    }

    public func showFontPanel() {
        NSFontManager.shared.orderFrontFontPanel(nil)
    }
}
#endif
